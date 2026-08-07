import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// First run, in four beats: the claim, the choice, one service at a time, and
/// what it actually achieved.
///
/// The flow's length is the user's — two fixed beats plus one page per chosen
/// service plus the close — which is why progress is the ring closing rather
/// than a fixed bar of segments.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    this.certificateProber = probeUntrustedCertificate,
  });

  /// Injectable so a widget test can stay off a real socket — see
  /// [CertificateProber].
  final CertificateProber certificateProber;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const _doorPage = 0;
  static const _pickPage = 1;
  static const _firstWalkPage = 2;

  final _pageController = PageController();

  /// The ring's entrance. One authored moment on the door, then stillness.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppAnimation.durationXl,
  );

  final Set<ServiceKey> _picked = {};

  final Map<ServiceKey, TextEditingController> _urlCtrl = {
    for (final k in ServiceKey.values) k: TextEditingController(),
  };
  final Map<ServiceKey, TextEditingController> _apiKeyCtrl = {
    for (final k in ServiceKey.values) k: TextEditingController(),
  };
  final Map<ServiceKey, TextEditingController> _usernameCtrl = {
    for (final k in ServiceKey.values) k: TextEditingController(),
  };
  final Map<ServiceKey, TextEditingController> _passwordCtrl = {
    for (final k in ServiceKey.values) k: TextEditingController(),
  };

  final Map<ServiceKey, ServiceConnectionStatus?> _status = {};
  final Map<ServiceKey, ServiceFailureReason?> _reason = {};

  /// The verbatim sentence a failure carried, for the few that carry one — see
  /// `ServiceDiagnosis.detail`. Kept beside [_reason] rather than folded into it
  /// so the walk renders the same words the settings screen does.
  final Map<ServiceKey, String?> _failureDetail = {};
  final Map<ServiceKey, bool> _verifying = {};

  /// Self-signed fingerprints the user chose to trust, persisted on save
  /// (ADR-6) — one per service's *origin*, so two services typed at the same
  /// host:port share the value a save later stores under one key.
  ///
  /// Never read directly: go through [_pinFor], which is what ties an entry to
  /// [_certOriginOf].
  final Map<ServiceKey, String> _certFingerprint = {};

  /// The TLS origin each [_certFingerprint] entry was decided against.
  ///
  /// A trust decision is about a certificate a *specific host* presented, so it
  /// stops applying the moment the address does. Without this, resuming a walk
  /// with a pinned service and then editing its address carried the old host's
  /// fingerprint onto the new one: `_save` writes every ready service, not only
  /// the one on screen, so paging forward was enough. Because a pin is keyed by
  /// origin alone, that bogus entry then failed the handshake closed for every
  /// service later pointed at the new host, with no trust prompt to explain it.
  final Map<ServiceKey, String> _certOriginOf = {};

  /// A certificate probe the last test ran into, waiting for the user to
  /// trust it inside the step rather than in a dialog that lands on top of
  /// the failure. Carries whether this origin already had a *different* pin
  /// (ADR-6) — that is a certificate change, not a first trust, and the card
  /// escalates rather than offering it as routine.
  final Map<ServiceKey, UntrustedCertificateProbe> _pendingCert = {};

  /// The field values a verification result belongs to. Editing an address after
  /// a successful check would otherwise leave a green verdict standing for an
  /// instance that is no longer the one configured.
  final Map<ServiceKey, String> _verifiedAgainst = {};

  /// Services the user explicitly walked past. They keep their place in the ring
  /// but are not written to settings.
  final Set<ServiceKey> _skipped = {};

  @override
  void initState() {
    super.initState();
    // Resume, rather than restart. Saving happens as the walk proceeds, so an
    // interrupted setup leaves settings on disk that this screen must show —
    // otherwise finishing a second time writes empty fields over a real
    // configuration.
    final settings = ref.read(currentSettingsProvider);
    for (final k in ServiceKey.values) {
      final url = settings.urlFor(k);
      if (url.isEmpty) continue;
      _picked.add(k);
      _urlCtrl[k]!.text = url;
      // Which fields a service even has is the registry's answer, so a new
      // credential-authenticated service resumes correctly without an arm here.
      if (k.usesApiKey) {
        _apiKeyCtrl[k]!.text = settings.apiKeyFor(k);
      } else {
        _usernameCtrl[k]!.text = settings.usernameFor(k);
        _passwordCtrl[k]!.text = settings.passwordFor(k);
      }
      final pin = settings.pinForUrl(url);
      final origin = UrlUtils.certOrigin(url);
      if (pin != null && origin != null) {
        _certFingerprint[k] = pin;
        _certOriginOf[k] = origin;
      }
    }
    // Reduce Motion removes the animator rather than shortening it: the ring
    // simply starts seated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entrance.dispose();
    for (final c in _urlCtrl.values) {
      c.dispose();
    }
    for (final c in _apiKeyCtrl.values) {
      c.dispose();
    }
    for (final c in _usernameCtrl.values) {
      c.dispose();
    }
    for (final c in _passwordCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── The walk ──────────────────────────────────────────────────────────────

  /// Chosen services in registry order — the same order the ring draws.
  List<ServiceKey> get _walk =>
      ServiceRing.order.where(_picked.contains).toList(growable: false);

  int get _closePage => _firstWalkPage + _walk.length;

  bool _isReady(ServiceKey k) {
    if (!_picked.contains(k) || _skipped.contains(k)) return false;
    if (_urlCtrl[k]!.text.trim().isEmpty) return false;
    if (!k.usesApiKey) return true;
    return _apiKeyCtrl[k]!.text.trim().isNotEmpty;
  }

  List<ServiceKey> get _configured =>
      ServiceRing.order.where(_isReady).toList(growable: false);

  List<ServiceKey> get _answering => _configured
      .where((k) => _status[k] == ServiceConnectionStatus.connected)
      .toList(growable: false);

  List<ServiceKey> get _silent => _configured
      .where((k) => _status[k] != ServiceConnectionStatus.connected)
      .toList(growable: false);

  /// The ring's state, derived rather than stored: one map, four beats.
  Map<ServiceKey, ServiceRingState> get _ringStates => {
    for (final k in _picked)
      k: switch (_status[k]) {
        ServiceConnectionStatus.connected => ServiceRingState.connected,
        null => ServiceRingState.picked,
        _ => _isReady(k) ? ServiceRingState.silent : ServiceRingState.picked,
      },
  };

  /// The fingerprint [k]'s *currently typed* address is trusted under, or null.
  ///
  /// The gate on [_certFingerprint]: a pin only applies while the address still
  /// resolves to the origin the user accepted the certificate for. Retyping the
  /// old address brings its pin back, which is right — the trust decision was
  /// about that host and still holds.
  String? _pinFor(ServiceKey k) {
    final pin = _certFingerprint[k];
    if (pin == null) return null;
    final origin = UrlUtils.certOrigin(_urlCtrl[k]!.text);
    return origin != null && origin == _certOriginOf[k] ? pin : null;
  }

  String _fingerprintOf(ServiceKey k) => [
    _urlCtrl[k]!.text.trim(),
    _apiKeyCtrl[k]!.text.trim(),
    _usernameCtrl[k]!.text.trim(),
    _passwordCtrl[k]!.text,
    _pinFor(k) ?? '',
  ].join(' ');

  bool _needsCheck(ServiceKey k) =>
      _status[k] == null || _verifiedAgainst[k] != _fingerprintOf(k);

  /// Every service in this walk whose typed address shares [service]'s TLS
  /// origin — the set a trust decision on it actually covers, computed from
  /// the in-progress form fields rather than saved settings, since several
  /// services can be typed in the same walk before anything is saved.
  List<ServiceKey> _servicesSharingOrigin(ServiceKey service) {
    final origin = UrlUtils.certOrigin(_urlCtrl[service]!.text);
    if (origin == null) return [service];
    return ServiceKey.values
        .where((k) {
          final url = _urlCtrl[k]!.text.trim();
          return url.isNotEmpty && UrlUtils.certOrigin(url) == origin;
        })
        .toList(growable: false);
  }

  // ── Address help ──────────────────────────────────────────────────────────

  /// Fills the address from the host of whichever service was configured before
  /// this one, on this service's own default port.
  ///
  /// On a home lab one box usually runs everything, so after the first service
  /// the rest are a tap plus a pasted key. Never overwrites a typed value.
  void _prefillAddress(ServiceKey service) {
    if (_urlCtrl[service]!.text.trim().isNotEmpty) return;
    final host = _lastKnownHost(exclude: service);
    if (host == null) return;
    _urlCtrl[service]!.text = 'https://$host:${service.defaultPort}';
  }

  String? _lastKnownHost({required ServiceKey exclude}) {
    for (final k in _walk.reversed) {
      if (k == exclude) continue;
      final raw = _urlCtrl[k]!.text.trim();
      if (raw.isEmpty) continue;
      final host = Uri.tryParse(UrlUtils.normalizeBaseUrl(raw))?.host ?? '';
      if (host.isNotEmpty) return host;
    }
    return null;
  }

  /// Puts this service's default port on whatever host is already typed.
  void _suggestPort(ServiceKey service) {
    final controller = _urlCtrl[service]!;
    final host =
        Uri.tryParse(UrlUtils.normalizeBaseUrl(controller.text))?.host ?? '';
    final target = host.isEmpty ? _lastKnownHost(exclude: service) ?? '' : host;
    if (target.isEmpty) return;
    setState(() {
      controller.text = 'https://$target:${service.defaultPort}';
    });
  }

  // ── Verification ──────────────────────────────────────────────────────────

  Future<void> _test(ServiceKey service) async {
    setState(() {
      _verifying[service] = true;
      _pendingCert.remove(service);
    });
    try {
      await _runTest(service);
    } finally {
      // A throw anywhere above used to leave the button spinning for the rest of
      // the session: a client constructor that rejects the address raises rather
      // than returning a failed status.
      if (mounted) setState(() => _verifying[service] = false);
    }
  }

  Future<void> _runTest(ServiceKey service) async {
    final result = await diagnoseCredentials(
      service,
      url: _urlCtrl[service]!.text,
      apiKey: _apiKeyCtrl[service]!.text,
      username: _usernameCtrl[service]!.text,
      password: _passwordCtrl[service]!.text,
      certFingerprint: _pinFor(service) ?? '',
      // Plex's persisted per-install identity. Minted once by `SettingsService`
      // and read rather than generated here, because a fresh value registers
      // another "device" row on the user's server.
      clientIdentifier: ref.read(currentSettingsProvider).plexClientId,
    );

    // A TLS failure resolves *in the step*: probe for the certificate and let
    // the card offer to trust it. Probing after the server rejected a key is
    // a wasted round trip that can only return null. Every service can reach
    // this since ADR-6 — there is no pinning-capability gate left to check.
    UntrustedCertificateProbe? certProbe;
    if (result.status == ServiceConnectionStatus.disconnected &&
        certProbeWorthwhile(result.reason)) {
      certProbe = await widget.certificateProber(
        _urlCtrl[service]!.text,
        pinnedFingerprint: _pinFor(service) ?? '',
      );
    }

    if (!mounted) return;
    if (result.status == ServiceConnectionStatus.connected) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _status[service] = result.status;
      _reason[service] = result.reason;
      _failureDetail[service] = result.detail;
      _verifiedAgainst[service] = _fingerprintOf(service);
      if (certProbe != null) _pendingCert[service] = certProbe;
    });
  }

  Future<void> _trustCertificate(ServiceKey service) async {
    final probe = _pendingCert[service];
    if (probe == null) return;
    // Recorded against the address the certificate was actually presented by,
    // so a later edit of that address drops the pin rather than carrying it to
    // a host that never presented it — see [_certOriginOf].
    final origin = UrlUtils.certOrigin(_urlCtrl[service]!.text);
    if (origin == null) return;
    setState(() {
      _certFingerprint[service] = probe.certificate.fingerprint;
      _certOriginOf[service] = origin;
      _pendingCert.remove(service);
    });
    await _test(service);
  }

  /// Checks every configured service the user did not test by hand.
  ///
  /// The close is the last chance to learn that an address or a key is wrong
  /// while the fields are still one tap away. Runs non-interactively: the result
  /// is information, not a gate.
  Future<void> _testUntested() async {
    final pending = _configured.where(_needsCheck).toList();
    if (pending.isEmpty) return;
    await Future.wait(pending.map(_test));
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Writes what this walk actually configured, and **only** that.
  ///
  /// Additive on purpose: a service the user skipped, left half-filled, or
  /// unpicked is not written at all. It used to be written *blank*, which
  /// deleted the saved address and the secure credential of a service that was
  /// working — reachable from the settings screen's "Revisit onboarding", which
  /// promises in as many words that nothing about your services is changed or
  /// removed, and from "Skip for now" on the very first beat. Removing a
  /// connection is a deliberate, confirmed action and lives in the settings
  /// screen; walking past one here means "not now", never "delete it".
  ///
  /// On a first run this is indistinguishable from the old behaviour, because
  /// there is nothing on disk to preserve.
  Future<bool> _save() async {
    final current = ref.read(currentSettingsProvider);
    var updated = current;

    // Addresses this walk moves a service *away from*. Their pins can only be
    // reconsidered once every URL has settled, so they are collected here and
    // resolved in the pass below.
    final abandonedUrls = <String>[];

    for (final k in ServiceKey.values) {
      if (!_isReady(k)) continue;
      // Store the scheme the client will actually use: saving the bare host
      // the user typed left the settings form showing a value its own
      // stricter validator rejects.
      final url = UrlUtils.normalizeBaseUrl(_urlCtrl[k]!.text);
      final priorUrl = current.urlFor(k);
      if (priorUrl.isNotEmpty && priorUrl != url) abandonedUrls.add(priorUrl);
      updated = k.usesApiKey
          ? updated.copyWithService(
              k,
              url: url,
              apiKey: _apiKeyCtrl[k]!.text.trim(),
            )
          : updated.copyWithCredentials(
              k,
              url: url,
              username: _usernameCtrl[k]!.text.trim(),
              password: _passwordCtrl[k]!.text,
            );
    }

    // Trust-map bookkeeping runs as its own pass, once every service's final
    // URL is known — an abandoned address's pin is only forgotten when no
    // configured service still reaches its origin, and that can only be
    // answered after the loop above has settled every URL, including services
    // later than `k` in registry order.
    for (final k in ServiceKey.values) {
      if (!_isReady(k)) continue;
      // [_pinFor], not the raw map: this loop runs for every ready service, not
      // just the one on screen, so an address edited after a trust decision
      // would otherwise file the old host's fingerprint under the new one.
      final pin = _pinFor(k);
      if (pin == null) continue;
      updated = updated.copyWithTrustedCertificate(
        url: updated.urlFor(k),
        fingerprint: pin,
      );
    }
    for (final priorUrl in abandonedUrls) {
      updated = updated.copyWithoutUnusedCertificate(priorUrl);
    }

    try {
      await ref.read(settingsProvider.notifier).updateSettings(updated);
      return true;
    } catch (e) {
      if (!mounted) return false;
      SnackBarHelper.error(
        context,
        "Couldn't save your services. Please try again. ($e)",
      );
      return false;
    }
  }

  /// Marks onboarding complete — triggers the router redirect to /services.
  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    try {
      await markOnboardingComplete(ref);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't finish setup. Please try again. ($e)",
      );
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// The beat on screen. Held in state rather than read off the controller
  /// because `PageController.page` is fractional mid-flight, and the ring above
  /// the pager needs the destination to aim at, not the halfway point.
  int _page = _doorPage;

  void _goTo(int page) {
    if (!_pageController.hasClients) return;
    setState(() => _page = page);
    _pageController.animateToPage(
      page,
      duration: AppAnimation.durationMd,
      curve: AppAnimation.standardCurve,
    );
  }

  Future<void> _enterWalk() async {
    if (_walk.isEmpty) {
      // Nothing chosen is a legitimate outcome; the close says so plainly.
      await _save();
      if (!mounted) return;
      setState(() {});
      _goTo(_closePage);
      return;
    }
    setState(() => _prefillAddress(_walk.first));
    _goTo(_firstWalkPage);
  }

  /// Saves what has been entered so far, then moves on. Saving per service
  /// rather than once at the end is what makes an interrupted setup resumable.
  Future<void> _advanceFrom(ServiceKey service) async {
    final index = _walk.indexOf(service);
    await _save();
    if (!mounted) return;
    if (index >= 0 && index + 1 < _walk.length) {
      final next = _walk[index + 1];
      setState(() => _prefillAddress(next));
      _goTo(_firstWalkPage + index + 1);
      return;
    }
    setState(() {});
    _goTo(_closePage);
    // Not awaited: the close is on screen while the checks run, and the way out
    // stays usable throughout.
    _testUntested();
  }

  void _skip(ServiceKey service) {
    setState(() {
      _skipped.add(service);
      _status.remove(service);
      _reason.remove(service);
      _failureDetail.remove(service);
      _pendingCert.remove(service);
    });
    _advanceFrom(service);
  }

  void _backFrom(ServiceKey service) {
    final index = _walk.indexOf(service);
    _goTo(index <= 0 ? _pickPage : _firstWalkPage + index - 1);
  }

  Future<void> _skipEverything() async {
    await _save();
    if (!mounted) return;
    setState(() {});
    _goTo(_closePage);
  }

  void _fix(ServiceKey service) {
    final index = _walk.indexOf(service);
    if (index < 0) {
      _goTo(_pickPage);
      return;
    }
    setState(() => _skipped.remove(service));
    _goTo(_firstWalkPage + index);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  /// The ring's size for the beat currently on screen.
  ///
  /// Two sizes, not four: the door and the close are about the whole stack, so
  /// the instrument is the subject there; picking and configuring are about one
  /// service at a time, so it steps down to leave the form room — but it is the
  /// *same* ring resizing, never a second one.
  double _ringDiameter(BuildContext context) => serviceRingDiameter(
    context,
    preferred: _page == _doorPage || _page >= _closePage ? 300 : 190,
  );

  @override
  Widget build(BuildContext context) {
    final walk = _walk;
    final ringStates = _ringStates;
    final activeWalk = _page >= _firstWalkPage && _page < _closePage
        ? walk[_page - _firstWalkPage]
        : null;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: onboardingMaxWidth),
              child: Column(
                children: [
                  // The instrument, outside the pager on purpose. One ring for
                  // the whole flow: it holds its place while the forms page
                  // behind it, rotates the active service to noon, and grows a
                  // spoke the moment one answers. Hoisting it out is what stops
                  // the ring and the shell arriving from two different places on
                  // every step.
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppSpacing.lg,
                      bottom: AppSpacing.md,
                    ),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: _ringDiameter(context)),
                      // The page slide's own timing, so the resize and the
                      // shell's travel read as one movement.
                      duration: AppAnimation.durationMd,
                      curve: AppAnimation.standardCurve,
                      builder: (context, diameter, _) => AnimatedBuilder(
                        animation: _entrance,
                        builder: (context, _) => ServiceRing(
                          states: ringStates,
                          diameter: diameter,
                          entrance: AppAnimation.emphasizedCurve.transform(
                            _entrance.value,
                          ),
                          activeService: activeWalk,
                          progress: activeWalk == null
                              ? (_page >= _closePage &&
                                        _silent.isEmpty &&
                                        _answering.isNotEmpty
                                    ? 1
                                    : 0)
                              : (_page - _firstWalkPage) / walk.length,
                          spin: true,
                        ),
                      ),
                    ),
                  ),
                  // The step's subject, hoisted for the same reason the ring is:
                  // a `PageView` builds one element per page, so a headline held
                  // inside the pager can only ever be replaced, never rolled.
                  // Held here it is one widget across the whole walk and the
                  // service name rolls inside a sentence that stays put.
                  if (activeWalk case final service?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: OnboardingWalkSubject(
                        service: service,
                        position: _page - _firstWalkPage + 1,
                        total: walk.length,
                      ),
                    ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        OnboardingDoor(
                          onStart: () => _goTo(_pickPage),
                          onSkip: _skipEverything,
                        ),
                        OnboardingPick(
                          picked: _picked,
                          onToggle: (service) => setState(() {
                            if (_picked.remove(service)) {
                              _status.remove(service);
                              _reason.remove(service);
                              _pendingCert.remove(service);
                            } else {
                              _picked.add(service);
                              _skipped.remove(service);
                            }
                          }),
                          onContinue: _enterWalk,
                          onBack: () => _goTo(_doorPage),
                        ),
                        for (var i = 0; i < walk.length; i++)
                          OnboardingWalk(
                            service: walk[i],
                            urlController: _urlCtrl[walk[i]]!,
                            apiKeyController: _apiKeyCtrl[walk[i]]!,
                            usernameController: _usernameCtrl[walk[i]]!,
                            passwordController: _passwordCtrl[walk[i]]!,
                            status: _status[walk[i]],
                            reason: _reason[walk[i]],
                            failureDetail: _failureDetail[walk[i]],
                            verifying: _verifying[walk[i]] ?? false,
                            certificateProbe: _pendingCert[walk[i]],
                            trustedFingerprint: _pinFor(walk[i]),
                            affectedServices: _servicesSharingOrigin(walk[i]),
                            next: i + 1 < walk.length ? walk[i + 1] : null,
                            onTest: () => _test(walk[i]),
                            onTrustCertificate: () =>
                                _trustCertificate(walk[i]),
                            onSuggestPort: () => _suggestPort(walk[i]),
                            onSkip: () => _skip(walk[i]),
                            onAdvance: () => _advanceFrom(walk[i]),
                            onBack: () => _backFrom(walk[i]),
                          ),
                        OnboardingClose(
                          connected: _answering,
                          silent: _silent,
                          onFix: _fix,
                          onFinish: _finish,
                          onReview: () => _goTo(_pickPage),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

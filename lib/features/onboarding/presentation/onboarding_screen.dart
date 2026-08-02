import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/data/service_verification.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/presentation/widgets/cert_trust_dialog.dart';
import 'package:seekarr/features/truenas/domain/truenas_version.dart';

// ─── Design tokens (pixel-faithful to prototype) ───────────────────────────
//
// This screen is deliberately always-dark, independent of the app's themeMode:
// it is the product's first impression and its own visual moment, the way a
// welcome screen usually is. That is why it carries a local palette instead of
// reading `colorScheme` — but every value is named here rather than inlined at
// the point of use, and anything with an app-wide equivalent (the brand indigo,
// the success green, the font family, animation durations, the pill radius)
// defers to the shared token so the two can never drift apart.
const _bg = Color(0xFF07080D);
const _border = Color(0xFF283247);
const _fg = Color(0xFFF3F6FF);
const _muted = Color(0xFF98A3B9);
const _muted2 = Color(0xFF647089);
const _accent = AppColors.primary; // brand indigo — single source of truth
const _success = AppColors.success;
const _screenPad = EdgeInsets.fromLTRB(22, 22, 22, 32);

/// Corner radii specific to this screen's prototype. They sit between the
/// app-wide steps (`AppRadius.md` 12 / `lg` 16 / `xl` 28), so they are named
/// locally rather than rounded onto a token that would change the look.
final _radiusChip = BorderRadius.circular(14);
final _radiusPanel = BorderRadius.circular(22);

/// Widest the onboarding column is allowed to get. Beyond this a form field's
/// label and its control drift too far apart to read as a pair.
const _contentMaxWidth = 560.0;

/// Service accent, sourced from the app-wide [ServiceKey.accent] so onboarding
/// matches the rest of the app (previously Seerr was mistakenly tinted green).
Color _serviceColor(ServiceKey service) => service.accent;

// ─── Main screen ────────────────────────────────────────────────────────────
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();

  // Step-2 per-service state
  final Map<ServiceKey, bool> _enabled = {
    for (final k in ServiceKey.values) k: false,
  };
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
  final Map<ServiceKey, ServiceConnectionStatus?> _verifyStatus = {
    for (final k in ServiceKey.values) k: null,
  };

  /// Why the last verification failed, so the error copy can name the cause.
  final Map<ServiceKey, ServiceFailureReason?> _verifyReason = {
    for (final k in ServiceKey.values) k: null,
  };
  final Map<ServiceKey, bool> _verifying = {
    for (final k in ServiceKey.values) k: false,
  };

  /// Self-signed certificate fingerprints the user chose to trust during
  /// onboarding, persisted to settings on continue. Only TrueNAS and Dockge
  /// (the WebSocket clients) support pinning.
  final Map<ServiceKey, String> _certFingerprint = {};

  @override
  void initState() {
    super.initState();
    // Resume, rather than restart. Continue on step 2 saves immediately, so an
    // interrupted setup left settings on disk that this screen then showed as
    // empty — and finishing a second time with every toggle off wrote those
    // empty fields back over the real configuration.
    final settings = ref.read(currentSettingsProvider);
    for (final k in ServiceKey.values) {
      final url = settings.urlFor(k);
      if (url.isEmpty) continue;
      _enabled[k] = true;
      _urlCtrl[k]!.text = url;
      if (k == ServiceKey.qbittorrent) {
        _usernameCtrl[k]!.text = settings.qbittorrentUsername;
        _passwordCtrl[k]!.text = settings.qbittorrentPassword;
      } else if (k == ServiceKey.dockge) {
        _usernameCtrl[k]!.text = settings.dockgeUsername;
        _passwordCtrl[k]!.text = settings.dockgePassword;
      } else if (k == ServiceKey.nzbget) {
        _usernameCtrl[k]!.text = settings.nzbgetUsername;
        _passwordCtrl[k]!.text = settings.nzbgetPassword;
      } else {
        _apiKeyCtrl[k]!.text = settings.apiKeyFor(k);
      }
      if (supportsCertPinning(k)) {
        final pin = settings.certFingerprintFor(k);
        if (pin.isNotEmpty) _certFingerprint[k] = pin;
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _urlCtrl.values) c.dispose();
    for (final c in _apiKeyCtrl.values) c.dispose();
    for (final c in _usernameCtrl.values) c.dispose();
    for (final c in _passwordCtrl.values) c.dispose();
    super.dispose();
  }

  bool _isServiceReady(ServiceKey k) {
    if (!_enabled[k]!) return false;
    if (_urlCtrl[k]!.text.trim().isEmpty) return false;
    if (!k.usesApiKey) return true;
    return _apiKeyCtrl[k]!.text.trim().isNotEmpty;
  }

  List<ServiceKey> get _configuredServices =>
      ServiceKey.values.where(_isServiceReady).toList();

  /// The field values a verification result belongs to.
  ///
  /// Editing an address after a successful check would otherwise leave a green
  /// "Reachable" standing for an instance that is no longer the one configured.
  final Map<ServiceKey, String> _verifiedAgainst = {};

  String _fieldsFingerprint(ServiceKey k) => [
    _urlCtrl[k]!.text.trim(),
    _apiKeyCtrl[k]!.text.trim(),
    _usernameCtrl[k]!.text.trim(),
    _passwordCtrl[k]!.text,
    _certFingerprint[k] ?? '',
  ].join('\u0000');

  /// Whether [service] still needs a check before the summary can say anything
  /// about it.
  bool _needsCheck(ServiceKey service) =>
      _verifyStatus[service] == null ||
      _verifiedAgainst[service] != _fieldsFingerprint(service);

  /// Checks every configured service the user did not verify by hand.
  ///
  /// The summary step is the last chance to learn that an address or a key is
  /// wrong while the fields are still one tap away; without this, someone who
  /// never pressed Verify finished setup with no idea whether any of it works.
  /// Runs non-interactively: a certificate-trust dialog per service, stacked ten
  /// deep, is not something to spring on someone reading a summary.
  Future<void> _autoVerifyConfigured() async {
    final pending = _configuredServices.where(_needsCheck).toList();
    if (pending.isEmpty) return;
    await Future.wait(
      pending.map((service) => _doVerify(service, interactive: false)),
    );
  }

  Future<void> _doVerify(ServiceKey service, {bool interactive = true}) async {
    setState(() => _verifying[service] = true);
    try {
      await _runVerify(service, interactive: interactive);
    } finally {
      // A throw anywhere above used to leave the button spinning for the rest
      // of the session with nothing to explain it — a client constructor that
      // rejects the address raises rather than returning a failed status.
      if (mounted) setState(() => _verifying[service] = false);
    }
  }

  Future<void> _runVerify(ServiceKey service, {bool interactive = true}) async {
    var result = await diagnoseCredentials(
      service,
      url: _urlCtrl[service]!.text,
      apiKey: _apiKeyCtrl[service]!.text,
      username: _usernameCtrl[service]!.text,
      password: _passwordCtrl[service]!.text,
      certFingerprint: _certFingerprint[service] ?? '',
    );

    // TLS exception flow: if a pinning-capable service failed specifically
    // because of an untrusted certificate, offer to trust it, then re-verify.
    //
    // Skipped when the failure is already attributed to something else: probing
    // for a certificate after the server rejected our API key is a wasted round
    // trip that can only return null.
    if (interactive &&
        result.status == ServiceConnectionStatus.disconnected &&
        certProbeWorthwhile(result.reason) &&
        supportsCertPinning(service) &&
        mounted) {
      final cert = await probeUntrustedCertificate(
        _urlCtrl[service]!.text,
        pinnedFingerprint: _certFingerprint[service] ?? '',
      );
      if (cert != null && mounted) {
        final trust = await showCertTrustDialog(
          context,
          serviceTitle: service.title,
          certificate: cert,
        );
        if (trust && mounted) {
          _certFingerprint[service] = cert.fingerprint;
          result = await diagnoseCredentials(
            service,
            url: _urlCtrl[service]!.text,
            apiKey: _apiKeyCtrl[service]!.text,
            username: _usernameCtrl[service]!.text,
            password: _passwordCtrl[service]!.text,
            certFingerprint: cert.fingerprint,
          );
        }
      }
    }

    if (!mounted) return;
    if (result.status == ServiceConnectionStatus.connected) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _verifyStatus[service] = result.status;
      _verifyReason[service] = result.reason;
      _verifiedAgainst[service] = _fieldsFingerprint(service);
    });
  }

  Future<void> _saveAndContinue() async {
    final current = ref.read(currentSettingsProvider);
    var updated = current;
    for (final k in ServiceKey.values) {
      if (_isServiceReady(k)) {
        // Store the scheme the client will actually use. Saving the bare host
        // the user typed left the settings form showing a value its own
        // (stricter) validator rejects.
        final url = UrlUtils.normalizeBaseUrl(_urlCtrl[k]!.text);
        if (k == ServiceKey.qbittorrent) {
          updated = updated.copyWithQbittorrent(
            url: url,
            username: _usernameCtrl[k]!.text.trim(),
            password: _passwordCtrl[k]!.text,
          );
        } else if (k == ServiceKey.dockge) {
          updated = updated.copyWithDockge(
            url: url,
            username: _usernameCtrl[k]!.text.trim(),
            password: _passwordCtrl[k]!.text,
          );
        } else if (k == ServiceKey.nzbget) {
          updated = updated.copyWithNzbget(
            url: url,
            username: _usernameCtrl[k]!.text.trim(),
            password: _passwordCtrl[k]!.text,
          );
        } else {
          updated = updated.copyWithService(
            k,
            url: url,
            apiKey: _apiKeyCtrl[k]!.text.trim(),
          );
        }
      } else {
        if (k == ServiceKey.qbittorrent) {
          updated = updated.copyWithQbittorrent(
            url: '',
            username: '',
            password: '',
          );
        } else if (k == ServiceKey.dockge) {
          updated = updated.copyWithDockge(url: '', username: '', password: '');
        } else if (k == ServiceKey.nzbget) {
          updated = updated.copyWithNzbget(url: '', username: '', password: '');
        } else {
          updated = updated.copyWithService(k, url: '', apiKey: '');
        }
      }
      // Persist (or clear) any trusted self-signed certificate fingerprint.
      if (supportsCertPinning(k)) {
        updated = updated.copyWithCertFingerprint(
          k,
          _isServiceReady(k) ? (_certFingerprint[k] ?? '') : '',
        );
      }
    }
    try {
      await ref.read(settingsProvider.notifier).updateSettings(updated);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't save your services. Please try again. ($e)",
      );
      return;
    }
    if (!mounted) return;
    // Rebuild before showing the summary. Typing into a field changes only its
    // controller, so nothing rebuilt this screen between the last toggle and
    // Continue — and the Ready step was still holding the list of configured
    // services from back then. Anyone who filled in a URL and key without
    // touching a toggle afterwards was told "No services configured" on the
    // final step, with their settings saved correctly all along.
    setState(() {});
    _goToStep(2);
    // Not awaited: the summary is on screen while the checks run, and "Let's go"
    // stays usable throughout — the result is information, not a gate.
    _autoVerifyConfigured();
  }

  /// Marks onboarding complete — triggers router redirect to /services.
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

  void _goToStep(int step) {
    _pageController.animateToPage(
      step,
      duration: AppAnimation.durationMd,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Read here, above the Scaffold — see [_keyboardVisible].
    final keyboardUp = _keyboardVisible(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // Background gradient (matches prototype radial gradients)
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.9, -0.9),
                    radius: 1.1,
                    colors: [Color(0x1F6366F1), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.9, -0.9),
                    radius: 1.0,
                    colors: [Color(0x148B5CF6), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Content
            //
            // Capped and centred: onboarding is a single column of form fields,
            // and on an iPad or a wide desktop window an unconstrained column
            // stretched labels and their toggles ~800pt apart, breaking the
            // proximity that pairs them, and made the Continue button the width
            // of the screen.
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _WelcomeStep(onContinue: () => _goToStep(1)),
                      _ServicesStep(
                        compactHeader: keyboardUp,
                        enabled: _enabled,
                        urlCtrl: _urlCtrl,
                        apiKeyCtrl: _apiKeyCtrl,
                        usernameCtrl: _usernameCtrl,
                        passwordCtrl: _passwordCtrl,
                        verifyStatus: _verifyStatus,
                        verifyReason: _verifyReason,
                        verifying: _verifying,
                        onToggle: (k, v) => setState(() {
                          _enabled[k] = v;
                          if (!v) {
                            _verifyStatus[k] = null;
                            _verifyReason[k] = null;
                          }
                        }),
                        onVerify: _doVerify,
                        onBack: () => _goToStep(0),
                        onContinue: _saveAndContinue,
                      ),
                      _ReadyStep(
                        configuredServices: _configuredServices,
                        verifyStatus: _verifyStatus,
                        verifying: _verifying,
                        onReviewSettings: () async => _goToStep(1),
                        onFinish: _finish,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Progress bar ────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step});
  final int step; // 0-based

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final active = i <= step;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
            height: 4,
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusFull,
              gradient: active
                  ? const LinearGradient(colors: [_accent, Color(0xFF818CF8)])
                  : null,
              color: active ? null : const Color(0x14FFFFFF),
            ),
          ),
        );
      }),
    );
  }
}

/// Scrolls [context]'s widget into view inside its **nearest** scroll view only.
///
/// `Scrollable.ensureVisible` walks every enclosing scrollable, and this screen
/// is a horizontal `PageView` of vertical lists: revealing a card also dragged
/// the PageView back to that card's page. With the summary step's automatic
/// checks, ten finishing verifications cancelled the transition to step 3 and
/// pinned onboarding on step 2.
void _revealInOwnScrollView(BuildContext context, {required double alignment}) {
  final position = Scrollable.maybeOf(context)?.position;
  final target = context.findRenderObject();
  if (position == null || target == null) return;
  position.ensureVisible(
    target,
    alignment: alignment,
    duration: AppAnimation.durationMd,
    curve: Curves.easeInOutCubic,
  );
}

/// Whether the software keyboard is currently covering part of the screen.
///
/// Must be read from above the [Scaffold]: its body is wrapped in
/// `MediaQuery.removeViewInsets(removeBottom: true)` whenever
/// `resizeToAvoidBottomInset` is on, so inside the body this is always 0.
bool _keyboardVisible(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom > 0;

/// The "Step N of 3" eyebrow above each step's headline. Also the only text that
/// tells a screen reader where it is in the flow — the progress bar is decorative.
class _StepLabel extends StatelessWidget {
  const _StepLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.08 * 11,
        color: _muted2,
      ),
    );
  }
}

// ─── Step 1: Welcome ─────────────────────────────────────────────────────────
class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _screenPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProgressBar(step: 0),
          const SizedBox(height: 18),
          // Steps 2 and 3 name themselves; this one used to leave the position
          // in the flow to the progress bar alone, which says nothing out loud.
          const _StepLabel('Step 1 of 3'),
          const SizedBox(height: 14),
          Expanded(child: SingleChildScrollView(child: _HeroCard())),
          const SizedBox(height: 16),
          _PrimaryButton(label: 'Continue', onPressed: onContinue),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: _radiusPanel,
        border: Border.all(color: const Color(0x3D6366F1), width: 1),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x296366F1), Color(0xEB111521)],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "S" logo mark
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: _radiusChip,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_accent, Color(0xF28B5CF6)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x28FFFFFF),
                  blurRadius: 0,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              'S',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _fg,
                letterSpacing: -0.03 * 20,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Your whole homelab, managed from one place.',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: _fg,
              letterSpacing: -0.05 * 34,
              height: 0.98,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Seekarr is the control surface for the services you run yourself — media, downloads and infrastructure — in one UI, from wherever you are.',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 14,
              color: _muted,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          // Stack preview — compact rows
          _StackRow(
            color: Color(0xFFF59E0B),
            name: 'Radarr',
            sub: 'Movie library and download management',
          ),
          const SizedBox(height: 12),
          _StackDivider(),
          const SizedBox(height: 12),
          _StackRow(
            color: AppColors.seerr,
            name: 'Seerr',
            sub: 'Requests and discovery across your stack',
          ),
          const SizedBox(height: 12),
          _StackDivider(),
          const SizedBox(height: 12),
          _StackRow(
            color: AppColors.truenas,
            name: 'TrueNAS',
            sub: 'Storage, apps and datasets on your NAS',
          ),
          const SizedBox(height: 12),
          _StackDivider(),
          const SizedBox(height: 12),
          _StackRow(
            color: null, // gradient dot for "And others"
            name: 'And others',
            sub: 'Connect more services as support grows',
          ),
        ],
      ),
    );
  }
}

class _StackDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: Color(0x14FFFFFF));
  }
}

class _StackRow extends StatelessWidget {
  const _StackRow({required this.color, required this.name, required this.sub});
  final Color? color; // null → gradient dot
  final String name;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ServiceDot(color: color),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _fg,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                sub,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 12,
                  color: _muted2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceDot extends StatelessWidget {
  const _ServiceDot({required this.color});
  final Color? color; // null → gradient

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        gradient: color == null
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_accent, _success],
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: (color ?? _accent).withValues(alpha: 0.25),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

// ─── Step 2: Services ────────────────────────────────────────────────────────
class _ServicesStep extends StatelessWidget {
  const _ServicesStep({
    required this.compactHeader,
    required this.enabled,
    required this.urlCtrl,
    required this.apiKeyCtrl,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.verifyStatus,
    required this.verifyReason,
    required this.verifying,
    required this.onToggle,
    required this.onVerify,
    required this.onBack,
    required this.onContinue,
  });

  /// Drops the headline and its paragraph, for when the keyboard is up.
  final bool compactHeader;

  final Map<ServiceKey, bool> enabled;
  final Map<ServiceKey, TextEditingController> urlCtrl;
  final Map<ServiceKey, TextEditingController> apiKeyCtrl;
  final Map<ServiceKey, TextEditingController> usernameCtrl;
  final Map<ServiceKey, TextEditingController> passwordCtrl;
  final Map<ServiceKey, ServiceConnectionStatus?> verifyStatus;
  final Map<ServiceKey, ServiceFailureReason?> verifyReason;
  final Map<ServiceKey, bool> verifying;
  final void Function(ServiceKey, bool) onToggle;
  final Future<void> Function(ServiceKey) onVerify;
  final VoidCallback onBack;
  final Future<void> Function() onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _screenPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProgressBar(step: 1),
          const SizedBox(height: 18),
          // The heading scrolls with the list. Pinned above it, a 34pt headline
          // and its paragraph grew past the whole screen at an accessibility
          // reading size — 812px of overflow on a 4.7" phone — because only the
          // list below them could scroll.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _StepLabel('Step 2 of 3'),
                  // The headline and its paragraph stand down while the keyboard is up.
                  // They are 150pt of chrome above the fields, and the keyboard has
                  // already cut the visible area to a sliver.
                  if (!compactHeader) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Connect the services you already host.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: _fg,
                        letterSpacing: -0.05 * 34,
                        height: 0.98,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Every service depends on its own self-hosted instance. Seekarr helps you manage them with one unified UI, from wherever you are.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 14,
                        color: _muted,
                        height: 1.55,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  for (final domain in ServiceDomain.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OnboardingDomainSection(
                        label: domain.label,
                        initiallyExpanded: domain == ServiceDomain.media,
                        enabledCount: domain.services
                            .where((k) => enabled[k]!)
                            .length,
                        serviceCards: [
                          for (final k in domain.services)
                            _ServiceCard(
                              serviceKey: k,
                              isEnabled: enabled[k]!,
                              urlCtrl: urlCtrl[k]!,
                              apiKeyCtrl: apiKeyCtrl[k]!,
                              usernameCtrl: usernameCtrl[k]!,
                              passwordCtrl: passwordCtrl[k]!,
                              verifyStatus: verifyStatus[k],
                              verifyReason: verifyReason[k],
                              verifying: verifying[k]!,
                              onToggle: (v) => onToggle(k, v),
                              onVerify: () => onVerify(k),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StepFooter(
            secondary: _SecondaryButton(label: 'Back', onPressed: onBack),
            primary: _AsyncButton(
              label: 'Continue',
              filled: true,
              onPressed: onContinue,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible domain group for the onboarding connect step. Styled with the
/// onboarding's dark tokens (rather than the shared Material [DomainSection])
/// so it matches the surrounding gradient UI. Media starts expanded; the other
/// domains start collapsed to keep the initial scroll short.
class _OnboardingDomainSection extends StatefulWidget {
  const _OnboardingDomainSection({
    required this.label,
    required this.serviceCards,
    required this.enabledCount,
    this.initiallyExpanded = false,
  });

  final String label;
  final List<Widget> serviceCards;
  final int enabledCount;
  final bool initiallyExpanded;

  @override
  State<_OnboardingDomainSection> createState() =>
      _OnboardingDomainSectionState();
}

class _OnboardingDomainSectionState extends State<_OnboardingDomainSection> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (!_expanded) return;
    // Expanding a section below the fold used to reveal it off-screen, behind
    // the footer buttons — the tap looked like it had done nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _revealInOwnScrollView(context, alignment: 0.05);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label: widget.label,
          value: widget.enabledCount > 0
              ? '${widget.enabledCount} connected'
              : null,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            child: Padding(
              // 44pt total: the row's content is 19pt, so the padding is what
              // makes the header reach the iOS minimum target.
              padding: const EdgeInsets.symmetric(
                vertical: 12.5,
                horizontal: 2,
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0,
                    duration: AppAnimation.durationSm,
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.label.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.08 * 11,
                        color: _muted2,
                      ),
                    ),
                  ),
                  if (widget.enabledCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.borderRadiusFull,
                        color: const Color(0x1F22C55E),
                      ),
                      child: Text(
                        '${widget.enabledCount} on',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.06 * 10,
                          color: Color(0xFFBFE9CA),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Collapsed sections build nothing: with AnimatedCrossFade every card in
        // every section was built on the first frame of the step, whether or not
        // its section was open.
        AnimatedSize(
          duration: AppAnimation.durationSm,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(
                  children: [
                    for (final card in widget.serviceCards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: card,
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.serviceKey,
    required this.isEnabled,
    required this.urlCtrl,
    required this.apiKeyCtrl,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.verifyStatus,
    required this.verifyReason,
    required this.verifying,
    required this.onToggle,
    required this.onVerify,
  });

  final ServiceKey serviceKey;
  final bool isEnabled;
  final TextEditingController urlCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final ServiceConnectionStatus? verifyStatus;
  final ServiceFailureReason? verifyReason;
  final bool verifying;
  final ValueChanged<bool> onToggle;
  final VoidCallback onVerify;

  Color get _color => _serviceColor(serviceKey);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimation.durationSm,
      decoration: BoxDecoration(
        borderRadius: _radiusPanel,
        border: Border.all(
          color: isEnabled ? _color.withValues(alpha: 0.28) : _border,
        ),
        color: isEnabled ? const Color(0xD5111521) : const Color(0x94111521),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header row — one control, the full width of the card.
          //
          // The row says "tap to connect", but only the 46pt switch answered a
          // tap; the name, the subtitle and the space between them did nothing.
          // Semantics wraps the whole row for the same reason: assistive
          // technology now sees a single switch with its on/off state instead of
          // three labels and an unnamed gesture.
          Semantics(
            toggled: isEnabled,
            label: '${serviceKey.title} enabled',
            container: true,
            excludeSemantics: true,
            onTap: () => onToggle(!isEnabled),
            child: GestureDetector(
              onTap: () => onToggle(!isEnabled),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  _ServiceDot(color: _color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serviceKey.title,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _fg,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          // "Not enabled on this setup" read as an external
                          // constraint rather than the user's own choice.
                          isEnabled ? 'Enabled' : 'Off — tap to connect',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 11,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    child: Center(
                      child: _Toggle(isOn: isEnabled, color: _color),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Inline config, built only when the service is on.
          //
          // This was an AnimatedCrossFade, which builds both children: every one
          // of the thirteen cards carried a live config panel — twenty-six text
          // fields and their validator listeners — to show at most one.
          AnimatedSize(
            duration: AppAnimation.durationSm,
            alignment: Alignment.topCenter,
            child: isEnabled
                ? _ServiceConfig(
                    serviceKey: serviceKey,
                    urlCtrl: urlCtrl,
                    apiKeyCtrl: apiKeyCtrl,
                    usernameCtrl: usernameCtrl,
                    passwordCtrl: passwordCtrl,
                    verifyStatus: verifyStatus,
                    verifyReason: verifyReason,
                    verifying: verifying,
                    onVerify: onVerify,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.isOn, required this.color});
  final bool isOn;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimation.durationSm,
      width: 46,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusFull,
        border: Border.all(
          color: isOn ? color.withValues(alpha: 0.4) : const Color(0x14FFFFFF),
        ),
        color: isOn ? color.withValues(alpha: 0.36) : const Color(0x14FFFFFF),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: AppAnimation.durationSm,
            curve: Curves.easeInOut,
            left: isOn ? 18 : 3,
            top: 3,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceConfig extends StatefulWidget {
  const _ServiceConfig({
    required this.serviceKey,
    required this.urlCtrl,
    required this.apiKeyCtrl,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.verifyStatus,
    required this.verifyReason,
    required this.verifying,
    required this.onVerify,
  });

  final ServiceKey serviceKey;
  final TextEditingController urlCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passwordCtrl;
  final ServiceConnectionStatus? verifyStatus;
  final ServiceFailureReason? verifyReason;
  final bool verifying;
  final VoidCallback onVerify;

  @override
  State<_ServiceConfig> createState() => _ServiceConfigState();
}

class _ServiceConfigState extends State<_ServiceConfig> {
  @override
  void didUpdateWidget(_ServiceConfig oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A finished verification adds a badge and a line of explanation at the
    // bottom of the panel — which, on a card near the fold, appeared behind the
    // footer buttons. Scroll the outcome of the tap into view.
    if (oldWidget.verifying && !widget.verifying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _revealInOwnScrollView(context, alignment: 0.9);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceKey = widget.serviceKey;
    final urlCtrl = widget.urlCtrl;
    final apiKeyCtrl = widget.apiKeyCtrl;
    final usernameCtrl = widget.usernameCtrl;
    final passwordCtrl = widget.passwordCtrl;
    final verifyStatus = widget.verifyStatus;
    final verifyReason = widget.verifyReason;
    final verifying = widget.verifying;
    final onVerify = widget.onVerify;

    return Column(
      children: [
        const Divider(height: 28, color: Color(0x0FFFFFFF)),
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.borderRadiusLg,
            color: const Color(0xFF0A0C14),
            border: Border.all(color: const Color(0x12FFFFFF)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${serviceKey.title} configuration',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _fg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Point Seekarr to your ${serviceKey.title} instance and confirm it answers correctly.',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 12,
                  color: _muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              _ConfigField(label: 'Base URL', controller: urlCtrl, isUrl: true),
              if (serviceKey.usesApiKey) ...[
                const SizedBox(height: 10),
                _ConfigField(
                  label: 'API key',
                  controller: apiKeyCtrl,
                  isPassword: true,
                ),
              ] else if (serviceKey == ServiceKey.qbittorrent ||
                  serviceKey == ServiceKey.dockge ||
                  serviceKey == ServiceKey.nzbget) ...[
                const SizedBox(height: 10),
                _ConfigField(
                  label: 'Username (optional)',
                  controller: usernameCtrl,
                  hint: 'Enter username',
                ),
                const SizedBox(height: 10),
                _ConfigField(
                  label: 'Password (optional)',
                  controller: passwordCtrl,
                  isPassword: true,
                  hint: 'Enter password',
                ),
                const SizedBox(height: 10),
                Text(
                  'Leave credentials empty if your ${serviceKey.title} instance does not require authentication.',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    color: _muted,
                    height: 1.5,
                  ),
                ),
              ],
              if (serviceKey == ServiceKey.readarr) ...[
                const SizedBox(height: 10),
                // The settings screen says this; setup — where the choice is
                // actually made — said nothing.
                const Text(
                  'Readarr development has stopped upstream. Existing instances '
                  'keep working against its last released API, but expect no '
                  'new server-side fixes.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    color: _muted,
                    height: 1.5,
                  ),
                ),
              ],
              if (serviceKey == ServiceKey.truenas) ...[
                const SizedBox(height: 10),
                Text(
                  'Requires TrueNAS SCALE $kTrueNasMinVersion or newer.',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    color: _muted,
                    height: 1.5,
                  ),
                ),
              ],
              if (serviceKey == ServiceKey.unraid) ...[
                const SizedBox(height: 10),
                const Text(
                  'Enable the Unraid API first (Settings → Management Access → '
                  'Developer Options → GraphQL sandbox) and create an API key. '
                  'The endpoint stays silent until it is enabled.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    color: _muted,
                    height: 1.5,
                  ),
                ),
              ],
              if (verifyStatus == ServiceConnectionStatus.notConfigured) ...[
                const SizedBox(height: 10),
                Text(
                  serviceKey.usesApiKey
                      ? 'Enter the base URL and the API key, then verify.'
                      : 'Enter the base URL, then verify.',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    color: AppColors.warning,
                    height: 1.5,
                  ),
                ),
              ],
              if (verifyStatus == ServiceConnectionStatus.disconnected) ...[
                const SizedBox(height: 10),
                Text(
                  connectionFailureMessage(serviceKey, verifyReason),
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    color: Color(0xFFFCA5A5),
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Verify row
              Row(
                children: [
                  Expanded(
                    child: _VerifyButton(verifying: verifying, onTap: onVerify),
                  ),
                  const SizedBox(width: 10),
                  _VerifyStatusBadge(
                    status: verifyStatus,
                    verifying: verifying,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConfigField extends StatefulWidget {
  const _ConfigField({
    required this.label,
    required this.controller,
    this.isUrl = false,
    this.isPassword = false,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final bool isUrl;
  final bool isPassword;

  /// Overrides the placeholder. Credential fields must pass this — the default
  /// only makes sense for the API-key field.
  final String? hint;

  @override
  State<_ConfigField> createState() => _ConfigFieldState();
}

class _ConfigFieldState extends State<_ConfigField> {
  String? _error;
  String? _warning;

  /// Secrets start hidden but must be checkable: a 32-character key typed on a
  /// phone keyboard is unverifiable behind dots, and the settings screen already
  /// offers this.
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isUrl) {
      widget.controller.addListener(_validate);
      _validate();
    }
  }

  @override
  void dispose() {
    if (widget.isUrl) widget.controller.removeListener(_validate);
    super.dispose();
  }

  /// Validates the address as it is typed.
  ///
  /// Without this a malformed URL reached the client, which could only report
  /// "Unreachable" — sending the user to hunt for a network fault when the real
  /// problem was a typo. A cleartext address outside the local network is
  /// flagged as a warning rather than an error: it is a supported choice, just
  /// one worth knowing about.
  void _validate() {
    final raw = widget.controller.text;
    final error = raw.trim().isEmpty
        ? null // don't scold an untouched field
        : UrlUtils.validateServiceHost(raw);
    final warning = error == null ? UrlUtils.cleartextWarning(raw) : null;
    if (error == _error && warning == _warning) return;
    setState(() {
      _error = error;
      _warning = warning;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(context),
        if (_error != null || _warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _error != null
                      ? Icons.error_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 13,
                  color: _error != null ? AppColors.error : AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error ?? _warning!,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 11,
                      height: 1.35,
                      color: _error != null
                          ? AppColors.error
                          : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _field(BuildContext context) {
    final label = widget.label;
    final controller = widget.controller;
    final isUrl = widget.isUrl;
    final isPassword = widget.isPassword;
    final hint = widget.hint;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusLg,
        border: Border.all(
          color: _error != null
              ? AppColors.error.withValues(alpha: 0.6)
              : const Color(0x12FFFFFF),
        ),
        color: const Color(0xB8080A10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08 * 10,
              color: _muted2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: isPassword && !_revealed,
                  keyboardType: isUrl ? TextInputType.url : TextInputType.text,
                  textInputAction: isUrl
                      ? TextInputAction.next
                      : TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  // Smart substitutions are off as well as autocorrect: iOS
                  // otherwise rewrites `--` and quotes inside a typed address.
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13,
                    color: Color(0xFFDDE4FA),
                    height: 1.2,
                  ),
                  decoration: InputDecoration(
                    // https by default: the clients normalise a scheme-less host
                    // to TLS, and the old http:// placeholder taught the
                    // opposite.
                    hintText: isUrl
                        ? 'https://your-server:port'
                        : (hint ?? 'Enter API key'),
                    hintStyle: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      color: _muted2,
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    isDense: false,
                    // Every state is borderless: the surrounding container draws
                    // the frame. `border` alone left the app-wide
                    // `focusedBorder` — a 2px indigo outline — painting a second
                    // box inside this one on focus.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (isPassword)
                Semantics(
                  button: true,
                  label: _revealed ? 'Hide $label' : 'Show $label',
                  child: IconButton(
                    onPressed: () => setState(() => _revealed = !_revealed),
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: _muted,
                    ),
                    // 44pt hit target inside a 13pt-padded field.
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: _revealed ? 'Hide $label' : 'Show $label',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerifyButton extends StatelessWidget {
  const _VerifyButton({required this.verifying, required this.onTap});
  final bool verifying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: verifying ? null : onTap,
      semanticLabel: 'Verify service',
      semanticValue: verifying ? 'Verifying' : null,
      excludeChildSemantics: true,
      child: Container(
        // 44pt: the iOS minimum target, which 42 missed.
        height: 44,
        decoration: BoxDecoration(
          borderRadius: _radiusChip,
          border: Border.all(color: const Color(0x14FFFFFF)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x0FFFFFFF), Color(0x05FFFFFF)],
          ),
        ),
        alignment: Alignment.center,
        child: verifying
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _muted),
              )
            : const Text(
                'Verify service',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.02 * 13,
                  color: _fg,
                ),
              ),
      ),
    );
  }
}

class _VerifyStatusBadge extends StatelessWidget {
  const _VerifyStatusBadge({required this.status, required this.verifying});
  final ServiceConnectionStatus? status;
  final bool verifying;

  @override
  Widget build(BuildContext context) {
    if (verifying ||
        status == null ||
        status == ServiceConnectionStatus.checking) {
      return const SizedBox(width: 90, height: 42);
    }

    // An unfilled form is its own outcome. Reporting it as "Unreachable" — the
    // old binary — blamed the network for a field the user simply had not typed
    // into yet, and left nothing to act on.
    final (label, background, foreground) = switch (status!) {
      ServiceConnectionStatus.checking => ('', Colors.transparent, _muted),
      ServiceConnectionStatus.connected => (
        'Reachable',
        const Color(0x1F22C55E),
        const Color(0xFFBFE9CA),
      ),
      ServiceConnectionStatus.notConfigured => (
        'Incomplete',
        const Color(0x1FF59E0B),
        const Color(0xFFFCD9A0),
      ),
      ServiceConnectionStatus.disconnected => (
        'Unreachable',
        const Color(0x1FEF4444),
        const Color(0xFFFCA5A5),
      ),
    };
    return Container(
      width: 90,
      height: 42,
      decoration: BoxDecoration(borderRadius: _radiusChip, color: background),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.08 * 10,
          color: foreground,
        ),
      ),
    );
  }
}

// ─── Step 3: Ready ────────────────────────────────────────────────────────────

/// Row subtitle on the summary step.
///
/// "Configured" alone said only that fields were filled in; it never said
/// whether the instance answers.
String _readySubtitle({
  required bool checking,
  required ServiceConnectionStatus? status,
}) {
  if (checking) return 'Checking the connection…';
  return switch (status) {
    ServiceConnectionStatus.connected => 'Connected',
    ServiceConnectionStatus.disconnected => 'Configured, but not answering',
    _ => 'Configured',
  };
}

/// ONLINE / OFFLINE / spinner for one row of the summary.
class _ReadyStatusChip extends StatelessWidget {
  const _ReadyStatusChip({required this.checking, required this.status});
  final bool checking;
  final ServiceConnectionStatus? status;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: _muted),
      );
    }
    final (label, background, foreground) = switch (status) {
      ServiceConnectionStatus.connected => (
        'ONLINE',
        const Color(0x1F22C55E),
        const Color(0xFFBFE9CA),
      ),
      ServiceConnectionStatus.disconnected => (
        'OFFLINE',
        const Color(0x1FEF4444),
        const Color(0xFFFCA5A5),
      ),
      _ => (null, Colors.transparent, _muted),
    };
    if (label == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusFull,
        color: background,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.08 * 10,
          color: foreground,
        ),
      ),
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({
    required this.configuredServices,
    required this.verifyStatus,
    required this.verifying,
    required this.onReviewSettings,
    required this.onFinish,
  });

  final List<ServiceKey> configuredServices;
  final Map<ServiceKey, ServiceConnectionStatus?> verifyStatus;

  /// Services whose check is still in flight, so the row can say so rather than
  /// looking like a verdict that has not arrived.
  final Map<ServiceKey, bool> verifying;
  final Future<void> Function() onReviewSettings;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _screenPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ProgressBar(step: 2),
          const SizedBox(height: 18),
          // Heading and card scroll together, and only the footer is pinned.
          //
          // Both halves of this used to be fixed: nine connected services
          // overflowed by 151px and pushed "Let's go" off the screen, and a 34pt
          // headline at an accessibility reading size did the same on its own.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _StepLabel('Step 3 of 3'),
                  const SizedBox(height: 8),
                  Text(
                    configuredServices.isEmpty
                        ? 'Ready when you are.'
                        : "You're all set.",
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: _fg,
                      letterSpacing: -0.05 * 34,
                      height: 0.98,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Congratulating someone on connecting nothing read as a bug.
                  // The empty case is legitimate — you can add services later —
                  // so it gets copy that says what actually happened.
                  Text(
                    configuredServices.isEmpty
                        ? 'Nothing is connected yet. Seekarr will stay empty '
                              'until you add a service — you can do that any '
                              'time in Settings.'
                        : 'Your connected services are available and you can '
                              'start using the app right away.',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 14,
                      color: _muted,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: _radiusPanel,
                      border: Border.all(color: const Color(0x0FFFFFFF)),
                      color: const Color(0xD5111521),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Connected services',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _fg,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (configuredServices.isEmpty)
                          const Text(
                            'No services configured — you can add them later in Settings.',
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 13,
                              color: _muted,
                            ),
                          )
                        else
                          ...configuredServices.asMap().entries.map((e) {
                            final idx = e.key;
                            final k = e.value;
                            final isChecking = verifying[k] ?? false;
                            return Column(
                              children: [
                                if (idx > 0)
                                  const Divider(
                                    height: 24,
                                    color: Color(0x14FFFFFF),
                                  ),
                                Row(
                                  children: [
                                    _ServiceDot(color: _serviceColor(k)),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            k.title,
                                            style: const TextStyle(
                                              fontFamily: AppTheme.fontFamily,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: _fg,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _readySubtitle(
                                              checking: isChecking,
                                              status: verifyStatus[k],
                                            ),
                                            style: const TextStyle(
                                              fontFamily: AppTheme.fontFamily,
                                              fontSize: 12,
                                              color: _muted2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _ReadyStatusChip(
                                      checking: isChecking,
                                      status: verifyStatus[k],
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StepFooter(
            secondary: _AsyncButton(
              label: 'Review settings',
              onPressed: onReviewSettings,
            ),
            primary: _AsyncButton(
              label: "Let's go",
              filled: true,
              onPressed: onFinish,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pinned action row at the bottom of a step.
///
/// Side by side, the two labels stop fitting as the reading size grows — the row
/// overflowed by 119px at 2x. Past that point they stack, full width, with the
/// primary action first.
class _StepFooter extends StatelessWidget {
  const _StepFooter({required this.secondary, required this.primary});
  final Widget secondary;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    final labelWidth = MediaQuery.textScalerOf(context).scale(14);
    if (labelWidth > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primary, const SizedBox(height: 10), secondary],
      );
    }
    return Row(
      children: [
        secondary,
        const SizedBox(width: 10),
        Expanded(child: primary),
      ],
    );
  }
}

/// Height for a step's buttons, grown by however much their label grew.
double _buttonHeight(BuildContext context) =>
    TextScaleMetrics.boxHeight(context, base: 48, textHeight: 17);

// ─── Button components ───────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  static const _labelStyle = TextStyle(
    fontFamily: AppTheme.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02 * 14,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: _buttonHeight(context),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
        ),
        child: Text(label, style: _labelStyle),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _buttonHeight(context),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: _fg,
          side: const BorderSide(color: Color(0x14FFFFFF)),
          backgroundColor: const Color(0x08FFFFFF),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.02 * 14,
          ),
        ),
      ),
    );
  }
}

class _AsyncButton extends StatefulWidget {
  const _AsyncButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });
  final String label;
  final Future<void> Function() onPressed;
  final bool filled;

  @override
  State<_AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<_AsyncButton> {
  bool _loading = false;

  static const _labelStyle = TextStyle(
    fontFamily: AppTheme.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02 * 14,
  );

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  @override
  Widget build(BuildContext context) {
    final child = _loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Text(widget.label, style: _labelStyle);

    final onTap = _loading
        ? null
        : () async {
            setState(() => _loading = true);
            try {
              await widget.onPressed();
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          };

    if (widget.filled) {
      return SizedBox(
        height: _buttonHeight(context),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _accent.withValues(alpha: 0.6),
            elevation: 0,
            shape: _shape,
          ),
          child: child,
        ),
      );
    }

    return SizedBox(
      height: _buttonHeight(context),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _fg,
          side: const BorderSide(color: Color(0x14FFFFFF)),
          backgroundColor: const Color(0x08FFFFFF),
          shape: _shape,
        ),
        child: child,
      ),
    );
  }
}

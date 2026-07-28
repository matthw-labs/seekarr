import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/dockge/data/dockge_client.dart';
import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/presentation/widgets/cert_trust_dialog.dart';
import 'package:seekarr/features/truenas/data/truenas_ws_client.dart';
import 'package:seekarr/features/truenas/domain/truenas_version.dart';
import 'package:seekarr/features/unraid/data/unraid_client.dart';

// ─── Design tokens (pixel-faithful to prototype) ───────────────────────────
const _bg = Color(0xFF07080D);
const _border = Color(0xFF283247);
const _fg = Color(0xFFF3F6FF);
const _muted = Color(0xFF98A3B9);
const _muted2 = Color(0xFF647089);
const _accent = AppColors.primary; // brand indigo — single source of truth
const _success = AppColors.success;
const _screenPad = EdgeInsets.fromLTRB(22, 22, 22, 32);

/// Widest the onboarding column is allowed to get. Beyond this a form field's
/// label and its control drift too far apart to read as a pair.
const _contentMaxWidth = 560.0;

/// Service accent, sourced from the app-wide [ServiceKey.accent] so onboarding
/// matches the rest of the app (previously Seerr was mistakenly tinted green).
Color _serviceColor(ServiceKey service) => service.accent;

// ─── Health-check helper (mirrors serviceConnectionProvider logic) ──────────
String _healthEndpoint(ServiceKey service) {
  switch (service) {
    case ServiceKey.seerr:
      return '/api/v1/status';
    case ServiceKey.radarr:
    case ServiceKey.sonarr:
      return '/api/v3/system/status';
    case ServiceKey.lidarr:
      return '/api/v1/system/status';
    case ServiceKey.qbittorrent:
      return '/api/v2/app/version';
    case ServiceKey.bazarr:
      return '/api/system/status';
    case ServiceKey.truenas:
      // TrueNAS verifies over WebSocket, not a REST endpoint.
      return '';
    case ServiceKey.dockge:
      // Dockge verifies over Socket.IO, not a REST endpoint.
      return '';
    case ServiceKey.prowlarr:
      return '/api/v1/system/status';
    case ServiceKey.readarr:
      return '/api/v1/system/status';
    case ServiceKey.sabnzbd:
      // SABnzbd verifies via its query-string API, not a REST endpoint.
      return '';
    case ServiceKey.nzbget:
      // NZBGet verifies via JSON-RPC, not a REST endpoint.
      return '';
    case ServiceKey.unraid:
      // Unraid verifies via a GraphQL query, not a REST endpoint.
      return '';
  }
}

/// Outcome of a verification attempt: the status and, when it failed, why.
///
/// Reachability alone leaves every failure looking identical, so the reason is
/// what lets the UI say "credentials rejected" instead of "check everything".
class _VerifyResult {
  const _VerifyResult(this.status, [this.reason]);

  const _VerifyResult.connected() : this(ServiceConnectionStatus.connected);

  const _VerifyResult.notConfigured()
    : this(ServiceConnectionStatus.notConfigured);

  /// The service answered, but could not be reached again to confirm.
  const _VerifyResult.dropped()
    : this(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.unreachable,
      );

  _VerifyResult.failed(
    Object error, {
    ServiceFailureReason fallback = ServiceFailureReason.unknown,
  }) : this(
         ServiceConnectionStatus.disconnected,
         classifyConnectionFailure(error, fallback: fallback),
       );

  final ServiceConnectionStatus status;

  /// Null unless [status] is `disconnected`.
  final ServiceFailureReason? reason;
}

Future<_VerifyResult> _verifyService(
  ServiceKey service, {
  required String url,
  required String apiKey,
  required String username,
  required String password,
  String certFingerprint = '',
}) async {
  final pin = certFingerprint.trim().isEmpty ? null : certFingerprint.trim();
  if (service == ServiceKey.dockge) {
    final urlTrimmed = url.trim();
    if (urlTrimmed.isEmpty) return const _VerifyResult.notConfigured();
    final client = DockgeClient(
      baseUrl: urlTrimmed,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password.isEmpty ? null : password,
      certFingerprint: pin,
    );
    try {
      final ok = await client.ping().timeout(const Duration(seconds: 8));
      // A rejected login throws with `unauthorized`, so `false` here means the
      // socket dropped after authenticating — a connection fault, not a wrong
      // password. Reporting it as "credentials rejected" sent users to re-type a
      // password that was fine.
      return ok
          ? const _VerifyResult.connected()
          : const _VerifyResult.dropped();
    } catch (e) {
      return _VerifyResult.failed(e);
    } finally {
      await client.close();
    }
  }
  if (service == ServiceKey.nzbget) {
    final urlTrimmed = url.trim();
    if (urlTrimmed.isEmpty) return const _VerifyResult.notConfigured();
    final client = NzbgetClient(
      url: urlTrimmed,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password.isEmpty ? null : password,
    );
    try {
      await client.testConnection().timeout(const Duration(seconds: 6));
      return const _VerifyResult.connected();
    } catch (e) {
      return _VerifyResult.failed(e);
    } finally {
      client.close();
    }
  }
  if (!service.usesApiKey) {
    final urlTrimmed = url.trim();
    if (urlTrimmed.isEmpty) return const _VerifyResult.notConfigured();
    final client = QbittorrentClient(
      url: urlTrimmed,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password.isEmpty ? null : password,
    );
    try {
      // Two round trips (login + version), so allow more than a single hop.
      await client.getVersion().timeout(const Duration(seconds: 8));
      return const _VerifyResult.connected();
    } catch (e) {
      return _VerifyResult.failed(e);
    } finally {
      client.close();
    }
  }
  if (url.trim().isEmpty || apiKey.trim().isEmpty) {
    return const _VerifyResult.notConfigured();
  }
  if (service == ServiceKey.sabnzbd) {
    final client = SabnzbdClient(url: url.trim(), apiKey: apiKey.trim());
    try {
      await client.testConnection().timeout(const Duration(seconds: 6));
      return const _VerifyResult.connected();
    } catch (e) {
      return _VerifyResult.failed(e);
    } finally {
      client.close();
    }
  }
  if (service == ServiceKey.unraid) {
    final client = UnraidClient(url: url.trim(), apiKey: apiKey.trim());
    try {
      await client.testConnection().timeout(const Duration(seconds: 6));
      return const _VerifyResult.connected();
    } catch (e) {
      return _VerifyResult.failed(e);
    } finally {
      client.close();
    }
  }
  if (service == ServiceKey.truenas) {
    final client = TrueNasWsClient(
      baseUrl: url.trim(),
      apiKey: apiKey.trim(),
      certFingerprint: pin,
    );
    try {
      await client.call('core.ping').timeout(const Duration(seconds: 6));
      return const _VerifyResult.connected();
    } catch (e) {
      return _VerifyResult.failed(e);
    } finally {
      await client.close();
    }
  }
  final client = ApiClient(baseUrl: url.trim(), apiKey: apiKey.trim());
  try {
    final code =
        (await client
                .get(_healthEndpoint(service))
                .timeout(const Duration(seconds: 5)))
            .statusCode ??
        0;
    if (code >= 200 && code < 300) return const _VerifyResult.connected();
    return _VerifyResult(
      ServiceConnectionStatus.disconnected,
      reasonForStatusCode(code),
    );
  } catch (e) {
    return _VerifyResult.failed(e);
  } finally {
    client.close();
  }
}

/// Whether a certificate probe could still explain this failure.
///
/// An untrusted certificate surfaces as `tls`, and as `unreachable`/`unknown`
/// when the handshake fails before a reason can be attributed. Anything the
/// server answered — a rejected key, a 404, a 500 — rules the certificate out.
bool _certProbeWorthwhile(ServiceFailureReason? reason) => switch (reason) {
  ServiceFailureReason.unauthorized ||
  ServiceFailureReason.notFound ||
  ServiceFailureReason.serverError => false,
  _ => true,
};

/// User-facing copy for a failed verification. Each cause names the thing the
/// user can actually change.
String _failureMessage(ServiceKey service, ServiceFailureReason? reason) {
  switch (reason) {
    case ServiceFailureReason.unreachable:
      return 'Could not reach the server. Check the address and port, and '
          'that ${service.title} is running and reachable from this device.';
    case ServiceFailureReason.timeout:
      return 'The server did not answer in time. Check the address, or try '
          'again if the instance is just slow to wake up.';
    case ServiceFailureReason.tls:
      // Never suggest downgrading to http:// here. A certificate that fails to
      // verify is the same signal an interception attack produces, and the
      // pinning-capable services already offer the right answer: verify again
      // and confirm the certificate when Seekarr offers to trust it.
      return supportsCertPinning(service)
          ? 'The HTTPS certificate could not be verified. If ${service.title} '
                'uses a self-signed certificate, run Verify again and confirm '
                'the certificate when Seekarr offers to trust it.'
          : 'The HTTPS certificate could not be verified. Check the address, '
                'and that the certificate is valid for this hostname and not '
                'expired.';
    case ServiceFailureReason.unauthorized:
      return service.usesApiKey
          ? 'Reached ${service.title}, which rejected the API key.'
          : 'Reached ${service.title}, which rejected the username or '
                'password.';
    case ServiceFailureReason.notFound:
      return 'Reached the server, but the ${service.title} API is not at this '
          'address. Check for a missing or wrong base path.';
    case ServiceFailureReason.serverError:
      return '${service.title} answered with a server error. Check the '
          'instance and its logs.';
    case ServiceFailureReason.unknown:
    case null:
      return 'Could not verify the instance. Double-check the address and '
          'credentials.';
  }
}

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

  Future<void> _doVerify(ServiceKey service) async {
    setState(() => _verifying[service] = true);
    var result = await _verifyService(
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
    if (result.status == ServiceConnectionStatus.disconnected &&
        _certProbeWorthwhile(result.reason) &&
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
          result = await _verifyService(
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
      _verifying[service] = false;
    });
  }

  Future<void> _saveAndContinue() async {
    final current = ref.read(currentSettingsProvider);
    var updated = current;
    for (final k in ServiceKey.values) {
      if (_isServiceReady(k)) {
        if (k == ServiceKey.qbittorrent) {
          updated = updated.copyWithQbittorrent(
            url: _urlCtrl[k]!.text.trim(),
            username: _usernameCtrl[k]!.text.trim(),
            password: _passwordCtrl[k]!.text,
          );
        } else if (k == ServiceKey.dockge) {
          updated = updated.copyWithDockge(
            url: _urlCtrl[k]!.text.trim(),
            username: _usernameCtrl[k]!.text.trim(),
            password: _passwordCtrl[k]!.text,
          );
        } else if (k == ServiceKey.nzbget) {
          updated = updated.copyWithNzbget(
            url: _urlCtrl[k]!.text.trim(),
            username: _usernameCtrl[k]!.text.trim(),
            password: _passwordCtrl[k]!.text,
          );
        } else {
          updated = updated.copyWithService(
            k,
            url: _urlCtrl[k]!.text.trim(),
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
    _goToStep(2);
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
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
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
              borderRadius: BorderRadius.circular(999),
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
        borderRadius: BorderRadius.circular(22),
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
              borderRadius: BorderRadius.circular(14),
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
                fontFamily: 'Inter',
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
              fontFamily: 'Inter',
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
              fontFamily: 'Inter',
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
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _fg,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                sub,
                style: const TextStyle(
                  fontFamily: 'Inter',
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
          const Text(
            'Step 2 of 3',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08 * 11,
              color: _muted2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect the services you already host.',
            style: TextStyle(
              fontFamily: 'Inter',
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
              fontFamily: 'Inter',
              fontSize: 14,
              color: _muted,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
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
          Row(
            children: [
              _SecondaryButton(label: 'Back', onPressed: onBack),
              const SizedBox(width: 10),
              Expanded(
                child: _AsyncButton(
                  label: 'Continue',
                  filled: true,
                  onPressed: onContinue,
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 200),
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
                      fontFamily: 'Inter',
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
                      borderRadius: BorderRadius.circular(999),
                      color: const Color(0x1F22C55E),
                    ),
                    child: Text(
                      '${widget.enabledCount} on',
                      style: const TextStyle(
                        fontFamily: 'Inter',
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
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(
            children: [
              for (final card in widget.serviceCards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: card,
                ),
            ],
          ),
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
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isEnabled ? _color.withValues(alpha: 0.28) : _border,
        ),
        color: isEnabled ? const Color(0xD5111521) : const Color(0x94111521),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header row
          Row(
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
                        fontFamily: 'Inter',
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
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              // Toggle. Semantics + a 44pt target: this was a bare
              // GestureDetector around a custom switch, so assistive technology
              // saw neither a control nor its on/off state.
              Semantics(
                toggled: isEnabled,
                label: '${serviceKey.title} enabled',
                container: true,
                excludeSemantics: true,
                onTap: () => onToggle(!isEnabled),
                child: GestureDetector(
                  onTap: () => onToggle(!isEnabled),
                  behavior: HitTestBehavior.opaque,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    child: Center(
                      child: _Toggle(isOn: isEnabled, color: _color),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Inline config (animated)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: isEnabled
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _ServiceConfig(
              serviceKey: serviceKey,
              urlCtrl: urlCtrl,
              apiKeyCtrl: apiKeyCtrl,
              usernameCtrl: usernameCtrl,
              passwordCtrl: passwordCtrl,
              verifyStatus: verifyStatus,
              verifyReason: verifyReason,
              verifying: verifying,
              onVerify: onVerify,
              accentColor: _color,
            ),
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
      duration: const Duration(milliseconds: 200),
      width: 46,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isOn ? color.withValues(alpha: 0.4) : const Color(0x14FFFFFF),
        ),
        color: isOn ? color.withValues(alpha: 0.36) : const Color(0x14FFFFFF),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
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

class _ServiceConfig extends StatelessWidget {
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
    required this.accentColor,
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
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 28, color: Color(0x0FFFFFFF)),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _fg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Point Seekarr to your ${serviceKey.title} instance and confirm it answers correctly.',
                style: const TextStyle(
                  fontFamily: 'Inter',
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
                    fontFamily: 'Inter',
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
                    fontFamily: 'Inter',
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
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: _muted,
                    height: 1.5,
                  ),
                ),
              ],
              if (verifyStatus == ServiceConnectionStatus.disconnected) ...[
                const SizedBox(height: 10),
                Text(
                  _failureMessage(serviceKey, verifyReason),
                  style: const TextStyle(
                    fontFamily: 'Inter',
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
        borderRadius: BorderRadius.circular(16),
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
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08 * 10,
              color: _muted2,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: isPassword,
            keyboardType: isUrl ? TextInputType.url : TextInputType.text,
            textInputAction: isUrl
                ? TextInputAction.next
                : TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            // Smart substitutions are off as well as autocorrect: iOS otherwise
            // rewrites `--` and quotes inside an address the user typed.
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              color: Color(0xFFDDE4FA),
              height: 1.2,
            ),
            decoration: InputDecoration(
              // https by default: the clients normalise a scheme-less host to
              // TLS, and the old http:// placeholder taught the opposite.
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
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
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
    return GestureDetector(
      onTap: verifying ? null : onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
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
                  fontFamily: 'Inter',
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
    if (verifying || status == null) {
      return const SizedBox(width: 90, height: 42);
    }

    final isOk = status == ServiceConnectionStatus.connected;
    return Container(
      width: 90,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isOk ? const Color(0x1F22C55E) : const Color(0x1FEF4444),
      ),
      alignment: Alignment.center,
      child: Text(
        isOk ? 'Reachable' : 'Unreachable',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.08 * 10,
          color: isOk ? const Color(0xFFBFE9CA) : const Color(0xFFFCA5A5),
        ),
      ),
    );
  }
}

// ─── Step 3: Ready ────────────────────────────────────────────────────────────
class _ReadyStep extends StatelessWidget {
  const _ReadyStep({
    required this.configuredServices,
    required this.verifyStatus,
    required this.onReviewSettings,
    required this.onFinish,
  });

  final List<ServiceKey> configuredServices;
  final Map<ServiceKey, ServiceConnectionStatus?> verifyStatus;
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
          const Text(
            'Step 3 of 3',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08 * 11,
              color: _muted2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "You're all set.",
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: _fg,
              letterSpacing: -0.05 * 34,
              height: 0.98,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your connected services are available and you can start using the app right away.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: _muted,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          // Connected services card
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
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
                    fontFamily: 'Inter',
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
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: _muted,
                    ),
                  )
                else
                  ...configuredServices.asMap().entries.map((e) {
                    final idx = e.key;
                    final k = e.value;
                    final isConnected =
                        verifyStatus[k] == ServiceConnectionStatus.connected;
                    return Column(
                      children: [
                        if (idx > 0)
                          const Divider(height: 24, color: Color(0x14FFFFFF)),
                        Row(
                          children: [
                            _ServiceDot(color: _serviceColor(k)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    k.title,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: _fg,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    isConnected ? 'Connected' : 'Configured',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      color: _muted2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isConnected)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: const Color(0x1F22C55E),
                                ),
                                child: const Text(
                                  'ONLINE',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.08 * 10,
                                    color: Color(0xFFBFE9CA),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  }),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              _AsyncButton(
                label: 'Review settings',
                onPressed: onReviewSettings,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AsyncButton(
                  label: "Let's go",
                  filled: true,
                  onPressed: onFinish,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Button components ───────────────────────────────────────────────────────
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  static const _labelStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02 * 14,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
      height: 48,
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
            fontFamily: 'Inter',
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
    fontFamily: 'Inter',
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
        height: 48,
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
      height: 48,
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

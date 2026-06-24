import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

// ─── Design tokens (pixel-faithful to prototype) ───────────────────────────
const _bg = Color(0xFF07080D);
const _border = Color(0xFF283247);
const _fg = Color(0xFFF3F6FF);
const _muted = Color(0xFF98A3B9);
const _muted2 = Color(0xFF647089);
const _accent = Color(0xFF6366F1);
const _success = Color(0xFF22C55E);
const _screenPad = EdgeInsets.fromLTRB(22, 22, 22, 32);

// Service-specific colors (from prototype --radarr, --sonarr, --lidarr)
const _serviceColors = {
  ServiceKey.seerr: Color(0xFF22C55E), // green
  ServiceKey.radarr: Color(0xFFF59E0B), // amber
  ServiceKey.sonarr: Color(0xFF8B5CF6), // purple
  ServiceKey.lidarr: Color(0xFFEC4899), // pink
  ServiceKey.qbittorrent: Color(0xFF2F67BA), // blue
  ServiceKey.bazarr: Color(0xFF25A7DF), // bazarr cyan
};

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
  }
}

Future<ServiceConnectionStatus> _verifyService(
  ServiceKey service, {
  required String url,
  required String apiKey,
  required String username,
  required String password,
}) async {
  if (!service.usesApiKey) {
    final urlTrimmed = url.trim();
    if (urlTrimmed.isEmpty) return ServiceConnectionStatus.notConfigured;
    final client = QbittorrentClient(
      url: urlTrimmed,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password.isEmpty ? null : password,
    );
    try {
      await client.getVersion().timeout(const Duration(seconds: 5));
      return ServiceConnectionStatus.connected;
    } catch (_) {
      return ServiceConnectionStatus.disconnected;
    } finally {
      client.close();
    }
  }
  if (url.trim().isEmpty || apiKey.trim().isEmpty) {
    return ServiceConnectionStatus.notConfigured;
  }
  final client = ApiClient(baseUrl: url.trim(), apiKey: apiKey.trim());
  try {
    final code =
        (await client
                .get(_healthEndpoint(service))
                .timeout(const Duration(seconds: 5)))
            .statusCode ??
        0;
    return (code >= 200 && code < 300)
        ? ServiceConnectionStatus.connected
        : ServiceConnectionStatus.disconnected;
  } catch (_) {
    return ServiceConnectionStatus.disconnected;
  } finally {
    client.close();
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
  final Map<ServiceKey, bool> _verifying = {
    for (final k in ServiceKey.values) k: false,
  };

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
    final status = await _verifyService(
      service,
      url: _urlCtrl[service]!.text,
      apiKey: _apiKeyCtrl[service]!.text,
      username: _usernameCtrl[service]!.text,
      password: _passwordCtrl[service]!.text,
    );
    if (!mounted) return;
    setState(() {
      _verifyStatus[service] = status;
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
        } else {
          updated = updated.copyWithService(k, url: '', apiKey: '');
        }
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
            SafeArea(
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
                    verifying: _verifying,
                    onToggle: (k, v) => setState(() {
                      _enabled[k] = v;
                      if (!v) _verifyStatus[k] = null;
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
            'Manage your self-hosted media services from one place.',
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
            'Seekarr is the control surface for the services you run yourself, starting from the Arr stack and giving you one UI to manage requests, libraries, and activity.',
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
            color: Color(0xFF22C55E),
            name: 'Seerr',
            sub: 'Requests and discovery across your stack',
          ),
          const SizedBox(height: 12),
          _StackDivider(),
          const SizedBox(height: 12),
          _StackRow(
            color: Color(0xFF8B5CF6),
            name: 'Sonarr',
            sub: 'Series automation on your instance',
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
                children: ServiceKey.values
                    .map(
                      (k) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ServiceCard(
                          serviceKey: k,
                          isEnabled: enabled[k]!,
                          urlCtrl: urlCtrl[k]!,
                          apiKeyCtrl: apiKeyCtrl[k]!,
                          usernameCtrl: usernameCtrl[k]!,
                          passwordCtrl: passwordCtrl[k]!,
                          verifyStatus: verifyStatus[k],
                          verifying: verifying[k]!,
                          onToggle: (v) => onToggle(k, v),
                          onVerify: () => onVerify(k),
                        ),
                      ),
                    )
                    .toList(),
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

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.serviceKey,
    required this.isEnabled,
    required this.urlCtrl,
    required this.apiKeyCtrl,
    required this.usernameCtrl,
    required this.passwordCtrl,
    required this.verifyStatus,
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
  final bool verifying;
  final ValueChanged<bool> onToggle;
  final VoidCallback onVerify;

  Color get _color => _serviceColors[serviceKey]!;

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
                      isEnabled ? 'Enabled' : 'Not enabled on this setup',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              // Toggle
              GestureDetector(
                onTap: () => onToggle(!isEnabled),
                child: _Toggle(isOn: isEnabled, color: _color),
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
              ] else if (serviceKey == ServiceKey.qbittorrent) ...[
                const SizedBox(height: 10),
                _ConfigField(
                  label: 'Username (optional)',
                  controller: usernameCtrl,
                ),
                const SizedBox(height: 10),
                _ConfigField(
                  label: 'Password (optional)',
                  controller: passwordCtrl,
                  isPassword: true,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Leave credentials empty if your qBittorrent instance does not require authentication.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: _muted,
                    height: 1.5,
                  ),
                ),
              ],
              if (serviceKey == ServiceKey.qbittorrent &&
                  verifyStatus == ServiceConnectionStatus.disconnected) ...[
                const SizedBox(height: 10),
                const Text(
                  'Could not reach the instance. Double-check the URL and credentials.',
                  style: TextStyle(
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

class _ConfigField extends StatelessWidget {
  const _ConfigField({
    required this.label,
    required this.controller,
    this.isUrl = false,
    this.isPassword = false,
  });

  final String label;
  final TextEditingController controller;
  final bool isUrl;
  final bool isPassword;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x12FFFFFF)),
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
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 13,
              color: Color(0xFFDDE4FA),
              height: 1.2,
            ),
            decoration: InputDecoration(
              hintText: isUrl ? 'http://your-server:port' : 'Enter API key',
              hintStyle: const TextStyle(
                fontFamily: 'JetBrains Mono',
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
                            _ServiceDot(color: _serviceColors[k]),
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

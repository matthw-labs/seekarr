import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/data/service_verification.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/connection_presentation.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/presentation/widgets/cert_trust_dialog.dart';
import 'package:seekarr/features/truenas/domain/truenas_version.dart';

/// One service's address and credentials, and the state of that connection.
///
/// This is where a red service gets fixed, so the screen leads with what is
/// wrong: the header states the saved connection in the service's own colour,
/// and a failed test names the actual cause — a rejected key, a wrong base
/// path, an untrusted certificate — rather than listing everything it could be.
class ServiceSettingsScreen extends ConsumerStatefulWidget {
  final ServiceKey service;

  const ServiceSettingsScreen({super.key, required this.service});

  @override
  ConsumerState<ServiceSettingsScreen> createState() =>
      _ServiceSettingsScreenState();
}

class _ServiceSettingsScreenState extends ConsumerState<ServiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  bool _saving = false;
  bool _testing = false;
  bool _revealApiKey = false;

  /// Result of the last "Test connection", or null when it has not been run
  /// since the fields last changed.
  ServiceDiagnosis? _testResult;

  /// Field values as loaded, so leaving with edits can warn instead of silently
  /// discarding them.
  late final Map<String, String> _initialValues;

  ServiceKey get service => widget.service;

  bool get isQbittorrent => service == ServiceKey.qbittorrent;
  bool get isDockge => service == ServiceKey.dockge;
  bool get isNzbget => service == ServiceKey.nzbget;
  bool get isTrueNas => service == ServiceKey.truenas;
  bool get isUnraid => service == ServiceKey.unraid;
  bool get isReadarr => service == ServiceKey.readarr;

  /// Services authenticated with username/password rather than an API key.
  bool get usesCredentials => isQbittorrent || isDockge || isNzbget;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(currentSettingsProvider);
    _urlController = TextEditingController(text: settings.urlFor(service));
    _apiKeyController = TextEditingController(
      text: usesCredentials ? '' : settings.apiKeyFor(service),
    );
    _usernameController = TextEditingController(
      text: usesCredentials ? settings.usernameFor(service) : '',
    );
    _passwordController = TextEditingController(
      text: usesCredentials ? settings.passwordFor(service) : '',
    );

    _initialValues = {
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };
    for (final controller in _controllers.values) {
      controller.addListener(_onFieldChanged);
    }
  }

  Map<String, TextEditingController> get _controllers => {
    'url': _urlController,
    'apiKey': _apiKeyController,
    'username': _usernameController,
    'password': _passwordController,
  };

  /// Whether any field differs from what was loaded.
  bool get _isDirty => _controllers.entries.any(
    (entry) => entry.value.text != _initialValues[entry.key],
  );

  void _onFieldChanged() {
    // A test result describes the values that were tested; once they change it
    // is stale and claiming otherwise would be worse than showing nothing. The
    // header also switches to "unsaved changes" on the first edit, so the row
    // has to rebuild either way.
    setState(() => _testResult = null);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.removeListener(_onFieldChanged);
    }
    _urlController.dispose();
    _apiKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Verifies the values currently in the form without saving them.
  ///
  /// Onboarding has always had this; settings did not, so the only way to find
  /// out whether an edited URL or key worked was to save it and watch the
  /// service list go offline.
  Future<void> _testConnection() async {
    if (_testing || _saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final candidate = _updateServiceSettings(
        ref.read(currentSettingsProvider),
      );
      var result = await diagnoseService(service, candidate);

      // TLS exception flow: when a pinning-capable service failed in a way a
      // certificate could explain, offer to trust it and test again. Skipped
      // once the server has answered — probing for a certificate after a
      // rejected API key is a round trip that can only come back null.
      if (mounted &&
          result.isDisconnected &&
          supportsCertPinning(service) &&
          certProbeWorthwhile(result.reason)) {
        final cert = await probeUntrustedCertificate(
          candidate.urlFor(service),
          pinnedFingerprint: candidate.certFingerprintFor(service),
        );
        if (cert != null && mounted) {
          final trust = await showCertTrustDialog(
            context,
            serviceTitle: service.title,
            certificate: cert,
          );
          if (trust && mounted) {
            await ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  ref
                      .read(currentSettingsProvider)
                      .copyWithCertFingerprint(service, cert.fingerprint),
                );
            if (!mounted) return;
            result = await diagnoseService(
              service,
              _updateServiceSettings(ref.read(currentSettingsProvider)),
            );
          }
        }
      }

      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() => _testResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = ServiceDiagnosis.failed(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Confirms before dropping unsaved edits.
  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Discard changes?',
      message:
          'Your edits to the ${service.title} settings have not been saved.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
      destructive: true,
      dangerNote: '',
    );
    return result.confirmed;
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final current = ref.read(currentSettingsProvider);
    var updated = _updateServiceSettings(current);

    final notifier = ref.read(settingsProvider.notifier);
    await notifier.updateSettings(updated);
    if (!mounted) return;

    // For TLS-pinning services, offer to trust a self-signed certificate so the
    // connection is authenticated rather than blindly accepted. Only prompts
    // when the failure is specifically an untrusted certificate; a reachable
    // server or an unrelated failure just saves as before.
    if (supportsCertPinning(service)) {
      final pinned = await _maybePromptCertTrust(updated, notifier);
      if (!mounted) return;
      if (pinned != null) updated = pinned;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    SnackBarHelper.success(context, '${service.title} settings saved');
  }

  /// Returns the updated settings when the user trusts a certificate, else null.
  Future<SettingsModel?> _maybePromptCertTrust(
    SettingsModel updated,
    SettingsNotifier notifier,
  ) async {
    setState(() => _saving = true);
    try {
      final result = await diagnoseServiceWithCertProbe(service, updated);
      if (!mounted) return null;
      final cert = result.untrustedCertificate;
      if (cert == null) return null;

      final trust = await showCertTrustDialog(
        context,
        serviceTitle: service.title,
        certificate: cert,
      );
      if (!mounted || !trust) return null;

      final pinned = updated.copyWithCertFingerprint(service, cert.fingerprint);
      await notifier.updateSettings(pinned);
      return pinned;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  SettingsModel _updateServiceSettings(SettingsModel current) {
    // Same normalisation onboarding applies, so a trailing slash or a scheme
    // typed in either screen ends up stored the one way the clients use.
    final url = UrlUtils.normalizeBaseUrl(_urlController.text);
    return _writeService(
      current,
      url: url,
      apiKey: _apiKeyController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
    );
  }

  /// Writes this service's fields onto [current].
  ///
  /// Every credential-authenticated service goes through its own `copyWith`,
  /// which is what makes clearing work: routing Dockge or NZBGet through the
  /// API-key path left their saved username and password behind.
  SettingsModel _writeService(
    SettingsModel current, {
    required String url,
    required String apiKey,
    required String username,
    required String password,
  }) {
    if (isQbittorrent) {
      return current.copyWithQbittorrent(
        url: url,
        username: username,
        password: password,
      );
    }
    if (isDockge) {
      return current.copyWithDockge(
        url: url,
        username: username,
        password: password,
      );
    }
    if (isNzbget) {
      return current.copyWithNzbget(
        url: url,
        username: username,
        password: password,
      );
    }
    return current.copyWithService(service, url: url, apiKey: apiKey);
  }

  Future<void> _removeConnection() async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.link_off_rounded,
      title: 'Remove ${service.title}?',
      message:
          'This deletes the saved address and credentials for ${service.title}. '
          'Nothing on the server itself is touched.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!result.confirmed || !mounted) return;

    final cleared = _writeService(
      ref.read(currentSettingsProvider),
      url: '',
      apiKey: '',
      username: '',
      password: '',
    );
    await ref.read(settingsProvider.notifier).updateSettings(cleared);
    if (!mounted) return;

    Navigator.of(context).pop();
    SnackBarHelper.info(context, '${service.title} removed');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Never blocks the iOS back gesture outright — `canPop` stays true unless
      // there is something to lose, and the guard only asks.
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        if (await _confirmDiscard() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(service);

    return AmbientScaffold(
      // The room takes the colour of the service being worked on.
      accent: service.accent,
      appBar: GlassAppBar(
        title: Text('${service.title} Settings'),
        actions: [_buildSaveAction()],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            _buildHeader(context, isConfigured: isConfigured),
            if (_setupNote != null) ...[
              const SizedBox(height: AppSpacing.md),
              _buildInfoNote(context, _setupNote!),
            ],
            const SizedBox(height: AppSpacing.xl),
            _buildUrlField(),
            const SizedBox(height: AppSpacing.lg),
            if (usesCredentials) _buildUsernameField() else _buildApiKeyField(),
            if (usesCredentials) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildPasswordField(),
            ],
            const SizedBox(height: AppSpacing.xl),
            _buildTestConnectionRow(context),
            if (_testResult != null) ...[
              const SizedBox(height: AppSpacing.md),
              _buildTestResult(context, _testResult!),
            ],
            if (isConfigured) ...[
              const SizedBox(height: AppSpacing.xxl),
              _buildRemoveRow(context),
            ],
          ],
        ),
      ),
    );
  }

  /// Per-service setup guidance, where the API needs turning on or the project
  /// itself carries a caveat worth stating before the user types anything.
  String? get _setupNote {
    if (isTrueNas) {
      return 'Requires TrueNAS SCALE $kTrueNasMinVersion or newer. Create an '
          'API key under Credentials → Local Users, and use the https:// '
          'address of the web UI.';
    }
    if (isUnraid) {
      return 'Enable the Unraid API first: Settings → Management Access → '
          'Developer Options → turn on the GraphQL sandbox, then create an API '
          'key under API Keys. Without this the endpoint will not respond.';
    }
    if (isReadarr) {
      // Readarr development stopped upstream. Saying so here is the honest
      // thing: the integration works against the last released API, but the
      // user should know they are pointing at a project that will not receive
      // fixes.
      return 'Readarr development has stopped upstream. Seekarr targets its '
          'last released API, so existing instances keep working, but expect no '
          'new server-side fixes.';
    }
    return null;
  }

  /// The service, its host, and the state of the saved connection.
  ///
  /// Once the form is dirty the saved state no longer describes what is on
  /// screen, so it steps aside rather than contradicting the fields.
  Widget _buildHeader(BuildContext context, {required bool isConfigured}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final serviceTheme = ServiceTheme.fromAccent(service.accent);

    return AppCard.filled(
      accentColor: service.accent,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: serviceTheme.softContainer,
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Icon(service.icon, color: service.accent, size: 24),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  service.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${service.domain.label} · ${service.apiVersion}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_isDirty)
                  _HeaderStatus(
                    icon: Icons.edit_note_rounded,
                    label: 'Unsaved changes',
                    color: colorScheme.onSurfaceVariant,
                  )
                else if (isConfigured)
                  _SavedConnectionStatus(service: service)
                else
                  _HeaderStatus(
                    icon: Icons.add_link_rounded,
                    label: 'Not set up yet',
                    color: colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestConnectionRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final serviceTheme = ServiceTheme.fromAccent(service.accent);

    // Tonal rather than a saturated accent slab. Two reasons, and both hold for
    // all thirteen accents: a full-strength fill in Readarr's red or Unraid's
    // orange reads as a destructive button — outshouting the genuinely
    // destructive "Remove" row below it — and the accent cannot be its own
    // label colour over its own tint (Radarr amber measures ≈1.80:1 there in
    // light theme). The tint carries the identity, `onSurface` carries the
    // words.
    return FilledButton.icon(
      onPressed: _testing || _saving ? null : _testConnection,
      icon: _testing
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onSurface,
              ),
            )
          : const Icon(Icons.wifi_tethering_rounded, size: 18),
      label: Text(_testing ? 'Testing…' : 'Test connection'),
      style: FilledButton.styleFrom(
        // Grows with the reading size instead of clipping its own label: a
        // 46pt button around a 20pt label has 26pt of chrome that must not
        // move when the label does.
        minimumSize: Size.fromHeight(
          TextScaleMetrics.boxHeight(context, base: 46, textHeight: 20),
        ),
        backgroundColor: serviceTheme.softContainer,
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: service.accent.withValues(alpha: 0.28)),
      ),
    );
  }

  Widget _buildTestResult(BuildContext context, ServiceDiagnosis result) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentation = describeConnection(
      service,
      status: result.status,
      reason: result.reason,
    );
    final color = result.isConnected
        ? AppColors.success
        : statusToneColor(colorScheme, presentation.tone);
    final outcome = result.isConnected
        ? 'Connection test succeeded'
        : 'Connection test failed';
    final message = switch (result.status) {
      ServiceConnectionStatus.connected =>
        '${service.title} answered as expected.',
      ServiceConnectionStatus.notConfigured =>
        'Fill in the address and credentials first.',
      ServiceConnectionStatus.disconnected ||
      ServiceConnectionStatus.checking => connectionFailureMessage(
        service,
        result.reason,
      ),
    };

    // A live region rather than an announcement: this panel appears below the
    // button while focus stays on it, so the verdict — the whole point of the
    // action — would otherwise have to be hunted for. `liveRegion` is the
    // mechanism both platforms honour; a programmatic announcement is dropped on
    // Android. The outcome is spelled out because the glyph and the tint are the
    // only things carrying it (the "Fill in the address" message, for one, never
    // says it failed).
    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: '$outcome. $message',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              result.isConnected
                  ? Icons.check_circle_outline_rounded
                  : presentation.icon,
              size: 18,
              color: color,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    result.isConnected ? 'Connected' : presentation.label,
                    style: theme.textTheme.labelLarge?.copyWith(color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoveRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SettingsGroupCard(
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.link_off_rounded),
          title: 'Remove ${service.title}',
          subtitle: 'Deletes the saved address and credentials',
          accentColor: colorScheme.error,
          onTap: _removeConnection,
        ),
      ],
    );
  }

  Widget _buildSaveAction() {
    if (_saving) {
      // Labelled, because the button is replaced rather than disabled: an
      // unlabelled spinner drops the control out of the tree entirely, so the
      // action appears to have vanished mid-save.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Semantics(
          label: 'Saving',
          excludeSemantics: true,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return TextButton.icon(
      onPressed: _saveSettings,
      icon: const Icon(Icons.check_rounded),
      label: const Text('Save'),
    );
  }

  /// A neutral, icon-led information banner used for per-service setup hints.
  Widget _buildInfoNote(BuildContext context, String message) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrlField() {
    // Rebuilds on every keystroke so the cleartext warning tracks the field.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _urlController,
      builder: (context, value, _) {
        final warning = UrlUtils.cleartextWarning(value.text);
        return TextFormField(
          controller: _urlController,
          decoration: InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://',
            helperText: warning,
            helperMaxLines: 3,
            helperStyle: warning == null
                ? null
                : const TextStyle(color: AppColors.warning),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          // iOS otherwise rewrites `--` and quotes inside a typed address.
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          // Same rule as onboarding: a bare host is accepted here too and
          // normalised to HTTPS on save. Two rules for one field meant an
          // address typed during setup was rejected when reopened here.
          validator: UrlUtils.validateServiceHost,
        );
      },
    );
  }

  Widget _buildApiKeyField() {
    return TextFormField(
      controller: _apiKeyController,
      decoration: InputDecoration(
        labelText: 'API Key',
        hintText: 'Enter your API key',
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reveal is offered alongside copy: checking a pasted key by eye
            // should not require putting it on the system clipboard, where any
            // other app can read it.
            IconButton(
              icon: Icon(
                _revealApiKey
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () => setState(() => _revealApiKey = !_revealApiKey),
              tooltip: _revealApiKey ? 'Hide API key' : 'Show API key',
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyApiKey,
              tooltip: 'Copy API key',
            ),
          ],
        ),
      ),
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _saveSettings(),
      obscureText: !_revealApiKey,
      validator: _validateApiKey,
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      decoration: const InputDecoration(
        labelText: 'Username',
        hintText: 'Optional',
      ),
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      autocorrect: false,
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      decoration: const InputDecoration(
        labelText: 'Password',
        hintText: 'Optional',
      ),
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _saveSettings(),
      obscureText: true,
    );
  }

  String? _validateApiKey(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'API Key is required';
    }

    return null;
  }

  void _copyApiKey() {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: apiKey));
      SnackBarHelper.info(context, 'API key copied to clipboard');
    }
  }
}

/// The saved connection's state, watched live so trusting a certificate or
/// saving a new key updates the header without a reload.
class _SavedConnectionStatus extends ConsumerWidget {
  const _SavedConnectionStatus({required this.service});

  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final async = ref.watch(serviceDiagnosisProvider(service));
    final diagnosis = async.when(
      loading: () => const ServiceDiagnosis.checking(),
      error: (_, __) =>
          const ServiceDiagnosis(ServiceConnectionStatus.disconnected),
      data: (value) => value,
    );
    final presentation = describeConnection(
      service,
      status: diagnosis.status,
      reason: diagnosis.reason,
    );

    return _HeaderStatus(
      icon: presentation.icon,
      label: presentation.label,
      color: statusToneColor(colorScheme, presentation.tone),
      busy: diagnosis.status == ServiceConnectionStatus.checking,
    );
  }
}

class _HeaderStatus extends StatelessWidget {
  const _HeaderStatus({
    required this.icon,
    required this.label,
    required this.color,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

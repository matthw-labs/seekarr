import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/presentation/widgets/cert_trust_dialog.dart';
import 'package:seekarr/features/truenas/domain/truenas_version.dart';

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
  ({bool ok, String message})? _testResult;

  /// Field values as loaded, so leaving with edits can warn instead of silently
  /// discarding them.
  late final Map<String, String> _initialValues;

  bool get isQbittorrent => widget.service == ServiceKey.qbittorrent;
  bool get isDockge => widget.service == ServiceKey.dockge;
  bool get isNzbget => widget.service == ServiceKey.nzbget;
  bool get isTrueNas => widget.service == ServiceKey.truenas;
  bool get isUnraid => widget.service == ServiceKey.unraid;

  /// Services whose clients support pinning a self-signed TLS certificate.
  bool get supportsCertPinning => isTrueNas || isDockge;

  /// Services authenticated with username/password rather than an API key.
  bool get usesCredentials => isQbittorrent || isDockge || isNzbget;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(currentSettingsProvider);
    _urlController = TextEditingController(
      text: settings.urlFor(widget.service),
    );
    _apiKeyController = TextEditingController(
      text: usesCredentials ? '' : settings.apiKeyFor(widget.service),
    );
    _usernameController = TextEditingController(
      text: usesCredentials ? settings.usernameFor(widget.service) : '',
    );
    _passwordController = TextEditingController(
      text: usesCredentials ? settings.passwordFor(widget.service) : '',
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
    // is stale and claiming otherwise would be worse than showing nothing.
    if (_testResult != null) setState(() => _testResult = null);
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
      final result = await checkServiceWithCertProbe(widget.service, candidate);
      if (!mounted) return;

      final cert = result.untrustedCertificate;
      if (cert != null) {
        final trust = await showCertTrustDialog(
          context,
          serviceTitle: widget.service.title,
          certificate: cert,
        );
        if (!mounted) return;
        if (trust) {
          await ref
              .read(settingsProvider.notifier)
              .updateSettings(
                ref
                    .read(currentSettingsProvider)
                    .copyWithCertFingerprint(widget.service, cert.fingerprint),
              );
          if (!mounted) return;
          setState(() => _testing = false);
          // Retry now that the certificate is pinned.
          return _testConnection();
        }
      }

      setState(() {
        _testResult = switch (result.status) {
          ServiceConnectionStatus.connected => (
            ok: true,
            message: '${widget.service.title} answered as expected.',
          ),
          ServiceConnectionStatus.notConfigured => (
            ok: false,
            message: 'Fill in the address and credentials first.',
          ),
          ServiceConnectionStatus.disconnected ||
          ServiceConnectionStatus.checking => (
            ok: false,
            message:
                'Could not reach ${widget.service.title} with these settings. '
                'Check the address, the credentials, and that the instance is '
                'running.',
          ),
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = (ok: false, message: 'Test failed: $e'));
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
          'Your edits to the ${widget.service.title} settings have not been '
          'saved.',
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
    if (supportsCertPinning) {
      final pinned = await _maybePromptCertTrust(updated, notifier);
      if (!mounted) return;
      if (pinned != null) updated = pinned;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    SnackBarHelper.success(context, '${widget.service.title} settings saved');
  }

  /// Returns the updated settings when the user trusts a certificate, else null.
  Future<SettingsModel?> _maybePromptCertTrust(
    SettingsModel updated,
    SettingsNotifier notifier,
  ) async {
    setState(() => _saving = true);
    try {
      final result = await checkServiceWithCertProbe(widget.service, updated);
      if (!mounted) return null;
      final cert = result.untrustedCertificate;
      if (cert == null) return null;

      final trust = await showCertTrustDialog(
        context,
        serviceTitle: widget.service.title,
        certificate: cert,
      );
      if (!mounted || !trust) return null;

      final pinned = updated.copyWithCertFingerprint(
        widget.service,
        cert.fingerprint,
      );
      await notifier.updateSettings(pinned);
      return pinned;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  SettingsModel _updateServiceSettings(SettingsModel current) {
    if (isQbittorrent) {
      return current.copyWithQbittorrent(
        url: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );
    }
    if (isDockge) {
      return current.copyWithDockge(
        url: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );
    }
    if (isNzbget) {
      return current.copyWithNzbget(
        url: _urlController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );
    }
    return current.copyWithService(
      widget.service,
      url: _urlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
    );
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
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.service.title} Settings'),
        actions: [_buildSaveAction()],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _buildHeader(context),
            if (isTrueNas) ...[
              const SizedBox(height: AppSpacing.md),
              _buildTrueNasVersionNote(context),
            ],
            if (isUnraid) ...[
              const SizedBox(height: AppSpacing.md),
              _buildInfoNote(
                context,
                'Enable the Unraid API first: Settings → Management Access → '
                'Developer Options → turn on the GraphQL sandbox, then create an '
                'API key under API Keys. Without this the endpoint will not '
                'respond.',
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
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
          ],
        ),
      ),
    );
  }

  Widget _buildTestConnectionRow(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _testing || _saving ? null : _testConnection,
      icon: _testing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.wifi_tethering_rounded, size: 18),
      label: Text(_testing ? 'Testing…' : 'Test connection'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        foregroundColor: widget.service.accent,
      ),
    );
  }

  Widget _buildTestResult(
    BuildContext context,
    ({bool ok, String message}) result,
  ) {
    final theme = Theme.of(context);
    final color = result.ok ? AppColors.success : theme.colorScheme.error;

    return Container(
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
            result.ok
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              result.message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveAction() {
    if (_saving) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return TextButton.icon(
      onPressed: _saveSettings,
      icon: const Icon(Icons.check_rounded),
      label: const Text('Save'),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SectionHeader(
      title: widget.service.title,
      // The service's own accent, not colorScheme.primary: the settings list one
      // screen back shows Radarr amber, and this header showed the same icon in
      // indigo.
      trailing: Icon(widget.service.icon, color: widget.service.accent),
    );
  }

  Widget _buildTrueNasVersionNote(BuildContext context) {
    return _buildInfoNote(
      context,
      'Requires TrueNAS SCALE $kTrueNasMinVersion or newer. Create an '
      'API key under Credentials → Local Users, and use the '
      'https:// address of the web UI.',
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
        borderRadius: BorderRadius.circular(AppSpacing.md),
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
          validator: UrlUtils.validateServiceUrl,
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

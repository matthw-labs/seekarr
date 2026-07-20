import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/utils/url_utils.dart';
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

  bool get isQbittorrent => widget.service == ServiceKey.qbittorrent;
  bool get isDockge => widget.service == ServiceKey.dockge;
  bool get isTrueNas => widget.service == ServiceKey.truenas;

  /// Services whose clients support pinning a self-signed TLS certificate.
  bool get supportsCertPinning => isTrueNas || isDockge;

  /// Services authenticated with username/password rather than an API key.
  bool get usesCredentials => isQbittorrent || isDockge;

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
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
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
    return current.copyWithService(
      widget.service,
      url: _urlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: AppSpacing.lg),
            _buildUrlField(),
            const SizedBox(height: AppSpacing.lg),
            if (usesCredentials)
              _buildUsernameField()
            else
              _buildApiKeyField(),
            if (usesCredentials) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildPasswordField(),
            ],
          ],
        ),
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
      trailing: Icon(
        widget.service.icon,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildTrueNasVersionNote(BuildContext context) {
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
              'Requires TrueNAS SCALE $kTrueNasMinVersion or newer. Create an '
              'API key under Credentials → Local Users, and use the '
              'https:// address of the web UI.',
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
    return TextFormField(
      controller: _urlController,
      decoration: const InputDecoration(
        labelText: 'Server URL',
        hintText: 'https://',
      ),
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      validator: UrlUtils.validateServiceUrl,
    );
  }

  Widget _buildApiKeyField() {
    return TextFormField(
      controller: _apiKeyController,
      decoration: InputDecoration(
        labelText: 'API Key',
        hintText: 'Enter your API key',
        suffixIcon: IconButton(
          icon: const Icon(Icons.copy),
          onPressed: _copyApiKey,
          tooltip: 'Copy API key',
        ),
      ),
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _saveSettings(),
      obscureText: true,
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

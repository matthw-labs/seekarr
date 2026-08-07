import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/platform/secure_clipboard.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/release_search/presentation/widgets/search_headroom_card.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/stream/presentation/widgets/jellyfin_viewer_picker.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_dialog.dart';

/// One service's address and credentials, and the state of that connection.
///
/// This is where a red service gets fixed, so the screen leads with what is
/// wrong: the header states the saved connection in the service's own colour,
/// and a failed test names the actual cause — a rejected key, a wrong base
/// path, an untrusted certificate — rather than listing everything it could be.
class ServiceSettingsScreen extends ConsumerStatefulWidget {
  final ServiceKey service;

  /// Injectable so a widget test can stay off a real socket — see
  /// [CertificateProber].
  final CertificateProber certificateProber;

  const ServiceSettingsScreen({
    super.key,
    required this.service,
    this.certificateProber = probeUntrustedCertificate,
  });

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

  bool get isPlex => service == ServiceKey.plex;

  /// Services authenticated with username/password rather than an API key.
  ///
  /// The registry owns this fact — see [ServiceKeyExtension.usesApiKey]. Spelled
  /// out here as its own three-way check, adding a credential-authenticated
  /// service meant this screen and the persistence layer could disagree about
  /// which fields the service even has.
  bool get usesCredentials => !service.usesApiKey;

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

      // TLS exception flow: when the failure could be explained by a
      // certificate, offer to trust it and test again. Every service can
      // reach this since ADR-6. Skipped once the server has answered —
      // probing for a certificate after a rejected API key is a round trip
      // that can only come back null.
      if (mounted &&
          result.isDisconnected &&
          certProbeWorthwhile(result.reason)) {
        final url = candidate.urlFor(service);
        final previousPin = candidate.pinForUrl(url);
        final probe = await widget.certificateProber(
          url,
          pinnedFingerprint: previousPin ?? '',
        );
        if (probe != null && mounted) {
          final trust = await showCertTrustDialog(
            context,
            origin: UrlUtils.certOrigin(url) ?? url,
            probe: probe,
            previousFingerprint: previousPin,
            sharedWith: candidate
                .servicesSharingOriginOf(url)
                .where((s) => s != service)
                .toList(),
          );
          if (trust && mounted) {
            await ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  ref
                      .read(currentSettingsProvider)
                      .copyWithTrustedCertificate(
                        url: url,
                        fingerprint: probe.certificate.fingerprint,
                      ),
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
    // Captured before the write: an edited URL moves this service off an origin
    // whose certificate may have been pinned, and `_maybePromptCertTrust` below
    // can only ever *add* a pin. Left behind, the entry outlives the address —
    // and because `pinForUrl` is keyed purely by origin, any service later
    // pointed back at it would silently reuse the stale trust with no prompt.
    final priorUrl = current.urlFor(service);
    var updated = _updateServiceSettings(
      current,
    ).copyWithoutUnusedCertificate(priorUrl);

    final notifier = ref.read(settingsProvider.notifier);
    await notifier.updateSettings(updated);
    if (!mounted) return;

    // Offer to trust a self-signed certificate so the connection is
    // authenticated rather than blindly accepted. Only prompts when the
    // failure is specifically an untrusted certificate; a reachable server or
    // an unrelated failure just saves as before.
    final pinned = await _maybePromptCertTrust(updated, notifier);
    if (!mounted) return;
    if (pinned != null) updated = pinned;

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
      final result = await diagnoseServiceWithCertProbe(
        service,
        updated,
        probe: widget.certificateProber,
      );
      if (!mounted) return null;
      final probe = result.certificateProbe;
      if (probe == null) return null;

      final url = updated.urlFor(service);
      final trust = await showCertTrustDialog(
        context,
        origin: UrlUtils.certOrigin(url) ?? url,
        probe: probe,
        previousFingerprint: updated.pinForUrl(url),
        sharedWith: updated
            .servicesSharingOriginOf(url)
            .where((s) => s != service)
            .toList(),
      );
      if (!mounted || !trust) return null;

      final pinned = updated.copyWithTrustedCertificate(
        url: url,
        fingerprint: probe.certificate.fingerprint,
      );
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
  /// Which of the two shapes to write is the registry's answer — one branch on
  /// the capability rather than a per-service chain. Routing a
  /// credential-authenticated service through the API-key path is what used to
  /// leave a saved username and password behind on a clear.
  SettingsModel _writeService(
    SettingsModel current, {
    required String url,
    required String apiKey,
    required String username,
    required String password,
  }) {
    if (usesCredentials) {
      return current.copyWithCredentials(
        service,
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

    final before = ref.read(currentSettingsProvider);
    final priorUrl = before.urlFor(service);
    final cleared =
        _writeService(before, url: '', apiKey: '', username: '', password: '')
            // The `{url, apiKey}` pair is not all of what described that server:
            // Jellyfin's chosen viewer sits outside it, and carrying it over to a
            // *different* Jellyfin binds every per-viewer query to a user id that
            // does not exist there.
            .copyWithoutServiceExtras(service)
            // Forget this origin's pin too, but only when nothing else configured
            // still reaches it — removing Sonarr must never break Radarr's trust
            // in the same reverse proxy.
            .copyWithoutUnusedCertificate(priorUrl);

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
            // Setup guidance is registry data, alongside the default port and
            // the credential breadcrumb this screen already reads from there.
            if (service.setupNote case final note?) ...[
              const SizedBox(height: AppSpacing.md),
              _buildInfoNote(context, note),
            ],
            const SizedBox(height: AppSpacing.xl),
            _buildUrlField(),
            _buildTrustedCertificateIndicator(settings),
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
            // Directly under the connection test, because the ceiling is a
            // property of *this instance's path* — a stack can easily have Sonarr
            // behind a proxy and Radarr direct over Tailscale.
            if (SearchHeadroomCard.appliesTo(widget.service)) ...[
              const SizedBox(height: AppSpacing.lg),
              SearchHeadroomCard(service: widget.service),
            ],
            // A capability check, the same shape as `appliesTo` two lines up:
            // the picker belongs to any service whose library has to be entered
            // through a person, not to "Jellyfin" by name. Only once a
            // connection exists, because the viewer list comes from `/Users` on
            // the server — offering it before there is a server to ask would be
            // a control that can only fail.
            if (service.needsViewerSelection && isConfigured) ...[
              const SizedBox(height: AppSpacing.xxl),
              const JellyfinViewerPicker(),
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
                  style: theme.textTheme.titleMedium!.weight(FontWeight.w700),
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
      // `messageFor`, not `connectionFailureMessage`: a failure that already
      // reached its own verdict (a refused cross-origin redirect naming where
      // it was sent) says so verbatim, and everything else falls back to the
      // reason-derived sentence exactly as before.
      ServiceConnectionStatus.disconnected ||
      ServiceConnectionStatus.checking => result.messageFor(service),
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
            hintText: 'https://your-server:${service.defaultPort}',
            // The default port comes from the registry, so this screen and
            // onboarding cannot disagree about it. The cleartext warning wins
            // the helper slot when it fires — a live problem outranks a hint.
            helperText:
                warning ??
                "${service.title}'s default port is "
                    '${service.defaultPort}.',
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

  /// A standing confirmation that this address's origin has a trusted
  /// self-signed certificate, with a way to revoke it.
  ///
  /// Rebuilds on every keystroke of the URL field — [settings] is captured
  /// from the enclosing build, but the origin a trust decision applies to
  /// depends on what is actually typed, which the saved value may no longer
  /// match. Renders nothing for the overwhelming majority of services, which
  /// reach a certificate the OS already trusts and have never pinned one.
  Widget _buildTrustedCertificateIndicator(SettingsModel settings) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _urlController,
      builder: (context, value, _) {
        final rawUrl = value.text;
        final pin = settings.pinForUrl(rawUrl);
        if (pin == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final origin = displayOrigin(UrlUtils.certOrigin(rawUrl) ?? rawUrl);
        final sharedWith = settings
            .servicesSharingOriginOf(rawUrl)
            .where((s) => s != service)
            .toList();

        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  sharedWith.isEmpty
                      ? 'Trusted self-signed certificate for $origin.'
                      : 'Trusted self-signed certificate for $origin — also '
                            'covers ${sharedWith.map((s) => s.title).join(', ')}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _forgetCertificate(rawUrl),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
                child: const Text('Forget'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Revokes the trusted certificate for [rawUrl]'s origin, after naming
  /// every other configured service the revocation also affects.
  Future<void> _forgetCertificate(String rawUrl) async {
    final settings = ref.read(currentSettingsProvider);
    final sharedWith = settings
        .servicesSharingOriginOf(rawUrl)
        .where((s) => s != service)
        .toList();

    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.gpp_bad_outlined,
      title: 'Forget this certificate?',
      message: sharedWith.isEmpty
          ? 'The next connection to this address will need to be trusted '
                'again.'
          : 'This also affects ${sharedWith.map((s) => s.title).join(', ')} '
                '— the next connection from any of them will need to be '
                'trusted again.',
      confirmLabel: 'Forget',
      destructive: true,
      // Reversible — the next connection re-offers the trust prompt — so the
      // default "This cannot be undone." would overstate the stakes.
      dangerNote: '',
    );
    if (!result.confirmed || !mounted) return;

    final updated = settings.copyWithTrustedCertificate(
      url: rawUrl,
      fingerprint: '',
    );
    await ref.read(settingsProvider.notifier).updateSettings(updated);
    if (!mounted) return;
    SnackBarHelper.info(context, 'Certificate forgotten');
  }

  Widget _buildApiKeyField() {
    final credentialPath = service.credentialPath;
    return TextFormField(
      controller: _apiKeyController,
      decoration: InputDecoration(
        labelText: service.credentialLabel,
        hintText: isPlex ? 'X-Plex-Token' : 'Enter your API key',
        // Where the credential lives inside the service's own interface. Same
        // registry fact onboarding shows under the same field, so someone who
        // set this up once recognises the breadcrumb when they come back to fix
        // it.
        helperText: credentialPath == null
            ? null
            : '${service.title} → $credentialPath',
        helperMaxLines: 2,
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
      decoration: InputDecoration(
        labelText: service.usernameLabel,
        // Optional for the download clients, which commonly run without auth
        // behind a reverse proxy. Nginx Proxy Manager is the exception: there
        // is no anonymous mode, and its login needs an email address.
        hintText: service == ServiceKey.nginxProxyManager
            ? 'The email you sign in with'
            : 'Optional',
      ),
      keyboardType: service == ServiceKey.nginxProxyManager
          ? TextInputType.emailAddress
          : TextInputType.text,
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
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return isPlex ? 'Plex token is required' : 'API Key is required';
    }

    // A Plex JSON Web Token expires after seven days and can only be renewed by
    // calling plex.tv, which this app never does. Accepting one would produce
    // software that works for a week and then fails with a 401 the user has no
    // way to interpret — so it is refused at the point of paste, where the
    // message can still say what to paste instead.
    if (isPlex && trimmed.startsWith('eyJ')) {
      return 'That is a temporary token — it expires in 7 days and Cupola '
          'cannot renew it. Paste a device token instead.';
    }

    return null;
  }

  /// How long a copied credential is left on the clipboard.
  ///
  /// Long enough to switch apps and paste, short enough that it is not still
  /// sitting there an hour later. Password managers land in the same range.
  static const Duration _copiedCredentialLifetime = Duration(seconds: 45);

  Future<void> _copyApiKey() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;

    // Two layers, in order of how much they actually protect. The host's own
    // sensitive-clip flags come first — they are the only thing that keeps the
    // key out of Android's copy preview and off Universal Clipboard — and a
    // plain copy is the fallback for every platform and OS version that has no
    // such flag, because a copy button that refuses to copy is worse than an
    // unhardened one. Either way the timed clear below still runs.
    final hardened = await SecureClipboard.copySecret(
      apiKey,
      expiresIn: _copiedCredentialLifetime,
    );
    if (!hardened) {
      await Clipboard.setData(ClipboardData(text: apiKey));
    }
    if (!mounted) return;
    // The wording is part of the mitigation, not chrome: the clipboard is a
    // shared surface — Android 13+ renders a preview of what was copied, and on
    // Apple platforms the general pasteboard syncs to the user's other devices
    // through Universal Clipboard — so the honest thing is to say the key left
    // the app and when it will be taken back.
    SnackBarHelper.info(
      context,
      'API key copied — the clipboard is cleared in '
      '${_copiedCredentialLifetime.inSeconds} seconds',
    );
    unawaited(_expireCopiedCredential(apiKey));
  }

  /// Takes [secret] back off the clipboard once it has had time to be pasted.
  ///
  /// Runs whether or not [SecureClipboard] hardened the copy, and it is the only
  /// half of this that runs at all on Android 12 and below, where there is no
  /// `EXTRA_IS_SENSITIVE` to set. Of the flagged platforms only iOS can expire a
  /// clip by itself, so this stays the thing that bounds how long the key sits
  /// there everywhere else.
  ///
  /// Static, and deliberately not tied to this widget's lifetime: leaving the
  /// screen is not a reason to leave a credential on the clipboard.
  ///
  /// The read-back only *spares* a clipboard it can actually see holding
  /// something else — the user copying over the key in the meantime, which is
  /// worth not destroying. An unreadable clipboard is cleared, not spared:
  /// since Android 10 `getPrimaryClip` answers null to any app that does not
  /// have window focus, and 45 seconds after the copy the user is by
  /// construction in the app they left to paste into. Treating that null as
  /// "something else is on the clipboard" is what used to make this never fire
  /// on Android in exactly the case it exists for, under a SnackBar promising
  /// it would.
  static Future<void> _expireCopiedCredential(String secret) async {
    await Future<void>.delayed(_copiedCredentialLifetime);
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current != null && current.text != secret) return;
    await Clipboard.setData(const ClipboardData(text: ''));
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
              style: theme.textTheme.labelMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

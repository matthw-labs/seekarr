import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/app_bottom_sheet.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/features/onboarding/data/onboarding_provider.dart';
import 'package:seekarr/features/settings/data/donation_service.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/regions.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/presentation/widgets/donation_sheet.dart';

class SettingsHomeScreen extends ConsumerWidget {
  const SettingsHomeScreen({super.key});

  static final Uri _githubUri = Uri.parse(
    'https://github.com/matthw-labs/seekarr',
  );
  static final Uri _feedbackUri = Uri(
    scheme: 'mailto',
    path: 'matthw.labs@gmail.com',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );
    final content = [
      ..._buildGeneralSection(context, settings),
      const SizedBox(height: AppSpacing.lg),
      ..._buildServicesSection(context, ref, settings),
      const SizedBox(height: AppSpacing.lg),
      ..._buildAboutSection(context),
      const SizedBox(height: AppSpacing.lg),
      ..._buildDangerZoneSection(context, ref),
    ];

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Settings')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                bottomPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGeneralSection(
    BuildContext context,
    SettingsModel settings,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return [
      const _SettingsSectionLabel('General'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          SettingsCard.grouped(
            leading: const Icon(Icons.language_rounded),
            title: 'Region',
            subtitle: _formatRegionLabel(settings.region),
            accentColor: AppColors.success,
            onTap: () => context.push('/settings/region'),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.palette_rounded),
            title: 'Appearance',
            subtitle: settings.themeMode.label,
            onTap: () => context.push('/settings/appearance'),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.apps_rounded),
            title: 'Dashboard',
            subtitle: 'All services',
            accentColor: colorScheme.primary,
            onTap: () => context.push('/settings/services'),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildServicesSection(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
  ) {
    final configured = ServiceKey.values
        .where((s) => settings.isServiceConfigured(s))
        .toList();

    if (configured.isEmpty) return [];

    return [
      const _SettingsSectionLabel('Services'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          for (final service in configured)
            SettingsCard.grouped(
              leading: Icon(service.icon),
              title: service.title,
              subtitle: _getServiceSubtitle(settings, service),
              accentColor: service.accent,
              subtitleLeading: _buildConnectionIndicator(
                context,
                ref,
                settings,
                service,
              ),
              onTap: () =>
                  context.push('/settings/service/${service.routeParam}'),
            ),
        ],
      ),
    ];
  }

  Widget? _buildConnectionIndicator(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
    ServiceKey service,
  ) {
    // No indicator when the service isn't configured yet.
    if (settings.urlFor(service).isEmpty) {
      return null;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final asyncStatus = ref.watch(serviceConnectionProvider(service));
    const checkingIndicator = SizedBox(
      width: 14,
      height: 14,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    final disconnectedIndicator = Icon(
      Icons.cloud_off_rounded,
      size: 16,
      color: colorScheme.error,
    );

    return asyncStatus.when(
      loading: () => checkingIndicator,
      error: (_, __) => disconnectedIndicator,
      data: (status) {
        switch (status) {
          case ServiceConnectionStatus.connected:
            return Icon(
              Icons.cloud_done_rounded,
              size: 16,
              color: service.accent,
            );
          case ServiceConnectionStatus.disconnected:
            return disconnectedIndicator;
          case ServiceConnectionStatus.checking:
            return checkingIndicator;
          case ServiceConnectionStatus.notConfigured:
            return null;
        }
      },
    );
  }

  List<Widget> _buildAboutSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return [
      const _SettingsSectionLabel('About'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          SettingsCard.grouped(
            leading: const Icon(Icons.share_rounded),
            title: 'Share App',
            accentColor: AppColors.success,
            onTap: () => SnackBarHelper.info(context, 'Coming soon!'),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.code_rounded),
            title: 'GitHub',
            accentColor: colorScheme.onSurfaceVariant,
            onTap: () => _openGitHub(context),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.feedback_rounded),
            title: 'Send Feedback',
            accentColor: AppColors.warning,
            onTap: () => _sendFeedback(context),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.favorite_rounded),
            title: 'Support Development',
            subtitle: 'Buy me a coffee',
            accentColor: AppColors.lidarr,
            onTap: () => _openDonation(context),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildDangerZoneSection(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return [
      const _SettingsSectionLabel('Danger Zone'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          SettingsCard.grouped(
            leading: const Icon(Icons.restart_alt_rounded),
            title: 'Reset app data',
            subtitle: 'Clear all services, settings, and restart onboarding',
            accentColor: colorScheme.error,
            onTap: () => _confirmReset(context, ref),
          ),
        ],
      ),
    ];
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.warning_amber_rounded,
      title: 'Reset all data?',
      message:
          'This clears all saved services, credentials, and preferences. '
          'Onboarding will restart. This cannot be undone.',
      confirmLabel: 'Reset',
      destructive: true,
    );

    if (!result.confirmed) return;

    try {
      await ref.read(settingsProvider.notifier).resetSettings();
      await markOnboardingIncomplete(ref);
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, "Couldn't reset app data. ($e)");
    }
  }

  String _getServiceSubtitle(SettingsModel settings, ServiceKey service) {
    final url = settings.urlFor(service);
    return url.isEmpty ? 'Not configured' : service.extractHost(url) ?? url;
  }

  String _formatRegionLabel(String region) {
    final normalizedRegion = SettingsModel.normalizeRegion(region);
    final regionName = commonRegions[normalizedRegion] ?? normalizedRegion;
    return '$regionName ($normalizedRegion)';
  }

  Future<void> _openGitHub(BuildContext context) {
    return _launchExternalUri(
      context: context,
      uri: _githubUri,
      failureMessage: 'Unable to open the GitHub repository.',
    );
  }

  Future<void> _sendFeedback(BuildContext context) {
    return _launchExternalUri(
      context: context,
      uri: _feedbackUri,
      failureMessage: 'Unable to open the email composer.',
    );
  }

  Future<void> _openDonation(BuildContext context) async {
    if (DonationService.usesIAP) {
      final useFallback = await AppBottomSheet.show<bool>(
        context: context,
        title: 'Support Seekarr',
        icon: Icons.favorite_rounded,
        builder: (_) => const DonationSheet(),
      );
      // Sheet returned true when IAP products aren't available — open Ko-fi.
      if (useFallback == true && context.mounted) {
        final launched = await DonationService.launchKofi();
        if (!launched && context.mounted) {
          SnackBarHelper.info(context, 'Unable to open the donation page.');
        }
      }
    } else {
      final launched = await DonationService.launchKofi();
      if (!launched && context.mounted) {
        SnackBarHelper.info(context, 'Unable to open the donation page.');
      }
    }
  }

  Future<void> _launchExternalUri({
    required BuildContext context,
    required Uri uri,
    required String failureMessage,
  }) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      SnackBarHelper.info(context, failureMessage);
    }
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String title;

  const _SettingsSectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          fontSize: 11,
        ),
      ),
    );
  }
}

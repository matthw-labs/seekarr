import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/donation_service.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/regions.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/donation_sheet.dart';
import 'package:cupola/features/settings/presentation/widgets/service_connection_row.dart';

/// The settings index.
///
/// Connections lead, and they lead *by exception*: with thirteen services, a
/// list of the healthy ones is an inventory nobody reads, so the summary states
/// the count and only failing services get a row of their own. Everything else
/// on this screen is a preference.
class SettingsHomeScreen extends ConsumerWidget {
  const SettingsHomeScreen({super.key});

  /// The most failing services to name on this screen before deferring to the
  /// connections list. Past a handful the cause is usually one thing — the VPN
  /// is down, the host is asleep — and a wall of red rows says it no better.
  static const int _maxPromotedFailures = 3;

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

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Settings')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          const _ConnectionsBlock(),
          const SizedBox(height: AppSpacing.xl),
          ..._buildGeneralSection(context, ref, settings),
          const SizedBox(height: AppSpacing.xl),
          ..._buildAboutSection(context),
          const SizedBox(height: AppSpacing.xl),
          ..._buildDangerZoneSection(context, ref),
        ],
      ),
    );
  }

  List<Widget> _buildGeneralSection(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
  ) {
    return [
      const SettingsSectionLabel('General'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          SettingsCard.grouped(
            leading: const Icon(Icons.language_rounded),
            title: 'Region',
            subtitle: _formatRegionLabel(settings.region),
            accentColor: AppColors.success,
            semanticHint: 'opens the region picker',
            onTap: () => context.push('/settings/region'),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.palette_rounded),
            title: 'Appearance',
            subtitle: settings.themeMode.label,
            semanticHint: 'opens the appearance picker',
            onTap: () => context.push('/settings/appearance'),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.travel_explore_rounded),
            title: 'Background search',
            subtitle: 'How long to wait, and how many at once',
            semanticHint: 'opens background release search settings',
            onTap: () => context.push('/settings/background-search'),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.replay_rounded),
            title: 'Revisit onboarding',
            subtitle: 'Walk through the intro screens again',
            semanticHint: 'restarts the onboarding flow for this session',
            onTap: () => _confirmRevisitOnboarding(context, ref),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildAboutSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return [
      const SettingsSectionLabel('About'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(
        children: [
          SettingsCard.grouped(
            leading: const Icon(Icons.code_rounded),
            title: 'GitHub',
            subtitle: 'Source, issues and releases',
            accentColor: colorScheme.onSurfaceVariant,
            semanticHint: 'opens the repository in your browser',
            onTap: () => _openGitHub(context),
          ),
          SettingsCard.grouped(
            leading: const Icon(Icons.feedback_rounded),
            title: 'Send Feedback',
            subtitle: 'Email the developer',
            accentColor: AppColors.warning,
            semanticHint: 'opens your email composer',
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
      const SettingsSectionLabel('Danger Zone'),
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

  Future<void> _confirmRevisitOnboarding(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.replay_rounded,
      title: 'Revisit onboarding?',
      message:
          "You'll go through the intro screens again for this session. "
          'Nothing about your services or settings is changed or removed.',
      confirmLabel: 'Continue',
    );

    if (!result.confirmed) return;

    await markOnboardingIncomplete(ref);
    if (!context.mounted) return;
    context.go('/onboarding');
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
        title: 'Support Cupola',
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

/// The connections summary and, under it, the services that need attention.
class _ConnectionsBlock extends ConsumerWidget {
  const _ConnectionsBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = ref.watch(currentSettingsProvider);
    final configured = ServiceKey.values
        .where(settings.isServiceConfigured)
        .toList(growable: false);

    var checking = 0;
    final failing = <ServiceKey>[];
    for (final service in configured) {
      final async = ref.watch(serviceDiagnosisProvider(service));
      if (async.isLoading) {
        checking++;
        continue;
      }
      final diagnosis = async.asData?.value;
      final presentation = describeConnection(
        service,
        status: diagnosis?.status ?? ServiceConnectionStatus.disconnected,
        reason: diagnosis?.reason,
      );
      if (presentation.needsAttention) failing.add(service);
    }

    final summary = _summarize(
      total: configured.length,
      checking: checking,
      failing: failing.length,
    );
    final tone = failing.isNotEmpty
        ? StatusTone.error
        : (configured.isEmpty ? StatusTone.neutral : StatusTone.success);
    final promoted = failing.take(SettingsHomeScreen._maxPromotedFailures);
    final remaining = failing.length - promoted.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionLabel('Connections'),
        const SizedBox(height: AppSpacing.sm),
        SettingsGroupCard(
          children: [
            SettingsCard.grouped(
              leading: const Icon(Icons.hub_rounded),
              // Not "Services": that is the name of another tab, and the two
              // being confusable is the thing this screen is untangling.
              title: 'All connections',
              subtitle: summary,
              // The tile carries the verdict: green when the stack is whole,
              // red when it is not. It is the one thing worth seeing before
              // reading anything.
              accentColor: statusToneColor(colorScheme, tone),
              semanticHint: 'opens the connections list',
              onTap: () => context.push('/settings/connections'),
            ),
            for (final service in promoted)
              ServiceConnectionRow(
                service: service,
                onTap: () =>
                    context.push('/settings/service/${service.routeParam}'),
              ),
            if (remaining > 0)
              SettingsCard.grouped(
                leading: const Icon(Icons.more_horiz_rounded),
                title: remaining == 1
                    ? '1 more service needs attention'
                    : '$remaining more services need attention',
                accentColor: colorScheme.error,
                semanticHint: 'opens the connections list',
                onTap: () => context.push('/settings/connections'),
              ),
          ],
        ),
      ],
    );
  }

  String _summarize({
    required int total,
    required int checking,
    required int failing,
  }) {
    if (total == 0) return 'No services set up yet';
    if (failing > 0) return '$failing of $total need attention';
    if (checking > 0) return 'Checking $checking of $total…';
    return total == 1 ? '1 service connected' : 'All $total connected';
  }
}

/// The overline above a group of settings rows.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      header: true,
      // The un-uppercased title: '.toUpperCase()' is typography, and VoiceOver
      // spells out all-caps tokens it does not recognise.
      label: title,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Text(
          title.toUpperCase(),
          style: AppTheme.eyebrow(colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

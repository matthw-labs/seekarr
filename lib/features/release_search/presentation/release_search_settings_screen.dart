import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/features/release_search/data/release_search_transport.dart';
import 'package:seekarr/features/release_search/domain/release_search_reach.dart';
import 'package:seekarr/features/release_search/presentation/release_search_entry.dart';
import 'package:seekarr/features/release_search/domain/release_search_job.dart';
import 'package:seekarr/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:seekarr/features/release_search/presentation/widgets/search_headroom_card.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Settings for background release search — and, underneath them, the limits.
///
/// This is the third home in the awareness topology: the place a constraint that
/// shapes the user's setup lives, next to the setting it shapes. Written in the
/// second person and in the order someone actually meets these limits.
class ReleaseSearchSettingsScreen extends ConsumerStatefulWidget {
  const ReleaseSearchSettingsScreen({super.key});

  @override
  ConsumerState<ReleaseSearchSettingsScreen> createState() =>
      _ReleaseSearchSettingsScreenState();
}

class _ReleaseSearchSettingsScreenState
    extends ConsumerState<ReleaseSearchSettingsScreen> {
  bool _asking = false;

  /// Asks the OS **first**, then records what it answered — so a denied
  /// permission never leaves the toggle claiming to be on.
  Future<void> _toggleNotifications(bool wanted) async {
    final notifier = ref.read(releaseSearchSettingsProvider.notifier);
    if (!wanted) {
      notifier.setNotifyOnFinish(false);
      return;
    }
    setState(() => _asking = true);
    var granted = false;
    try {
      granted = await ref
          .read(releaseSearchNotificationsProvider)
          .requestPermission();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    setState(() => _asking = false);
    notifier.setNotifyOnFinish(granted);
    if (!granted) {
      SnackBarHelper.error(
        context,
        'Notifications are turned off for Seekarr in system settings.',
      );
    }
  }

  /// Every release-search-capable service (Sonarr, Radarr, Lidarr) whose reach
  /// is [reach] — the sets this screen's global settings have to name rather
  /// than hedge, since each limit is per instance, not per app. At most three
  /// names each.
  List<ServiceKey> _servicesWithReach(ReleaseSearchReach reach) => ServiceKey
      .values
      .where(SearchHeadroomCard.appliesTo)
      .where((s) => ref.watch(releaseSearchReachProvider(s)) == reach)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(releaseSearchSettingsProvider);
    final notifier = ref.read(releaseSearchSettingsProvider.notifier);
    final pinnedServices = _servicesWithReach(
      ReleaseSearchReach.whileOpenTrustedCert,
    );
    final cleartextServices = _servicesWithReach(
      ReleaseSearchReach.whileOpenCleartext,
    );

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Background search')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          SettingsGroupCard(
            children: [
              _StepperRow(
                icon: Icons.call_split_rounded,
                title: 'At the same time',
                subtitle: 'More is harder on rate-limited indexers',
                value: '${settings.concurrency}',
                range:
                    '${ReleaseSearchSettings.minConcurrency}'
                    '–${ReleaseSearchSettings.maxConcurrency}',
                onDecrement:
                    settings.concurrency > ReleaseSearchSettings.minConcurrency
                    ? () => notifier.setConcurrency(settings.concurrency - 1)
                    : null,
                onIncrement:
                    settings.concurrency < ReleaseSearchSettings.maxConcurrency
                    ? () => notifier.setConcurrency(settings.concurrency + 1)
                    : null,
              ),
              _StepperRow(
                icon: Icons.schedule_rounded,
                title: 'Give up after',
                subtitle: 'Above every common proxy ceiling on purpose',
                value: '${settings.timeout.inMinutes} min',
                range:
                    '${ReleaseSearchSettings.minTimeout.inMinutes}'
                    '–${ReleaseSearchSettings.maxTimeout.inMinutes}',
                onDecrement: settings.timeout > ReleaseSearchSettings.minTimeout
                    ? () => notifier.setTimeoutMinutes(
                        settings.timeout.inMinutes - 1,
                      )
                    : null,
                onIncrement: settings.timeout < ReleaseSearchSettings.maxTimeout
                    ? () => notifier.setTimeoutMinutes(
                        settings.timeout.inMinutes + 1,
                      )
                    : null,
              ),
              _NotifyRow(
                enabled: settings.notifyOnFinish,
                busy: _asking,
                foregroundOnlyServices: [
                  ...pinnedServices,
                  ...cleartextServices,
                ],
                onChanged: _toggleNotifications,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _LimitsCard(
            pinnedServices: pinnedServices,
            cleartextServices: cleartextServices,
          ),
        ],
      ),
    );
  }
}

/// The one notification setting, and the only place permission is ever asked for.
class _NotifyRow extends StatelessWidget {
  const _NotifyRow({
    required this.enabled,
    required this.busy,
    required this.foregroundOnlyServices,
    required this.onChanged,
  });

  final bool enabled;
  final bool busy;

  /// Release-search services whose background reach is cut off by something
  /// about the instance itself — a certificate trusted only inside Seekarr, or
  /// a cleartext origin. Both land in the same sentence because the user-facing
  /// consequence is identical: a search that stops when they leave the app.
  /// See [ReleaseSearchReach].
  final List<ServiceKey> foregroundOnlyServices;
  final Future<void> Function(bool value) onChanged;

  String get _subtitle {
    if (!backgroundSearchSupported()) {
      return 'Not needed here — the app keeps running';
    }
    if (foregroundOnlyServices.isEmpty) {
      return 'Only when Seekarr is not in front of you';
    }
    final names = foregroundOnlyServices.map((s) => s.title).join(', ');
    return 'Only when Seekarr is not in front of you — for $names, that '
        "includes a search stopping because it couldn't keep running in the "
        'background';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.notifications_active_outlined,
              size: 18,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tell me when one finishes',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  _subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(value: enabled, onChanged: (value) => onChanged(value)),
        ],
      ),
    );
  }
}

/// What this cannot do, said plainly and before it bites.
class _LimitsCard extends StatelessWidget {
  const _LimitsCard({
    required this.pinnedServices,
    required this.cleartextServices,
  });

  /// Release-search services whose background reach is cut off by a
  /// certificate trusted only inside Seekarr — see [ReleaseSearchReach].
  final List<ServiceKey> pinnedServices;

  /// Release-search services whose background reach is cut off because they
  /// are reached over cleartext `http://` — see [ReleaseSearchReach]. Kept
  /// apart from [pinnedServices] because the fix is a different one.
  final List<ServiceKey> cleartextServices;

  /// Only stated where it is true, rather than hedged everywhere.
  bool get androidCeilingApplies =>
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );

    return AppCard.surfaceOutlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("What this can't do", style: theme.textTheme.titleSmall),
          line(
            'Found releases stay grabbable for '
            '${kGrabWindow.inMinutes} minutes. That is the service\'s own limit, '
            'not a setting here — after it, grabbing needs a fresh search.',
          ),
          line(
            backgroundSearchSupported()
                ? 'A search keeps going when you switch apps, but it ends if you '
                      'force-quit Seekarr — no app can continue work after that.'
                : 'A search runs as long as Seekarr is running. Quitting the app '
                      'ends it.',
          ),
          if (androidCeilingApplies)
            line(
              'Android stops background work after '
              '${BackgroundReleaseSearchTransport.androidCeiling.inMinutes} '
              'minutes. A longer search needs Seekarr open, where there is no '
              'ceiling.',
            ),
          if (pinnedServices.isNotEmpty)
            line(
              '${pinnedServices.map((s) => s.title).join(', ')} '
              '${pinnedServices.length == 1 ? 'uses' : 'use'} a certificate '
              "trusted only inside Seekarr, so ${pinnedServices.length == 1 ? 'its' : 'their'} "
              'searches run in the foreground instead of the background — see '
              "that service's connection in Settings for how to restore it.",
            ),
          if (cleartextServices.isNotEmpty)
            line(
              '${cleartextServices.map((s) => s.title).join(', ')} '
              '${cleartextServices.length == 1 ? 'is' : 'are'} reached over '
              'plain http, so ${cleartextServices.length == 1 ? 'its' : 'their'} '
              'searches run in the foreground instead of the background: a '
              'background search cannot refuse a redirect, and over http '
              'anyone on the network can inject one to collect the API key. '
              'Switching to https restores it.',
            ),
          line(
            'Nothing is searched on a server of ours — there is not one. Your '
            'own instances do the work, and what Seekarr measures about them '
            'never leaves this device.',
          ),
        ],
      ),
    );
  }
}

/// A settings row whose value is a small integer.
///
/// Two buttons rather than a slider: the useful range is four steps wide, and a
/// slider would give a coarse gesture control over a value where every step
/// matters to someone's indexers.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.range,
    this.onDecrement,
    this.onIncrement,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final String range;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    void tap(VoidCallback? action) {
      if (action == null) return;
      HapticFeedback.selectionClick();
      action();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: colors.primary),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Semantics(
              container: true,
              label: '$title, $value. $subtitle. Range $range.',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onDecrement == null ? null : () => tap(onDecrement),
            icon: const Icon(Icons.remove_rounded, size: 18),
            tooltip: 'Less',
          ),
          // Tabular so the row does not shift as the figure changes width.
          Text(value, style: theme.textTheme.titleSmall?.tabular),
          IconButton(
            onPressed: onIncrement == null ? null : () => tap(onIncrement),
            icon: const Icon(Icons.add_rounded, size: 18),
            tooltip: 'More',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class BazarrScreen extends ConsumerWidget {
  const BazarrScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.bazarr);

    return AmbientScaffold(
      accent: AppColors.bazarr,
      appBar: showAppBar ? const GlassAppBar(title: Text('Bazarr')) : null,
      body: SafeArea(
        // The shared placeholder, not a private copy — Bazarr was the fifth
        // dashboard to have grown its own "isn't set up" card. `.forService`
        // keeps the deep link to Bazarr's own settings page that the private
        // copy had.
        child: isConfigured
            ? _BazarrDashboard(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.bazarr),
      ),
    );
  }
}

class _BazarrDashboard extends ConsumerWidget {
  const _BazarrDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wantedAsync = ref.watch(bazarrDashboardWantedProvider);
    final historyAsync = ref.watch(bazarrDashboardHistoryProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bazarrBadgesProvider);
        ref.invalidate(bazarrDashboardWantedProvider);
        ref.invalidate(bazarrDashboardHistoryProvider);
        ref.invalidate(serviceSummaryProvider(ServiceKey.bazarr));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          // Stat row — shared premium KPI peek
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.bazarr)),
            accent: AppColors.bazarr,
          ),
          const SizedBox(height: 4),
          // Search bar — decorative, non-functional for Fase 3
          _SearchBar(accent: AppColors.bazarr),
          const SizedBox(height: 8),
          // Quick action: open wanted/library lists
          _BazarrQuickActions(accent: AppColors.bazarr),
          const SizedBox(height: 8),
          // Wanted Subtitles
          SectionHeader(
            title: 'Wanted Subtitles',
            showChevron: true,
            onTap: () => context.push(ServiceRoutes.bazarrWanted),
          ),
          const SizedBox(height: 2),
          _WantedList(wantedAsync: wantedAsync),
          const SizedBox(height: 8),
          // Recent Activity
          const SectionHeader(title: 'Recent Activity', showChevron: false),
          const SizedBox(height: 2),
          _HistoryList(historyAsync: historyAsync),
          const SizedBox(height: 16),
          // CTA
          _BazarrCta(accent: AppColors.bazarr),
        ],
      ),
    );
  }
}

/// Decorative search bar matching the prototype. Not wired to search yet.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        enabled: false,
        decoration: InputDecoration(
          hintText: 'Search movies, series, subtitles...',
          hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: accent),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: AppRadius.borderRadiusMd,
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// List of wanted subtitle items (episodes + movies).
class _WantedList extends ConsumerWidget {
  const _WantedList({required this.wantedAsync});

  final AsyncValue<List<BazarrWantedItem>> wantedAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return wantedAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No wanted subtitles. Everything is covered!'),
          );
        }
        return Column(
          children: items.map((item) => _WantedTile(item: item)).toList(),
        );
      },
      loading: () => const _ListShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load wanted subtitles',
        onRetry: () => ref.invalidate(bazarrDashboardWantedProvider),
      ),
    );
  }
}

/// Single wanted subtitle row.
class _WantedTile extends ConsumerWidget {
  const _WantedTile({required this.item});

  final BazarrWantedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMovie = item.radarrId != null;
    final title = isMovie ? item.title : item.seriesTitle;
    final subtitle = _wantedSubtitle(item, isMovie);
    final langCodes = item.missingLanguages
        .map((l) => l.code2 ?? l.name)
        .join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          borderRadius: AppRadius.borderRadiusMd,
          onTap: () => _openWanted(context, item),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    isMovie ? '🎬' : '📺',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? 'Unknown',
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall!.weight(FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bazarr.withValues(alpha: 0.12),
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  child: Text(
                    langCodes.isNotEmpty ? langCodes.toUpperCase() : 'WANTED',
                    style: Theme.of(context).textTheme.labelSmall!
                        .weight(FontWeight.w800)
                        .copyWith(color: AppColors.bazarr),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _wantedSubtitle(BazarrWantedItem item, bool isMovie) {
    if (isMovie) {
      return item.sceneName;
    }
    final parts = <String>[];
    if (item.episodeNumber != null) {
      parts.add(item.episodeNumber!);
    }
    if (item.episodeTitle != null) {
      parts.add(item.episodeTitle!);
    }
    return parts.isNotEmpty ? parts.join(' · ') : null;
  }

  void _openWanted(BuildContext context, BazarrWantedItem item) {
    if (item.radarrId != null) {
      context.push(ServiceRoutes.bazarrMovie(item.radarrId!), extra: item);
    } else if (item.sonarrSeriesId != null) {
      context.push(
        ServiceRoutes.bazarrSeries(item.sonarrSeriesId!),
        extra: item,
      );
    }
  }
}

/// Compact row of two buttons that link to the full wanted/library lists.
class _BazarrQuickActions extends StatelessWidget {
  const _BazarrQuickActions({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _QuickActionButton(
              icon: Icons.subtitles_rounded,
              label: 'Wanted',
              accent: accent,
              onTap: () => context.push(ServiceRoutes.bazarrWanted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickActionButton(
              icon: Icons.library_books_rounded,
              label: 'Library',
              accent: accent,
              onTap: () => context.push(ServiceRoutes.bazarrLibrary),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent.withValues(alpha: 0.12),
      borderRadius: AppRadius.borderRadiusSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusSm,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: accent.withValues(alpha: 0.4)),
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!
                    .weight(FontWeight.w800)
                    .copyWith(color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// List of recent history entries.
class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.historyAsync});

  final AsyncValue<List<BazarrHistoryItem>> historyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return historyAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No recent activity yet.'),
          );
        }
        return Column(
          children: items.map((item) => _HistoryTile(item: item)).toList(),
        );
      },
      loading: () => const _ListShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load recent activity',
        onRetry: () => ref.invalidate(bazarrDashboardHistoryProvider),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final BazarrHistoryItem item;

  Color _historyColor() {
    return switch (item.action) {
      BazarrHistoryAction.downloaded => AppColors.success,
      BazarrHistoryAction.upgraded => AppColors.bazarr,
      BazarrHistoryAction.matched => AppColors.success,
      BazarrHistoryAction.failed => AppColors.error,
      BazarrHistoryAction.removed => AppColors.warning,
      BazarrHistoryAction.unknown => AppColors.warning,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tagColor = _historyColor();
    final isEpisode = item.kind == BazarrHistoryKind.episode;
    final subtitleParts = <String>[
      if (item.languageLabel != null) item.languageLabel!,
      if (item.provider != null) item.provider!,
    ];
    final subTitle = subtitleParts.isNotEmpty
        ? subtitleParts.join(' · ')
        : item.subtitle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Text(
                  isEpisode ? '📺' : '🎬',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? 'Unknown',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subTitle != null)
                      Text(
                        subTitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: Text(
                  item.action.label,
                  style: Theme.of(context).textTheme.labelSmall!
                      .weight(FontWeight.w800)
                      .copyWith(color: tagColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CTA button matching the prototype "Add Provider" row.
class _BazarrCta extends StatelessWidget {
  const _BazarrCta({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton.icon(
          onPressed: null, // Fase 5
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(23),
            ),
          ),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text(
            'Add Provider',
            style: Theme.of(
              context,
            ).textTheme.labelLarge!.weight(FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _ListShimmer extends StatelessWidget {
  const _ListShimmer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(
          3,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: ShimmerPlaceholder(height: 60),
          ),
        ),
      ),
    );
  }
}

/// Inline error placeholder with a retry action so failures are
/// distinguishable from the loading shimmer state.
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

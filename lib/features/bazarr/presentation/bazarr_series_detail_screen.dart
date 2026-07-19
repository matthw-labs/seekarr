import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/route_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class BazarrSeriesDetailScreen extends ConsumerWidget {
  const BazarrSeriesDetailScreen({
    super.key,
    required this.sonarrSeriesId,
    this.heroTag,
    this.initialWanted,
  });

  final int sonarrSeriesId;
  final String? heroTag;
  final BazarrWantedItem? initialWanted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.bazarr);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bazarr.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () =>
              RouteUtils.popOrGo(context, ServiceRoutes.bazarrLibrary),
          tooltip: 'Back',
        ),
        title: const Text('Series'),
      ),
      body: isConfigured
          ? _BazarrSeriesDetailBody(
              sonarrSeriesId: sonarrSeriesId,
              initialWanted: initialWanted,
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Bazarr is not configured yet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
    );
  }
}

class _BazarrSeriesDetailBody extends ConsumerWidget {
  const _BazarrSeriesDetailBody({
    required this.sonarrSeriesId,
    required this.initialWanted,
  });

  final int sonarrSeriesId;
  final BazarrWantedItem? initialWanted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesAsync = ref.watch(bazarrSeriesByIdProvider(sonarrSeriesId));
    final wantedAsync = ref.watch(
      bazarrWantedEpisodesForSeriesProvider(sonarrSeriesId),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bazarrSeriesByIdProvider(sonarrSeriesId));
        ref.invalidate(bazarrWantedEpisodesForSeriesProvider(sonarrSeriesId));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          seriesAsync.when(
            data: (series) {
              if (series == null && initialWanted == null) {
                return _DetailMessage(
                  icon: Icons.tv_off_rounded,
                  label: 'Series not found in Bazarr.',
                );
              }
              return _SeriesHeader(series: series, fallback: initialWanted);
            },
            loading: () => const _HeaderShimmer(),
            error: (error, _) => _DetailError(
              message: 'Failed to load series: $error',
              onRetry: () =>
                  ref.invalidate(bazarrSeriesByIdProvider(sonarrSeriesId)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionTitle('Missing Subtitles'),
          wantedAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return _DetailMessage(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'No missing subtitles. All languages covered!',
                  color: AppColors.success,
                );
              }
              return Column(
                children: items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _MissingSubtitleTile(item: item),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const _ListShimmerList(),
            error: (error, _) => _DetailError(
              message: 'Failed to load missing subtitles: $error',
              onRetry: () => ref.invalidate(
                bazarrWantedEpisodesForSeriesProvider(sonarrSeriesId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeriesHeader extends StatelessWidget {
  const _SeriesHeader({required this.series, required this.fallback});

  final BazarrSeries? series;
  final BazarrWantedItem? fallback;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = series?.title ?? fallback?.seriesTitle ?? 'Unknown series';
    final year = series?.year;
    final monitored = series?.monitored ?? false;
    final missing = series?.episodeMissingCount ?? 0;
    final langs = series?.profileId != null
        ? 'Profile #${series!.profileId}'
        : null;
    final tags = series?.tags ?? const <String>[];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.bazarr.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: const Text('📺', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (year != null)
                      Text(
                        'Year: $year',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: monitored
                      ? AppColors.success.withValues(alpha: 0.12)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: Text(
                  monitored ? 'MONITORED' : 'UNMONITORED',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: monitored
                        ? AppColors.success
                        : colorScheme.onSurfaceVariant,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _MetaBadge(label: 'Missing: $missing', accent: AppColors.bazarr),
              if (langs != null) _MetaBadge(label: langs, accent: null),
              ...tags.take(4).map((t) => _MetaBadge(label: t, accent: null)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingSubtitleTile extends StatelessWidget {
  const _MissingSubtitleTile({required this.item});

  final BazarrWantedItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final langs = item.missingLanguages
        .map((l) => l.code2 ?? l.name)
        .join(', ')
        .toUpperCase();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
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
            child: const Text('📺', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.episodeTitle ?? 'Episode ${item.episodeNumber ?? '?'}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.episodeNumber != null)
                  Text(
                    'Episode ${item.episodeNumber}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: AppColors.bazarr.withValues(alpha: 0.12),
              borderRadius: AppRadius.borderRadiusSm,
            ),
            child: Text(
              langs.isNotEmpty ? langs : 'WANTED',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.bazarr,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.label, required this.accent});

  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = accent ?? colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _HeaderShimmer extends StatelessWidget {
  const _HeaderShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ShimmerPlaceholder(
                width: 48,
                height: 48,
                borderRadius: null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    ShimmerPlaceholder(height: 18, borderRadius: null),
                    SizedBox(height: AppSpacing.xs),
                    ShimmerPlaceholder(height: 12, borderRadius: null),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const ShimmerPlaceholder(height: 16, borderRadius: null),
        ],
      ),
    );
  }
}

class _ListShimmerList extends StatelessWidget {
  const _ListShimmerList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: const ShimmerPlaceholder(height: 56, borderRadius: null),
        ),
      ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tint = color ?? colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Row(
        children: [
          Icon(icon, color: tint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

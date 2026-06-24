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

class BazarrMovieDetailScreen extends ConsumerWidget {
  const BazarrMovieDetailScreen({
    super.key,
    required this.radarrId,
    this.heroTag,
    this.initialWanted,
  });

  final int radarrId;
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
              RouteUtils.popOrGo(context, ServiceRoutes.bazarrWanted),
          tooltip: 'Back',
        ),
        title: const Text('Movie'),
      ),
      body: isConfigured
          ? _BazarrMovieDetailBody(
              radarrId: radarrId,
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

class _BazarrMovieDetailBody extends ConsumerWidget {
  const _BazarrMovieDetailBody({
    required this.radarrId,
    required this.initialWanted,
  });

  final int radarrId;
  final BazarrWantedItem? initialWanted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movieAsync = ref.watch(bazarrMovieByIdProvider(radarrId));
    final wantedAsync = ref.watch(bazarrWantedMovieByIdProvider(radarrId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bazarrMovieByIdProvider(radarrId));
        ref.invalidate(bazarrWantedMovieByIdProvider(radarrId));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          movieAsync.when(
            data: (movie) {
              if (movie == null && initialWanted == null) {
                return _DetailMessage(
                  icon: Icons.movie_filter_rounded,
                  label: 'Movie not found in Bazarr.',
                );
              }
              return _MovieHeader(movie: movie, fallback: initialWanted);
            },
            loading: () => const _HeaderShimmer(),
            error: (error, _) => _DetailError(
              message: 'Failed to load movie: $error',
              onRetry: () => ref.invalidate(bazarrMovieByIdProvider(radarrId)),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionTitle('Missing Subtitles'),
          wantedAsync.when(
            data: (item) {
              if (item == null) {
                return const _DetailMessage(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'No missing subtitles. All languages covered!',
                  color: AppColors.success,
                );
              }
              return _MissingMovieLanguages(item: item);
            },
            loading: () => const _LanguagesShimmer(),
            error: (error, _) => _DetailError(
              message: 'Failed to load missing subtitles: $error',
              onRetry: () =>
                  ref.invalidate(bazarrWantedMovieByIdProvider(radarrId)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovieHeader extends StatelessWidget {
  const _MovieHeader({required this.movie, required this.fallback});

  final BazarrMovie? movie;
  final BazarrWantedItem? fallback;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = movie?.title ?? fallback?.title ?? 'Unknown movie';
    final year = movie?.year;
    final monitored = movie?.monitored ?? false;
    final missing = movie?.missingSubtitlesCount ?? 0;
    final langs = movie?.profileId != null
        ? 'Profile #${movie!.profileId}'
        : null;
    final tags = movie?.tags ?? const <String>[];

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
                child: const Text('🎬', style: TextStyle(fontSize: 22)),
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

class _MissingMovieLanguages extends StatelessWidget {
  const _MissingMovieLanguages({required this.item});

  final BazarrWantedItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final langs = item.missingLanguages;
    if (langs.isEmpty) {
      return _DetailMessage(
        icon: Icons.language_rounded,
        label: 'No language data available.',
        color: colorScheme.onSurfaceVariant,
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: langs
          .map(
            (lang) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.bazarr.withValues(alpha: 0.12),
                borderRadius: AppRadius.borderRadiusSm,
                border: Border.all(
                  color: AppColors.bazarr.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (lang.code2 ?? lang.name ?? '?').toUpperCase(),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.bazarr,
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (lang.name != null && lang.code2 != null)
                    Text(
                      lang.name!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (lang.forced || lang.hi)
                    Text(
                      [
                        if (lang.forced) 'forced',
                        if (lang.hi) 'hi',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          )
          .toList(),
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

class _LanguagesShimmer extends StatelessWidget {
  const _LanguagesShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
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

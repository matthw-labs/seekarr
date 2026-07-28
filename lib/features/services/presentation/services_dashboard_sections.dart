import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/async_value_widget.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

class ServicesTrendingSection extends ConsumerWidget {
  const ServicesTrendingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (settings.seerrUrl.isEmpty || settings.seerrApiKey.isEmpty) {
      return const SizedBox.shrink();
    }
    return _PosterSection<MediaPreview>(
      title: 'Trending',
      service: ServiceKey.seerr,
      asyncValue: ref.watch(servicesTrendingProvider),
      serviceName: 'Seerr',
      actionLabel: 'Seerr',
      onAction: () => context.push(ServiceRoutes.seerr),
      onRetry: () => ref.invalidate(servicesTrendingProvider),
      itemTitle: (item) => item.title,
      itemSubtitle: (item) => item.year,
      imageUrl: (item, _) => ImageUtils.buildTmdbPosterUrl(item.posterPath),
      heroTag: (item) => 'services_seerr_${item.mediaType}_${item.id}',
      onTap: (item) => _openSeerrPreview(
        context,
        item,
        heroTag: 'services_seerr_${item.mediaType}_${item.id}',
      ),
    );
  }
}

class ServicesRecentlyAddedMoviesSection extends ConsumerWidget {
  const ServicesRecentlyAddedMoviesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (settings.radarrUrl.isEmpty || settings.radarrApiKey.isEmpty) {
      return const SizedBox.shrink();
    }
    return _PosterSection<RadarrMovie>(
      title: 'Recently Added · Movies',
      service: ServiceKey.radarr,
      asyncValue: ref.watch(servicesMoviesProvider),
      serviceName: 'Radarr',
      actionLabel: 'See all',
      onAction: () => context.push(ServiceRoutes.radarr),
      onRetry: () => ref.invalidate(servicesMoviesProvider),
      itemTitle: (item) => item.title,
      itemSubtitle: (item) => item.year.toString(),
      imageUrl: (item, settings) => ImageUtils.extractPosterUrl(
        item.images,
        baseUrl: settings.radarrUrl,
        apiKey: settings.radarrApiKey,
      ).url,
      heroTag: (item) => 'services_radarr_${item.id}',
      onTap: (item) => context.push(
        ServiceRoutes.radarrMovie(
          item.id,
          heroTag: 'services_radarr_${item.id}',
        ),
        extra: item,
      ),
      limit: 8,
    );
  }
}

class ServicesRecentlyAddedSeriesSection extends ConsumerWidget {
  const ServicesRecentlyAddedSeriesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (settings.sonarrUrl.isEmpty || settings.sonarrApiKey.isEmpty) {
      return const SizedBox.shrink();
    }
    return _PosterSection<SonarrSeries>(
      title: 'Recently Added · Series',
      service: ServiceKey.sonarr,
      asyncValue: ref.watch(servicesSeriesProvider),
      serviceName: 'Sonarr',
      actionLabel: 'See all',
      onAction: () => context.push(ServiceRoutes.sonarr),
      onRetry: () => ref.invalidate(servicesSeriesProvider),
      itemTitle: (item) => item.title,
      itemSubtitle: (item) => item.year.toString(),
      imageUrl: (item, settings) => ImageUtils.extractPosterUrl(
        item.images,
        baseUrl: settings.sonarrUrl,
        apiKey: settings.sonarrApiKey,
      ).url,
      heroTag: (item) => 'services_sonarr_${item.id}',
      onTap: (item) => context.push(
        ServiceRoutes.sonarrSeries(
          item.id,
          heroTag: 'services_sonarr_${item.id}',
        ),
        extra: item,
      ),
      limit: 8,
    );
  }
}

class ServicesRecentRequestsSection extends ConsumerWidget {
  const ServicesRecentRequestsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (settings.seerrUrl.isEmpty || settings.seerrApiKey.isEmpty) {
      return const SizedBox.shrink();
    }
    final requests = ref.watch(servicesRequestsProvider);

    return _ListSection<SeerrRequest>(
      title: 'Recent Requests',
      service: ServiceKey.seerr,
      asyncValue: requests,
      serviceName: 'Seerr',
      actionLabel: 'See all',
      onAction: () => context.push(ServiceRoutes.seerrRequests),
      onRetry: () => ref.invalidate(servicesRequestsProvider),
      emptyLabel: 'No recent requests',
      itemsBuilder: (items) => items.take(3).map(_RequestRow.new).toList(),
      loadingWidget: const Column(
        children: [
          _RequestRowSkeleton(),
          _RequestRowSkeleton(),
          _RequestRowSkeleton(),
        ],
      ),
    );
  }
}

class ServicesDownloadingSection extends ConsumerWidget {
  const ServicesDownloadingSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final hasDownloadService =
        (settings.radarrUrl.isNotEmpty && settings.radarrApiKey.isNotEmpty) ||
        (settings.sonarrUrl.isNotEmpty && settings.sonarrApiKey.isNotEmpty);
    if (!hasDownloadService) return const SizedBox.shrink();

    final queue = ref.watch(servicesQueueProvider);

    return _ListSection<ServiceQueueItem>(
      title: 'Downloading',
      service: ServiceKey.radarr,
      asyncValue: queue,
      serviceName: 'download queue',
      actionLabel: 'Queue',
      onAction: () => context.go('/activity'),
      onRetry: () => ref.invalidate(servicesQueueProvider),
      emptyLabel: 'No active downloads',
      itemsBuilder: (items) => items.map(_DownloadRow.new).toList(),
    );
  }
}

class _PosterSection<T> extends StatelessWidget {
  final String title;
  final ServiceKey service;
  final AsyncValue<List<T>> asyncValue;
  final String serviceName;
  final String actionLabel;
  final VoidCallback onAction;
  final String Function(T item) itemTitle;
  final String Function(T item) itemSubtitle;
  final String Function(T item, SettingsModel settings) imageUrl;
  final String Function(T item)? heroTag;
  final void Function(T item) onTap;
  final VoidCallback? onRetry;
  final int limit;

  const _PosterSection({
    required this.title,
    required this.service,
    required this.asyncValue,
    required this.serviceName,
    required this.actionLabel,
    required this.onAction,
    required this.itemTitle,
    required this.itemSubtitle,
    required this.imageUrl,
    required this.onTap,
    this.heroTag,
    this.onRetry,
    this.limit = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          showChevron: false,
          trailing: _SectionAction(label: actionLabel, color: service.accent),
          onTap: onAction,
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          // 138pt poster + gap + title/subtitle: grows with the reading size so
          // the labels are not clipped at accessibility text sizes.
          height: TextScaleMetrics.boxHeight(
            context,
            base: 176,
            textHeight: 34,
          ),
          child: AsyncValueWidget<List<T>>(
            value: asyncValue,
            serviceName: serviceName,
            onRetry: onRetry,
            skeleton: AppSkeleton.posterRow(height: 138),
            data: (items) {
              final visibleItems = items.take(limit).toList(growable: false);
              if (visibleItems.isEmpty) {
                return _SectionEmptyState(label: 'No items found');
              }

              return Consumer(
                builder: (context, ref, _) {
                  final settings = ref.watch(currentSettingsProvider);
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    itemCount: visibleItems.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppSpacing.carouselGap),
                    itemBuilder: (context, index) {
                      final item = visibleItems[index];
                      return _ServicePosterTile(
                        title: itemTitle(item),
                        subtitle: itemSubtitle(item),
                        imageUrl: imageUrl(item, settings),
                        accent: service.accent,
                        heroTag: heroTag?.call(item),
                        onTap: () => onTap(item),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _ListSection<T> extends StatelessWidget {
  final String title;
  final ServiceKey service;
  final AsyncValue<List<T>> asyncValue;
  final String serviceName;
  final String actionLabel;
  final VoidCallback onAction;
  final String emptyLabel;
  final List<Widget> Function(List<T> items) itemsBuilder;

  /// Optional widget shown while [asyncValue] is loading.
  /// Defaults to a centered [CircularProgressIndicator].
  final Widget? loadingWidget;
  final VoidCallback? onRetry;

  const _ListSection({
    required this.title,
    required this.service,
    required this.asyncValue,
    required this.serviceName,
    required this.actionLabel,
    required this.onAction,
    required this.emptyLabel,
    required this.itemsBuilder,
    this.loadingWidget,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          showChevron: false,
          trailing: _SectionAction(label: actionLabel, color: service.accent),
          onTap: onAction,
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AsyncValueWidget<List<T>>(
            value: asyncValue,
            serviceName: serviceName,
            loadingWidget: loadingWidget,
            onRetry: onRetry,
            data: (items) {
              final rows = itemsBuilder(items);
              if (rows.isEmpty) {
                return _SectionEmptyState(label: emptyLabel);
              }

              return Column(children: rows);
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _ServicePosterTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String imageUrl;
  final Color accent;
  final String? heroTag;
  final VoidCallback onTap;

  const _ServicePosterTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.accent,
    required this.onTap,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 96,
      child: PressableScale(
        onTap: onTap,
        // The tile is a poster plus a truncated title; announce the full title
        // and its subtitle as one button rather than an unlabelled image.
        semanticLabel: title,
        semanticValue: subtitle.isEmpty ? null : subtitle,
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 138,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _HeroContentCard(
                      heroTag: heroTag,
                      imageUrl: imageUrl,
                    ),
                  ),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroContentCard extends StatelessWidget {
  final String? heroTag;
  final String imageUrl;

  const _HeroContentCard({required this.heroTag, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final card = ContentCard(imageUrl: imageUrl);
    // Only fly a Hero when there is both a tag AND an image on this end. An
    // empty image would produce a blank/orphaned Hero whose destination has no
    // matching poster (common for Seerr items without a posterPath), which
    // shows up as a fade instead of a shared-element flight.
    if (heroTag == null || heroTag!.isEmpty || imageUrl.isEmpty) {
      return card;
    }

    return Hero(tag: heroTag!, child: card);
  }
}

class _RequestRow extends StatelessWidget {
  final SeerrRequest request;

  const _RequestRow(this.request);

  @override
  Widget build(BuildContext context) {
    final media = request.media;
    final title = media?.title ?? 'Unknown Media';
    final requester = request.requestedBy?.displayName ?? 'Unknown';
    final subtitle =
        '$requester · ${request.type == 'tv' ? 'Series' : 'Movie'}';
    final displayStatus = request.displayStatus;
    final statusColor = _requestStatusColor(displayStatus.kind);
    final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    final heroTag = _requestHeroTag(request);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: _CompactListRow(
        icon: request.type == 'tv' ? Icons.tv_rounded : Icons.movie_rounded,
        title: title,
        subtitle: subtitle,
        imageUrl: posterUrl,
        heroTag: heroTag,
        trailing: _SmallStatusPill(
          label: displayStatus.label,
          color: statusColor,
        ),
        onTap: () => _openRequest(context, request, heroTag: heroTag),
      ),
    );
  }

  void _openRequest(
    BuildContext context,
    SeerrRequest request, {
    String? heroTag,
  }) {
    final media = request.media;
    final id = media?.tmdbId ?? media?.id;
    if (id == null || id <= 0) {
      context.go(ServiceRoutes.seerr);
      return;
    }

    final mediaType = request.type == 'tv' ? 'tv' : 'movie';
    final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    final tag = heroTag ?? 'services_request_${request.id}';
    context.push(
      ServiceRoutes.seerrDetail(
        mediaType: mediaType,
        id: id,
        heroTag: tag,
        posterUrl: posterUrl,
      ),
    );
  }
}

/// Skeleton placeholder for a single [_RequestRow] while data is loading.
class _RequestRowSkeleton extends StatelessWidget {
  const _RequestRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard.surfaceOutlined(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ShimmerPlaceholder(
              width: 38,
              height: 54,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerPlaceholder.text(width: 140),
                  const SizedBox(height: AppSpacing.xs),
                  ShimmerPlaceholder.text(width: 90),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ShimmerPlaceholder(
              width: 110,
              height: 26,
              borderRadius: AppRadius.borderRadiusSm,
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final ServiceQueueItem item;

  const _DownloadRow(this.item);

  @override
  Widget build(BuildContext context) {
    final percent = item.progress == null
        ? null
        : (item.progress! * 100).round();
    final trailing = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (item.warning != null) ...[
          _SmallStatusPill(label: 'Warning', color: AppColors.error),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(
          percent == null ? 'DL' : '$percent%',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: item.service.accent,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: _CompactListRow(
        icon: item.service.icon,
        title: item.title,
        subtitle: item.subtitle,
        trailing: trailing,
        progressValue: item.progress,
        progressColor: item.progress == null ? null : item.service.accent,
        onTap: () => context.go('/activity'),
      ),
    );
  }
}

class _CompactListRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String? heroTag;
  final Widget trailing;
  final double? progressValue;
  final Color? progressColor;
  final VoidCallback onTap;

  const _CompactListRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.imageUrl,
    this.heroTag,
    this.progressValue,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard.surfaceOutlined(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            height: 54,
            child: imageUrl == null || imageUrl!.isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : _HeroContentCard(heroTag: heroTag, imageUrl: imageUrl!),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (progressColor != null) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progressValue,
                      minHeight: 3,
                      color: progressColor,
                      backgroundColor: colorScheme.outlineVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          trailing,
        ],
      ),
    );
  }
}

class _SmallStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _SmallStatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SectionAction extends StatelessWidget {
  final String label;
  final Color color;

  const _SectionAction({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label →',
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SectionEmptyState extends StatelessWidget {
  final String label;

  const _SectionEmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      alignment: Alignment.center,
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

Color _requestStatusColor(SeerrRequestDisplayKind kind) {
  switch (kind) {
    case SeerrRequestDisplayKind.pending:
      return AppColors.warning;
    case SeerrRequestDisplayKind.approved:
    case SeerrRequestDisplayKind.processing:
      return AppColors.info;
    case SeerrRequestDisplayKind.available:
    case SeerrRequestDisplayKind.partiallyAvailable:
    case SeerrRequestDisplayKind.completed:
      return AppColors.success;
    case SeerrRequestDisplayKind.declined:
    case SeerrRequestDisplayKind.failed:
    case SeerrRequestDisplayKind.deleted:
      return AppColors.error;
    case SeerrRequestDisplayKind.unknown:
      return AppColors.info;
  }
}

void _openSeerrPreview(
  BuildContext context,
  MediaPreview item, {
  required String heroTag,
}) {
  final posterUrl = ImageUtils.buildTmdbPosterUrl(item.posterPath);
  context.push(
    ServiceRoutes.seerrDetail(
      mediaType: item.mediaType,
      id: item.id,
      heroTag: heroTag,
      posterUrl: posterUrl,
    ),
  );
}

String _requestHeroTag(SeerrRequest request) =>
    'services_request_${request.id}';

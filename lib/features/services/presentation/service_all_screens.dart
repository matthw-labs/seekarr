import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/domain/seerr_request_filter.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class ServiceAllRequestsScreen extends ConsumerStatefulWidget {
  const ServiceAllRequestsScreen({super.key});

  @override
  ConsumerState<ServiceAllRequestsScreen> createState() =>
      _ServiceAllRequestsScreenState();
}

class _ServiceAllRequestsScreenState
    extends ConsumerState<ServiceAllRequestsScreen> {
  // Screen-local rather than a provider: the chosen bucket is not worth
  // restoring when the user comes back to this screen.
  SeerrRequestFilter _filter = SeerrRequestFilter.all;

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(servicesRequestsProvider);

    return Scaffold(
      appBar: _ServiceListAppBar(
        title: 'All Requests',
        backRoute: ServiceRoutes.seerr,
        accent: ServiceKey.seerr.accent,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(servicesRequestsProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom:
                AppSpacing.lg +
                FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            _FilterChipRow(
              accent: ServiceKey.seerr.accent,
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AsyncValueWidget<List<SeerrRequest>>(
                value: requests,
                serviceName: 'Seerr requests',
                data: (items) {
                  final visible = _filter.apply(items);
                  if (visible.isEmpty) {
                    return _EmptyListState(label: _filter.emptyLabel);
                  }

                  return Column(
                    children: [
                      for (final request in visible)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _RequestListRow(request: request),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceListAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final String backRoute;
  final Color accent;

  const _ServiceListAppBar({
    required this.title,
    required this.backRoute,
    required this.accent,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.chevron_left_rounded),
        onPressed: () => RouteUtils.popOrGo(context, backRoute),
        tooltip: 'Back',
      ),
      title: Text(title),
      titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  final Color accent;
  final SeerrRequestFilter selected;
  final ValueChanged<SeerrRequestFilter> onSelected;

  const _FilterChipRow({
    required this.accent,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    const filters = SeerrRequestFilter.values;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = filter == selected;
          // FilterChip supplies the button role and the selected state to
          // assistive technology, so no explicit Semantics is needed here.
          return FilterChip(
            label: Text(filter.label),
            selected: isSelected,
            showCheckmark: false,
            onSelected: (_) => onSelected(filter),
            labelStyle: Theme.of(context).textTheme.labelMedium
                ?.weight(FontWeight.w700)
                .copyWith(
                  color: isSelected
                      ? ServiceTheme.foregroundOn(accent)
                      : accent,
                ),
            selectedColor: accent,
            backgroundColor: accent.withValues(alpha: 0.10),
            side: BorderSide(color: isSelected ? accent : Colors.transparent),
            shape: const StadiumBorder(),
          );
        },
      ),
    );
  }
}

class _RequestListRow extends ConsumerWidget {
  final SeerrRequest request;

  const _RequestListRow({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = request.media;
    final title = media?.title ?? 'Unknown Media';
    final requester = request.requestedBy?.displayName ?? 'Unknown';
    final mediaType = request.type == 'tv' ? 'Series' : 'Movie';
    final displayStatus = request.displayStatus;
    final statusColor = _requestStatusColor(displayStatus.kind);
    final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    final heroTag = 'services_all_request_${request.id}';

    return AppCard.outlined(
      onTap: () => _openRequest(context, request, heroTag: heroTag),
      // The body is seven fragments on screen — including a bare '·' that reads
      // as "middle dot" — so it is composed into one label here. The delete
      // button is left out of the exclusion so it keeps a node of its own.
      semanticLabel: title,
      semanticValue: seerrRequestRowValue(
        mediaTypeLabel: mediaType,
        requester: requester,
        statusLabel: displayStatus.label,
        dateLabel: _formatRequestDate(request.createdAt),
      ),
      backgroundColor: colorScheme.surfaceContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: 38,
              height: 54,
              child: posterUrl.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        request.type == 'tv'
                            ? Icons.tv_rounded
                            : Icons.movie_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Hero(
                      tag: heroTag,
                      transitionOnUserGestures:
                          MediaPosterCard.flightOnUserGestures,
                      child: ContentCard(imageUrl: posterUrl),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.weight(FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _RequesterAvatar(name: requester),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          requester,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      Text(
                        '·',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        mediaType,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatRequestDate(request.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.tabular
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ExcludeSemantics(
                child: _SmallPill(
                  label: displayStatus.label,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox.square(
                dimension: 28,
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.delete_outline_rounded, size: 14),
                  color: AppColors.error,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.error.withValues(alpha: 0.10),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _deleteRequest(context, ref, title),
                  // Names which request: there is one of these per row.
                  tooltip: 'Delete request for $title',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRequest(
    BuildContext context,
    WidgetRef ref,
    String title,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Delete Request?',
      message: 'This removes the request for $title from Seerr.',
      destructive: true,
      confirmLabel: 'Delete',
    );
    if (!result.confirmed || !context.mounted) return;

    try {
      await ref.read(seerrServiceProvider).deleteRequest(request.id);
      ref.invalidate(servicesRequestsProvider);
      if (!context.mounted) return;
      // The row simply vanishes otherwise, which reads as a glitch rather than a
      // result. SnackBar carries liveRegion, so this is also the announcement.
      SnackBarHelper.success(context, 'Deleted the request for $title');
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, 'Could not delete the request: $error');
    }
  }

  void _openRequest(
    BuildContext context,
    SeerrRequest request, {
    required String heroTag,
  }) {
    final media = request.media;
    final id = media?.tmdbId ?? media?.id;
    if (id == null || id <= 0) return;
    final mediaType = request.type == 'tv' ? 'tv' : 'movie';
    final posterUrl = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    context.push(
      ServiceRoutes.seerrDetail(
        mediaType: mediaType,
        id: id,
        heroTag: heroTag,
        posterUrl: posterUrl,
      ),
    );
  }
}

class _RequesterAvatar extends StatelessWidget {
  final String name;

  const _RequesterAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: ServiceKey.seerr.accent.withValues(alpha: 0.14),
        border: Border.all(
          color: ServiceKey.seerr.accent.withValues(alpha: 0.27),
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: Theme.of(context).textTheme.labelSmall
            ?.weight(FontWeight.w800)
            .copyWith(color: ServiceKey.seerr.accent),
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  final String label;
  final Color color;

  const _SmallPill({required this.label, required this.color});

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
        // Uppercase but *not* `AppTheme.eyebrow`: this pill repeats once per
        // request row, and the eyebrow earns its tracking by being the single
        // kicker over a region. So it stays on the label ramp and takes the
        // tracking the ramp derives for 11pt.
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.weight(FontWeight.w800).copyWith(color: color),
      ),
    );
  }
}

class _EmptyListState extends StatelessWidget {
  final String label;

  const _EmptyListState({required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Center(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

String _formatRequestDate(String value) {
  if (value.trim().isEmpty) return 'Unknown date';
  return formatIsoDate(value);
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

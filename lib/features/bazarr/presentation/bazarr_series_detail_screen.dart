import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_detail_view_model.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_movie_detail_screen.dart'
    show BazarrDetailErrorState, BazarrDetailNotFoundState;
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/presentation/widgets/bazarr_detail_sections.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Bazarr series subtitle detail, on the shared media-detail scaffold.
class BazarrSeriesDetailScreen extends ConsumerWidget {
  const BazarrSeriesDetailScreen({
    super.key,
    required this.sonarrSeriesId,
    this.initialWanted,
  });

  final int sonarrSeriesId;
  final BazarrWantedItem? initialWanted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!settings.isServiceConfigured(ServiceKey.bazarr)) {
      return const BazarrDetailErrorState(error: 'Bazarr is not configured');
    }

    final seriesAsync = ref.watch(bazarrSeriesByIdProvider(sonarrSeriesId));
    final wantedAsync = ref.watch(
      bazarrWantedEpisodesForSeriesProvider(sonarrSeriesId),
    );
    final series = seriesAsync.asData?.value;

    // Declared above the early returns so the failure and not-found states can
    // offer the same recovery the loaded page offers.
    void refresh() {
      ref.invalidate(bazarrSeriesByIdProvider(sonarrSeriesId));
      ref.invalidate(bazarrWantedEpisodesForSeriesProvider(sonarrSeriesId));
    }

    if (series == null && initialWanted == null) {
      if (seriesAsync.isLoading) {
        return MediaDetailLoadingView(
          accent: ServiceKey.bazarr.accent,
          heroFallbackIcon: Icons.subtitles_outlined,
        );
      }
      if (seriesAsync.hasError) {
        return BazarrDetailErrorState(
          error: seriesAsync.error!,
          onRetry: refresh,
        );
      }
      // Bazarr learns about a series on its next Sonarr sync, so "not here yet"
      // is a state a retry can genuinely resolve.
      return BazarrDetailNotFoundState(
        icon: Icons.tv_off_rounded,
        title: 'Series not found in Bazarr',
        onRetry: refresh,
      );
    }

    final viewModel = BazarrDetailViewModel.forSeries(series, initialWanted);
    final accent = ServiceKey.bazarr.accent;
    final wantedItems = wantedAsync.asData?.value ?? const <BazarrWantedItem>[];
    final missing = viewModel.missing;

    final refreshAction = IconButton(
      icon: const Icon(Icons.refresh_rounded, size: 20),
      // Names the side being re-read, the same way the Bazarr movie page does.
      tooltip: 'Refresh from Bazarr',
      onPressed: refresh,
    );
    const label = 'Missing subtitles';
    // How many episode rows follow — a different fact from the hero chip's
    // "$missing missing", so the same sentence is not printed twice.
    final count = wantedItems.isEmpty
        ? null
        : '${wantedItems.length} '
              '${wantedItems.length == 1 ? 'episode' : 'episodes'}';

    return MediaDetailView(
      accent: accent,
      title: viewModel.title,
      heroFallbackIcon: Icons.subtitles_outlined,
      // The spine owns the indicator and the always-scrollable physics now, so
      // there is exactly one claimant on the pull gesture.
      onRefresh: () async => refresh(),
      posterRow: MediaDetailPosterRow(
        statusBadge: StatusBadge.animated(info: viewModel.status),
        title: viewModel.title,
        metadataItems: [if (series?.year != null) '${series!.year}'],
        tags: [
          TagChip(
            text: missing > 0 ? '$missing missing' : 'All covered',
            color: accent,
          ),
        ],
        posterCard: MediaDetailFigurePlate(
          value: '$missing',
          label: 'Missing',
          accent: accent,
        ),
      ),
      body: MediaDetailBody(
        // No deck: see the Bazarr movie screen — region 1 wants a Bazarr action
        // resolver, and a null deck costs no air where a blank box did.
        // Region 3 — the manifest. The lazy episode list used to be handed to the
        // view as a sliver while the states went in as content sections, and the
        // old spine emitted every content section first — so these rows rendered
        // *after* Details and Tags. A named region makes that unreachable while
        // keeping the list lazy: a heavily-wanted series builds the rows on
        // screen, not all of them.
        operate: [
          if (wantedItems.isEmpty)
            MediaDetailSlot.box(
              label: label,
              count: count,
              labelAction: refreshAction,
              child: wantedAsync.when(
                data: (items) => const AppEmptyState.compact(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'All languages covered',
                  message: 'No missing subtitles for this series.',
                  accentColor: AppColors.success,
                ),
                loading: () => ShimmerList(itemCount: 3, itemHeight: 56),
                error: (error, _) => AppErrorState.compact(
                  error: error,
                  serviceName: 'Bazarr',
                  onRetry: () => ref.invalidate(
                    bazarrWantedEpisodesForSeriesProvider(sonarrSeriesId),
                  ),
                ),
              ),
            )
          else
            MediaDetailSlot.lazy(
              label: label,
              count: count,
              labelAction: refreshAction,
              sliver: SliverList.builder(
                itemCount: wantedItems.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: BazarrWantedEpisodeTile(item: wantedItems[index]),
                ),
              ),
            ),
        ],
        reference: [
          if (viewModel.facts.isNotEmpty)
            MediaDetailSlot.box(
              label: 'Details',
              child: AppCard.surfaceOutlined(
                child: MediaFactsList(facts: viewModel.facts),
              ),
            ),
          if (viewModel.tags.isNotEmpty)
            MediaDetailSlot.box(
              // Real Bazarr tags, so the word is true here.
              label: 'Tags',
              child: MediaChipSection.accented(
                values: viewModel.tags,
                accent: accent,
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_detail_view_model.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/bazarr/presentation/widgets/bazarr_detail_sections.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Bazarr movie subtitle detail, on the shared media-detail scaffold.
class BazarrMovieDetailScreen extends ConsumerWidget {
  const BazarrMovieDetailScreen({
    super.key,
    required this.radarrId,
    this.initialWanted,
  });

  final int radarrId;
  final BazarrWantedItem? initialWanted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!settings.isServiceConfigured(ServiceKey.bazarr)) {
      return const BazarrDetailErrorState(error: 'Bazarr is not configured');
    }

    final movieAsync = ref.watch(bazarrMovieByIdProvider(radarrId));
    final wantedAsync = ref.watch(bazarrWantedMovieByIdProvider(radarrId));
    final movie = movieAsync.asData?.value;

    // Declared above the early returns so the failure and not-found states can
    // offer the same recovery the loaded page offers.
    void refresh() {
      ref.invalidate(bazarrMovieByIdProvider(radarrId));
      ref.invalidate(bazarrWantedMovieByIdProvider(radarrId));
    }

    if (movie == null && initialWanted == null) {
      if (movieAsync.isLoading) {
        return MediaDetailLoadingView(
          accent: ServiceKey.bazarr.accent,
          heroFallbackIcon: Icons.subtitles_outlined,
        );
      }
      if (movieAsync.hasError) {
        return BazarrDetailErrorState(
          error: movieAsync.error!,
          onRetry: refresh,
        );
      }
      // Bazarr learns about a movie on its next Radarr sync, so "not here yet"
      // is a state a retry can genuinely resolve.
      return BazarrDetailNotFoundState(
        icon: Icons.movie_filter_rounded,
        title: 'Movie not found in Bazarr',
        onRetry: refresh,
      );
    }

    final viewModel = BazarrDetailViewModel.forMovie(movie, initialWanted);
    final accent = ServiceKey.bazarr.accent;
    final missing = viewModel.missing;

    return MediaDetailView(
      accent: accent,
      title: viewModel.title,
      // Bazarr has no artwork of its own, so the fallback glyph is the hero's
      // only art and it must be Bazarr's, not a film reel.
      heroFallbackIcon: Icons.subtitles_outlined,
      // The spine owns the indicator, the always-scrollable physics and the
      // reconciliation with the hero's overscroll stretch, so this screen no
      // longer wraps its own.
      onRefresh: () async => refresh(),
      posterRow: MediaDetailPosterRow(
        statusBadge: StatusBadge.animated(info: viewModel.status),
        title: viewModel.title,
        // Year only: the missing count is the figure plate and the chip below,
        // so it is not also a third item in the metadata line.
        metadataItems: [if (movie?.year != null) '${movie!.year}'],
        tags: [
          TagChip(
            text: missing > 0 ? '$missing missing' : 'All covered',
            color: accent,
          ),
        ],
        // Bazarr has no poster *by definition*, so the 82x123 slot carried a
        // fake one rendering a film reel. It now carries the page's own figure.
        posterCard: MediaDetailFigurePlate(
          value: '$missing',
          label: 'Missing',
          accent: accent,
        ),
      ),
      body: MediaDetailBody(
        // Region 1 wants Bazarr's own promoted action ('Refresh from Bazarr'
        // while anything is missing). Until a Bazarr action resolver exists the
        // refresh lives on the section label, where the spine documents a
        // refresh control as belonging, and on the pull gesture above.
        // Region 3 — the manifest, and the only question this page exists to
        // answer. It used to render *after* Details and Tags, because the old
        // spine emitted every content section before every sliver.
        operate: [
          MediaDetailSlot.box(
            label: 'Missing subtitles',
            // No count: the hero chip already states the missing figure in
            // words, and the language pills below are the detail.
            labelAction: IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              // Names the side being re-read. A bare "Refresh" on a page whose
              // whole subject is what another service has not done yet leaves
              // the user guessing whether it re-checks Bazarr or asks Bazarr to
              // go hunting.
              tooltip: 'Refresh from Bazarr',
              onPressed: refresh,
            ),
            child: wantedAsync.when(
              data: (item) {
                if (item == null) {
                  return const AppEmptyState.compact(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'All languages covered',
                    message: 'No missing subtitles for this movie.',
                    accentColor: AppColors.success,
                  );
                }
                if (item.missingLanguages.isEmpty) {
                  // Bazarr filed this movie as wanted but named no languages —
                  // "No language data available" reported the app's own gap
                  // rather than the server's, and gave a self-hoster nothing to
                  // check.
                  return const AppEmptyState.compact(
                    icon: Icons.language_rounded,
                    title: 'No languages listed',
                    message:
                        'Bazarr is looking for subtitles here but did not say '
                        'which languages are missing. Check the language '
                        'profile on this movie in Bazarr.',
                  );
                }
                return BazarrSubtitleLanguageWrap(
                  languages: item.missingLanguages,
                );
              },
              loading: () => ShimmerList(itemCount: 2, itemHeight: 56),
              error: (error, _) => AppErrorState.compact(
                error: error,
                serviceName: 'Bazarr',
                onRetry: () =>
                    ref.invalidate(bazarrWantedMovieByIdProvider(radarrId)),
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
              // The one page in the app where this word is true: these are real
              // Bazarr tags off the user's server, not genres.
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

/// Error / not-configured state for the two Bazarr detail screens.
///
/// A thin alias over the shared [MediaDetailPlaceholderView] so both screens
/// name Bazarr and light the room in Bazarr's accent from one place.
class BazarrDetailErrorState extends StatelessWidget {
  const BazarrDetailErrorState({super.key, required this.error, this.onRetry});

  final Object error;

  /// Re-runs the failed load in place. Omitted for the not-configured case,
  /// whose fix is in Settings rather than another request.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MediaDetailPlaceholderView.error(
      error: error,
      serviceName: 'Bazarr',
      accent: ServiceKey.bazarr.accent,
      onRetry: onRetry,
    );
  }
}

/// The looked-up item does not exist in Bazarr — a normal state, not an
/// error, so it gets the empty-state voice rather than alarm chrome.
class BazarrDetailNotFoundState extends StatelessWidget {
  const BazarrDetailNotFoundState({
    super.key,
    required this.icon,
    required this.title,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MediaDetailPlaceholderView.notFound(
      icon: icon,
      title: title,
      message: 'Bazarr picks new titles up on its next sync with the -arrs.',
      serviceName: 'Bazarr',
      accent: ServiceKey.bazarr.accent,
      onRetry: onRetry,
    );
  }
}

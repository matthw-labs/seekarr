import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/core/widgets/media_info_card.dart';
import 'package:seekarr/features/bazarr/domain/bazarr_subtitle_status.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';

/// Presentation model for the Bazarr movie/series detail screens.
///
/// Owns the title-fallback cascade (library record → wanted item → constant)
/// and every derived display string, so both screens and their tests share
/// one resolution rule instead of re-deriving it per widget.
class BazarrDetailViewModel {
  final String title;
  final List<String> tags;
  final String? profileLabel;
  final MediaStatusInfo status;
  final List<MediaFact> facts;

  /// Subtitles Bazarr says are still outstanding.
  ///
  /// Exposed rather than derived per screen: both screens need it three times
  /// over (the figure plate, the hero chip and the empty state), and each was
  /// re-deriving it from the same `movie ?? fallback` cascade this class already
  /// owns — two copies of one rule.
  final int missing;

  /// Whether anything (library record or wanted fallback) exists to render.
  final bool found;

  const BazarrDetailViewModel._({
    required this.title,
    required this.tags,
    required this.profileLabel,
    required this.status,
    required this.facts,
    required this.missing,
    required this.found,
  });

  factory BazarrDetailViewModel.forMovie(
    BazarrMovie? movie,
    BazarrWantedItem? fallback,
  ) {
    final missing =
        movie?.missingSubtitlesCount ?? fallback?.missingSubtitlesCount ?? 0;
    final profileLabel = movie?.profileId != null
        ? 'Profile #${movie!.profileId}'
        : null;
    return BazarrDetailViewModel._(
      title: movie?.title ?? fallback?.title ?? 'Unknown movie',
      tags: movie?.tags ?? const [],
      profileLabel: profileLabel,
      status: bazarrSubtitleStatus(monitored: movie?.monitored ?? false),
      facts: [
        if (profileLabel != null) MediaFact('Profile', profileLabel),
        MediaFact('Monitored', (movie?.monitored ?? false) ? 'Yes' : 'No'),
        if ((movie?.path ?? '').isNotEmpty) MediaFact('Path', movie!.path!),
      ],
      missing: missing,
      found: movie != null || fallback != null,
    );
  }

  factory BazarrDetailViewModel.forSeries(
    BazarrSeries? series,
    BazarrWantedItem? fallback,
  ) {
    final missing = series?.episodeMissingCount ?? 0;
    final profileLabel = series?.profileId != null
        ? 'Profile #${series!.profileId}'
        : null;
    return BazarrDetailViewModel._(
      title: series?.title ?? fallback?.seriesTitle ?? 'Unknown series',
      tags: series?.tags ?? const [],
      profileLabel: profileLabel,
      status: bazarrSubtitleStatus(monitored: series?.monitored ?? false),
      facts: [
        if (profileLabel != null) MediaFact('Profile', profileLabel),
        if (series?.episodeCount != null)
          MediaFact('Episodes', '${series!.episodeCount}'),
        MediaFact('Monitored', (series?.monitored ?? false) ? 'Yes' : 'No'),
        if ((series?.path ?? '').isNotEmpty) MediaFact('Path', series!.path!),
      ],
      missing: missing,
      found: series != null || fallback != null,
    );
  }
}

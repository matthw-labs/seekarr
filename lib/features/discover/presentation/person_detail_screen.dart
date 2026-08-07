import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Premium person (cast member) page: profile hero, biography and a filmography
/// rail. Reached by tapping a cast member on a detail page.
class PersonDetailScreen extends ConsumerWidget {
  final int personId;
  final String? heroTag;

  /// Profile URL passed from the source avatar so the Hero flight lands on a
  /// cached image immediately.
  final String? initialProfileUrl;

  const PersonDetailScreen({
    super.key,
    required this.personId,
    this.heroTag,
    this.initialProfileUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personAsync = ref.watch(personDetailProvider(personId));
    final tag = heroTag ?? 'person_$personId';
    final hasInitial =
        initialProfileUrl != null && initialProfileUrl!.isNotEmpty;

    return personAsync.when(
      loading: () => MediaDetailLoadingView(
        accent: ServiceKey.seerr.accent,
        heroFallbackIcon: Icons.person_rounded,
        posterCard: hasInitial
            ? MediaPosterCard(
                heroTag: tag,
                imageUrl: initialProfileUrl,
                fallbackIcon: Icons.person_rounded,
                circular: true,
              )
            : null,
      ),
      // A lookup that failed and a person Seerr has no record of are two
      // different facts, and they used to share one sentence under one
      // empty-title bar with no way to try again. The failure now names Seerr,
      // keeps the diagnostics and offers a retry; "no record" keeps the
      // empty-state voice.
      error: (error, _) => MediaDetailPlaceholderView.error(
        error: error,
        serviceName: 'Seerr',
        accent: ServiceKey.seerr.accent,
        onRetry: () => ref.invalidate(personDetailProvider(personId)),
      ),
      data: (person) {
        if (person.isEmpty) {
          return MediaDetailPlaceholderView.notFound(
            icon: Icons.person_off_rounded,
            title: 'No details for this person',
            message: 'Seerr answered, but it has no record of them.',
            serviceName: 'Seerr',
            accent: ServiceKey.seerr.accent,
          );
        }

        final profileUrl = ImageUtils.buildTmdbPosterUrl(person.profilePath);
        final effectivePoster = profileUrl.isNotEmpty
            ? profileUrl
            : initialProfileUrl;
        final creditsAsync = ref.watch(personCreditsProvider(personId));
        final credits = creditsAsync.asData?.value ?? const <MediaPreview>[];
        final facts = <MediaInfoGroup>[
          if ((person.knownForDepartment ?? '').isNotEmpty)
            MediaInfoGroup(
              title: 'Known for',
              child: Text(person.knownForDepartment!),
            ),
          // Through the shared formatter, so a birthday reads `Jun 9, 1965` here
          // and on every other detail page rather than TMDB's raw `1965-06-09`.
          if ((person.birthday ?? '').isNotEmpty)
            MediaInfoGroup(
              title: 'Born',
              child: Text(formatMediumDate(person.birthday!)),
            ),
          if ((person.deathday ?? '').isNotEmpty)
            MediaInfoGroup(
              title: 'Died',
              child: Text(formatMediumDate(person.deathday!)),
            ),
          if ((person.placeOfBirth ?? '').isNotEmpty)
            MediaInfoGroup(
              title: 'Place of birth',
              child: Text(person.placeOfBirth!),
            ),
        ];

        return MediaDetailView(
          accent: ServiceKey.seerr.accent,
          posterUrl: effectivePoster,
          title: person.name,
          heroFallbackIcon: Icons.person_rounded,
          posterRow: MediaDetailPosterRow(
            circularPoster: true,
            title: person.name,
            metadataItems: [
              if ((person.knownForDepartment ?? '').isNotEmpty)
                person.knownForDepartment!,
              if ((person.birthday ?? '').isNotEmpty) _year(person.birthday!),
            ],
            // The chip slot's one meaning, applied to a reference page: how many
            // records there are.
            tags: [
              if (credits.isNotEmpty)
                TagChip(
                  text:
                      '${credits.length} '
                      '${credits.length == 1 ? 'credit' : 'credits'}',
                  color: ServiceKey.seerr.accent,
                ),
            ],
            posterCard: MediaPosterCard(
              heroTag: tag,
              imageUrl: effectivePoster,
              fallbackIcon: Icons.person_rounded,
              circular: true,
            ),
          ),
          onRefresh: () async {
            ref.invalidate(personDetailProvider(personId));
            ref.invalidate(personCreditsProvider(personId));
          },
          body: MediaDetailBody(
            // See the collection screen: a reference page's state needs a
            // resolved person status and a status-only deck, neither of which
            // exists yet.
            // Region 3 — the records Seerr holds under this name. The carousel
            // owns its own gutter and its own heading, hence `.rail`.
            operate: [
              MediaDetailSlot.rail(
                builder: (_) => DiscoverCarousel(
                  title: 'Filmography',
                  sectionId: 'person_$personId',
                  items: creditsAsync,
                ),
              ),
            ],
            synopsis: [
              if ((person.biography ?? '').isNotEmpty)
                MediaDetailSlot.box(
                  // The old overview section declared a `heading` parameter and
                  // never rendered it, so this string was silently discarded.
                  // As a slot label it finally appears.
                  label: 'Biography',
                  child: MediaProseSection(text: person.biography!),
                ),
            ],
            reference: [
              if (facts.isNotEmpty)
                MediaDetailSlot.box(
                  label: 'Details',
                  child: AppCard.surfaceOutlined(
                    child: MediaInfoCard(groups: facts),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _year(String date) =>
      date.length >= 4 ? date.substring(0, 4) : date;
}

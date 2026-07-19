import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/presentation/discover_details_provider.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

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
        posterCard: hasInitial
            ? MediaPosterCard(
                heroTag: tag,
                imageUrl: initialProfileUrl,
                fallbackIcon: Icons.person_rounded,
                circular: true,
              )
            : null,
      ),
      error: (error, _) =>
          _PersonMessage(message: 'Person details are unavailable.'),
      data: (person) {
        if (person.isEmpty) {
          return const _PersonMessage(
            message: 'Person details are unavailable.',
          );
        }

        final profileUrl = ImageUtils.buildTmdbPosterUrl(person.profilePath);
        final effectivePoster = profileUrl.isNotEmpty
            ? profileUrl
            : initialProfileUrl;
        final creditsAsync = ref.watch(personCreditsProvider(personId));
        final metadata = <String>[
          if ((person.knownForDepartment ?? '').isNotEmpty)
            person.knownForDepartment!,
          if ((person.birthday ?? '').isNotEmpty) _year(person.birthday!),
        ];

        return MediaDetailView(
          accent: ServiceKey.seerr.accent,
          posterUrl: effectivePoster,
          posterRow: (collapseFactor) => MediaDetailPosterRow(
            collapseFactor: collapseFactor,
            circularPoster: true,
            title: person.name,
            metadataItems: metadata,
            posterCard: MediaPosterCard(
              heroTag: tag,
              imageUrl: effectivePoster,
              fallbackIcon: Icons.person_rounded,
              circular: true,
            ),
          ),
          contentSections: [
            if ((person.biography ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: MediaDetailOverviewSection(
                  overview: person.biography!,
                  heading: 'Biography',
                ),
              ),
            if ((person.placeOfBirth ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: _PersonFact(
                  icon: Icons.place_outlined,
                  label: person.placeOfBirth!,
                ),
              ),
            DiscoverCarousel(
              title: 'Filmography',
              sectionId: 'person_$personId',
              items: creditsAsync,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }

  static String _year(String date) =>
      date.length >= 4 ? date.substring(0, 4) : date;
}

class _PersonFact extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PersonFact({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonMessage extends StatelessWidget {
  final String message;

  const _PersonMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('')),
      body: AppEmptyState(
        icon: Icons.person_off_rounded,
        title: 'Unavailable',
        message: message,
      ),
    );
  }
}

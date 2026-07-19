import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/features/discover/presentation/arr_media_extras_provider.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_cast_list.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_collection_banner.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Cast + collection on *arr (Radarr/Sonarr) detail pages, fetched from TMDB via
/// Seerr. Shows a "Connect Seerr" prompt when Seerr isn't configured.
class ArrMediaExtrasSection extends ConsumerWidget {
  final int tmdbId;
  final String mediaType; // 'movie' | 'tv'

  const ArrMediaExtrasSection({
    super.key,
    required this.tmdbId,
    required this.mediaType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extrasAsync = ref.watch(
      arrMediaExtrasProvider((tmdbId: tmdbId, mediaType: mediaType)),
    );

    return extrasAsync.maybeWhen(
      data: (extras) {
        // Seerr not configured → prompt the user to connect it.
        if (extras == null) return const _ConnectSeerrCta();

        final hasCast = extras.cast.isNotEmpty;
        final hasCollection = extras.collection != null;
        if (!hasCast && !hasCollection) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasCast) DiscoverCastList(cast: extras.cast),
            if (hasCast && hasCollection)
              const SizedBox(height: AppSpacing.lg),
            if (hasCollection)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: DiscoverCollectionBanner(collection: extras.collection!),
              ),
            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ConnectSeerrCta extends StatelessWidget {
  const _ConnectSeerrCta();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: AppCard.surfaceOutlined(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.seerr.withValues(alpha: 0.14),
                borderRadius: AppRadius.borderRadiusMd,
              ),
              child: const Icon(Icons.people_alt_rounded, color: AppColors.seerr),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cast & collections',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Connect Seerr to see cast, collections and more.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: () => context.go(
                '/settings/service/${ServiceKey.seerr.routeParam}',
              ),
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

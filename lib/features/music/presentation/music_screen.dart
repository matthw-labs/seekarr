import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/music/domain/models/lidarr_artist.dart';
import 'package:seekarr/features/music/presentation/music_provider.dart';
import 'package:seekarr/features/music/presentation/music_search_provider.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class MusicScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const MusicScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queuedArtistIds = ref
        .watch(lidarrQueuedArtistIdsProvider)
        .maybeWhen(data: (ids) => ids, orElse: () => const <int>{});

    return MediaBrowseScaffold<LidarrArtist>(
      title: 'Music',
      searchHint: 'Search artists...',
      activityRoute: '/activity/music',
      navigationSection: NavigationSection.services,
      serviceName: 'Lidarr',
      accentColor: ServiceKey.lidarr.accent,
      heroTagPrefix: 'artist',
      searchHeroTagPrefix: 'artist_search',
      libraryProvider: musicProvider,
      searchQueryProvider: musicSearchQueryProvider,
      searchResultsProvider: musicSearchResultsProvider,
      titleExtractor: (artist) => artist.artistName,
      subtitleExtractor: (artist) => artist.albumCount > 0
          ? '${artist.albumCount} album${artist.albumCount == 1 ? '' : 's'}'
          : '',
      sortTitleExtractor: (artist) => artist.artistName,
      imagesExtractor: (artist) => artist.images,
      idExtractor: (artist) => artist.id,
      statusExtractor: (artist) => MediaAvailabilityInfo(
        hasFile: artist.hasFiles,
        status: artist.status,
        fileCount: artist.trackFileCount,
        totalCount: artist.trackCount,
      ),
      browseStatusExtractor: (artist) =>
          queuedArtistIds.contains(artist.id) ? MediaStatus.queued : null,
      onRefresh: (ref) {
        ref.invalidate(lidarrQueuedArtistIdsProvider);
      },
      settingsSelector: (settings) =>
          (settings.lidarrUrl, settings.lidarrApiKey),
      onItemTap: (context, artist, heroTag) {
        context.push(
          ServiceRoutes.lidarrArtist(artist.id, heroTag: heroTag),
          extra: artist,
        );
      },
      coverTypes: const ['poster', 'fanart', 'banner'],
      showAppBar: showAppBar,
      topPadding: topPadding,
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.lidarr)),
        accent: ServiceKey.lidarr.accent,
      ),
    );
  }
}

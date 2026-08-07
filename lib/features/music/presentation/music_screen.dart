import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/domain/lidarr_status.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class MusicScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const MusicScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref
        .watch(lidarrQueueSnapshotsProvider)
        .maybeWhen(data: (snapshots) => snapshots.byArtist, orElse: () => null);

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
      statusExtractor: (artist) =>
          lidarrArtistStatus(artist, queueEntry: queue?.entryFor(artist.id)),
      onRefresh: (ref) {
        ref.invalidate(lidarrQueueSnapshotsProvider);
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

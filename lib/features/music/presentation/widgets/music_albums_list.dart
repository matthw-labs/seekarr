import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_status.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Lidarr's albums, and each album's tracks one tap away.
///
/// **This builds slivers** — hand it to `MediaDetailSlot.lazy(sliver: ...)`, so
/// the rows stay lazy and land in the page's third region instead of after the
/// genre chips.
///
/// The tracks used to live in an `ExpansionTile`, the third implementation of
/// `container -> children` in the codebase and the one that could not be shared:
/// album titles are long, so a pill rail of them is unusable where a rail of
/// two-character season numbers is ideal. So albums keep a row each and open a
/// sheet, and Sonarr's seasons keep the inline selector — both through
/// [MediaChildTile], which is the consolidation that matters.
class MusicAlbumsList extends StatelessWidget {
  final List<LidarrAlbum> albums;
  final LidarrService lidarrService;
  final String baseUrl;
  final String apiKey;
  final void Function(int albumId) onSearchAlbum;
  final void Function(int albumId) onInteractiveSearchAlbum;
  final Set<int> searchingAlbums;

  /// The Lidarr queue indexed by album id, so an album being grabbed shows its
  /// download state instead of a bare "missing" dot.
  final ArrQueueSnapshot albumQueue;

  const MusicAlbumsList({
    super.key,
    required this.albums,
    required this.lidarrService,
    required this.baseUrl,
    required this.apiKey,
    required this.onSearchAlbum,
    required this.onInteractiveSearchAlbum,
    required this.searchingAlbums,
    this.albumQueue = ArrQueueSnapshot.empty,
  });

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return SliverToBoxAdapter(
        child: AppEmptyState.compact(
          icon: Icons.album_outlined,
          title: 'No albums yet',
          message:
              'Lidarr is not tracking an album for this artist. It picks new '
              'releases up on its next refresh.',
          accentColor: ServiceKey.lidarr.accent,
        ),
      );
    }

    return SliverList.builder(
      itemCount: albums.length,
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.xs),
        child: _albumRow(context, albums[index]),
      ),
    );
  }

  Widget _albumRow(BuildContext context, LidarrAlbum album) {
    final status = lidarrAlbumStatus(
      album,
      queueEntry: albumQueue.entryFor(album.id),
    );
    final summary = lidarrAlbumSummary(album);
    final statusWord = mediaStatusWord(status);

    return MediaChildTile.stacked(
      leading: _AlbumArtwork(
        images: album.images,
        baseUrl: baseUrl,
        apiKey: apiKey,
      ),
      title: album.title,
      facts: <String>[
        if (album.year.isNotEmpty) album.year,
        if (summary != null) summary,
        if (statusWord != null) statusWord,
      ],
      status: status,
      progress: album.trackCount > 0 ? album.completionPercent : null,
      onTap: () => _openTracks(context, album, summary: summary),
      semanticHint: 'opens the track list',
      // Albums have no other search path: unlike an episode, there is no
      // container menu above them, so the affordance stays on every row.
      trailing: MediaSearchPopupMenu(
        onAutoSearch: () => onSearchAlbum(album.id),
        onInteractiveSearch: () => onInteractiveSearchAlbum(album.id),
        isLoading: searchingAlbums.contains(album.id),
        iconSize: 18,
        tooltip: 'Search ${album.title}',
      ),
    );
  }

  Future<void> _openTracks(
    BuildContext context,
    LidarrAlbum album, {
    required String? summary,
  }) {
    return AppBottomSheet.showScrollable<void>(
      context: context,
      title: album.title,
      subtitle: <String>[
        if (album.year.isNotEmpty) album.year,
        if (summary != null) summary,
      ].join(' • '),
      icon: Icons.album_rounded,
      accent: ServiceKey.lidarr.accent,
      builder: (context, controller) => _AlbumTracksSheet(
        controller: controller,
        lidarrService: lidarrService,
        albumId: album.id,
      ),
    );
  }
}

/// The track list for one album, loaded when the sheet opens.
class _AlbumTracksSheet extends StatefulWidget {
  final ScrollController controller;
  final LidarrService lidarrService;
  final int albumId;

  const _AlbumTracksSheet({
    required this.controller,
    required this.lidarrService,
    required this.albumId,
  });

  @override
  State<_AlbumTracksSheet> createState() => _AlbumTracksSheetState();
}

class _AlbumTracksSheetState extends State<_AlbumTracksSheet> {
  List<LidarrTrack>? _tracks;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _tracks = null;
      _error = null;
    });

    try {
      final tracks = await widget.lidarrService.getTracks(widget.albumId);
      if (!mounted) return;
      setState(() => _tracks = _sorted(tracks));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  static List<LidarrTrack> _sorted(List<LidarrTrack> tracks) {
    final sorted = List<LidarrTrack>.of(tracks);
    sorted.sort((a, b) {
      final medium = (a.mediumNumber ?? 1).compareTo(b.mediumNumber ?? 1);
      if (medium != 0) return medium;
      return a.sortableTrackNumber.compareTo(b.sortableTrackNumber);
    });

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    final error = _error;

    // Every branch is a scrollable attached to the sheet's controller, or
    // drag-to-expand stops working while the tracks are on their way.
    if (error != null) {
      return ListView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          AppErrorState.compact(
            error: error,
            serviceName: 'Lidarr',
            onRetry: _load,
          ),
        ],
      );
    }

    if (tracks == null) {
      return ListView(
        controller: widget.controller,
        padding: EdgeInsets.zero,
        children: [
          Semantics(
            container: true,
            label: 'Loading tracks',
            child: const ExcludeSemantics(
              child: ShimmerList(itemCount: 6, itemHeight: 52),
            ),
          ),
        ],
      );
    }

    if (tracks.isEmpty) {
      return ListView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          AppEmptyState.compact(
            icon: Icons.music_off_rounded,
            title: 'No tracks',
            message: 'Lidarr lists no tracks for this album yet.',
            accentColor: ServiceKey.lidarr.accent,
          ),
        ],
      );
    }

    return ListView.builder(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final status = lidarrTrackStatus(track);
        final statusWord = mediaStatusWord(status);

        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.xs),
          child: MediaChildTile.numbered(
            ordinal: track.displayTrackNumber,
            ordinalLabel: 'Track ${track.displayTrackNumber}',
            title: track.title,
            facts: <String>[
              track.formattedDuration,
              if (statusWord != null) statusWord,
            ],
            status: status,
          ),
        );
      },
    );
  }
}

class _AlbumArtwork extends StatelessWidget {
  static const double _width = 38;
  static const double _height = 54;

  final List<dynamic> images;
  final String baseUrl;
  final String apiKey;

  const _AlbumArtwork({
    required this.images,
    required this.baseUrl,
    required this.apiKey,
  });

  @override
  Widget build(BuildContext context) {
    final imageSource = ImageUtils.extractPosterUrl(
      images,
      baseUrl: baseUrl,
      apiKey: apiKey,
      coverTypes: const ['cover', 'disc'],
    );

    return ClipRRect(
      borderRadius: AppRadius.borderRadiusSm,
      child: imageSource.url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageSource.url,
              httpHeaders: imageSource.headers,
              cacheManager: pinnedImageCacheFor(imageSource.url),
              width: _width,
              height: _height,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => const _AlbumPlaceholder(),
            )
          : const _AlbumPlaceholder(),
    );
  }
}

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: _AlbumArtwork._width,
      height: _AlbumArtwork._height,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.album, color: colorScheme.outline),
    );
  }
}

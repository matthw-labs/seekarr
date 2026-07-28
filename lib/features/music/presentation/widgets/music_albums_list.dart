import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/status/arr_queue_snapshot.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/music/domain/lidarr_status.dart';
import 'package:seekarr/features/music/domain/models/lidarr_album.dart';
import 'package:seekarr/features/music/domain/models/lidarr_track.dart';

class MusicAlbumsList extends StatefulWidget {
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
  State<MusicAlbumsList> createState() => _MusicAlbumsListState();
}

class _MusicAlbumsListState extends State<MusicAlbumsList> {
  final Map<int, List<LidarrTrack>?> _tracksByAlbum = {};
  final Set<int> _tracksLoadingError = {};

  Future<void> _loadTracksForAlbum(int albumId) async {
    if (_tracksByAlbum.containsKey(albumId) &&
        !_tracksLoadingError.contains(albumId)) {
      return;
    }

    setState(() {
      _tracksByAlbum[albumId] = null;
      _tracksLoadingError.remove(albumId);
    });

    try {
      final tracks = await widget.lidarrService.getTracks(albumId);
      if (!mounted) {
        return;
      }

      setState(() {
        _tracksByAlbum[albumId] = tracks;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _tracksLoadingError.add(albumId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.albums.isEmpty) {
      return const _EmptyAlbumsState();
    }

    return Column(
      children: widget.albums
          .map(
            (album) => _AlbumTile(
              album: album,
              status: lidarrAlbumStatus(
                album,
                queueEntry: widget.albumQueue.entryFor(album.id),
              ),
              baseUrl: widget.baseUrl,
              apiKey: widget.apiKey,
              isSearching: widget.searchingAlbums.contains(album.id),
              onExpanded: () => _loadTracksForAlbum(album.id),
              onSearchAlbum: () => widget.onSearchAlbum(album.id),
              onInteractiveSearchAlbum: () =>
                  widget.onInteractiveSearchAlbum(album.id),
              children: _buildTracksList(context, album.id),
            ),
          )
          .toList(growable: false),
    );
  }

  List<Widget> _buildTracksList(BuildContext context, int albumId) {
    if (_tracksLoadingError.contains(albumId)) {
      return [_TracksLoadError(onRetry: () => _loadTracksForAlbum(albumId))];
    }

    if (!_tracksByAlbum.containsKey(albumId)) {
      return const [];
    }

    final tracks = _tracksByAlbum[albumId];
    if (tracks == null) {
      return const [_TracksLoadingState()];
    }

    if (tracks.isEmpty) {
      return const [_EmptyTracksState()];
    }

    return _sortTracks(
      tracks,
    ).map((track) => _TrackTile(track: track)).toList(growable: false);
  }

  List<LidarrTrack> _sortTracks(List<LidarrTrack> tracks) {
    final sortedTracks = List<LidarrTrack>.from(tracks);
    sortedTracks.sort((a, b) {
      final mediumCompare = (a.mediumNumber ?? 1).compareTo(
        b.mediumNumber ?? 1,
      );
      if (mediumCompare != 0) {
        return mediumCompare;
      }

      return a.sortableTrackNumber.compareTo(b.sortableTrackNumber);
    });
    return sortedTracks;
  }
}

class _EmptyAlbumsState extends StatelessWidget {
  const _EmptyAlbumsState();

  @override
  Widget build(BuildContext context) {
    return Text(
      'No albums found.',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _AlbumTile extends StatelessWidget {
  final LidarrAlbum album;
  final MediaStatusInfo status;
  final String baseUrl;
  final String apiKey;
  final bool isSearching;
  final VoidCallback onExpanded;
  final VoidCallback onSearchAlbum;
  final VoidCallback onInteractiveSearchAlbum;
  final List<Widget> children;

  const _AlbumTile({
    required this.album,
    required this.status,
    required this.baseUrl,
    required this.apiKey,
    required this.isSearching,
    required this.onExpanded,
    required this.onSearchAlbum,
    required this.onInteractiveSearchAlbum,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(
          11,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(11, 0, 11, AppSpacing.sm),
        shape: const Border(),
        collapsedShape: const Border(),
        onExpansionChanged: (expanded) {
          if (expanded) {
            onExpanded();
          }
        },
        leading: _AlbumArtwork(
          images: album.images,
          baseUrl: baseUrl,
          apiKey: apiKey,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(info: status, iconOnly: true),
          ],
        ),
        subtitle: _AlbumSubtitle(album: album),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MediaSearchPopupMenu(
              onAutoSearch: onSearchAlbum,
              onInteractiveSearch: onInteractiveSearchAlbum,
              isLoading: isSearching,
              iconSize: 18,
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              album.monitored ? Icons.bookmark_rounded : Icons.bookmark_border,
              size: 18,
              color: album.monitored
                  ? colorScheme.tertiary
                  : colorScheme.outline,
            ),
          ],
        ),
        children: children,
      ),
    );
  }
}

class _AlbumArtwork extends StatelessWidget {
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
      borderRadius: BorderRadius.circular(6),
      child: imageSource.url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageSource.url,
              httpHeaders: imageSource.headers,
              width: 38,
              height: 54,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => const _AlbumPlaceholder(),
            )
          : const _AlbumPlaceholder(),
    );
  }
}

class _AlbumSubtitle extends StatelessWidget {
  final LidarrAlbum album;

  const _AlbumSubtitle({required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (album.year.isNotEmpty)
          Text(
            album.year,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppRadius.borderRadiusXs,
          child: LinearProgressIndicator(
            value: album.completionPercent,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              _albumProgressColor(colorScheme, album),
            ),
            minHeight: AppSpacing.xs,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${album.trackFileCount} / ${album.trackCount} tracks',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 38,
      height: 54,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(Icons.album, color: colorScheme.outline),
    );
  }
}

class _TracksLoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const _TracksLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error, size: 32),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Failed to load tracks',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.error,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: AppSpacing.lg),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _TracksLoadingState extends StatelessWidget {
  const _TracksLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyTracksState extends StatelessWidget {
  const _EmptyTracksState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        'No tracks found.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final LidarrTrack track;

  const _TrackTile({required this.track});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusSm,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  track.displayTrackNumber,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                track.formattedDuration,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: track.hasFile
                      ? colorScheme.primary
                      : colorScheme.outline,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _albumProgressColor(ColorScheme colorScheme, LidarrAlbum album) {
  if (album.completionPercent >= 1) {
    return colorScheme.primary;
  }
  if (album.completionPercent > 0) {
    return colorScheme.tertiary;
  }
  return colorScheme.outline;
}

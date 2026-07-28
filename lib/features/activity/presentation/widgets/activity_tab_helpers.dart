import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:seekarr/core/api/base_arr_service.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/interactive_search_sheet.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:seekarr/features/activity/presentation/widgets/segment_selector.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/music/data/lidarr_service.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

typedef ReleaseFetcher = Future<List<dynamic>> Function(CancelToken token);

int? extractWantedItemId(ServiceType serviceType, Map<String, dynamic> item) {
  switch (serviceType) {
    case ServiceType.movies:
      return intOrNull(item['id'] ?? item['movieId']);
    case ServiceType.series:
      return intOrNull(item['id']);
    case ServiceType.music:
      return intOrNull(item['id'] ?? item['albumId']);
    case ServiceType.discover:
      return null;
  }
}

Future<void> runWantedAutoSearch(
  BuildContext context,
  ArrActivityMixin service,
  ServiceType serviceType,
  Map<String, dynamic> item,
) async {
  final itemId = extractWantedItemId(serviceType, item);
  if (itemId == null) return;

  try {
    switch (serviceType) {
      case ServiceType.movies:
        await (service as RadarrService).searchMovie(itemId);
        break;
      case ServiceType.series:
        await (service as SonarrService).searchEpisodes([itemId]);
        break;
      case ServiceType.music:
        await (service as LidarrService).searchAlbums([itemId]);
        break;
      case ServiceType.discover:
        return;
    }

    if (!context.mounted) return;
    SnackBarHelper.success(context, 'Search started');
  } catch (error) {
    if (!context.mounted) return;
    SnackBarHelper.error(context, 'Search failed: $error');
  }
}

Future<void> showWantedInteractiveSearch(
  BuildContext context,
  ArrActivityMixin service,
  ServiceType serviceType,
  Map<String, dynamic> item, {
  String? title,
}) async {
  final itemId = extractWantedItemId(serviceType, item);
  if (itemId == null) return;

  final sheetTitle =
      title ??
      'Releases for ${stringOrNull(item['title']) ?? _fallbackLabel(serviceType)}';

  final ReleaseFetcher? fetchReleases = switch (serviceType) {
    ServiceType.movies => (token) => (service as RadarrService).getReleases(
      itemId,
      cancelToken: token,
    ),
    ServiceType.series => (token) => (service as SonarrService).getReleases(
      episodeId: itemId,
      cancelToken: token,
    ),
    ServiceType.music => (token) => (service as LidarrService).getReleases(
      albumId: itemId,
      cancelToken: token,
    ),
    ServiceType.discover => null,
  };
  if (fetchReleases == null) return;

  final accent = switch (serviceType) {
    ServiceType.movies => ServiceKey.radarr.accent,
    ServiceType.series => ServiceKey.sonarr.accent,
    ServiceType.music => ServiceKey.lidarr.accent,
    ServiceType.discover => null,
  };

  await InteractiveSearchSheet.showAsync(
    context: context,
    accent: accent,
    title: sheetTitle,
    fetchReleases: fetchReleases,
    onGrabRelease: (guid, indexerId) =>
        service.grabReleaseByGuid(guid: guid, indexerId: indexerId),
  );
}

String _fallbackLabel(ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies => 'Movie',
    ServiceType.series => 'Episode',
    ServiceType.music => 'Album',
    ServiceType.discover => 'Item',
  };
}

/// Mixin providing shared async sliver builders for activity tabs.
mixin ActivityTabHelpers {
  Widget buildRefreshableSegmentedView<T extends Enum>({
    required Key refreshKey,
    required VoidCallback onRefreshRequested,
    required List<T> segments,
    required T selected,
    required ValueChanged<T> onSegmentChanged,
    required String Function(T) labelBuilder,
    required Widget contentSliver,
  }) {
    return RefreshIndicator(
      onRefresh: () async => onRefreshRequested(),
      child: CustomScrollView(
        key: refreshKey,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ActivitySegmentSelector<T>(
            segments: segments,
            selected: selected,
            onChanged: onSegmentChanged,
            labelBuilder: labelBuilder,
          ),
          contentSliver,
        ],
      ),
    );
  }

  Widget buildAsyncContentSliver(
    Future<List<dynamic>> future,
    Widget Function(dynamic item) itemBuilder,
  ) {
    return _buildAsyncSliver(future, (items) {
      return SliverList.separated(
        itemCount: items.length,
        itemBuilder: (context, index) => itemBuilder(items[index]),
        separatorBuilder: (context, index) => const Divider(height: 1),
      );
    });
  }

  Widget _buildAsyncSliver(
    Future<List<dynamic>> future,
    Widget Function(List<dynamic> items) contentBuilder,
  ) {
    return FutureBuilder<List<dynamic>>(
      future: future,
      builder: (context, snapshot) {
        final stateSliver = _buildAsyncStateSliver(context, snapshot);
        if (stateSliver != null) return stateSliver;

        return contentBuilder(snapshot.data ?? const []);
      },
    );
  }

  Widget buildAsyncGroupedContentSliver(
    Future<List<dynamic>> future,
    Widget Function(List<dynamic> items) groupBuilder,
  ) {
    return _buildAsyncSliver(
      future,
      (items) => SliverToBoxAdapter(child: groupBuilder(items)),
    );
  }

  Widget? _buildAsyncStateSliver(
    BuildContext context,
    AsyncSnapshot<List<dynamic>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (snapshot.hasError) {
      return _buildMessageSliver(
        context,
        'Error: ${snapshot.error}',
        color: Theme.of(context).colorScheme.error,
        textAlign: TextAlign.center,
      );
    }

    final items = snapshot.data ?? const [];
    if (items.isEmpty) {
      return _buildMessageSliver(
        context,
        'Nothing here',
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }

    return null;
  }

  Widget _buildMessageSliver(
    BuildContext context,
    String message, {
    required Color color,
    TextAlign? textAlign,
  }) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            style: TextStyle(color: color),
            textAlign: textAlign,
          ),
        ),
      ),
    );
  }
}

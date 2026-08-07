import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/activity/presentation/widgets/segment_selector.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
    // "<Service> is searching <what>" — the one shape every detail page uses.
    // This surface is one tap from those pages and used to answer a search with
    // a bare "Search started", which named neither the actor nor the scope.
    SnackBarHelper.success(
      context,
      '${_serviceName(serviceType)} is searching ${_scopeLabel(serviceType)}',
    );
  } catch (error) {
    if (!context.mounted) return;
    SnackBarHelper.error(
      context,
      "Couldn't start a search in ${_serviceName(serviceType)}.",
      detail: error,
    );
  }
}

/// Opens interactive search for a Wanted row.
///
/// Takes a [WidgetRef] rather than a service because the single entry point
/// resolves the service from the target — which is also what makes this row obey
/// the same adoption and cache rules as the detail screens.
Future<void> showWantedInteractiveSearch(
  BuildContext context,
  WidgetRef ref,
  ServiceType serviceType,
  Map<String, dynamic> item, {
  String? title,
}) async {
  final itemId = extractWantedItemId(serviceType, item);
  if (itemId == null) return;

  // The sheet heads itself "Releases" and this string lands in its subtitle, so
  // "Releases for X" printed the word twice. Capped for the same reason the
  // detail screens cap it: the subtitle is where an untrusted service title
  // lands, and a 200-character one grows the header until it eats the list.
  final sheetTitle = truncateTitle(
    title ?? stringOrNull(item['title']) ?? _fallbackLabel(serviceType),
  );

  final target = switch (serviceType) {
    ServiceType.movies => ReleaseSearchTarget.movie(
      movieId: itemId,
      label: sheetTitle,
    ),
    // A Wanted row knows the episode but not its season, so this target cannot
    // be matched to a running season search — the containment check requires
    // both, and guessing would adopt a job that does not cover this episode.
    ServiceType.series => ReleaseSearchTarget.episode(
      episodeId: itemId,
      label: sheetTitle,
    ),
    ServiceType.music => ReleaseSearchTarget.album(
      albumId: itemId,
      label: sheetTitle,
    ),
    ServiceType.discover => null,
  };
  if (target == null) return;

  await showReleaseSearch(context, ref, target);
}

String _fallbackLabel(ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies => 'Movie',
    ServiceType.series => 'Episode',
    ServiceType.music => 'Album',
    ServiceType.discover => 'Item',
  };
}

/// The service that will actually do the work, named in its own confirmation.
String _serviceName(ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies => ServiceKey.radarr.title,
    ServiceType.series => ServiceKey.sonarr.title,
    ServiceType.music => ServiceKey.lidarr.title,
    ServiceType.discover => ServiceKey.seerr.title,
  };
}

/// What the search covers, in the words the detail pages use.
String _scopeLabel(ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies => 'for this movie',
    ServiceType.series => 'this episode',
    ServiceType.music => 'this album',
    ServiceType.discover => 'this title',
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
        // No divider: these rows are outlined cards with a gap already.
        separatorBuilder: (context, index) => const SizedBox.shrink(),
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
      return SliverToBoxAdapter(child: AppSkeleton.listRows(count: 6));
    }

    if (snapshot.hasError) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: AppErrorState(error: snapshot.error!),
      );
    }

    final items = snapshot.data ?? const [];
    if (items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: AppEmptyState(
          icon: Icons.inbox_rounded,
          title: 'Nothing to show',
          message: 'Anything this service reports will appear here.',
        ),
      );
    }

    return null;
  }
}

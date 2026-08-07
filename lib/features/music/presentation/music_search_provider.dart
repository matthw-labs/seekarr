import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/utils/search_results_loader.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

/// Provider for the current search query in Music section.
final musicSearchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for search results in Music section.
///
/// Returns null when query is empty, otherwise returns lookup results.
///
/// The lookup carries a [CancelToken] cancelled on dispose — see
/// `moviesSearchResultsProvider` for why the superseded round has to stop.
final musicSearchResultsProvider = FutureProvider<List<LidarrArtist>?>((
  ref,
) async {
  final query = ref.watch(musicSearchQueryProvider);
  final service = ref.read(lidarrServiceProvider);
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return loadNullableSearchResults(
    query: query,
    lookup: (term) => service.lookupArtists(term, cancelToken: cancelToken),
  );
});

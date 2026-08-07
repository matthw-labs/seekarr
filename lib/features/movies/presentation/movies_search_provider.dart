import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:seekarr/core/utils/search_results_loader.dart';
import 'package:seekarr/features/movies/data/radarr_service.dart';
import 'package:seekarr/features/movies/domain/models/radarr_movie.dart';

/// Provider for the current search query in Movies section.
final moviesSearchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for search results in Movies section.
///
/// Returns null when query is empty, otherwise returns lookup results.
///
/// The lookup carries a [CancelToken] cancelled on dispose. Riverpod tears the
/// previous build down before it starts the next one, so the request a
/// keystroke supersedes is aborted rather than left to run to completion
/// against an arr instance that may take seconds to answer a query nobody is
/// asking any more.
final moviesSearchResultsProvider = FutureProvider<List<RadarrMovie>?>((
  ref,
) async {
  final query = ref.watch(moviesSearchQueryProvider);
  final service = ref.read(radarrServiceProvider);
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return loadNullableSearchResults(
    query: query,
    lookup: (term) => service.lookupMovies(term, cancelToken: cancelToken),
  );
});

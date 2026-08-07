import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:seekarr/core/utils/search_results_loader.dart';
import 'package:seekarr/features/series/data/sonarr_service.dart';
import 'package:seekarr/features/series/domain/models/sonarr_series.dart';

/// Provider for the current search query in Series section.
final seriesSearchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for search results in Series section.
///
/// Returns null when query is empty, otherwise returns lookup results.
///
/// The lookup carries a [CancelToken] cancelled on dispose — see
/// `moviesSearchResultsProvider` for why the superseded round has to stop.
final seriesSearchResultsProvider = FutureProvider<List<SonarrSeries>?>((
  ref,
) async {
  final query = ref.watch(seriesSearchQueryProvider);
  final service = ref.read(sonarrServiceProvider);
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return loadNullableSearchResults(
    query: query,
    lookup: (term) => service.lookupSeries(term, cancelToken: cancelToken),
  );
});

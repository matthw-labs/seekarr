import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';

/// Provider for the current search query in Discover section.
final discoverSearchQueryProvider = StateProvider<String>((ref) => '');

/// Provider for search results in Discover section.
///
/// Returns null when query is empty, otherwise returns search results.
final discoverSearchResultsProvider = FutureProvider<List<MediaPreview>?>((
  ref,
) async {
  final query = ref.watch(discoverSearchQueryProvider);
  if (query.isEmpty) {
    return null;
  }

  try {
    final service = ref.read(seerrServiceProvider);
    return await service.search(query);
  } catch (e) {
    return [];
  }
});

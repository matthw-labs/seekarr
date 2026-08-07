import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';

/// Service for interacting with the Readarr API (v1).
///
/// Reuses the shared *arr contract via [ArrActivityMixin] (queue, history,
/// wanted, releases). Readarr is archived upstream but its v1 API is unchanged,
/// so the same header-auth [ApiClient] and mixin apply as for Lidarr.
class ReadarrService with ArrActivityMixin {
  ReadarrService(this.client);

  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.readarr;

  /// Fetches all authors (the primary library entity).
  Future<List<ReadarrAuthor>> getAuthors() {
    return fetchAllItems('author', ReadarrAuthor.fromJson);
  }

  /// Fetches a single author by id, or null if unknown.
  Future<ReadarrAuthor?> getAuthorById(int authorId) async {
    try {
      final response = await client.get('/api/v1/author/$authorId');
      return ReadarrAuthor.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Fetches recent history mapped to typed items for the dashboard.
  Future<List<ReadarrHistoryItem>> getRecentHistory({int pageSize = 20}) async {
    final records = await getHistory(page: 1, pageSize: pageSize);
    return records
        .whereType<Map>()
        .map((e) => ReadarrHistoryItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// Triggers an automatic search for an author's missing books.
  Future<void> searchAuthor(int authorId) async {
    await client.post(
      '/api/v1/command',
      data: {'name': 'AuthorSearch', 'authorId': authorId},
    );
  }

  /// Updates an author's monitored state.
  Future<void> updateAuthorMonitored(int authorId, bool monitored) async {
    await updateItemMonitored('author', authorId, monitored);
  }
}

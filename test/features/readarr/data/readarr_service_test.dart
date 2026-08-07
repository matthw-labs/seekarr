import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/readarr/data/readarr_service.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/fixtures.dart';

void main() {
  group('ReadarrService', () {
    test('getAuthors parses the author list from /api/v1/author', () async {
      final client = FakeApiClient()
        ..getResponseData = jsonFixtureList('readarr/author_list.json');
      final service = ReadarrService(client);

      final authors = await service.getAuthors();

      expect(client.lastGetPath, '/api/v1/author');
      expect(authors, hasLength(2));
      expect(authors.first.authorName, 'Brandon Sanderson');
      expect(authors.first.bookCount, 20);
      expect(authors.first.bookFileCount, 15);
      expect(authors.first.missingBookCount, 5);
      expect(authors[1].monitored, isFalse);
    });

    test('getRecentHistory maps records from /api/v1/history', () async {
      final client = FakeApiClient()
        ..getResponseData = jsonFixtureMap('readarr/history.json');
      final service = ReadarrService(client);

      final items = await service.getRecentHistory();

      expect(client.lastGetPath, '/api/v1/history');
      expect(items, hasLength(2));
      expect(items.first.eventType, 'grabbed');
      expect(items.first.authorName, 'Brandon Sanderson');
    });
  });
}

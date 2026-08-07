import 'package:flutter_test/flutter_test.dart';

import '../../../test_helpers/fixtures.dart';

/// Tier-3 contract test (plan §7.4). Readarr publishes an OpenAPI spec, so the
/// spec is the source of truth: these tests fail loudly if an endpoint we call
/// or a field we parse is renamed/removed upstream — the drift signal for a
/// service we cannot exercise live. Regenerate `readarr/openapi.json` from a
/// pinned container to refresh the contract (plan §9 contract-drift job).
void main() {
  group('Readarr OpenAPI contract', () {
    final spec = jsonFixtureMap('readarr/openapi.json');

    test('the endpoints Cupola calls exist in the schema', () {
      final paths = (spec['paths'] as Map).keys;
      for (final p in const [
        '/api/v1/system/status',
        '/api/v1/author',
        '/api/v1/author/{id}',
        '/api/v1/book',
        '/api/v1/queue',
        '/api/v1/history',
        '/api/v1/command',
      ]) {
        expect(paths, contains(p), reason: 'Readarr removed $p');
      }
    });

    Map<String, dynamic> schema(String name) =>
        ((spec['components'] as Map)['schemas'] as Map)[name]
            as Map<String, dynamic>;

    test('AuthorResource keeps the fields ReadarrAuthor parses', () {
      final props = (schema('AuthorResource')['properties'] as Map).keys;
      for (final f in const [
        'id',
        'authorName',
        'monitored',
        'overview',
        'status',
        'statistics',
      ]) {
        expect(props, contains(f), reason: 'AuthorResource lost $f');
      }
      final statsProps =
          (schema('AuthorStatisticsResource')['properties'] as Map).keys;
      for (final f in const ['bookCount', 'bookFileCount']) {
        expect(statsProps, contains(f), reason: 'statistics lost $f');
      }
    });

    test('HistoryResource keeps the fields ReadarrHistoryItem parses', () {
      final props = (schema('HistoryResource')['properties'] as Map).keys;
      for (final f in const [
        'id',
        'eventType',
        'sourceTitle',
        'date',
        'author',
      ]) {
        expect(props, contains(f), reason: 'HistoryResource lost $f');
      }
    });
  });
}

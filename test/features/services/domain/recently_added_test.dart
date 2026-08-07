import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/recently_added.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

RecentlyAddedItem _item(
  String title, {
  String? added,
  ServiceKey service = ServiceKey.radarr,
  int id = 1,
}) => RecentlyAddedItem(
  service: service,
  id: id,
  title: title,
  subtitle: '',
  posterUrl: '',
  addedAt: parseAddedTimestamp(added),
);

void main() {
  group('parseAddedTimestamp', () {
    test('parses the ISO 8601 string the arr APIs return', () {
      expect(
        parseAddedTimestamp('2024-03-14T09:26:53Z'),
        DateTime.utc(2024, 3, 14, 9, 26, 53),
      );
    });

    test('returns null for absent, blank or unparseable values', () {
      // Null rather than the epoch: a bad timestamp must not sort an item to the
      // top of a "newest first" rail, and must not take the rail down either.
      expect(parseAddedTimestamp(null), isNull);
      expect(parseAddedTimestamp(''), isNull);
      expect(parseAddedTimestamp('   '), isNull);
      expect(parseAddedTimestamp('not a date'), isNull);
    });
  });

  group('sortRecentlyAdded', () {
    test('orders newest first across services', () {
      // The bug this exists to fix: the two rails it replaced took the first
      // eight items of an unsorted full-library fetch and called them recent.
      final sorted = sortRecentlyAdded([
        _item('Oldest', added: '2023-01-01T00:00:00Z'),
        _item('Newest', added: '2024-06-01T00:00:00Z'),
        _item(
          'Middle',
          added: '2024-01-01T00:00:00Z',
          service: ServiceKey.sonarr,
        ),
      ], limit: 10);

      expect(sorted.map((item) => item.title), ['Newest', 'Middle', 'Oldest']);
    });

    test('sorts undated items last and drops them first at the limit', () {
      final sorted = sortRecentlyAdded([
        _item('No date'),
        _item('Dated', added: '2024-01-01T00:00:00Z'),
      ], limit: 1);

      expect(sorted.single.title, 'Dated');
    });

    test('caps at the limit', () {
      final sorted = sortRecentlyAdded([
        for (var index = 0; index < 30; index++)
          _item('Item $index', added: '2024-01-${(index % 28) + 1}T00:00:00Z'),
      ], limit: 12);

      expect(sorted, hasLength(12));
    });

    test('leaves the caller\'s list untouched', () {
      final input = [
        _item('Oldest', added: '2023-01-01T00:00:00Z'),
        _item('Newest', added: '2024-06-01T00:00:00Z'),
      ];

      sortRecentlyAdded(input, limit: 10);

      expect(input.first.title, 'Oldest');
    });

    test('hero tags are unique per service and id', () {
      // Two libraries can hold the same numeric id, and a collision would make
      // two posters try to fly to the same destination.
      final radarr = _item('A', service: ServiceKey.radarr, id: 7);
      final sonarr = _item('B', service: ServiceKey.sonarr, id: 7);

      expect(radarr.heroTag, isNot(sonarr.heroTag));
    });
  });
}

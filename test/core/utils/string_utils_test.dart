import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/utils/string_utils.dart';

void main() {
  group('formatMediumDate', () {
    test('is the detail pages one date voice', () {
      // The drift this ends: Radarr printed `2019-05-22` in its Details grid
      // while Seerr printed `May 22, 2019` for the same film, two taps away.
      expect(formatMediumDate('2019-05-22'), 'May 22, 2019');
      expect(formatIsoDate('2019-05-22'), '2019-05-22');
    });

    test('does not pad a single-digit day', () {
      expect(formatMediumDate('1965-06-09'), 'Jun 9, 1965');
    });

    test('ignores a time component', () {
      expect(formatMediumDate('2026-07-17T20:00:00.000Z'), 'Jul 17, 2026');
    });

    test('covers both ends of the month table', () {
      expect(formatMediumDate('2020-01-31'), 'Jan 31, 2020');
      expect(formatMediumDate('2020-12-01'), 'Dec 1, 2020');
    });

    test('returns what the service said when it cannot be parsed', () {
      // A service that answers with something unexpected still shows its answer
      // rather than an empty cell.
      expect(formatMediumDate('not a date'), 'not a date');
      expect(formatMediumDate('2019-05'), '2019-05');
    });

    test('leaves an empty value empty', () {
      expect(formatMediumDate(''), '');
      expect(formatMediumDate('   '), '');
    });
  });

  group('formatMediumDateOrNull', () {
    test('speaks the same prose as formatMediumDate', () {
      // The whole point of the nullable variant is that a child row and the
      // Details grid above it cannot disagree about what a date looks like.
      expect(formatMediumDateOrNull('2026-07-17'), 'Jul 17, 2026');
      expect(
        formatMediumDateOrNull('2026-07-17T20:00:00Z'),
        formatMediumDate('2026-07-17T20:00:00Z'),
      );
    });

    test('drops a fact it cannot read instead of echoing raw JSON', () {
      // A dot-separated facts line has no cell to leave blank, so an unreadable
      // date has to leave the line entirely.
      expect(formatMediumDateOrNull('not a date'), isNull);
      expect(formatMediumDateOrNull('2019-05'), isNull);
    });

    test('treats absent and blank alike', () {
      expect(formatMediumDateOrNull(null), isNull);
      expect(formatMediumDateOrNull(''), isNull);
      expect(formatMediumDateOrNull('   '), isNull);
    });
  });

  group('formatRuntimeMinutes', () {
    test('speaks hours and minutes', () {
      // Radarr shipped `127 min`, Seerr `173min`.
      expect(formatRuntimeMinutes(127), '2h 7m');
      expect(formatRuntimeMinutes(173), '2h 53m');
    });

    test('drops the hour under an hour', () {
      expect(formatRuntimeMinutes(47), '47m');
      expect(formatRuntimeMinutes(1), '1m');
    });

    test('drops the minutes on a whole hour', () {
      expect(formatRuntimeMinutes(120), '2h');
      expect(formatRuntimeMinutes(60), '1h');
    });

    test('reports nothing for a runtime the service does not have', () {
      // Zero is a missing fact, not a film of no length, and an empty string is
      // dropped by both the metadata line and the fact grid.
      expect(formatRuntimeMinutes(0), '');
      expect(formatRuntimeMinutes(-5), '');
    });
  });

  group('truncateTitle', () {
    test('leaves a title that fits alone', () {
      expect(truncateTitle('Inception'), 'Inception');
    });

    test('trims surrounding whitespace', () {
      expect(truncateTitle('  Inception  '), 'Inception');
    });

    test('caps a title that would grow a dialog past its own buttons', () {
      final long = 'A ${'very ' * 60}long title';
      final result = truncateTitle(long);

      expect(result.length, lessThanOrEqualTo(65));
      expect(result, endsWith('…'));
      // An ellipsis glyph, not three periods, which read as a pause.
      expect(result, isNot(contains('...')));
    });

    test('cuts on a word boundary rather than mid-word', () {
      final result = truncateTitle(
        'The Lord of the Rings The Fellowship of the Ring Extended Edition '
        'Remastered',
        maxChars: 40,
      );

      expect(result, 'The Lord of the Rings The Fellowship of…');
      expect(result.length, lessThanOrEqualTo(41));
    });

    test('hard-cuts a single word longer than the budget', () {
      // A word boundary is only honoured in the last third, so a title with no
      // early space cannot collapse to a lone ellipsis.
      final result = truncateTitle('A${'b' * 200}', maxChars: 20);

      expect(result.length, 21);
      expect(result, endsWith('…'));
    });

    test('is stable at exactly the budget', () {
      final exact = 'x' * 64;
      expect(truncateTitle(exact), exact);
      // One character over: 64 kept plus the ellipsis glyph.
      expect(truncateTitle('${exact}y').length, 65);
    });
  });
}

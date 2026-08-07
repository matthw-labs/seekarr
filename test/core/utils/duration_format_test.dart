import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/duration_format.dart';

void main() {
  group('formatElapsed', () {
    test('pads seconds but not minutes', () {
      // A stopwatch, not a timestamp: `0:07`, never `00:07`.
      expect(formatElapsed(const Duration(seconds: 7)), '0:07');
      expect(formatElapsed(const Duration(minutes: 1, seconds: 12)), '1:12');
      expect(formatElapsed(const Duration(minutes: 12, seconds: 4)), '12:04');
    });

    test('rolls over at sixty seconds', () {
      expect(formatElapsed(const Duration(seconds: 59)), '0:59');
      expect(formatElapsed(const Duration(seconds: 60)), '1:00');
      expect(formatElapsed(const Duration(seconds: 61)), '1:01');
    });

    test('renders zero rather than an empty string', () {
      expect(formatElapsed(Duration.zero), '0:00');
    });

    test('keeps counting past an hour instead of wrapping', () {
      // The client timeout is minutes, but a search behind a stalled proxy can
      // sit for far longer, and a readout that silently wrapped to 0:xx would
      // report the opposite of what happened.
      expect(formatElapsed(const Duration(hours: 1, seconds: 5)), '60:05');
    });
  });

  group('formatElapsedForSpeech', () {
    test('spells out seconds only, below a minute', () {
      expect(formatElapsedForSpeech(const Duration(seconds: 7)), '7 seconds');
      expect(formatElapsedForSpeech(Duration.zero), '0 seconds');
    });

    test('singularises one second and one minute', () {
      expect(formatElapsedForSpeech(const Duration(seconds: 1)), '1 second');
      expect(formatElapsedForSpeech(const Duration(minutes: 1)), '1 minute');
      expect(
        formatElapsedForSpeech(const Duration(minutes: 1, seconds: 1)),
        '1 minute 1 second',
      );
    });

    test('drops a zero seconds component', () {
      expect(formatElapsedForSpeech(const Duration(minutes: 2)), '2 minutes');
    });

    test('reads both components when both are present', () {
      expect(
        formatElapsedForSpeech(const Duration(minutes: 1, seconds: 12)),
        '1 minute 12 seconds',
      );
    });

    test('never emits the glyph form, which a screen reader cannot read', () {
      final spoken = formatElapsedForSpeech(
        const Duration(minutes: 1, seconds: 12),
      );
      expect(spoken, isNot(contains(':')));
    });
  });
}

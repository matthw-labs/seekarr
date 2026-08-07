import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/domain/models/jellyfin_units.dart';

/// The highest-value tests in the feature: four units meet here and every
/// mistake produces a plausible number rather than an error, so nothing catches
/// it downstream.
void main() {
  group('ticks', () {
    test('a tick is 100ns, so a millisecond is 10 000 of them', () {
      expect(kJellyfinTicksPerMillisecond, 10000);
      expect(kJellyfinTicksPerSecond, 10000000);
    });

    test('a two-hour film is 7 200 000 ms, not 7 200 or 720 000 000', () {
      // 72e9 ticks. Dividing by 1e7 (seconds) or by 1e3 would both look
      // superficially fine in a duration label.
      expect(jellyfinMillisecondsFromTicks(72000000000), 7200000);
    });

    test('int64 tick counts survive without going through a double', () {
      // 24 hours of ticks: 864e9, comfortably past the 2^24 where a float32
      // rounds and well into the range where an accidental double round-trip
      // starts losing whole seconds.
      const oneDayInTicks = 864000000000;
      expect(jellyfinMillisecondsFromTicks(oneDayInTicks), 86400000);
      expect(jellyfinTicks(oneDayInTicks), isA<int>());
    });

    test('a quoted or floated tick count still parses', () {
      expect(jellyfinMillisecondsFromTicks('72000000000'), 7200000);
      expect(jellyfinMillisecondsFromTicks(72000000000.0), 7200000);
      // A gateway that round-trips the payload through a floating-point type and
      // re-quotes it hands back exponent notation, which `int.parse` rejects
      // outright — so a two-hour film would arrive as "no runtime".
      expect(jellyfinMillisecondsFromTicks('7.2e10'), 7200000);
      expect(jellyfinMillisecondsFromTicks('72000000000.0'), 7200000);
      // `Infinity` and `NaN` are parseable doubles with no integer value at all;
      // `double.infinity.toInt()` throws rather than returning anything.
      expect(jellyfinMillisecondsFromTicks('Infinity'), isNull);
      expect(jellyfinMillisecondsFromTicks('NaN'), isNull);
    });

    test('unknown and negative values are absent, not zero', () {
      expect(jellyfinMillisecondsFromTicks(null), isNull);
      expect(jellyfinMillisecondsFromTicks('not a number'), isNull);
      expect(jellyfinMillisecondsFromTicks(-1), isNull);
      expect(jellyfinMillisecondsFromTicks(double.nan), isNull);
    });

    test('zero means "unknown" only where the caller says so', () {
      // `RunTimeTicks: 0` on an unprobed file must not render as "0 min", but a
      // caller that wants the literal value can still have it.
      expect(jellyfinMillisecondsFromTicks(0), 0);
      expect(jellyfinMillisecondsFromTicks(0, zeroAsNull: true), isNull);
    });

    test('sub-millisecond remainders truncate rather than round up', () {
      expect(jellyfinMillisecondsFromTicks(19999), 1);
    });
  });

  group('progress', () {
    test('position over runtime is a 0-1 fraction', () {
      expect(
        jellyfinFractionFromTicks(position: 18000000000, runtime: 72000000000),
        0.25,
      );
    });

    test('a position past the runtime clamps instead of exceeding 1', () {
      expect(
        jellyfinFractionFromTicks(position: 80000000000, runtime: 72000000000),
        1.0,
      );
    });

    test(
      'live TV — a position with no runtime — yields null, not Infinity',
      () {
        expect(
          jellyfinFractionFromTicks(position: 18000000000, runtime: 0),
          null,
        );
        expect(
          jellyfinFractionFromTicks(position: 18000000000, runtime: null),
          null,
        );
        expect(
          jellyfinFractionFromTicks(position: null, runtime: 72000000000),
          null,
        );
      },
    );
  });

  group('percentages', () {
    test('PlayedPercentage is 0-100, so 40 is 0.4 and not 40x too far', () {
      expect(jellyfinFractionFromPercent(40.0), 0.4);
      expect(jellyfinFractionFromPercent(100), 1.0);
      expect(jellyfinFractionFromPercent(0), 0.0);
    });

    test('a percentage over 100 clamps', () {
      expect(jellyfinFractionFromPercent(140), 1.0);
    });

    test('a missing percentage is null', () {
      expect(jellyfinFractionFromPercent(null), isNull);
      expect(jellyfinFractionFromPercent('n/a'), isNull);
    });
  });

  group('bitrate', () {
    test('bits per second passes through untouched', () {
      // Not bytes: dividing by 8 here would report a 24 Mbps 4K remux as 3 Mbps.
      expect(jellyfinBitsPerSecond(24305112), 24305112);
      expect(jellyfinBitsPerSecond('5616000'), 5616000);
    });

    test('zero and nonsense are absent rather than 0 bps', () {
      expect(jellyfinBitsPerSecond(0), isNull);
      expect(jellyfinBitsPerSecond(-1), isNull);
      expect(jellyfinBitsPerSecond(null), isNull);
    });
  });

  group('counters', () {
    test('nullable so "fully watched" and "unknown" stay distinguishable', () {
      expect(jellyfinInt(0), 0);
      expect(jellyfinInt(null), isNull);
      expect(jellyfinInt('2024'), 2024);
      expect(jellyfinInt(2024.0), 2024);
      expect(jellyfinInt('  4 '), 4);
    });
  });
}

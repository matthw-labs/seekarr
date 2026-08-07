import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/byte_format.dart';

void main() {
  group('formatBytes', () {
    test('renders bytes as whole things', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1), '1 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('one decimal below ten, none at or above it', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(10 * 1024), '10 KB');
      expect(formatBytes(999 * 1024), '999 KB');
    });

    test('climbs the whole binary ladder', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
      expect(formatBytes(5497558138880), '5.0 TB');
      expect(formatBytes(1024 * 1024 * 1024 * 1024 * 1024), '1.0 PB');
      // Nothing above PB to promote into, so the number simply keeps growing
      // rather than falling off the ladder.
      expect(formatBytes(4096 * 1024 * 1024 * 1024 * 1024 * 1024), '4096 PB');
    });

    test('promotes after rounding, never printing 1024 of a unit', () {
      // 1023.7 KB rounds to "1024" at this unit's precision, which contradicts
      // its own label — the check reads the rendered number, not the raw one.
      expect(formatBytes(1023.7 * 1024), '1.0 MB');
      expect(formatBytes(1023.6), '1.0 KB');
    });

    test('carries a sign rather than pretending a negative is zero', () {
      expect(formatBytes(-1536), '-1.5 KB');
    });
  });

  group('formatBytesPrecise', () {
    test('keeps three significant digits instead of two', () {
      expect(formatBytesPrecise(1024), '1.00 KB');
      expect(formatBytesPrecise(1536), '1.50 KB');
      expect(formatBytesPrecise(4700000000), '4.38 GB');
      expect(formatBytesPrecise(26 * 1024 * 1024 * 1024), '26.0 GB');
      expect(formatBytesPrecise(837000000), '798 MB');
    });

    test('keeps the digit the compact ladder rounds away', () {
      // A TrueNAS pool and a release list are read by comparison, so the tenth
      // of a terabyte is the whole point; the compact ladder says "46 TB".
      const pool = 45.5 * 1024 * 1024 * 1024 * 1024;
      expect(formatBytesPrecise(pool), '45.5 TB');
      expect(formatBytes(pool), '46 TB');
    });

    test('shares the rest of the compact ladder verbatim', () {
      expect(formatBytesPrecise(0), '0 B');
      expect(formatBytesPrecise(512), '512 B');
      expect(formatBytesPrecise(-1536), '-1.50 KB');
      // Promotion still reads the rendered number: 1023.999 KB rounds to
      // "1024.00" at three digits, which contradicts its own unit.
      expect(formatBytesPrecise(1023.999 * 1024), '1.00 MB');
      expect(formatBytesPrecise(2 * 1024 * 1024 * 1024 * 1024), '2.00 TB');
    });

    test('prints every digit on the top rung, never dropping off it', () {
      expect(
        formatBytesPrecise(4096 * 1024 * 1024 * 1024 * 1024 * 1024),
        '4096 PB',
      );
    });
  });

  group('formatBytesPerSecond', () {
    test('appends the rate suffix at every magnitude', () {
      expect(formatBytesPerSecond(0), '0 B/s');
      expect(formatBytesPerSecond(512), '512 B/s');
      expect(formatBytesPerSecond(2097152), '2.0 MB/s');
    });
  });

  group('formatMegabytes', () {
    test('reads SABnzbd/NZBGet MB fields on the same ladder as raw bytes', () {
      expect(formatMegabytes(0), '0 B');
      expect(formatMegabytes(512), '512 MB');
      expect(formatMegabytes(1500), '1.5 GB');
      expect(formatMegabytes(3000), '2.9 GB');
    });

    test('drops below MB when the remainder is small, instead of "0.0 MB"', () {
      // The old SABnzbd-only formatter bottomed out at MB and printed
      // "0.5 MB" for half a megabyte; the shared ladder goes all the way down.
      expect(formatMegabytes(0.5), '512 KB');
    });
  });

  group('formatKilobytesPerSecond', () {
    test('reads SABnzbd kbpersec', () {
      expect(formatKilobytesPerSecond(0), '0 B/s');
      expect(formatKilobytesPerSecond(512), '512 KB/s');
      expect(formatKilobytesPerSecond(2048.5), '2.0 MB/s');
    });
  });
}

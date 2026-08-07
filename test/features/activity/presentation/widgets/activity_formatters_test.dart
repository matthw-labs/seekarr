import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/utils/release_utils.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_formatters.dart';

void main() {
  group('formatActivitySize', () {
    test('reads the same ladder as the queue sheet next to it', () {
      // The Activity detail sheet renders "Size" twice — the queue half through
      // formatActivityBytes, the history half through this — and the two used
      // to disagree, because this one was a GB-only ladder: 297 MB printed as
      // "0.29 GB" and 2 TiB as "2048.00 GB".
      for (final bytes in const [
        512,
        311385129,
        5307309140,
        8003897815,
        2199023255552,
      ]) {
        expect(formatActivitySize(bytes), formatActivityBytes(bytes));
        expect(formatActivitySize(bytes), formatReleaseSize(bytes));
      }

      expect(formatActivitySize(311385129), '297 MB');
      expect(formatActivitySize(2199023255552), '2.00 TB');
    });

    test('parses the loosely typed shapes the arr JSON arrives in', () {
      expect(formatActivitySize('8003897815'), '7.45 GB');
      expect(formatActivitySize(8003897815.4), '7.45 GB');
    });

    test('answers the em dash for anything that is not a size', () {
      expect(formatActivitySize(null), '—');
      expect(formatActivitySize('not a number'), '—');
      expect(formatActivitySize(double.nan), '—');
      expect(formatActivitySize(double.infinity), '—');
    });
  });
}

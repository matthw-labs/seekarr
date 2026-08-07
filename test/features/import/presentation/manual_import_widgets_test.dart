import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/features/import/presentation/manual_import_widgets.dart';

void main() {
  group('formatImportBytes', () {
    test('keeps the "no size reported" sentinel', () {
      expect(formatImportBytes(0), 'Unknown size');
      expect(formatImportBytes(-1), 'Unknown size');
    });

    test('renders every rung through the shared precise ladder', () {
      // The point of the test is the agreement, not the strings: manual import
      // used to carry its own ladder (`unit <= 1 ? 0 : 1` decimals, no rung
      // above TB), so a file that read "5.0 GB" while being imported read
      // "5.00 GB" in the qBittorrent list it landed in.
      for (final size in const [
        512,
        1024,
        1023 * 1024,
        5 * 1024 * 1024,
        5 * 1024 * 1024 * 1024,
        2199023255552,
      ]) {
        expect(formatImportBytes(size), formatBytesPrecise(size));
      }

      expect(formatImportBytes(512), '512 B');
      expect(formatImportBytes(5 * 1024 * 1024 * 1024), '5.00 GB');
      expect(formatImportBytes(2199023255552), '2.00 TB');
    });
  });
}

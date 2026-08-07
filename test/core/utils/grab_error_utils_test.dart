import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/grab_error_utils.dart';

void main() {
  group('translateGrabError', () {
    test('returns timeout message for 504 gateway timeout', () {
      final message = translateGrabError(
        Exception('Error 504 Gateway Timeout'),
      );

      expect(
        message,
        'Indexer timeout - the indexer took too long to respond. (Error 504)',
      );
    });

    test('returns server error message for 500 errors', () {
      final message = translateGrabError(
        Exception('500 Internal Server Error'),
      );

      expect(
        message,
        'This release may already be downloading or available. Check your download queue. (Error 500)',
      );
    });

    test('returns already exists message', () {
      final message = translateGrabError(Exception('Item already exists'));

      expect(
        message,
        'This item is already in your library or download queue.',
      );
    });

    test('returns disk space message', () {
      final message = translateGrabError(Exception('Not enough disk space'));

      expect(message, 'Not enough disk space for this download.');
    });

    test('returns generic timeout message', () {
      final message = translateGrabError(
        Exception('Connection timeout after 30s'),
      );

      expect(message, 'Request timed out. Please try again.');
    });

    test('returns fallback message with status code', () {
      final message = translateGrabError(Exception('403 Forbidden'));

      expect(message, 'Failed to grab release (Error 403): 403 Forbidden');
    });

    test('returns fallback message without status code', () {
      final message = translateGrabError(Exception('Network unreachable'));

      expect(message, 'Failed to grab release: Network unreachable');
    });

    test('uses trailing error segment for colon separated errors', () {
      final message = translateGrabError(
        Exception('Request failed: Upstream unavailable'),
      );

      expect(message, 'Failed to grab release: Upstream unavailable');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/features/bazarr/domain/bazarr_subtitle_status.dart';

void main() {
  group('bazarrSubtitleStatus', () {
    test('monitored resolves to a success-toned Monitored badge', () {
      final status = bazarrSubtitleStatus(monitored: true);
      expect(status.label, 'Monitored');
      expect(status.tone, StatusTone.success);
      expect(status.unmonitored, isFalse);
    });

    test('unmonitored resolves to a neutral Unmonitored badge', () {
      final status = bazarrSubtitleStatus(monitored: false);
      expect(status.label, 'Unmonitored');
      expect(status.tone, StatusTone.neutral);
      expect(status.unmonitored, isTrue);
    });
  });
}

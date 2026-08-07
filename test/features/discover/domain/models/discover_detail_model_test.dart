import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';

void main() {
  group('RelatedVideo.url', () {
    test('keeps an https url the server sent', () {
      final video = RelatedVideo.fromJson(const {
        'url': 'https://www.youtube.com/watch?v=abc',
        'key': 'abc',
        'site': 'YouTube',
        'name': 'Trailer',
        'type': 'Trailer',
      });

      expect(video.url, 'https://www.youtube.com/watch?v=abc');
    });

    test('falls back to the built url when the server sends a non-web one', () {
      // The URL is launched externally, so `Uri.tryParse` — a syntax check —
      // is not enough of a gate: these all parse.
      for (final hostile in const [
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'intent://evil#Intent;scheme=http;end',
        'file:///etc/passwd',
        'ftp://example.com/x',
        '//example.com/x',
      ]) {
        final video = RelatedVideo.fromJson({
          'url': hostile,
          'key': 'abc',
          'site': 'YouTube',
        });

        expect(
          video.url,
          'https://www.youtube.com/watch?v=abc',
          reason: 'rejected $hostile',
        );
      }
    });

    test('is empty when neither the url nor the site can be trusted', () {
      final video = RelatedVideo.fromJson(const {
        'url': 'javascript:alert(1)',
        'key': 'abc',
        'site': 'EvilTube',
      });

      // An empty url makes the row untappable — `playableVideos` drops it.
      expect(video.url, isEmpty);
    });
  });

  // The allowlist itself now lives on `UrlUtils.isLaunchableWebUrl`, shared with
  // the TrueNAS app-portal screen, and is exercised in
  // test/core/utils/url_utils_test.dart. What stays here is the part that is
  // this model's own: which field the guard is applied to, and what happens to a
  // video whose url it rejects.
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the screen-reader announcements a widget test triggers.
///
/// Announcements are platform messages on `SystemChannels.accessibility`, not
/// semantics-tree state, so no finder can see them — mocking the channel is the
/// only way to observe one.
///
/// This lives in `test_helpers/` rather than inline in each test file because it
/// mutates **global** binding state: a missed teardown leaks the mock handler
/// and the accessibility-features override into every later test in the file.
/// (That is also why the repo's usual per-file `_pumpX` convention does not
/// apply here — those differ per screen and share nothing.)
class SemanticsAnnouncementRecorder {
  SemanticsAnnouncementRecorder._();

  /// Announcement messages, in the order they were sent.
  final List<String> messages = <String>[];

  /// Installs the recorder and registers its own teardown.
  ///
  /// Call it **before** `pumpWidget` so the first build already sees the
  /// accessibility feature enabled.
  ///
  /// Pins `supportsAnnounce` on because the production `announce` helper
  /// short-circuits on `MediaQuery.supportsAnnounceOf`; pinning it keeps the test
  /// independent of the ambient default. Note that a hand-built
  /// `MediaQueryData(...)` defaults `supportsAnnounce` to false and would
  /// suppress announcements regardless of this — don't wrap the widget in one.
  static SemanticsAnnouncementRecorder install(WidgetTester tester) {
    final recorder = SemanticsAnnouncementRecorder._();

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(supportsAnnounce: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (Object? message) async {
        final envelope = message as Map<Object?, Object?>?;
        // The same channel also carries 'tooltip', 'tap' and 'longPress'.
        if (envelope != null && envelope['type'] == 'announce') {
          final data = envelope['data'] as Map<Object?, Object?>;
          recorder.messages.add(data['message']! as String);
        }
        return null;
      },
    );

    addTearDown(() {
      messenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        null,
      );
    });

    return recorder;
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/secure_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answerWith(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(SecureClipboard.channel, handler);
    addTearDown(
      () => messenger.setMockMethodCallHandler(SecureClipboard.channel, null),
    );
  }

  group('SecureClipboard.copySecret', () {
    test('hands the host the secret and the lifetime of the clip', () async {
      MethodCall? received;
      answerWith((call) async {
        received = call;
        return true;
      });

      final handled = await SecureClipboard.copySecret(
        'radarr-key',
        expiresIn: const Duration(seconds: 45),
      );

      expect(handled, isTrue);
      expect(received?.method, 'copySecret');
      // iOS expires the pasteboard item itself, so the duration has to cross the
      // channel rather than living only in the Dart-side timer.
      expect(received?.arguments, {
        'secret': 'radarr-key',
        'expiresInSeconds': 45,
      });
    });

    test('reports not handled when no host implements the channel', () async {
      // The fallback that keeps the copy button working on a platform with no
      // native side at all — desktop Linux/Windows, or any host where the
      // registration did not run.
      expect(
        await SecureClipboard.copySecret(
          'radarr-key',
          expiresIn: const Duration(seconds: 45),
        ),
        isFalse,
      );
    });

    test('reports not handled when the host has no such method', () async {
      // What `notImplemented()` looks like from Dart: the same
      // MissingPluginException an absent handler produces.
      answerWith((call) async => throw MissingPluginException());

      expect(
        await SecureClipboard.copySecret(
          'radarr-key',
          expiresIn: const Duration(seconds: 45),
        ),
        isFalse,
      );
    });

    test('reports not handled when the host refuses', () async {
      // What macOS 10.15 answers: it has no way to keep the clip off Universal
      // Clipboard, so it declines rather than copying unhardened behind the
      // caller's back.
      answerWith((call) async => false);

      expect(
        await SecureClipboard.copySecret(
          'radarr-key',
          expiresIn: const Duration(seconds: 45),
        ),
        isFalse,
      );
    });

    test('reports not handled when the host returns nothing', () async {
      answerWith((call) async => null);

      expect(
        await SecureClipboard.copySecret(
          'radarr-key',
          expiresIn: const Duration(seconds: 45),
        ),
        isFalse,
      );
    });

    test('reports not handled when the host throws', () async {
      answerWith(
        (call) async => throw PlatformException(code: 'no-clipboard-service'),
      );

      expect(
        await SecureClipboard.copySecret(
          'radarr-key',
          expiresIn: const Duration(seconds: 45),
        ),
        isFalse,
      );
    });

    test('never asks the host to copy nothing', () async {
      var called = false;
      answerWith((call) async {
        called = true;
        return true;
      });

      expect(
        await SecureClipboard.copySecret(
          '',
          expiresIn: const Duration(seconds: 45),
        ),
        isFalse,
      );
      expect(called, isFalse);
    });
  });
}

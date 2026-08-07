import 'package:flutter/services.dart';

/// Copies a credential using whatever the host OS offers to keep it off the
/// screen and off the user's other devices.
///
/// Flutter's [Clipboard] writes a plain clip, and a plain clip is a leak on two
/// of the three platforms this app ships to: Android 13+ renders a preview of
/// what was copied — the key in cleartext, on screen, over whatever is in front
/// of it — and Apple's general pasteboard syncs through Universal Clipboard to
/// every other device signed into the same account. Neither behaviour is
/// reachable from Dart: the flags that suppress them
/// (`ClipDescription.EXTRA_IS_SENSITIVE`, `UIPasteboardOptionLocalOnly` and
/// `UIPasteboardOptionExpirationDate`, `NSPasteboard.ContentsOptions
/// .currentHostOnly`) live on the native clipboard APIs, so this channel exists
/// to reach them.
///
/// [copySecret] answers whether the host actually wrote the clip, and it is
/// deliberately impossible for it to throw: an OS too old for the flags, a
/// platform with no handler registered, or a native failure all come back as
/// `false` so the caller can fall back to [Clipboard] and the copy button keeps
/// working. Hardening a copy is a bonus; a copy button that does nothing is a
/// bug.
abstract final class SecureClipboard {
  /// The host channel. Public so a test can stand in for the native side.
  static const MethodChannel channel = MethodChannel(
    'labs.matthw.seekarr/secure_clipboard',
  );

  /// Asks the host to put [secret] on the clipboard as sensitive content.
  ///
  /// [expiresIn] is passed through for the platforms that can expire a clip
  /// themselves (iOS); it does not replace the caller's own timed clear, which
  /// stays the only mitigation that works everywhere.
  ///
  /// Returns `true` only when the host reports it wrote the clip. On `false`
  /// nothing has been copied and the caller must fall back.
  static Future<bool> copySecret(
    String secret, {
    required Duration expiresIn,
  }) async {
    if (secret.isEmpty) {
      return false;
    }

    try {
      final handled = await channel.invokeMethod<bool>('copySecret', {
        'secret': secret,
        'expiresInSeconds': expiresIn.inSeconds,
      });
      return handled ?? false;
    } on MissingPluginException {
      // No native handler — a platform this app builds for but has not hardened,
      // or a test binding.
      return false;
    } on PlatformException {
      // The host tried and failed: an OS below the version that has the flags,
      // or no clipboard service at all.
      return false;
    } catch (_) {
      // Nothing about a copy button should be able to throw at the caller.
      return false;
    }
  }
}

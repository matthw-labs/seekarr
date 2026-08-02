import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Speaks [message] through the platform's screen reader.
///
/// Use this **only** where a state change leaves nothing new on screen: a
/// refresh that reloads the same list in place, a filter that reorders it, a
/// toggle whose only feedback was a colour. An announcement interrupts
/// VoiceOver's speech queue, so a spinner, a route change or a `SnackBar` is
/// always the better answer.
///
/// Two platform facts are worth knowing before reaching for this:
///
///  * A `SnackBar` already carries `liveRegion: true`, and so do dialogs and
///    error states. Announcing alongside one means the user hears it twice —
///    which is why `SnackBarHelper` deliberately does *not* route through here.
///  * Android deprecated announcement events: TalkBack clears its speech queue
///    when it receives one, so the engine reports
///    `AccessibilityFeatures.supportsAnnounce == false` there and this function
///    is a no-op. On Android the mechanism is `Semantics(liveRegion: true)` on
///    the widget that changed. So an announcement is a VoiceOver improvement,
///    never a message's only channel.
///
/// Wraps [SemanticsService.sendAnnouncement] rather than
/// `SemanticsService.announce`: the latter is deprecated after Flutter 3.35 and
/// CI runs `flutter analyze --fatal-infos`.
void announce(
  BuildContext context,
  String message, {
  Assertiveness assertiveness = Assertiveness.polite,
}) {
  if (message.isEmpty) return;
  // Checked here so call sites never have to branch on the platform.
  if (!MediaQuery.supportsAnnounceOf(context)) return;

  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
    assertiveness: assertiveness,
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:cupola/features/release_search/domain/release_search_job.dart';

/// What a finished search should say, if anything.
///
/// A pure function so the whole decision — including the rule that a finished
/// search never interrupts — is testable without a platform channel.
@immutable
class ReleaseSearchNotice {
  const ReleaseSearchNotice({required this.title, required this.body});

  final String title;
  final String body;
}

/// Composes the notice for a finished job, or null when none should be shown.
///
/// Three rules live here:
///
/// * **Nothing while the app is in the foreground.** The user is mid-task; the
///   badge lights and the detail page updates instead. A search completing must
///   never take the screen away from what they are doing.
/// * **A nil result still notifies.** Zero releases is the answer they were
///   waiting for, and withholding it makes the feature feel broken.
/// * **A failure names the target in the title.** A notification that does not
///   say *which* search stopped is useless.
ReleaseSearchNotice? noticeFor(
  ReleaseSearchJob job, {
  required bool appInForeground,
  required bool notificationsEnabled,
}) {
  if (!notificationsEnabled) return null;
  if (appInForeground) return null;
  if (job.isActive) return null;

  final label = job.target.label;

  return switch (job.status) {
    ReleaseSearchJobStatus.completed =>
      job.releaseCount == 0
          ? ReleaseSearchNotice(
              title: 'No releases found for $label',
              body: 'Your indexers answered — nothing matched.',
            )
          : ReleaseSearchNotice(
              title:
                  '${job.releaseCount} release'
                  '${job.releaseCount == 1 ? '' : 's'} for $label',
              body:
                  'Grabbable for ${kGrabWindow.inMinutes} minutes. '
                  'Tap to pick one.',
            ),
    ReleaseSearchJobStatus.failed =>
      job.failure?.kind == ReleaseSearchFailureKind.cancelled
          // Nobody needs telling about something they did on purpose.
          ? null
          : ReleaseSearchNotice(
              title: 'Search stopped — $label',
              body: job.failure?.headline ?? 'It did not finish.',
            ),
    _ => null,
  };
}

/// Posts the notices, and asks for permission only when the user opts in.
///
/// Permission is never requested at launch: it is requested the first time the
/// user switches "Notify me when one finishes" on, which is the only moment the
/// request means anything to them.
class ReleaseSearchNotifications {
  ReleaseSearchNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialised = false;

  /// One channel, default importance. Not high: a search the user asked for
  /// finishing is news, not an alarm.
  static const _androidChannelId = 'release_searches';
  static const _androidChannelName = 'Release searches';
  static const _androidChannelDescription =
      'Tells you when a background release search has finished.';

  /// Deliberately no `zonedSchedule` anywhere in this class — that single
  /// omission is what keeps the Android manifest at one permission and clear of
  /// the Play-restricted exact-alarm permissions.
  Future<void> initialise({void Function(String? payload)? onTap}) async {
    if (_initialised) return;
    _initialised = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Not requested here: asking at launch, before the user has expressed
        // any interest, is the pattern this deliberately avoids.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          onTap?.call(response.payload),
    );
  }

  /// Asks the OS, at the moment the user turns the toggle on.
  Future<bool> requestPermission() async {
    await initialise();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final darwin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (darwin != null) {
      return await darwin.requestPermissions(alert: true, sound: true) ?? false;
    }
    final mac = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (mac != null) {
      return await mac.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  Future<void> show(ReleaseSearchNotice notice, {required String jobId}) async {
    await initialise();
    await _plugin.show(
      id: jobId.hashCode,
      title: notice.title,
      body: notice.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: _androidChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      payload: jobId,
    );
  }
}

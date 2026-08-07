import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A release search, however it is actually performed.
///
/// The abstraction exists because Phase 2 changes the transport on two platforms
/// and not the others, and because every rule the feature enforces — adoption,
/// the concurrency cap, the verdicts — has to keep working the same either way.
/// Keeping the seam here means all of that stays testable without a plugin.
abstract interface class ReleaseSearchTransport {
  /// Runs the search and returns the raw release list.
  Future<List<dynamic>> run({
    required Uri url,
    required Map<String, String> headers,
    required Duration timeout,
    CancelToken? cancelToken,
  });

  /// Whether a search under this transport survives the app being backgrounded.
  /// Drives the phase-accurate promise the sheet makes.
  bool get survivesBackgrounding;

  /// A ceiling the platform imposes regardless of the user's own timeout, or null.
  Duration? get platformCeiling;
}

/// The foreground transport: the app's own Dio, guard and all.
///
/// Used on macOS, and anywhere the background path is unavailable — or unsafe.
/// macOS is not a compromise here, it is the better path: an unfocused desktop
/// app keeps running, so the request finishes on its own *and* keeps
/// `SameOriginRedirectInterceptor`, which the native path cannot. That same
/// guard is why a cleartext instance is sent here on every platform: this is
/// the only transport that can refuse a redirect rather than replay the API key
/// into it.
class ForegroundReleaseSearchTransport implements ReleaseSearchTransport {
  const ForegroundReleaseSearchTransport(this._get);

  final Future<Response<dynamic>> Function(
    Uri url, {
    Map<String, String>? headers,
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  })
  _get;

  @override
  bool get survivesBackgrounding => false;

  @override
  Duration? get platformCeiling => null;

  @override
  Future<List<dynamic>> run({
    required Uri url,
    required Map<String, String> headers,
    required Duration timeout,
    CancelToken? cancelToken,
  }) async {
    final response = await _get(
      url,
      headers: headers,
      receiveTimeout: timeout,
      cancelToken: cancelToken,
    );
    return response.data as List<dynamic>;
  }
}

/// The background transport: a native task that outlives suspension.
///
/// `DataTask` is not implemented as a data task on iOS — the library routes it
/// onto a real `URLSessionConfiguration.background`, which is what lets a
/// multi-minute request survive the app being suspended, and needs **no**
/// `UIBackgroundModes`.
///
/// **Only ever reached for an `https` origin**, and that is a boundary rather
/// than a preference — see `ReleaseSearchReach.whileOpenCleartext`, which is
/// where the reasoning lives and where the choice is actually made. In short:
/// this path cannot use `SameOriginRedirectInterceptor` and the plugin has no
/// redirect control of any kind (its own README states "redirects will be
/// followed"), while every stack underneath it strips only `Authorization` and
/// `Cookie` across origins and replays a custom `X-Api-Key` verbatim. A
/// redirect on this path is therefore a handover of the arr admin key, and the
/// only attacker who can *inject* one — as opposed to the instance itself,
/// which already holds the key — needs cleartext to do it. So cleartext takes
/// the in-app path instead, and [run] refuses anything but `https` outright so
/// a future call site cannot quietly undo that.
///
/// Refusing the *response* is not a substitute and never was: by the time
/// [decodeReleaseResponse] rejects a non-JSON body the credential has already
/// been sent. It stays as a second line, for a redirect that is merely a
/// misconfigured proxy.
///
/// One limit is carried honestly rather than hidden: Android's WorkManager
/// stops the job at nine minutes and the library's foreground escape is not
/// wired for this task type, so [platformCeiling] reports it and the verdict
/// names it.
class BackgroundReleaseSearchTransport implements ReleaseSearchTransport {
  /// [transmit], [cancelTask] and [grace] exist so the task's whole lifetime —
  /// the watchdog, the cancellation, the refusals — is testable offline.
  /// Production passes none of them and gets the plugin and [watchdogGrace].
  const BackgroundReleaseSearchTransport({
    Future<TaskStatusUpdate> Function(DataTask task)? transmit,
    Future<void> Function(String taskId)? cancelTask,
    this.grace = watchdogGrace,
  }) : _transmit = transmit,
       _cancelTask = cancelTask;

  final Future<TaskStatusUpdate> Function(DataTask task)? _transmit;
  final Future<void> Function(String taskId)? _cancelTask;

  /// This instance's watchdog grace. Only a test passes anything but
  /// [watchdogGrace] — one cannot wait thirty real seconds to prove a ceiling.
  final Duration grace;

  /// WorkManager stops a job here, and the library's `runInForeground` escape is
  /// never applied to a `DataTask`. Lifting it would cost a Play-restricted
  /// foreground-service permission and a review video, to gain headroom above a
  /// five-minute default — so the ceiling is accepted and stated instead.
  static const androidCeiling = Duration(minutes: 9);

  /// How long past the user's own ceiling the watchdog waits before it gives up
  /// on a task the plugin has stopped talking about.
  ///
  /// Not zero, because the clock here starts when the task is *enqueued*, and
  /// the native side still has to pick it up and report back — cutting at
  /// exactly the ceiling would turn that latency into a phantom timeout.
  static const watchdogGrace = Duration(seconds: 30);

  @override
  bool get survivesBackgrounding => true;

  @override
  Duration? get platformCeiling => Platform.isAndroid ? androidCeiling : null;

  @override
  Future<List<dynamic>> run({
    required Uri url,
    required Map<String, String> headers,
    required Duration timeout,
    CancelToken? cancelToken,
  }) async {
    // The invariant the class comment rests on, asserted at the point the
    // credential would actually be handed to native code. Reach decides this
    // long before here; this is what makes a wrong decision fail closed.
    //
    // A `StateError` rather than a `DioException` on purpose: nothing about the
    // network went wrong, the transport was simply used against its contract,
    // and `classifyReleaseSearchFailure` carries a non-Dio error's own text
    // into the verdict's detail — where "could not reach the service", which is
    // what an untyped `DioException` would produce, would be a lie.
    if (url.scheme != 'https') {
      throw StateError(
        'Background release search refuses a ${url.scheme}:// origin: a native '
        'task cannot be told to refuse a redirect, and a redirect replays the '
        'API key to whatever host it names.',
      );
    }

    // Nothing is enqueued for a search that is already cancelled: the task
    // carries the API key, and the plugin writes it to disk the moment it is
    // accepted.
    if (cancelToken?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: _releaseRequestOptions(),
        reason: 'cancelled',
      );
    }

    final task = DataTask(
      url: url.toString(),
      headers: headers,
      httpRequestMethod: 'GET',
      // Priority 0 is what routes this onto the OS's own job service on Android
      // 14+; it is also the only lever available for this task type.
      priority: 0,
      retries: 0,
    );

    var settled = false;

    // Cancelling is not a courtesy here, it is the cleanup. The plugin persists
    // the whole task — headers, so the API key — in plaintext (Android's default
    // SharedPreferences, iOS's `taskDescription` and, when the Dart side is
    // unreachable, `UserDefaults`), and removes it only when the task reaches a
    // **final** state. `canceled` is one; a task nobody ever finalises is not,
    // and leaves the key on disk for as long as the OS keeps the record.
    Future<void> discard() async {
      try {
        await (_cancelTask ?? _cancelViaPlugin)(task.taskId);
      } catch (_) {
        // Already gone, or no plugin behind it at all. Either way there is
        // nothing left here to clean up, and a search that already answered
        // must not fail over its own housekeeping.
      }
    }

    unawaited(cancelToken?.whenCancel.then((_) => settled ? null : discard()));

    try {
      final result = await (_transmit ?? _transmitViaPlugin)(task).timeout(
        timeout + grace,
        onTimeout: () {
          // Two things are wrong by now and both want the same answer: the
          // plugin can lose a task silently ("may disappear without
          // providing any status"), and nothing native enforces the user's
          // own ceiling — iOS would hold the task, key included, until the
          // resource timeout hours later. Reported as `failed` so it lands
          // in the timeout vocabulary the classifier already speaks.
          unawaited(discard());
          return TaskStatusUpdate(task, TaskStatus.failed);
        },
      );
      return decodeReleaseResponse(
        status: result.status,
        body: result.responseBody,
        statusCode: result.responseStatusCode,
      );
    } finally {
      settled = true;
    }
  }

  static Future<TaskStatusUpdate> _transmitViaPlugin(DataTask task) =>
      FileDownloader().transmit(task);

  static Future<void> _cancelViaPlugin(String taskId) =>
      FileDownloader().cancelTaskWithId(taskId);
}

/// The request the whole feature describes, for errors raised before or instead
/// of a real response. Matches what the arr services actually call.
RequestOptions _releaseRequestOptions() =>
    RequestOptions(path: '/api/v3/release');

/// Turns a background task's outcome into either releases or a `DioException`
/// the existing classifier already understands.
///
/// Separated out and public so the whole translation is testable without running
/// a native task — which is the only way this path can be covered at all.
List<dynamic> decodeReleaseResponse({
  required TaskStatus status,
  required String? body,
  required int? statusCode,
}) {
  final options = _releaseRequestOptions();

  if (status == TaskStatus.canceled) {
    throw DioException.requestCancelled(
      requestOptions: options,
      reason: 'cancelled',
    );
  }

  if (status != TaskStatus.complete) {
    // A task that simply stops is the case the library warns about: it "may
    // disappear without providing any status". Reported as a timeout so the
    // classifier can weigh it against the configured ceiling rather than
    // inventing a third vocabulary for it.
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.receiveTimeout,
      error: 'background task ${status.name}',
    );
  }

  if (statusCode != null && statusCode >= 400) {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: statusCode,
      ),
    );
  }

  // Parsed defensively: a gateway's HTML landing page throws `FormatException`
  // here, which would escape the feature's whole verdict vocabulary and surface
  // as "stopped unexpectedly" instead of something the user can act on.
  Object? decoded;
  if (body != null && body.isNotEmpty) {
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      decoded = null;
    }
  }
  if (decoded is List) return decoded;

  // Anything that is not a JSON list did not come from the API — most likely a
  // gateway's own page. Refused rather than trusted, which is this path's
  // stand-in for the redirect guard it cannot use.
  throw DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    error: 'unexpected response body',
  );
}

/// The plugin-wide ceiling on how long a task may live, set once in `main()`.
///
/// This is the *only* limit that still applies while the app is suspended — the
/// transport's own watchdog is a Dart `Timer`, which does not fire until the app
/// resumes. It therefore bounds two things that matter more than a download: how
/// long a task carrying the service's API key in its headers can exist, and how
/// long the plugin's plaintext task record (Android `taskMap`, iOS
/// `UserDefaults`) keeps that header on disk before the task reaches a final
/// state and is deleted.
///
/// So it is pinned just above the longest search the settings screen allows,
/// rather than at the library's hour: nothing here downloads a file, only a JSON
/// release list, and an hour left a credential-bearing task alive for ~50
/// minutes after the user's own ceiling had passed. The grace covers the same
/// enqueue-to-pickup latency [BackgroundReleaseSearchTransport.watchdogGrace]
/// does, widened because this clock is the coarse one.
///
/// Note for anyone changing it: the plugin accepts `resourceTimeout` only once,
/// before the first task, and persists it in native preferences — a device that
/// already stored the old hour keeps it until this value is written again.
const Duration kBackgroundSearchResourceTimeout = Duration(minutes: 11);

/// Whether this platform can run a search that outlives suspension.
///
/// iOS and Android only. macOS deliberately stays on the foreground path: it does
/// not suspend apps, so there is nothing to survive, and staying on `ApiClient`
/// keeps the redirect guard the native path gives up.
///
/// Reads `dart:io`'s [Platform] rather than [defaultTargetPlatform], and the
/// difference is load-bearing: `flutter_test` reports `defaultTargetPlatform` as
/// Android, so a check on that would send every widget test down a native path
/// with no plugin behind it. `Platform` reports the host, which under test is the
/// desktop running it — the foreground path, where a stubbed service still works.
/// The [platform] parameter exists so the rule itself stays unit-testable.
bool backgroundSearchSupported({TargetPlatform? platform}) {
  if (platform != null) {
    return platform == TargetPlatform.iOS || platform == TargetPlatform.android;
  }
  return Platform.isIOS || Platform.isAndroid;
}

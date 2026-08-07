import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';

/// How long Sonarr keeps a found release grabbable.
///
/// Not a value we chose: `ReleaseController` caches each mapped release for
/// `TimeSpan.FromMinutes(30)` and a grab afterwards is a bare 404
/// (`Couldn't find requested release in cache, try searching again`). Every
/// countdown in this feature is derived from it, so if upstream changes this,
/// this constant is the single place to correct.
const kGrabWindow = Duration(minutes: 30);

/// How long an expired job stays visible before it is evicted.
const kExpiredTail = Duration(minutes: 10);

/// The most jobs kept at once, newest first.
const kMaxJobs = 20;

enum ReleaseSearchJobStatus {
  /// Waiting for a concurrency slot. A first-class state, not a disguised
  /// [running] — the user is told the search has not started yet.
  queued,
  running,

  /// Finished with a result, which may be an empty list. Zero releases is a
  /// legitimate answer, not a failure.
  completed,
  failed,

  /// Finished, but Sonarr no longer holds the releases, so nothing here can be
  /// grabbed without searching again.
  expired,
}

/// Why a search stopped, classified well enough to tell the user something they
/// can act on.
///
/// The distinction that matters is not the exception type but *who* gave up: a
/// gateway in the middle, our own client, the server, or the operating system.
enum ReleaseSearchFailureKind {
  /// A reverse proxy or CDN closed the connection. The server is probably still
  /// searching, which is why retrying immediately is the wrong move.
  gatewayTimeout,

  /// The path goes through Cloudflare, whose 100 s cap cannot be raised on a
  /// free plan.
  cloudflareCap,

  /// Our own `receiveTimeout` fired.
  clientTimeout,

  /// The connection went away — most often because the device left the network
  /// that can reach the instance.
  connectionLost,

  /// The service itself answered with an error, typically an indexer throwing.
  serverError,

  /// The app was sent to the background while the search was in flight, and the
  /// request did not survive it. Phase 1 cannot prevent this.
  interruptedByBackground,

  /// Cancelled deliberately.
  cancelled,

  unknown,
}

@immutable
class ReleaseSearchFailure {
  const ReleaseSearchFailure({
    required this.kind,
    required this.headline,
    required this.diagnosis,
    this.detail,
    this.gateway,
  });

  final ReleaseSearchFailureKind kind;

  /// Plain words naming what happened. Never an exception string.
  final String headline;

  /// Why it happened and what to do, in the user's terms.
  final String diagnosis;

  /// The raw exception, kept because a self-hoster can genuinely act on
  /// "502 · nginx" — but always demoted beneath the headline, never the message.
  final String? detail;

  /// The intermediary named by the response, when one identified itself.
  final String? gateway;

  /// Whether offering an immediate retry would make things worse.
  ///
  /// After a gateway cut the connection the server is very likely still
  /// searching, so a second attempt puts a second load on the same indexers.
  bool get retryIsHarmful =>
      kind == ReleaseSearchFailureKind.gatewayTimeout ||
      kind == ReleaseSearchFailureKind.cloudflareCap;
}

/// One background release search.
@immutable
class ReleaseSearchJob {
  const ReleaseSearchJob({
    required this.id,
    required this.target,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.releases,
    this.failure,
    this.elapsed = Duration.zero,
    this.runningSince,
    this.wasBackgrounded = false,
    this.resultsOpened = false,
  });

  /// Unique within a session. Not persisted in Phase 1.
  final String id;
  final ReleaseSearchTarget target;
  final ReleaseSearchJobStatus status;

  /// When the search actually began. Null-safe by construction: a queued job
  /// carries the time it was queued, and [elapsed] stays zero until it runs.
  final DateTime startedAt;

  /// When the search actually left the queue — which is what elapsed counts from,
  /// since a job can sit queued for a while first.
  final DateTime? runningSince;

  final DateTime? finishedAt;

  /// Raw release maps, exactly as the sheet already consumes them.
  final List<dynamic>? releases;

  final ReleaseSearchFailure? failure;

  /// Time spent searching, **stamped when the search finished**.
  ///
  /// Zero while a job is still running: [elapsedAt] derives that from the clock
  /// instead. The alternative — a timer in the manager incrementing this once a
  /// second — kept the widget tree permanently dirty, which means no test using
  /// `pumpAndSettle` could ever settle while a search was in flight. A derived
  /// value costs nothing and makes the manager purely event-driven.
  final Duration elapsed;

  /// Whether the app went to the background at any point while this job ran.
  /// The failure classifier uses it to blame the OS instead of the network.
  final bool wasBackgrounded;

  /// Whether the user has opened this job's releases. Drives the nav badge,
  /// which counts finished searches nobody has looked at yet.
  final bool resultsOpened;

  /// How long this search has been going, or took.
  ///
  /// Live for a running job, frozen for a finished one.
  Duration elapsedAt(DateTime now) => status == ReleaseSearchJobStatus.running
      ? now.difference(runningSince ?? startedAt)
      : elapsed;

  bool get isActive =>
      status == ReleaseSearchJobStatus.queued ||
      status == ReleaseSearchJobStatus.running;

  /// True when this job has releases that can still be grabbed.
  bool get isGrabbable =>
      status == ReleaseSearchJobStatus.completed &&
      (releases?.isNotEmpty ?? false);

  /// How long the releases stay grabbable, or null when there is no window —
  /// a job that has not completed, or one already expired.
  Duration? grabWindowRemaining(DateTime now) {
    final finished = finishedAt;
    if (finished == null) return null;
    if (status != ReleaseSearchJobStatus.completed) return null;
    final remaining = kGrabWindow - now.difference(finished);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether the grab window has closed, given [now].
  bool hasExpired(DateTime now) {
    final finished = finishedAt;
    if (finished == null) return false;
    if (status != ReleaseSearchJobStatus.completed) return false;
    return now.difference(finished) >= kGrabWindow;
  }

  /// Whether the job should be dropped entirely, given [now].
  bool shouldEvict(DateTime now) {
    final finished = finishedAt;
    if (finished == null) return false;
    if (status != ReleaseSearchJobStatus.expired) return false;
    return now.difference(finished) >= kGrabWindow + kExpiredTail;
  }

  int get releaseCount => releases?.length ?? 0;

  ReleaseSearchJob copyWith({
    ReleaseSearchJobStatus? status,
    DateTime? runningSince,
    DateTime? finishedAt,
    List<dynamic>? releases,
    ReleaseSearchFailure? failure,
    Duration? elapsed,
    bool? wasBackgrounded,
    bool? resultsOpened,
  }) {
    return ReleaseSearchJob(
      id: id,
      target: target,
      status: status ?? this.status,
      startedAt: startedAt,
      runningSince: runningSince ?? this.runningSince,
      finishedAt: finishedAt ?? this.finishedAt,
      releases: releases ?? this.releases,
      failure: failure ?? this.failure,
      elapsed: elapsed ?? this.elapsed,
      wasBackgrounded: wasBackgrounded ?? this.wasBackgrounded,
      resultsOpened: resultsOpened ?? this.resultsOpened,
    );
  }
}

/// Resolves a job to the app's closed status vocabulary.
///
/// Lives here rather than in a widget because statuses arrive at the UI already
/// resolved — a badge renders a tone, it never derives one.
///
/// Two judgments are deliberate. A **completed search that found nothing takes
/// no tone at all**: green would be a lie and amber would make a working stack
/// look broken, when in fact the answer arrived correctly. And an **expired job
/// is calm, not alarming** — a window closing is normal for this product, so it
/// reads as unlit rather than as a fault.
StatusTone releaseSearchTone(ReleaseSearchJob job) {
  return switch (job.status) {
    ReleaseSearchJobStatus.queued => StatusTone.neutral,
    ReleaseSearchJobStatus.running => StatusTone.info,
    ReleaseSearchJobStatus.completed =>
      job.releaseCount == 0 ? StatusTone.neutral : StatusTone.success,
    ReleaseSearchJobStatus.failed => StatusTone.error,
    ReleaseSearchJobStatus.expired => StatusTone.neutral,
  };
}

/// Classifies a thrown error into something the user can act on.
///
/// [wasBackgrounded] flips a connection failure from "your network went away" to
/// "the app was suspended", which is the difference between a problem the user
/// should investigate and a limitation of the build they are running.
/// [reach] then decides *which* limitation: [ReleaseSearchReach.whileOpen] is
/// a platform fact with nothing to fix, [ReleaseSearchReach.whileOpenTrustedCert]
/// is permanent until the certificate is trusted at the OS level rather than
/// only inside Seekarr, [ReleaseSearchReach.whileOpenCleartext] lifts the moment
/// the instance is reached over https, and only [ReleaseSearchReach.beyondTheApp]
/// should never reach this branch at all — backgrounding does not interrupt it.
ReleaseSearchFailure classifyReleaseSearchFailure(
  Object error, {
  required Duration elapsed,
  required Duration configuredTimeout,
  bool wasBackgrounded = false,
  ReleaseSearchReach reach = ReleaseSearchReach.beyondTheApp,
}) {
  if (error is DioException && CancelToken.isCancel(error)) {
    return const ReleaseSearchFailure(
      kind: ReleaseSearchFailureKind.cancelled,
      headline: 'Search cancelled.',
      diagnosis: 'Nothing was sent to your indexers after you stopped it.',
    );
  }

  if (error is! DioException) {
    return ReleaseSearchFailure(
      kind: ReleaseSearchFailureKind.unknown,
      headline: 'The search stopped unexpectedly.',
      diagnosis: 'Searching again is safe — nothing was grabbed.',
      detail: error.toString(),
    );
  }

  final response = error.response;
  final status = response?.statusCode;
  final gateway = _gatewayFrom(response);

  // A gateway that closes the connection answers with its own status or its own
  // HTML, never the service's JSON.
  if (status == 502 || status == 504 || status == 503) {
    if (gateway != null && gateway.toLowerCase().contains('cloudflare')) {
      return ReleaseSearchFailure(
        kind: ReleaseSearchFailureKind.cloudflareCap,
        headline:
            'Cloudflare closed the connection after '
            '${_readable(elapsed)}.',
        diagnosis:
            'Cloudflare caps a request at 100 seconds and that limit cannot be '
            'raised on a free plan. Reach this instance over Tailscale or your '
            'LAN for long searches.',
        detail: 'HTTP $status · $gateway',
        gateway: gateway,
      );
    }
    return ReleaseSearchFailure(
      kind: ReleaseSearchFailureKind.gatewayTimeout,
      headline:
          'Your reverse proxy closed the connection after '
          '${_readable(elapsed)}.',
      diagnosis:
          '${_serviceWord(gateway)} is probably still searching. Starting again '
          'now would put a second search on the same indexers — raise the read '
          'timeout for this proxy host first.',
      detail: gateway == null ? 'HTTP $status' : 'HTTP $status · $gateway',
      gateway: gateway,
    );
  }

  if (status != null && status >= 500) {
    return ReleaseSearchFailure(
      kind: ReleaseSearchFailureKind.serverError,
      headline: 'The service reported an error.',
      diagnosis:
          'Usually an indexer throwing rather than the service itself. Checking '
          'indexer health will say which one.',
      detail: 'HTTP $status',
      gateway: gateway,
    );
  }

  final isTimeout =
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.connectionTimeout;

  if (wasBackgrounded) {
    return ReleaseSearchFailure(
      kind: ReleaseSearchFailureKind.interruptedByBackground,
      headline: 'Stopped when you left Seekarr.',
      diagnosis: switch (reach) {
        // Backgrounding a search that survives it should never land here —
        // named rather than silently falling through the generic case below,
        // so a bug in the resolver reads as a wrong sentence, not a crash.
        ReleaseSearchReach.beyondTheApp =>
          'The search cannot continue while the app is in the background. '
              'Searching again asks your indexers a second time.',
        ReleaseSearchReach.whileOpenTrustedCert =>
          'This instance uses a certificate trusted only inside Seekarr, and '
              'background search cannot see that trust — it needs the app '
              'open. Installing the certificate on this device would '
              'restore it. Searching again asks your indexers a second '
              'time.',
        ReleaseSearchReach.whileOpenCleartext =>
          'This instance is reached over plain http, so its searches stay in '
              'the app: a background search there could be redirected into '
              'handing its API key to another host, and only the in-app path '
              'can refuse that. Switching the instance to https restores '
              'background search. Searching again asks your indexers a '
              'second time.',
        ReleaseSearchReach.whileOpen =>
          'The search cannot continue while the app is in the background on '
              'this platform. Searching again asks your indexers a second '
              'time.',
      },
      detail: error.type.name,
    );
  }

  if (isTimeout) {
    // `connection_failure.dart` cannot separate our own ceiling from a stalled
    // socket, so elapsed against the configured timeout is the discriminator:
    // at the ceiling it was us, well short of it the connection went away.
    final atCeiling = elapsed >= configuredTimeout * 0.9;
    if (atCeiling) {
      return ReleaseSearchFailure(
        kind: ReleaseSearchFailureKind.clientTimeout,
        headline: 'Seekarr stopped waiting after ${_readable(elapsed)}.',
        diagnosis:
            'The search may still finish on the server. You can raise how long '
            'Seekarr waits in Settings.',
        detail: error.type.name,
      );
    }
    return ReleaseSearchFailure(
      kind: ReleaseSearchFailureKind.connectionLost,
      headline: 'Lost the connection after ${_readable(elapsed)}.',
      diagnosis:
          'Did the device leave the network that reaches this instance? '
          'Searching again is safe.',
      detail: error.type.name,
    );
  }

  return ReleaseSearchFailure(
    kind: ReleaseSearchFailureKind.connectionLost,
    headline: 'Could not reach the service.',
    diagnosis: 'Check the address and that the instance is running.',
    detail: error.type.name,
  );
}

/// Names the intermediary when the response identified one.
String? _gatewayFrom(Response<dynamic>? response) {
  if (response == null) return null;
  final headers = response.headers;
  if (headers.value('cf-ray') != null) return 'Cloudflare';
  final server = headers.value('server');
  if (server == null || server.isEmpty) return null;
  return server;
}

String _serviceWord(String? gateway) =>
    gateway == null ? 'The service' : 'The service behind $gateway';

String _readable(Duration d) {
  if (d.inMinutes == 0) return '${d.inSeconds}s';
  final seconds = d.inSeconds % 60;
  return seconds == 0
      ? '${d.inMinutes}m'
      : '${d.inMinutes}:${seconds.toString().padLeft(2, '0')}';
}

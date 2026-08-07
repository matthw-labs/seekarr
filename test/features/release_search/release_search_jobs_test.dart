import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/features/release_search/domain/release_search_job.dart';
import 'package:seekarr/features/release_search/domain/release_search_reach.dart';
import 'package:seekarr/features/release_search/domain/release_search_target.dart';
import 'package:seekarr/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// A clock the test moves by hand, so the 30-minute grab window can be crossed
/// without waiting for it.
class _FakeClock {
  DateTime value = DateTime.utc(2026, 8, 5, 9, 0);
  DateTime call() => value;
  void advance(Duration d) => value = value.add(d);
}

void main() {
  late ProviderContainer container;
  late _FakeClock clock;

  ReleaseSearchJobsNotifier notifier() =>
      container.read(releaseSearchJobsProvider.notifier);
  List<ReleaseSearchJob> jobs() => container.read(releaseSearchJobsProvider);

  setUp(() {
    clock = _FakeClock();
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  /// Wires a runner whose completion the test controls per target.
  Map<ReleaseSearchTarget, Completer<List<dynamic>>> wireManualRunner({
    int concurrency = kDefaultSearchConcurrency,
  }) {
    final completers = <ReleaseSearchTarget, Completer<List<dynamic>>>{};
    notifier().configure(
      now: clock.call,
      concurrency: concurrency,
      runner: (target, token) {
        final completer = completers.putIfAbsent(
          target,
          Completer<List<dynamic>>.new,
        );
        return completer.future;
      },
    );
    return completers;
  }

  final season2 = ReleaseSearchTarget.season(
    seriesId: 1,
    seasonNumber: 2,
    label: 'Severance · Season 2',
  );
  final season1 = ReleaseSearchTarget.season(
    seriesId: 1,
    seasonNumber: 1,
    label: 'Severance · Season 1',
  );
  final episodeInSeason2 = ReleaseSearchTarget.episode(
    episodeId: 44,
    seriesId: 1,
    seasonNumber: 2,
    label: 'Severance · S02E04',
  );
  final movie = ReleaseSearchTarget.movie(movieId: 9, label: 'Dune: Part Two');

  group('containment', () {
    test('an episode is covered by its own season, not another', () {
      expect(episodeInSeason2.isCoveredBy(season2), isTrue);
      expect(episodeInSeason2.isCoveredBy(season1), isFalse);
    });

    test('containment is one-directional', () {
      // A season search is not answered by an episode search — it needs more.
      expect(season2.isCoveredBy(episodeInSeason2), isFalse);
      expect(season2.conflictsWith(episodeInSeason2), isTrue);
    });

    test('an album is covered by its artist', () {
      final artist = ReleaseSearchTarget.artist(artistId: 3, label: 'Artist');
      final album = ReleaseSearchTarget.album(
        albumId: 7,
        artistId: 3,
        label: 'Album',
      );
      expect(album.isCoveredBy(artist), isTrue);
      expect(artist.isCoveredBy(album), isFalse);
    });

    test('an episode with no known season cannot be matched to one', () {
      // Without the parent ids there is nothing to compare, and guessing would
      // adopt a job that does not actually cover this episode.
      final orphan = ReleaseSearchTarget.episode(episodeId: 44, label: 'E04');
      expect(orphan.isCoveredBy(season2), isFalse);
    });

    test('targets across services never relate', () {
      expect(movie.conflictsWith(season2), isFalse);
    });
  });

  group('deduplication', () {
    test('starting the same target twice adopts the running job', () {
      wireManualRunner();

      final first = notifier().start(season2);
      final second = notifier().start(season2);

      expect(second.id, first.id);
      expect(jobs(), hasLength(1));
    });

    test('an episode adopts a running season search', () {
      wireManualRunner();

      final seasonJob = notifier().start(season2);
      final adopted = notifier().start(episodeInSeason2);

      expect(adopted.id, seasonJob.id);
      expect(jobs(), hasLength(1));
    });

    test('a season waits for a running episode instead of competing', () {
      wireManualRunner();

      notifier().start(episodeInSeason2);
      final seasonJob = notifier().start(season2);

      // Two distinct jobs — a season needs more than the episode's results — but
      // the season must not hit the same indexers at the same time.
      expect(jobs(), hasLength(2));
      expect(
        notifier().jobById(seasonJob.id)!.status,
        ReleaseSearchJobStatus.queued,
      );
    });

    test('unrelated targets run side by side', () {
      wireManualRunner();

      notifier().start(season2);
      notifier().start(movie);

      expect(
        jobs().where((j) => j.status == ReleaseSearchJobStatus.running),
        hasLength(2),
      );
    });
  });

  group('concurrency', () {
    test(
      'holds a third search at the cap and starts it when a slot frees',
      () async {
        final completers = wireManualRunner();

        notifier().start(season2);
        notifier().start(movie);
        final third = notifier().start(season1);

        expect(
          notifier().jobById(third.id)!.status,
          ReleaseSearchJobStatus.queued,
          reason: 'the default cap is two concurrent searches',
        );

        completers[movie]!.complete(const []);
        await pumpEventQueue();

        expect(
          notifier().jobById(third.id)!.status,
          ReleaseSearchJobStatus.running,
        );
      },
    );
  });

  group('completion and the grab window', () {
    test('a completed search carries its releases and a live window', () async {
      final completers = wireManualRunner();
      final job = notifier().start(season2);

      completers[season2]!.complete([
        {'guid': 'a'},
        {'guid': 'b'},
      ]);
      await pumpEventQueue();

      final done = notifier().jobById(job.id)!;
      expect(done.status, ReleaseSearchJobStatus.completed);
      expect(done.releaseCount, 2);
      expect(done.isGrabbable, isTrue);
      expect(done.grabWindowRemaining(clock.value), kGrabWindow);
    });

    test('zero releases is a completed answer with no tone at all', () async {
      final completers = wireManualRunner();
      final job = notifier().start(season2);

      completers[season2]!.complete(const []);
      await pumpEventQueue();

      final done = notifier().jobById(job.id)!;
      expect(done.status, ReleaseSearchJobStatus.completed);
      expect(done.isGrabbable, isFalse);
      // Green would be a lie and amber would make a working stack look broken.
      expect(releaseSearchTone(done), StatusTone.neutral);
    });

    test('releases found carry the success tone', () async {
      final completers = wireManualRunner();
      final job = notifier().start(season2);
      completers[season2]!.complete([
        {'guid': 'a'},
      ]);
      await pumpEventQueue();

      expect(
        releaseSearchTone(notifier().jobById(job.id)!),
        StatusTone.success,
      );
    });

    test(
      'the window closes after thirty minutes and drains, not alarms',
      () async {
        final completers = wireManualRunner();
        final job = notifier().start(season2);
        completers[season2]!.complete([
          {'guid': 'a'},
        ]);
        await pumpEventQueue();

        clock.advance(const Duration(minutes: 31));
        notifier().refreshWindows();

        final expired = notifier().jobById(job.id)!;
        expect(expired.status, ReleaseSearchJobStatus.expired);
        expect(expired.isGrabbable, isFalse);
        expect(releaseSearchTone(expired), StatusTone.neutral);
      },
    );

    test('an expired job is evicted after its tail', () async {
      final completers = wireManualRunner();
      final job = notifier().start(season2);
      completers[season2]!.complete(const []);
      await pumpEventQueue();

      clock.advance(const Duration(minutes: 31));
      notifier().refreshWindows();
      expect(notifier().jobById(job.id), isNotNull);

      clock.advance(kExpiredTail);
      notifier().refreshWindows();
      expect(notifier().jobById(job.id), isNull);
    });

    test('a fresh result is offered back, an expired one is not', () async {
      final completers = wireManualRunner();
      notifier().start(season2);
      completers[season2]!.complete([
        {'guid': 'a'},
      ]);
      await pumpEventQueue();

      expect(notifier().freshResultsFor(season2), isNotNull);

      clock.advance(const Duration(minutes: 31));
      expect(notifier().freshResultsFor(season2), isNull);
    });

    test(
      'searchAgain replaces the finished job rather than stacking one',
      () async {
        final completers = wireManualRunner();
        notifier().start(season2);
        completers[season2]!.complete([
          {'guid': 'a'},
        ]);
        await pumpEventQueue();

        notifier().searchAgain(season2);

        expect(jobs(), hasLength(1));
        expect(jobs().single.status, ReleaseSearchJobStatus.running);
      },
    );
  });

  group('cancellation', () {
    test('cancelling stops the job and says nothing was sent', () {
      wireManualRunner();
      final job = notifier().start(season2);

      notifier().cancel(job.id);

      final stopped = notifier().jobById(job.id)!;
      expect(stopped.status, ReleaseSearchJobStatus.failed);
      expect(stopped.failure!.kind, ReleaseSearchFailureKind.cancelled);
    });

    test('a later error does not overwrite the cancellation verdict', () async {
      final completers = wireManualRunner();
      final job = notifier().start(season2);

      notifier().cancel(job.id);
      completers[season2]!.completeError(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      await pumpEventQueue();

      expect(
        notifier().jobById(job.id)!.failure!.kind,
        ReleaseSearchFailureKind.cancelled,
      );
    });

    test('changing a service connection cancels only that service', () {
      wireManualRunner();
      final sonarrJob = notifier().start(season2);
      final radarrJob = notifier().start(movie);

      notifier().cancelForService(ServiceKey.sonarr);

      expect(
        notifier().jobById(sonarrJob.id)!.status,
        ReleaseSearchJobStatus.failed,
      );
      expect(
        notifier().jobById(sonarrJob.id)!.failure!.headline,
        contains('connection changed'),
      );
      expect(
        notifier().jobById(radarrJob.id)!.status,
        ReleaseSearchJobStatus.running,
      );
    });

    test('a search queued past the grab window is dropped, not run', () {
      wireManualRunner(concurrency: 1);
      notifier().start(season2);
      final queued = notifier().start(movie);
      expect(
        notifier().jobById(queued.id)!.status,
        ReleaseSearchJobStatus.queued,
      );

      clock.advance(const Duration(minutes: 31));
      notifier().refreshWindows();

      final dropped = notifier().jobById(queued.id)!;
      expect(dropped.status, ReleaseSearchJobStatus.failed);
      expect(dropped.failure!.headline, contains('queued too long ago'));
    });
  });

  group('the badge count', () {
    test('counts finished searches nobody has opened', () async {
      final completers = wireManualRunner();
      final job = notifier().start(season2);
      completers[season2]!.complete([
        {'guid': 'a'},
      ]);
      await pumpEventQueue();

      expect(container.read(unseenReleaseSearchCountProvider), 1);

      notifier().markResultsOpened(job.id);
      expect(container.read(unseenReleaseSearchCountProvider), 0);
    });

    test('a running search does not count', () {
      wireManualRunner();
      notifier().start(season2);
      expect(container.read(unseenReleaseSearchCountProvider), 0);
    });
  });

  group('failure classification', () {
    ReleaseSearchFailure classify(
      Object error, {
      Duration elapsed = const Duration(seconds: 62),
      bool wasBackgrounded = false,
    }) {
      return classifyReleaseSearchFailure(
        error,
        elapsed: elapsed,
        configuredTimeout: const Duration(minutes: 5),
        wasBackgrounded: wasBackgrounded,
      );
    }

    DioException withResponse(
      int status, {
      Map<String, List<String>>? headers,
    }) {
      final options = RequestOptions(path: '/api/v3/release');
      return DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: status,
          headers: Headers.fromMap(headers ?? const {}),
        ),
        type: DioExceptionType.badResponse,
      );
    }

    test(
      'a 502 blames the proxy and refuses to suggest an immediate retry',
      () {
        final failure = classify(
          withResponse(
            502,
            headers: {
              'server': ['nginx'],
            },
          ),
        );
        expect(failure.kind, ReleaseSearchFailureKind.gatewayTimeout);
        expect(failure.retryIsHarmful, isTrue);
        expect(failure.headline, contains('1:02'));
        expect(failure.detail, contains('nginx'));
      },
    );

    test('Cloudflare is named, with its cap called unraisable', () {
      final failure = classify(
        withResponse(
          502,
          headers: {
            'cf-ray': ['abc123'],
          },
        ),
      );
      expect(failure.kind, ReleaseSearchFailureKind.cloudflareCap);
      expect(failure.diagnosis, contains('cannot be'));
      expect(failure.gateway, 'Cloudflare');
    });

    test('a 500 blames the service, and points at indexer health', () {
      final failure = classify(withResponse(500));
      expect(failure.kind, ReleaseSearchFailureKind.serverError);
      expect(failure.diagnosis, contains('indexer'));
      expect(failure.retryIsHarmful, isFalse);
    });

    test('a timeout at our own ceiling blames us, not the network', () {
      final failure = classify(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
        elapsed: const Duration(minutes: 5),
      );
      expect(failure.kind, ReleaseSearchFailureKind.clientTimeout);
      expect(failure.headline, contains('Seekarr stopped waiting'));
    });

    test('a timeout well short of the ceiling blames the connection', () {
      final failure = classify(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
        elapsed: const Duration(seconds: 20),
      );
      expect(failure.kind, ReleaseSearchFailureKind.connectionLost);
      expect(failure.diagnosis, contains('leave the network'));
    });

    test('a backgrounded job blames the OS rather than the network', () {
      final failure = classify(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
        elapsed: const Duration(seconds: 20),
        wasBackgrounded: true,
      );
      expect(failure.kind, ReleaseSearchFailureKind.interruptedByBackground);
      expect(failure.headline, contains('left Seekarr'));
    });

    test('a certificate trusted only in-app names the cause and the remedy, '
        'and never says "yet"', () {
      // "Yet" was Phase-1 language: it implied background support was
      // coming. For this reach it is permanent until the certificate is
      // trusted at the OS level, so implying a roadmap fix would mislead.
      final failure = classifyReleaseSearchFailure(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
        elapsed: const Duration(seconds: 20),
        configuredTimeout: const Duration(minutes: 5),
        wasBackgrounded: true,
        reach: ReleaseSearchReach.whileOpenTrustedCert,
      );
      expect(failure.kind, ReleaseSearchFailureKind.interruptedByBackground);
      expect(failure.diagnosis, contains('certificate'));
      expect(failure.diagnosis, contains('Installing the certificate'));
      expect(failure.diagnosis.toLowerCase(), isNot(contains('yet')));
    });

    test('a plain platform limit (macOS) is worded as a platform fact, not a '
        'certificate one', () {
      final failure = classifyReleaseSearchFailure(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
        elapsed: const Duration(seconds: 20),
        configuredTimeout: const Duration(minutes: 5),
        wasBackgrounded: true,
        reach: ReleaseSearchReach.whileOpen,
      );
      expect(failure.diagnosis, isNot(contains('certificate')));
      expect(failure.diagnosis.toLowerCase(), isNot(contains('yet')));
    });

    test('a cancellation is never reported as a fault', () {
      final options = RequestOptions();
      final failure = classify(
        DioException(requestOptions: options, type: DioExceptionType.cancel),
      );
      expect(failure.kind, ReleaseSearchFailureKind.cancelled);
    });

    test('a non-Dio error still produces something actionable', () {
      final failure = classify(StateError('boom'));
      expect(failure.kind, ReleaseSearchFailureKind.unknown);
      expect(failure.diagnosis, contains('nothing was grabbed'));
      expect(failure.detail, contains('boom'));
    });
  });

  group('backgrounding', () {
    test('a failure after backgrounding is attributed to the OS', () async {
      final completers = wireManualRunner();
      final job = notifier().start(season2);

      notifier().noteBackgrounded();
      completers[season2]!.completeError(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      await pumpEventQueue();

      expect(
        notifier().jobById(job.id)!.failure!.kind,
        ReleaseSearchFailureKind.interruptedByBackground,
      );
    });

    test('a search that survives backgrounding still completes', () async {
      final completers = wireManualRunner();
      final job = notifier().start(season2);

      notifier().noteBackgrounded();
      completers[season2]!.complete([
        {'guid': 'a'},
      ]);
      await pumpEventQueue();

      // Android often does survive, and iOS survives a brief switch — the
      // manager must not pre-emptively fail a job that came back with results.
      expect(
        notifier().jobById(job.id)!.status,
        ReleaseSearchJobStatus.completed,
      );
    });
  });
}

import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/release_search/data/release_search_notifications.dart';
import 'package:cupola/features/release_search/data/release_search_transport.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/fake_services.dart';
import '../../test_helpers/settings_scope.dart';

/// Records that the *service* answered the search, which is the whole claim.
class _RecordingSonarrService extends FakeSonarrService {
  int releaseCalls = 0;

  @override
  Future<List<dynamic>> getReleases({
    int? seriesId,
    int? seasonNumber,
    int? episodeId,
    CancelToken? cancelToken,
  }) async {
    releaseCalls++;
    return const [];
  }
}

final _target = ReleaseSearchTarget.season(
  seriesId: 1,
  seasonNumber: 2,
  label: 'Severance · Season 2',
);

/// A saved URL that is reached over TLS, which is the only kind of origin the
/// native background task may ever carry an API key to.
const _httpsBase = 'https://sonarr.example.com';

/// The same instance over cleartext — where a redirect can be injected by
/// anyone on the path, and the native task would replay `X-Api-Key` into it.
const _httpBase = 'http://sonarr.example.com:8989';

final _httpsSearch = Uri.parse('$_httpsBase/api/v3/release?seriesId=1');
final _httpSearch = Uri.parse('$_httpBase/api/v3/release?seriesId=1');

/// The header the whole exercise is about.
const _credentialHeaders = {'X-Api-Key': 'the-arr-admin-key'};

TaskStatusUpdate _completed(
  DataTask task, {
  String body = '[]',
  int code = 200,
}) => TaskStatusUpdate(task, TaskStatus.complete, null, body, null, code);

ReleaseSearchJob _job({
  required ReleaseSearchJobStatus status,
  int releaseCount = 0,
  ReleaseSearchFailure? failure,
}) {
  return ReleaseSearchJob(
    id: 'rs-1',
    target: _target,
    status: status,
    startedAt: DateTime.utc(2026, 8, 5, 9),
    finishedAt: DateTime.utc(2026, 8, 5, 9, 2),
    releases: List.generate(releaseCount, (i) => {'guid': 'g$i'}),
    failure: failure,
  );
}

void main() {
  group('platform selection', () {
    test('only iOS and Android get the background transport', () {
      expect(backgroundSearchSupported(platform: TargetPlatform.iOS), isTrue);
      expect(
        backgroundSearchSupported(platform: TargetPlatform.android),
        isTrue,
      );
      // macOS stays on the foreground path on purpose: it does not suspend apps,
      // so there is nothing to survive — and staying on `ApiClient` keeps the
      // redirect guard the native path has to give up.
      expect(
        backgroundSearchSupported(platform: TargetPlatform.macOS),
        isFalse,
      );
    });

    test('reach depends on both the platform and the pin (ADR-6)', () {
      // beyondTheApp only when the platform can survive suspension AND
      // nothing about the origin stops it.
      expect(
        reachFor(
          ServiceKey.sonarr,
          baseUrl: _httpsBase,
          certTrustedInApp: false,
          platform: TargetPlatform.android,
        ),
        ReleaseSearchReach.beyondTheApp,
      );
      // A pinned origin cuts it off even where the platform could survive —
      // the native task cannot see an in-app trust at all.
      expect(
        reachFor(
          ServiceKey.sonarr,
          baseUrl: _httpsBase,
          certTrustedInApp: true,
          platform: TargetPlatform.android,
        ),
        ReleaseSearchReach.whileOpenTrustedCert,
      );
      expect(
        reachFor(
          ServiceKey.sonarr,
          baseUrl: _httpsBase,
          certTrustedInApp: true,
          platform: TargetPlatform.iOS,
        ),
        ReleaseSearchReach.whileOpenTrustedCert,
      );
      // macOS has nothing to survive regardless of the pin — a platform fact,
      // not a certificate limitation, so it must not read as one.
      expect(
        reachFor(
          ServiceKey.sonarr,
          baseUrl: _httpsBase,
          certTrustedInApp: false,
          platform: TargetPlatform.macOS,
        ),
        ReleaseSearchReach.whileOpen,
      );
      expect(
        reachFor(
          ServiceKey.sonarr,
          baseUrl: _httpsBase,
          certTrustedInApp: true,
          platform: TargetPlatform.macOS,
        ),
        ReleaseSearchReach.whileOpen,
      );
    });

    test('a cleartext instance never gets the background transport', () {
      // The one case here that is a security boundary rather than a capability
      // gap. The native task follows redirects with no way to stop it, and
      // every stack under it strips only `Authorization`/`Cookie` across
      // origins — a custom `X-Api-Key` is replayed to whatever a 302 names. The
      // attacker who can *inject* that 302 (as opposed to the instance itself,
      // which already holds the key) needs cleartext to do it, so cleartext is
      // exactly where the background path stops.
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        expect(
          reachFor(
            ServiceKey.sonarr,
            baseUrl: _httpBase,
            certTrustedInApp: false,
            platform: platform,
          ),
          ReleaseSearchReach.whileOpenCleartext,
          reason: '$platform must fall back to the in-app redirect guard',
        );
      }
    });

    test('the rule is about the scheme, not about the host', () {
      // A scheme-less saved URL is dialled over https by
      // `UrlUtils.normalizeBaseUrl`, so reading it as cleartext would take
      // background search away from a correctly configured instance for
      // nothing. And a LAN address over https keeps it: the danger is the
      // cleartext, not the address space.
      expect(
        reachFor(
          ServiceKey.sonarr,
          baseUrl: 'sonarr.example.com:8989',
          certTrustedInApp: false,
          platform: TargetPlatform.android,
        ),
        ReleaseSearchReach.beyondTheApp,
      );
      expect(
        reachFor(
          ServiceKey.sonarr,
          baseUrl: 'https://192.168.1.10:8989',
          certTrustedInApp: false,
          platform: TargetPlatform.android,
        ),
        ReleaseSearchReach.beyondTheApp,
      );
      // Including the LAN: an on-path attacker on the same network is the
      // textbook case, so a private address earns no exemption here.
      expect(
        reachFor(
          ServiceKey.sonarr,
          baseUrl: 'http://192.168.1.10:8989',
          certTrustedInApp: false,
          platform: TargetPlatform.android,
        ),
        ReleaseSearchReach.whileOpenCleartext,
      );
    });

    test('every searchable service is held to it, not just Sonarr', () {
      for (final service in [
        ServiceKey.sonarr,
        ServiceKey.radarr,
        ServiceKey.lidarr,
      ]) {
        expect(
          reachFor(
            service,
            baseUrl: _httpBase,
            certTrustedInApp: false,
            platform: TargetPlatform.iOS,
          ),
          ReleaseSearchReach.whileOpenCleartext,
        );
      }
    });

    test('only the background transport claims to survive suspension', () {
      expect(
        const BackgroundReleaseSearchTransport().survivesBackgrounding,
        isTrue,
      );
      expect(
        ForegroundReleaseSearchTransport(
          (url, {headers, receiveTimeout, cancelToken}) async =>
              Response<dynamic>(requestOptions: RequestOptions()),
        ).survivesBackgrounding,
        isFalse,
      );
    });
  });

  group('what the transport hands to native code', () {
    test('a cleartext URL is refused before the key leaves Dart', () async {
      // Belt to the reach braces: reach decides this long before here, and this
      // is what makes a future call site that gets it wrong fail closed. The
      // refusal has to happen *before* the task exists, because the plugin
      // writes the task — headers included — to disk the moment it accepts it.
      var transmitted = 0;
      final transport = BackgroundReleaseSearchTransport(
        transmit: (task) async {
          transmitted++;
          return _completed(task);
        },
        cancelTask: (_) async {},
      );

      await expectLater(
        transport.run(
          url: _httpSearch,
          headers: _credentialHeaders,
          timeout: kReleaseSearchReceiveTimeout,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('http://'), contains('redirect')),
          ),
        ),
      );
      expect(
        transmitted,
        0,
        reason: 'no task may be enqueued for a cleartext origin at all',
      );
    });

    test('the refusal reaches the user as a verdict, not a crash', () async {
      // Whatever the transport throws has to survive the classifier, because a
      // failure it cannot read surfaces as "stopped unexpectedly" with nothing
      // to act on. A non-Dio error keeps its own text in the detail.
      final failure = classifyReleaseSearchFailure(
        StateError('Background release search refuses a http:// origin'),
        elapsed: Duration.zero,
        configuredTimeout: kReleaseSearchReceiveTimeout,
      );
      expect(failure.kind, ReleaseSearchFailureKind.unknown);
      expect(failure.detail, contains('http://'));
    });

    test('an https URL runs and its releases come back', () async {
      DataTask? enqueued;
      final transport = BackgroundReleaseSearchTransport(
        transmit: (task) async {
          enqueued = task;
          return _completed(task, body: '[{"guid":"a"}]');
        },
        cancelTask: (_) async {},
      );

      final releases = await transport.run(
        url: _httpsSearch,
        headers: _credentialHeaders,
        timeout: kReleaseSearchReceiveTimeout,
      );

      expect(releases, hasLength(1));
      expect(enqueued!.url, _httpsSearch.toString());
      expect(enqueued!.headers, containsPair('X-Api-Key', 'the-arr-admin-key'));
      // A retry would re-run a full indexer pass *and* re-persist the key.
      expect(enqueued!.retries, 0);
    });
  });

  group("the background task's lifetime", () {
    // Why any of this matters: the plugin persists the whole task — headers, so
    // the API key — in plaintext on device, and removes it only when the task
    // reaches a *final* state. A task nobody finalises leaves the credential on
    // disk for as long as the OS keeps the record, which defeats the point of
    // holding it in secure storage. Cancelling is the removal.

    test(
      'a search that already answered is not cancelled afterwards',
      () async {
        final cancelled = <String>[];
        final transport = BackgroundReleaseSearchTransport(
          transmit: (task) async => _completed(task),
          cancelTask: (id) async => cancelled.add(id),
        );

        await transport.run(
          url: _httpsSearch,
          headers: _credentialHeaders,
          timeout: kReleaseSearchReceiveTimeout,
        );

        expect(cancelled, isEmpty, reason: 'completion already finalises it');
      },
    );

    test('a token cancelled before the run enqueues nothing', () async {
      var transmitted = 0;
      final token = CancelToken()..cancel();
      final transport = BackgroundReleaseSearchTransport(
        transmit: (task) async {
          transmitted++;
          return _completed(task);
        },
        cancelTask: (_) async {},
      );

      Object? thrown;
      try {
        await transport.run(
          url: _httpsSearch,
          headers: _credentialHeaders,
          timeout: kReleaseSearchReceiveTimeout,
          cancelToken: token,
        );
      } catch (e) {
        thrown = e;
      }

      expect(CancelToken.isCancel(thrown! as DioException), isTrue);
      expect(
        transmitted,
        0,
        reason: 'a stopped search must not write a credential to disk',
      );
    });

    test('cancelling mid-flight cancels the native task', () async {
      // The defect this guards: the transport used to ignore its `CancelToken`
      // entirely, so stopping a search from the sheet left the native task
      // running — and its persisted copy of the API key on disk — until the OS
      // felt like ending it.
      final cancelled = <String>[];
      DataTask? enqueued;
      final pending = Completer<TaskStatusUpdate>();
      final transport = BackgroundReleaseSearchTransport(
        transmit: (task) {
          enqueued = task;
          return pending.future;
        },
        cancelTask: (id) async {
          cancelled.add(id);
          // What the plugin does once the native task reaches `canceled`.
          pending.complete(TaskStatusUpdate(enqueued!, TaskStatus.canceled));
        },
      );

      final token = CancelToken();
      final future = transport.run(
        url: _httpsSearch,
        headers: _credentialHeaders,
        timeout: kReleaseSearchReceiveTimeout,
        cancelToken: token,
      );
      token.cancel();

      Object? thrown;
      try {
        await future;
      } catch (e) {
        thrown = e;
      }

      expect(cancelled, [enqueued!.taskId]);
      expect(CancelToken.isCancel(thrown! as DioException), isTrue);
    });

    test(
      'the watchdog ends a task that outlives the configured ceiling',
      () async {
        // Nothing native enforces the configured timeout: Android's WorkManager
        // cap is nine minutes and iOS would hold the task, key and all, until the
        // resource timeout an hour later. So the ceiling is enforced here, and
        // enforcing it *cancels* rather than just walking away — walking away is
        // what leaves the credential on disk.
        final cancelled = <String>[];
        DataTask? enqueued;
        final transport = BackgroundReleaseSearchTransport(
          transmit: (task) {
            enqueued = task;
            return Completer<TaskStatusUpdate>().future; // never answers
          },
          cancelTask: (id) async => cancelled.add(id),
          grace: Duration.zero,
        );

        await expectLater(
          transport.run(
            url: _httpsSearch,
            headers: _credentialHeaders,
            timeout: const Duration(milliseconds: 10),
          ),
          throwsA(
            isA<DioException>().having(
              (e) => e.type,
              'type',
              DioExceptionType.receiveTimeout,
            ),
          ),
        );
        expect(cancelled, [enqueued!.taskId]);
      },
    );

    test('the shipped grace is above zero but well under the cap', () {
      // Zero would turn the native side's own pick-up latency into a phantom
      // timeout; anything near Android's nine minutes would stop being a
      // ceiling at all.
      expect(
        BackgroundReleaseSearchTransport.watchdogGrace,
        greaterThan(Duration.zero),
      );
      expect(
        BackgroundReleaseSearchTransport.watchdogGrace,
        lessThan(const Duration(minutes: 1)),
      );
    });

    test('the plugin-wide resource timeout sits just above the user cap', () {
      // The only ceiling left while the app is suspended, and therefore the one
      // that bounds how long a task carrying the API key exists and how long the
      // plugin's plaintext task record keeps that header on disk. It has to
      // clear the longest search the settings screen permits — otherwise the OS
      // would cut searches the app told the user it would run — while staying
      // close enough that it is a backstop rather than an hour of residue.
      expect(
        kBackgroundSearchResourceTimeout,
        greaterThan(ReleaseSearchSettings.maxTimeout),
      );
      expect(
        kBackgroundSearchResourceTimeout,
        lessThan(ReleaseSearchSettings.maxTimeout * 2),
      );
    });
  });

  group('choosing a transport from real settings', () {
    // The wiring the two security rules actually ride on: a saved URL, through
    // reach, to the transport that runs. `releaseSearchPlatformProvider` is
    // overridden because the test host is a desktop, where the native path is
    // never chosen and neither rule would ever be exercised.
    Future<ProviderContainer> containerFor(
      String sonarrUrl, {
      TargetPlatform platform = TargetPlatform.android,
    }) async {
      final scope = await settingsScope();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => scope.prefs),
          secureSettingsStoreProvider.overrideWith((ref) => scope.secureStore),
          initialSettingsProvider.overrideWith(
            (ref) => scope.settings.copyWithService(
              ServiceKey.sonarr,
              url: sonarrUrl,
              apiKey: 'the-arr-admin-key',
            ),
          ),
          releaseSearchPlatformProvider.overrideWith((ref) => platform),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an https instance still gets the background task', () async {
      final container = await containerFor(_httpsBase);
      expect(
        container.read(releaseSearchTransportProvider(ServiceKey.sonarr)),
        isA<BackgroundReleaseSearchTransport>(),
      );
    });

    test('a cleartext instance falls back to the in-app path', () async {
      final container = await containerFor(_httpBase);
      final transport = container.read(
        releaseSearchTransportProvider(ServiceKey.sonarr),
      );

      expect(transport, isNot(isA<BackgroundReleaseSearchTransport>()));
      // And the fallback is a real one: the sheet's promise is derived from
      // this flag, so a transport that lied here would tell the user their
      // search survives leaving the app when it does not.
      expect(transport.survivesBackgrounding, isFalse);
      expect(
        container.read(releaseSearchReachProvider(ServiceKey.sonarr)),
        ReleaseSearchReach.whileOpenCleartext,
      );
    });

    // Where the cleartext instance's redirect guard actually lives. The runner
    // short-circuits every non-backgrounding transport into the arr service, so
    // the request rides `ApiClient` — guard, pinned adapter and all — and the
    // foreground transport's own `run` is not what protects it.
    test('the in-app path runs through the arr service, not the transport', () {
      final service = _RecordingSonarrService();
      final container = ProviderContainer(
        overrides: [
          sonarrServiceProvider.overrideWithValue(service),
          releaseSearchTransportProvider(ServiceKey.sonarr).overrideWithValue(
            ForegroundReleaseSearchTransport(
              (url, {headers, receiveTimeout, cancelToken}) async =>
                  throw StateError('the transport must not be used here'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final runner = container.read(releaseSearchRunnerProvider);

      expect(runner(_target, CancelToken()), completion(isEmpty));
      expect(service.releaseCalls, 1);
    });

    test('macOS is unaffected by the scheme', () async {
      // Its reason for staying in the app is a platform fact, and it must keep
      // reading as one rather than as a security limitation of the instance.
      final container = await containerFor(
        _httpBase,
        platform: TargetPlatform.macOS,
      );
      expect(
        container.read(releaseSearchReachProvider(ServiceKey.sonarr)),
        ReleaseSearchReach.whileOpen,
      );
    });
  });

  group('decoding a background task result', () {
    test('a complete task with a JSON list yields releases', () {
      final releases = decodeReleaseResponse(
        status: TaskStatus.complete,
        body: '[{"guid":"a"},{"guid":"b"}]',
        statusCode: 200,
      );
      expect(releases, hasLength(2));
    });

    test('a cancelled task is reported as a cancellation, never a fault', () {
      Object? thrown;
      try {
        decodeReleaseResponse(
          status: TaskStatus.canceled,
          body: null,
          statusCode: null,
        );
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<DioException>());
      expect(CancelToken.isCancel(thrown! as DioException), isTrue);

      final failure = classifyReleaseSearchFailure(
        thrown,
        elapsed: const Duration(seconds: 30),
        configuredTimeout: const Duration(minutes: 5),
      );
      expect(failure.kind, ReleaseSearchFailureKind.cancelled);
    });

    test('a task that simply vanishes lands in the timeout vocabulary', () {
      // The library warns a task "may disappear without providing any status".
      // Reported as a timeout so the existing classifier can weigh it against the
      // configured ceiling rather than inventing a third vocabulary.
      expect(
        () => decodeReleaseResponse(
          status: TaskStatus.failed,
          body: null,
          statusCode: null,
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.receiveTimeout,
          ),
        ),
      );
    });

    test('a gateway status still reaches the gateway verdict', () {
      Object? thrown;
      try {
        decodeReleaseResponse(
          status: TaskStatus.complete,
          body: '<html>502</html>',
          statusCode: 502,
        );
      } catch (e) {
        thrown = e;
      }
      final failure = classifyReleaseSearchFailure(
        thrown!,
        elapsed: const Duration(seconds: 62),
        configuredTimeout: const Duration(minutes: 5),
      );
      expect(failure.kind, ReleaseSearchFailureKind.gatewayTimeout);
      expect(failure.retryIsHarmful, isTrue);
    });

    test('a body that is not a JSON list is refused, not trusted', () {
      // This path cannot use SameOriginRedirectInterceptor, so a gateway's own
      // landing page must fail rather than be parsed as an answer.
      expect(
        () => decodeReleaseResponse(
          status: TaskStatus.complete,
          body: '<html>Sign in to continue</html>',
          statusCode: 200,
        ),
        throwsA(isA<DioException>()),
      );
      expect(
        () => decodeReleaseResponse(
          status: TaskStatus.complete,
          body: '{"error":"nope"}',
          statusCode: 200,
        ),
        throwsA(isA<DioException>()),
      );
    });

    test('an empty body is refused rather than read as zero releases', () {
      // "No releases" is a legitimate answer, but it arrives as `[]`. An empty
      // body is a transport failure, and conflating them would report a search
      // as answered when it never was.
      expect(
        () => decodeReleaseResponse(
          status: TaskStatus.complete,
          body: '',
          statusCode: 200,
        ),
        throwsA(isA<DioException>()),
      );
      expect(
        decodeReleaseResponse(
          status: TaskStatus.complete,
          body: '[]',
          statusCode: 200,
        ),
        isEmpty,
      );
    });
  });

  group('what a finished search says', () {
    test('nothing at all while the app is in front of the user', () {
      // The rule: a finished search never interrupts. The badge lights and the
      // detail page updates instead.
      final notice = noticeFor(
        _job(status: ReleaseSearchJobStatus.completed, releaseCount: 14),
        appInForeground: true,
        notificationsEnabled: true,
      );
      expect(notice, isNull);
    });

    test('nothing when the user never asked to be told', () {
      final notice = noticeFor(
        _job(status: ReleaseSearchJobStatus.completed, releaseCount: 14),
        appInForeground: false,
        notificationsEnabled: false,
      );
      expect(notice, isNull);
    });

    test('a result names the count, the target and the shelf life', () {
      final notice = noticeFor(
        _job(status: ReleaseSearchJobStatus.completed, releaseCount: 14),
        appInForeground: false,
        notificationsEnabled: true,
      )!;
      expect(notice.title, contains('14 releases'));
      expect(notice.title, contains('Severance · Season 2'));
      expect(notice.body, contains('${kGrabWindow.inMinutes} minutes'));
    });

    test('a nil result still notifies', () {
      // It is the answer they were waiting for; withholding it makes the feature
      // feel broken.
      final notice = noticeFor(
        _job(status: ReleaseSearchJobStatus.completed),
        appInForeground: false,
        notificationsEnabled: true,
      )!;
      expect(notice.title, contains('No releases found'));
      expect(notice.title, contains('Severance · Season 2'));
    });

    test('a failure names the target in the title, not just the fault', () {
      final notice = noticeFor(
        _job(
          status: ReleaseSearchJobStatus.failed,
          failure: const ReleaseSearchFailure(
            kind: ReleaseSearchFailureKind.gatewayTimeout,
            headline: 'Your reverse proxy closed the connection after 1:02.',
            diagnosis: 'Still searching, probably.',
          ),
        ),
        appInForeground: false,
        notificationsEnabled: true,
      )!;
      expect(notice.title, contains('Severance · Season 2'));
      expect(notice.body, contains('reverse proxy'));
    });

    test('a cancellation is never announced', () {
      final notice = noticeFor(
        _job(
          status: ReleaseSearchJobStatus.failed,
          failure: const ReleaseSearchFailure(
            kind: ReleaseSearchFailureKind.cancelled,
            headline: 'Search cancelled.',
            diagnosis: 'Nothing was sent.',
          ),
        ),
        appInForeground: false,
        notificationsEnabled: true,
      );
      expect(notice, isNull, reason: 'the user did this on purpose');
    });

    test('a running search is never announced', () {
      final notice = noticeFor(
        _job(status: ReleaseSearchJobStatus.running),
        appInForeground: false,
        notificationsEnabled: true,
      );
      expect(notice, isNull);
    });
  });

  group("Android's ceiling", () {
    test('is stated as nine minutes rather than hidden', () {
      // The library's foreground escape is not wired for this task type, and
      // lifting the cap would cost a Play-restricted permission plus a review
      // video — so it is accepted and named.
      expect(
        BackgroundReleaseSearchTransport.androidCeiling,
        const Duration(minutes: 9),
      );
    });
  });
}

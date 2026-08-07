import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/release_search/data/release_search_notifications.dart';
import 'package:cupola/features/release_search/data/release_search_transport.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/presentation/release_search_headroom_provider.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_sheet.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The platform reach is resolved for. Null means "ask the host", which is what
/// production always wants.
///
/// It exists to be overridden: `flutter_test` runs on the desktop, so without
/// this the mobile branch — the only one that ever chooses the native transport,
/// and therefore the only one where the choice is a security decision — could
/// not be exercised from a test at all. See [backgroundSearchSupported] for why
/// the host is read through `dart:io` rather than `defaultTargetPlatform`.
final releaseSearchPlatformProvider = Provider<TargetPlatform?>((ref) => null);

/// How far a search against [service] can travel — see [ReleaseSearchReach].
///
/// Both facts reach asks about — the saved URL's scheme and whether that origin
/// is trusted only inside Seekarr (ADR-6) — are read straight from settings
/// rather than through `serviceDiagnosisProvider`: reach must stay correct even
/// for an instance that has never been tested this session.
final releaseSearchReachProvider =
    Provider.family<ReleaseSearchReach, ServiceKey>((ref, service) {
      final settings = ref.watch(currentSettingsProvider);
      final baseUrl = settings.urlFor(service);
      return reachFor(
        service,
        baseUrl: baseUrl,
        certTrustedInApp: settings.pinForUrl(baseUrl) != null,
        platform: ref.watch(releaseSearchPlatformProvider),
      );
    });

/// The transport for a search against [service].
///
/// iOS and Android get the native background task when nothing about
/// [service]'s origin stops it, which is what lets a search outlive
/// suspension. Every other case falls back to the foreground path, which stays
/// on `ApiClient`'s redirect guard and, when the origin is pinned, on the same
/// pinned adapter the real client uses:
///
/// * macOS, which does not suspend apps and so has nothing to survive;
/// * a certificate trusted only inside Seekarr, which the native task cannot
///   see at all;
/// * a cleartext `http://` origin, where the native task's unstoppable redirect
///   following would let anyone on the path collect the API key — the one case
///   here that is a security boundary rather than a capability gap.
final releaseSearchTransportProvider =
    Provider.family<ReleaseSearchTransport, ServiceKey>((ref, service) {
      final reach = ref.watch(releaseSearchReachProvider(service));
      if (reach == ReleaseSearchReach.beyondTheApp) {
        return const BackgroundReleaseSearchTransport();
      }

      final settings = ref.watch(currentSettingsProvider);
      final pin = settings.pinForUrl(settings.urlFor(service));
      return ForegroundReleaseSearchTransport((
        url, {
        headers,
        receiveTimeout,
        cancelToken,
      }) async {
        // Note what actually carries the guarantee: [releaseSearchRunnerProvider]
        // routes every non-backgrounding transport through `_searchViaService`,
        // so a cleartext instance's search runs on the arr service's own
        // `ApiClient` and it is *that* client's redirect guard which refuses to
        // replay the API key off-origin. This closure is the transport's own
        // `run`, reached only from a test today — it mirrors the same three
        // lines so the seam cannot become the hole if a caller ever does use it.
        // `SameOriginRedirectInterceptor` needs both options set to see the 3xx.
        final dio = Dio(
          BaseOptions(
            followRedirects: false,
            validateStatus: allowRedirectStatus,
          ),
        );
        dio.interceptors.add(SameOriginRedirectInterceptor(dio));
        final adapter = pinnedHttpClientAdapterFor(
          url.toString(),
          pinnedFingerprint: pin,
        );
        if (adapter != null) dio.httpClientAdapter = adapter;
        try {
          return await dio.getUri<dynamic>(
            url,
            options: Options(headers: headers, receiveTimeout: receiveTimeout),
            cancelToken: cancelToken,
          );
        } finally {
          // Built per request, so it has to be closed per request: a pinned
          // origin gives this `Dio` its own `HttpClient`, and one leaked per
          // search is a socket pool the app never reclaims.
          dio.close();
        }
      });
    });

/// Posts the "your search finished" notices.
final releaseSearchNotificationsProvider = Provider(
  (ref) => ReleaseSearchNotifications(),
);

/// Performs a release search for any supported target.
///
/// One place resolves the service, so the job manager never learns about Sonarr,
/// Radarr or Lidarr and a test can drive it with a plain function.
final releaseSearchRunnerProvider = Provider<ReleaseSearchRunner>((ref) {
  return (target, cancelToken) async {
    final transport = ref.read(releaseSearchTransportProvider(target.service));

    // The foreground path goes through the arr service rather than round-tripping
    // through a URL: it keeps `ApiClient`'s redirect guard, and it keeps every
    // existing test able to stub a service the way it always could.
    if (!transport.survivesBackgrounding) {
      return _searchViaService(ref, target, cancelToken);
    }

    final request = _describeRequest(ref, target);
    return transport.run(
      url: request.url,
      headers: request.headers,
      timeout: ref.read(releaseSearchSettingsProvider).timeout,
      cancelToken: cancelToken,
    );
  };
});

/// Runs the search through the service that owns the endpoint.
Future<List<dynamic>> _searchViaService(
  Ref ref,
  ReleaseSearchTarget target,
  CancelToken cancelToken,
) {
  switch (target.service) {
    case ServiceKey.sonarr:
      final service = ref.read(sonarrServiceProvider);
      return target.scope == ReleaseSearchScope.episode
          ? service.getReleases(episodeId: target.id, cancelToken: cancelToken)
          : service.getReleases(
              seriesId: target.id,
              seasonNumber: target.seasonNumber ?? 1,
              cancelToken: cancelToken,
            );
    case ServiceKey.radarr:
      return ref
          .read(radarrServiceProvider)
          .getReleases(target.id, cancelToken: cancelToken);
    case ServiceKey.lidarr:
      final service = ref.read(lidarrServiceProvider);
      return target.scope == ReleaseSearchScope.album
          ? service.getReleases(albumId: target.id, cancelToken: cancelToken)
          : service.getReleases(artistId: target.id, cancelToken: cancelToken);
    default:
      throw UnsupportedError(
        '${target.service.name} has no interactive release search',
      );
  }
}

/// Describes the search as a URL and headers.
///
/// One place resolves the service, so neither the job manager nor the transport
/// learns about Sonarr, Radarr or Lidarr.
({Uri url, Map<String, String> headers}) _describeRequest(
  Ref ref,
  ReleaseSearchTarget target,
) {
  switch (target.service) {
    case ServiceKey.sonarr:
      final service = ref.read(sonarrServiceProvider);
      return service.releaseSearchRequest(
        target.scope == ReleaseSearchScope.episode
            ? {'episodeId': target.id}
            : {'seriesId': target.id, 'seasonNumber': target.seasonNumber ?? 1},
      );
    case ServiceKey.radarr:
      return ref.read(radarrServiceProvider).releaseSearchRequest({
        'movieId': target.id,
      });
    case ServiceKey.lidarr:
      final service = ref.read(lidarrServiceProvider);
      return service.releaseSearchRequest(
        target.scope == ReleaseSearchScope.album
            ? {'albumId': target.id}
            : {'artistId': target.id},
      );
    default:
      throw UnsupportedError(
        '${target.service.name} has no interactive release search',
      );
  }
}

/// Grabs a release on the service that found it.
final releaseGrabberProvider =
    Provider<Future<void> Function(ServiceKey, String, int)>((ref) {
      return (service, guid, indexerId) async {
        switch (service) {
          case ServiceKey.sonarr:
            await ref
                .read(sonarrServiceProvider)
                .grabRelease(guid: guid, indexerId: indexerId);
          case ServiceKey.radarr:
            await ref
                .read(radarrServiceProvider)
                .grabRelease(guid: guid, indexerId: indexerId);
          case ServiceKey.lidarr:
            await ref
                .read(lidarrServiceProvider)
                .grabRelease(guid: guid, indexerId: indexerId);
          default:
            throw UnsupportedError('${service.name} cannot grab releases');
        }
      };
    });

/// The one way into interactive release search.
///
/// Every entry point in the app goes through here — the series, season, episode,
/// movie, artist and album actions, and the Wanted dispatcher — because the rules
/// that protect the user's indexers only hold if they cannot be bypassed:
///
/// * an in-flight search for this target, or one that **covers** it, is adopted
///   rather than duplicated — and the sheet says so, because adopting silently
///   would be work the user cannot see;
/// * a finished search whose releases are still grabbable is offered back
///   instead of spending another pass on the indexers.
Future<void> showReleaseSearch(
  BuildContext context,
  WidgetRef ref,
  ReleaseSearchTarget target,
) async {
  HapticFeedback.selectionClick();
  final notifier = ref.read(releaseSearchJobsProvider.notifier);
  final settings = ref.read(releaseSearchSettingsProvider);
  notifier.configure(
    runner: ref.read(releaseSearchRunnerProvider),
    reachFor: (service) => ref.read(releaseSearchReachProvider(service)),
    concurrency: settings.concurrency,
    timeout: settings.timeout,
    onFinished: (job) => _onSearchFinished(ref, job),
  );

  final adopted = notifier.activeJobCovering(target);
  final fresh = adopted == null ? notifier.freshResultsFor(target) : null;
  final job = adopted ?? fresh ?? notifier.start(target);

  await ReleaseSearchSheet.show(
    context: context,
    ref: ref,
    jobId: job.id,
    target: target,
    // Both disclosures exist for the same reason: the user asked for a search
    // and is about to be shown something that is not one.
    adoptedFrom: adopted != null && adopted.target != target
        ? adopted.target.label
        : null,
    reusedResults: fresh != null,
  );
}

/// Everything that happens when a search finishes, in one place.
void _onSearchFinished(WidgetRef ref, ReleaseSearchJob job) {
  _recordHeadroom(ref, job);

  final notice = noticeFor(
    job,
    appInForeground: ref.read(appInForegroundProvider),
    notificationsEnabled: ref
        .read(releaseSearchSettingsProvider)
        .notifyOnFinish,
  );
  if (notice == null) return;
  ref.read(releaseSearchNotificationsProvider).show(notice, jobId: job.id);
}

/// Feeds a finished search into what the headroom card knows.
///
/// Only a **cut-off** teaches anything about the ceiling: a lost connection or a
/// server error says nothing about how long the path allows, and folding those in
/// would report a limit that does not exist.
void _recordHeadroom(WidgetRef ref, ReleaseSearchJob job) {
  final notifier = ref.read(searchHeadroomProvider.notifier);
  final service = job.target.service;
  if (job.status == ReleaseSearchJobStatus.completed) {
    notifier.recordSuccess(service, job.elapsed);
    return;
  }
  final kind = job.failure?.kind;
  final isCutoff =
      kind == ReleaseSearchFailureKind.gatewayTimeout ||
      kind == ReleaseSearchFailureKind.cloudflareCap ||
      kind == ReleaseSearchFailureKind.clientTimeout;
  if (isCutoff) notifier.recordCutoff(service, job.elapsed);
}

/// Builds the target for a Sonarr season or whole-series action.
///
/// Sonarr's `/release` has no series-wide form, so the "whole series" button
/// searches season 1 — that is upstream behaviour, not a shortcut here.
ReleaseSearchTarget sonarrSeasonTarget({
  required int seriesId,
  required int? seasonNumber,
  required String label,
}) => ReleaseSearchTarget.season(
  seriesId: seriesId,
  seasonNumber: seasonNumber ?? 1,
  label: label,
);

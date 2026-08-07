import 'package:dio/dio.dart';

import 'package:seekarr/core/network/cert_trust.dart';
import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/network/redirect_guard.dart';
import 'package:seekarr/core/utils/url_utils.dart';

import 'package:seekarr/features/sabnzbd/domain/models/sabnzbd_models.dart';

/// Error thrown by [SabnzbdClient]. The message is always run through
/// [redactSabnzbdSecrets] so an API key (which SABnzbd carries in the request
/// URL query string) can never reach a log, snackbar or crash report. Carries
/// the [reason] so a caller verifying the connection can tell an unreachable
/// host from a rejected API key.
class SabnzbdException implements Exception, HasFailureReason {
  const SabnzbdException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
  });
  final String message;
  @override
  final ServiceFailureReason reason;
  @override
  String toString() => 'SabnzbdException: $message';
}

/// Strips secret query parameters (API key, credentials) from any string before
/// it can surface in an error message, log line or UI. Security standard
/// §10.2 #7: SABnzbd's key travels in the URL, so unredacted `DioException`
/// text would otherwise leak it.
String redactSabnzbdSecrets(String input) {
  return input.replaceAllMapped(
    RegExp(
      r'(apikey|apkey|ma_username|ma_password)=[^&\s]*',
      caseSensitive: false,
    ),
    (m) => '${m.group(1)}=***',
  );
}

/// Client for the SABnzbd HTTP API.
///
/// SABnzbd exposes a single `/api` endpoint driven by a `mode` query parameter
/// and authenticates with an `apikey` query parameter (not a header), so it
/// needs a dedicated client rather than the shared header-auth [ApiClient].
class SabnzbdClient {
  /// [certFingerprint], when non-empty, is a self-signed certificate the user
  /// explicitly trusted for this origin (trust-on-first-use, ADR-6). Ignored
  /// when [dio] is injected — a caller supplying its own transport owns its
  /// TLS behaviour too.
  SabnzbdClient({
    required String url,
    required String apiKey,
    Dio? dio,
    String? certFingerprint,
  }) : baseUrl = UrlUtils.normalizeBaseUrl(url),
       _apiKey = apiKey.trim() {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            // Follow redirects by hand. This client is the one that most needs
            // it: the API key travels in the **query string**, and a redirect
            // is resolved against `$request_uri`, which includes the query by
            // definition. `dart:io`'s only protection is a header filter — it
            // cannot strip a credential that is part of the URL — so a single
            // `return 301 https://elsewhere$request_uri;` in a reverse proxy
            // delivers the key to another host, where it lands in that
            // server's access log in plaintext.
            followRedirects: false,
            validateStatus: allowRedirectStatus,
          ),
        );
    if (dio == null) {
      _dio.interceptors.add(SameOriginRedirectInterceptor(_dio));
      final adapter = pinnedHttpClientAdapterFor(
        baseUrl,
        pinnedFingerprint: certFingerprint,
      );
      if (adapter != null) _dio.httpClientAdapter = adapter;
    }
  }

  final String baseUrl;
  final String _apiKey;
  late final Dio _dio;

  Future<Map<String, dynamic>> _call(
    String mode, {
    Map<String, dynamic>? extra,
    bool withKey = true,
  }) async {
    try {
      final response = await _dio.get(
        '/api',
        queryParameters: {
          'mode': mode,
          'output': 'json',
          if (withKey && _apiKey.isNotEmpty) 'apikey': _apiKey,
          ...?extra,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        // SABnzbd reports failures as {"status": false} — usually, but *not
        // always*, with an "error" string alongside. The bare form comes back
        // for a queue command against an unknown `nzo_id`, which is exactly
        // what a user hits by deleting a job that finished between the last
        // poll and the tap. Requiring the error string as well meant that
        // response fell through as a success and the UI cheerfully reported
        // "Job removed" for a call the server had refused.
        if (data['status'] == false) {
          final reported = data['error'];
          // SABnzbd answers 200 even for "API Key Incorrect", so the reason
          // has to come from the message.
          final message = reported == null
              ? 'SABnzbd rejected the request'
              : redactSabnzbdSecrets(reported.toString());
          throw SabnzbdException(
            message,
            reason: looksUnauthorizedMessage(message)
                ? ServiceFailureReason.unauthorized
                : ServiceFailureReason.unknown,
          );
        }
        return data;
      }
      if (data is String) {
        return {'_raw': data};
      }
      return const {};
    } on DioException catch (e) {
      throw SabnzbdException(
        redactSabnzbdSecrets(e.message ?? 'SABnzbd request failed'),
        reason: classifyConnectionFailure(e),
      );
    }
  }

  /// Server version. Does not require the API key, so it doubles as a
  /// lightweight reachability probe.
  Future<String> getVersion() async {
    final data = await _call('version', withKey: false);
    return (data['version'] ?? data['_raw'] ?? '').toString().trim();
  }

  /// The active download queue.
  Future<SabnzbdQueue> getQueue({int limit = 50}) async {
    final data = await _call('queue', extra: {'start': 0, 'limit': limit});
    final queue = (data['queue'] as Map?)?.cast<String, dynamic>();
    return SabnzbdQueue.fromJson(queue ?? const {});
  }

  /// Recent completed/failed downloads.
  Future<List<SabnzbdHistorySlot>> getHistory({int limit = 20}) async {
    final data = await _call('history', extra: {'start': 0, 'limit': limit});
    final history = (data['history'] as Map?)?.cast<String, dynamic>();
    final slots = (history?['slots'] as List?) ?? const [];
    return slots
        .whereType<Map>()
        .map((e) => SabnzbdHistorySlot.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Aggregate transfer statistics (total / month / week / day bytes).
  Future<SabnzbdServerStats> getServerStats() async {
    final data = await _call('server_stats');
    return SabnzbdServerStats.fromJson(data);
  }

  /// The configured categories, always including the `*` default first.
  Future<List<String>> getCategories() async {
    final data = await _call('get_cats');
    final cats = (data['categories'] as List?) ?? const [];
    return cats.map((e) => e.toString()).toList(growable: false);
  }

  /// Verifies the configured URL + key by fetching the queue (which requires
  /// authentication). Returns true on success.
  Future<bool> testConnection() async {
    await getQueue(limit: 1);
    return true;
  }

  /// Pauses the whole queue.
  Future<void> pause() async {
    await _call('pause');
  }

  /// Resumes the whole queue.
  Future<void> resume() async {
    await _call('resume');
  }

  /// Adds an NZB by URL. [category] defaults to SABnzbd's `*` and [priority]
  /// runs -2..2. The URL is passed via Dio's [queryParameters] so it is encoded
  /// automatically — never concatenated (security §10.2 #8).
  Future<void> addUrl(
    String nzbUrl, {
    String? category,
    int priority = 0,
  }) async {
    await _call(
      'addurl',
      extra: {
        'name': nzbUrl,
        if (category != null && category.isNotEmpty) 'cat': category,
        'priority': priority,
      },
    );
  }

  /// Pauses a single queued job by its NZO id.
  Future<void> pauseJob(String nzoId) async {
    await _call('queue', extra: {'name': 'pause', 'value': nzoId});
  }

  /// Resumes a single queued job by its NZO id.
  Future<void> resumeJob(String nzoId) async {
    await _call('queue', extra: {'name': 'resume', 'value': nzoId});
  }

  /// Deletes a queued job by its NZO id.
  Future<void> deleteJob(String nzoId) async {
    await _call('queue', extra: {'name': 'delete', 'value': nzoId});
  }

  void close({bool force = false}) => _dio.close(force: force);
}

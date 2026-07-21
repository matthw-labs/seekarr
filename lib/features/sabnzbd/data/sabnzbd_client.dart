import 'package:dio/dio.dart';

import 'package:seekarr/features/sabnzbd/domain/models/sabnzbd_models.dart';

/// Error thrown by [SabnzbdClient]. The message is always run through
/// [redactSabnzbdSecrets] so an API key (which SABnzbd carries in the request
/// URL query string) can never reach a log, snackbar or crash report.
class SabnzbdException implements Exception {
  const SabnzbdException(this.message);
  final String message;
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
  SabnzbdClient({required String url, required String apiKey, Dio? dio})
    : baseUrl = _normalizeBaseUrl(url),
      _apiKey = apiKey.trim() {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );
  }

  final String baseUrl;
  final String _apiKey;
  late final Dio _dio;

  static String _normalizeBaseUrl(String url) {
    var n = url.trim();
    if (n.isEmpty) return '';
    // Default a scheme-less URL to HTTPS (security §10.2 #1); an explicit
    // http:// is honoured. Strip a trailing slash before appending `/api`.
    if (!n.startsWith('http://') && !n.startsWith('https://')) {
      n = 'https://$n';
    }
    if (n.endsWith('/')) n = n.substring(0, n.length - 1);
    return n;
  }

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
        // SABnzbd reports auth/other failures as {"status": false, "error": …}.
        if (data['status'] == false && data['error'] != null) {
          throw SabnzbdException(
            redactSabnzbdSecrets(data['error'].toString()),
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

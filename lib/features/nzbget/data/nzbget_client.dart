import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:seekarr/features/nzbget/domain/models/nzbget_models.dart';

/// Error thrown by [NzbgetClient].
class NzbgetException implements Exception {
  const NzbgetException(this.message);
  final String message;
  @override
  String toString() => 'NzbgetException: $message';
}

/// Client for the NZBGet JSON-RPC API.
///
/// NZBGet authenticates with HTTP Basic auth (ControlUsername/ControlPassword)
/// and only accepts positional parameters. Base64 Basic credentials are
/// cleartext-equivalent, so a scheme-less URL defaults to HTTPS (security
/// standard §10.2 #9); the credentials only ever travel in the `Authorization`
/// header, never in the URL.
class NzbgetClient {
  NzbgetClient({required String url, this.username, this.password, Dio? dio})
    : baseUrl = _normalizeBaseUrl(url) {
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
  final String? username;
  final String? password;
  late final Dio _dio;
  int _requestId = 0;

  static String _normalizeBaseUrl(String url) {
    var n = url.trim();
    if (n.isEmpty) return '';
    if (!n.startsWith('http://') && !n.startsWith('https://')) {
      n = 'https://$n';
    }
    if (n.endsWith('/')) n = n.substring(0, n.length - 1);
    return n;
  }

  Map<String, String> get _authHeaders {
    final user = username?.trim() ?? '';
    if (user.isEmpty) return const {};
    final token = base64Encode(utf8.encode('$user:${password ?? ''}'));
    return {'Authorization': 'Basic $token'};
  }

  /// Performs a JSON-RPC call. NZBGet only supports positional [params].
  Future<dynamic> _call(
    String method, [
    List<dynamic> params = const [],
  ]) async {
    try {
      final response = await _dio.post(
        '/jsonrpc',
        data: {
          'jsonrpc': '2.0',
          'method': method,
          'params': params,
          'id': ++_requestId,
        },
        options: Options(
          headers: {..._authHeaders, 'Content-Type': 'application/json'},
        ),
      );
      final data = response.data;
      final Map<String, dynamic> map;
      if (data is String) {
        map = jsonDecode(data) as Map<String, dynamic>;
      } else if (data is Map) {
        map = data.cast<String, dynamic>();
      } else {
        throw const NzbgetException('Unexpected NZBGet response');
      }
      final error = map['error'];
      if (error != null) {
        final message = error is Map
            ? (error['message'] ?? error).toString()
            : error.toString();
        throw NzbgetException(message);
      }
      return map['result'];
    } on DioException catch (e) {
      throw NzbgetException(e.message ?? 'NZBGet request failed');
    }
  }

  /// Server version. Doubles as a lightweight reachability/auth probe.
  Future<String> version() async {
    return (await _call('version')).toString();
  }

  /// Global download status (rate, remaining size, paused).
  Future<NzbgetStatus> status() async {
    final result = await _call('status');
    return NzbgetStatus.fromJson((result as Map).cast<String, dynamic>());
  }

  /// The active download queue.
  Future<List<NzbgetGroup>> listGroups() async {
    final result = await _call('listgroups', [0]);
    return (result as List)
        .whereType<Map>()
        .map((e) => NzbgetGroup.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Recent completed/failed downloads.
  Future<List<NzbgetHistoryItem>> history({bool hidden = false}) async {
    final result = await _call('history', [hidden]);
    return (result as List)
        .whereType<Map>()
        .map((e) => NzbgetHistoryItem.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Verifies the configured URL + credentials. Returns true on success.
  Future<bool> testConnection() async {
    await version();
    return true;
  }

  Future<void> pauseDownload() async {
    await _call('pausedownload');
  }

  Future<void> resumeDownload() async {
    await _call('resumedownload');
  }

  void close({bool force = false}) => _dio.close(force: force);
}

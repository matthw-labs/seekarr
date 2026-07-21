import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:seekarr/features/unraid/domain/models/unraid_models.dart';

/// Error thrown by [UnraidClient].
class UnraidException implements Exception {
  const UnraidException(this.message);
  final String message;
  @override
  String toString() => 'UnraidException: $message';
}

/// Client for the Unraid GraphQL API.
///
/// Authenticates with the `x-api-key` header (security §10.2 #10). All query
/// documents are static and any dynamic value is passed through the GraphQL
/// `variables` map — never string-interpolated into the query (§10.2 #11).
///
/// The Unraid API must be enabled server-side (Settings → Management Access →
/// Developer Options → GraphQL Sandbox) and an API key created before this can
/// connect. Field names below follow the documented schema but may differ by
/// Unraid release; confirm against the instance's SDL.
class UnraidClient {
  UnraidClient({required String url, required String apiKey, Dio? dio})
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
    if (!n.startsWith('http://') && !n.startsWith('https://')) {
      n = 'https://$n';
    }
    if (n.endsWith('/')) n = n.substring(0, n.length - 1);
    return n;
  }

  Future<Map<String, dynamic>> _query(
    String document, {
    Map<String, dynamic>? variables,
  }) async {
    try {
      final response = await _dio.post(
        '/graphql',
        data: {
          'query': document,
          if (variables != null) 'variables': variables,
        },
        options: Options(
          headers: {'x-api-key': _apiKey, 'Content-Type': 'application/json'},
        ),
      );
      final raw = response.data;
      final Map<String, dynamic> map = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : (raw as Map).cast<String, dynamic>();
      final errors = map['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        final message = first is Map
            ? (first['message'] ?? first).toString()
            : first.toString();
        throw UnraidException(message);
      }
      return (map['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    } on DioException catch (e) {
      throw UnraidException(e.message ?? 'Unraid request failed');
    }
  }

  static const _infoQuery = 'query { info { os { distro release uptime } } }';
  static const _arrayQuery =
      'query { array { state capacity { kilobytes { free used total } } '
      'disks { name status temp } } }';
  static const _dockerQuery =
      'query { dockerContainers { id names state status autoStart } }';

  Future<UnraidInfo> getInfo() async {
    final data = await _query(_infoQuery);
    return UnraidInfo.fromJson(
      (data['info'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Future<UnraidArray> getArray() async {
    final data = await _query(_arrayQuery);
    return UnraidArray.fromJson(
      (data['array'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Future<List<UnraidDockerContainer>> getDockerContainers() async {
    final data = await _query(_dockerQuery);
    final list = (data['dockerContainers'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => UnraidDockerContainer.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Unraid release string.
  Future<String> version() async => (await getInfo()).version;

  /// Verifies the URL + key by fetching system info. Returns true on success.
  Future<bool> testConnection() async {
    await getInfo();
    return true;
  }

  void close({bool force = false}) => _dio.close(force: force);
}

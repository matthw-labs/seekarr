import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/network/redirect_guard.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/features/unraid/domain/models/unraid_models.dart';

/// Error thrown by [UnraidClient]. Carries the [reason] so a caller verifying
/// the connection can tell an unreachable host from a rejected API key.
class UnraidException implements Exception, HasFailureReason {
  const UnraidException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
  });
  final String message;
  @override
  final ServiceFailureReason reason;
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
    : baseUrl = UrlUtils.normalizeBaseUrl(url),
      _apiKey = apiKey.trim() {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            // Follow redirects manually so `x-api-key` is never replayed to an
            // unconfigured host (a 303 would also downgrade this POST to GET).
            followRedirects: false,
            validateStatus: allowRedirectStatus,
          ),
        );
    if (dio == null) {
      _dio.interceptors.add(SameOriginRedirectInterceptor(_dio));
    }
  }

  final String baseUrl;
  final String _apiKey;
  late final Dio _dio;

  /// Decodes a GraphQL response body, or throws an [UnraidException] the caller
  /// can classify.
  ///
  /// A 200 carrying HTML — the URL points at some other web app, or at a reverse
  /// proxy's landing page — used to throw a raw `TypeError`/`FormatException`
  /// that was neither an `UnraidException` nor classifiable, so the UI fell back
  /// to a generic failure. `notFound` says the useful thing: the API is not here.
  static Map<String, dynamic> _decodeGraphQl(dynamic raw) {
    const notGraphQl =
        'The Unraid GraphQL API did not answer at this address. '
        'Check the URL and that the API is enabled.';
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } on FormatException {
      throw const UnraidException(
        notGraphQl,
        reason: ServiceFailureReason.notFound,
      );
    }
    throw const UnraidException(
      notGraphQl,
      reason: ServiceFailureReason.notFound,
    );
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
      final map = _decodeGraphQl(response.data);
      final errors = map['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        final message = first is Map
            ? (first['message'] ?? first).toString()
            : first.toString();
        // The Unraid API answers 200 with a GraphQL error for a bad API key.
        throw UnraidException(
          message,
          reason: looksUnauthorizedMessage(message)
              ? ServiceFailureReason.unauthorized
              : ServiceFailureReason.unknown,
        );
      }
      return (map['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    } on DioException catch (e) {
      throw UnraidException(
        e.message ?? 'Unraid request failed',
        reason: classifyConnectionFailure(e),
      );
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

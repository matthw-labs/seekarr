import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/features/nzbget/domain/models/nzbget_models.dart';

/// Error thrown by [NzbgetClient]. Carries the [reason] so a caller verifying
/// the connection can tell an unreachable host from rejected credentials.
class NzbgetException implements Exception, HasFailureReason {
  const NzbgetException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
  });
  final String message;
  @override
  final ServiceFailureReason reason;
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
    : baseUrl = UrlUtils.normalizeBaseUrl(url) {
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
      if (data is Map) {
        map = data.cast<String, dynamic>();
      } else if (data is String) {
        // A 200 carrying HTML means the URL points at something that is not the
        // JSON-RPC endpoint. Decoding it raw threw a FormatException that
        // escaped the exception contract and could not be classified; naming it
        // `notFound` tells the user the API is not at this address.
        try {
          final decoded = jsonDecode(data);
          if (decoded is! Map) throw const FormatException();
          map = decoded.cast<String, dynamic>();
        } on FormatException {
          throw const NzbgetException(
            'The NZBGet JSON-RPC API did not answer at this address. Check the '
            'URL and port.',
            reason: ServiceFailureReason.notFound,
          );
        }
      } else {
        throw const NzbgetException(
          'The NZBGet JSON-RPC API did not answer at this address. Check the '
          'URL and port.',
          reason: ServiceFailureReason.notFound,
        );
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
      throw NzbgetException(
        e.message ?? 'NZBGet request failed',
        reason: classifyConnectionFailure(e),
      );
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

  /// Sets the global download speed limit in kilobytes per second (0 = no
  /// limit). Positional param, per the JSON-RPC contract.
  Future<void> setRate(int kilobytesPerSec) async {
    await _call('rate', [kilobytesPerSec]);
  }

  /// Queues an NZB from a URL. NZBGet's `append` takes positional params; when
  /// [content] is a URL, NZBGet fetches it server-side. Signature follows the
  /// documented order: (NZBFilename, NZBContent, Category, Priority, AddToTop,
  /// AddPaused). Confirm against the target version before relying on the tail
  /// params (plan §2.1 `◦`).
  Future<int> append(
    String name,
    String content, {
    String category = '',
    int priority = 0,
    bool addToTop = false,
    bool addPaused = false,
  }) async {
    final result = await _call('append', [
      name,
      content,
      category,
      priority,
      addToTop,
      addPaused,
    ]);
    // Returns the new NZBID (>0) on success, 0/false on failure.
    if (result is num) return result.toInt();
    return result == true ? 1 : 0;
  }

  /// Low-level queue edit. NZBGet's `editqueue` is positional:
  /// (Command, Offset, EditText, IDs). Group commands ignore Offset/EditText.
  Future<bool> editQueue(
    String command,
    List<int> ids, {
    int offset = 0,
    String editText = '',
  }) async {
    final result = await _call('editqueue', [command, offset, editText, ids]);
    return result == true;
  }

  Future<bool> pauseGroup(int nzbId) => editQueue('GroupPause', [nzbId]);
  Future<bool> resumeGroup(int nzbId) => editQueue('GroupResume', [nzbId]);
  Future<bool> deleteGroup(int nzbId) => editQueue('GroupDelete', [nzbId]);

  void close({bool force = false}) => _dio.close(force: force);
}

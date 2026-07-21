import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// In-memory [HttpClientAdapter] that returns a canned JSON response and records
/// the last request (URI, headers, decoded body) for assertions.
///
/// This is the shared "fake transport" for the query-string / JSON-RPC / GraphQL
/// clients (SABnzbd, NZBGet, Unraid), mirroring the qBittorrent test approach of
/// driving a real [Dio] over a stubbed adapter so URL/header/body building and
/// response parsing are exercised end-to-end without a network.
class CapturingHttpAdapter implements HttpClientAdapter {
  CapturingHttpAdapter({this.response, this.statusCode = 200, this.byPath});

  /// Default response body (Map/List → encoded as JSON, or a raw String).
  dynamic response;

  int statusCode;

  /// Optional per-path routing: the first key that is a substring of the
  /// request path selects the response.
  Map<String, dynamic>? byPath;

  RequestOptions? lastRequest;
  Uri? lastUri;
  Map<String, dynamic>? lastHeaders;

  /// The request body decoded from the outgoing stream (JSON → Map/List), or
  /// the raw string when it is not valid JSON.
  dynamic lastBody;

  int callCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    lastRequest = options;
    lastUri = options.uri;
    lastHeaders = options.headers;

    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final raw = utf8.decode(chunks.expand((c) => c).toList());
      try {
        lastBody = jsonDecode(raw);
      } catch (_) {
        lastBody = raw;
      }
    } else {
      lastBody = options.data;
    }

    var body = response;
    if (byPath != null) {
      for (final entry in byPath!.entries) {
        if (options.uri.path.contains(entry.key)) {
          body = entry.value;
          break;
        }
      }
    }
    final bytes = body is String
        ? utf8.encode(body)
        : utf8.encode(jsonEncode(body));
    return ResponseBody.fromBytes(
      Uint8List.fromList(bytes),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}

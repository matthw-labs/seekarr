import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One canned reply.
class ScriptedReply {
  const ScriptedReply({
    this.statusCode = 200,
    this.body,
    this.headers = const {},
  });

  final int statusCode;

  /// Map/List → encoded as JSON; String → sent raw.
  final dynamic body;

  final Map<String, List<String>> headers;
}

/// One recorded request.
class ScriptedRequest {
  const ScriptedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final dynamic body;
}

/// An [HttpClientAdapter] that replies from a **queue**, so a test can drive a
/// multi-step exchange.
///
/// [CapturingHttpAdapter] answers every request the same way, which cannot
/// express the two protocols that matter most here: Transmission's `409` →
/// retry-with-session-id handshake, and Nginx Proxy Manager's
/// login-then-request pair. Both are exactly where a client loops forever or
/// leaks a credential, so they have to be testable offline.
///
/// Replies are consumed in order; once the queue is empty the last reply
/// repeats, so a test only has to script the interesting prefix.
class ScriptedHttpAdapter implements HttpClientAdapter {
  ScriptedHttpAdapter(List<ScriptedReply> replies)
    : _replies = List.of(replies);

  final List<ScriptedReply> _replies;

  /// Every request made, in order.
  final List<ScriptedRequest> requests = [];

  int get callCount => requests.length;

  ScriptedRequest get lastRequest => requests.last;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    dynamic body;
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final raw = utf8.decode(chunks.expand((c) => c).toList());
      try {
        body = jsonDecode(raw);
      } catch (_) {
        body = raw;
      }
    } else {
      body = options.data;
    }

    requests.add(
      ScriptedRequest(
        method: options.method,
        uri: options.uri,
        headers: Map<String, dynamic>.from(options.headers),
        body: body,
      ),
    );

    final reply = _replies.length > 1
        ? _replies.removeAt(0)
        : (_replies.isEmpty ? const ScriptedReply() : _replies.first);

    final encoded = reply.body is String
        ? reply.body as String
        : jsonEncode(reply.body ?? const <String, dynamic>{});

    return ResponseBody.fromString(
      encoded,
      reply.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...reply.headers,
      },
    );
  }
}

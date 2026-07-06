import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Error surfaced by the TrueNAS WebSocket client.
class TrueNasException implements Exception {
  final String message;
  const TrueNasException(this.message);
  @override
  String toString() => 'TrueNasException: $message';
}

/// A minimal JSON-RPC 2.0 over WebSocket client for TrueNAS SCALE 25.x.
///
/// TrueNAS deprecated the REST API in 25.04 (removed in 26); the supported
/// transport is JSON-RPC 2.0 over WebSocket at `wss://<host>/api/current`,
/// authenticated with `auth.login_with_api_key`. Self-signed certificates
/// (common on home installs) are accepted.
class TrueNasWsClient {
  final String baseUrl;
  final String apiKey;

  WebSocket? _socket;
  bool _authed = false;
  int _nextId = 1;
  Completer<void>? _connecting;
  final Map<int, Completer<dynamic>> _pending = {};

  TrueNasWsClient({required this.baseUrl, required this.apiKey});

  /// Derives the `wss://host:port/api/current` endpoint from the base URL.
  Uri resolveEndpoint() {
    var raw = baseUrl.trim();
    if (raw.isEmpty) {
      throw const TrueNasException('TrueNAS URL is empty');
    }
    if (!raw.contains('://')) raw = 'https://$raw';
    final uri = Uri.parse(raw);
    final secure = uri.scheme != 'http';
    return Uri(
      scheme: secure ? 'wss' : 'ws',
      host: uri.host,
      port: uri.hasPort ? uri.port : (secure ? 443 : 80),
      path: '/api/current',
    );
  }

  Future<void> _ensureConnected() {
    if (_socket != null && _authed) return Future.value();
    final existing = _connecting;
    if (existing != null) return existing.future;

    final completer = Completer<void>();
    _connecting = completer;
    _connect()
        .then((_) => completer.complete())
        .catchError((Object e) => completer.completeError(e))
        .whenComplete(() => _connecting = null);
    return completer.future;
  }

  Future<void> _connect() async {
    final httpClient = HttpClient();
    // Accept self-signed certificates (common on home TrueNAS installs).
    httpClient.badCertificateCallback = (_, __, ___) => true;
    httpClient.connectionTimeout = const Duration(seconds: 10);
    try {
      final socket = await WebSocket.connect(
        resolveEndpoint().toString(),
        customClient: httpClient,
      ).timeout(const Duration(seconds: 10));
      _socket = socket;
      socket.listen(
        _onMessage,
        onError: (Object e) => _failAll(TrueNasException(e.toString())),
        onDone: () {
          _authed = false;
          _socket = null;
          _failAll(const TrueNasException('Connection closed'));
        },
        cancelOnError: false,
      );

      final ok = await _rawCall('auth.login_with_api_key', [apiKey]);
      if (ok != true) {
        throw const TrueNasException('Authentication failed (check API key)');
      }
      _authed = true;
    } catch (e) {
      _authed = false;
      await _socket?.close();
      _socket = null;
      httpClient.close(force: true);
      if (e is TrueNasException) rethrow;
      throw TrueNasException('Could not connect: $e');
    }
  }

  /// Calls a JSON-RPC method, connecting/authenticating on first use.
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    await _ensureConnected();
    return _rawCall(method, params);
  }

  Future<dynamic> _rawCall(String method, List<dynamic> params) {
    final socket = _socket;
    if (socket == null) {
      return Future.error(const TrueNasException('Not connected'));
    }
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(id);
        throw TrueNasException('Timed out calling $method');
      },
    );
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (decoded is! Map || decoded['id'] == null) return;
    final id = decoded['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;

    final error = decoded['error'];
    if (error != null) {
      final message = error is Map
          ? (error['message']?.toString() ?? 'RPC error')
          : error.toString();
      completer.completeError(TrueNasException(message));
    } else {
      completer.complete(decoded['result']);
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  Future<void> close() async {
    _failAll(const TrueNasException('Client closed'));
    _authed = false;
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:seekarr/core/network/cert_trust.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';

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
/// authenticated with `auth.login_with_api_key`. TLS certificates are verified
/// against the platform trust store; a self-signed certificate is trusted only
/// after the user explicitly pins it via [certFingerprint].
/// Progress callback for long-running [TrueNasWsClient.callJob] operations.
typedef TrueNasJobProgress =
    void Function(double? percent, String? description);

class TrueNasWsClient {
  final String baseUrl;
  final String apiKey;

  /// SHA-256 fingerprint of a self-signed certificate the user chose to trust.
  /// When null/empty, TLS certificates are verified against the platform trust
  /// store like any HTTPS client.
  final String? certFingerprint;

  WebSocket? _socket;
  HttpClient? _httpClient;
  bool _authed = false;
  int _nextId = 1;
  Completer<void>? _connecting;
  final Map<int, Completer<dynamic>> _pending = {};

  /// Cached method names from `core.get_methods` (capability discovery).
  Set<String>? _methods;
  Future<Set<String>>? _methodsInFlight;

  TrueNasWsClient({
    required this.baseUrl,
    required this.apiKey,
    this.certFingerprint,
  });

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
    // Verify TLS against the platform trust store, additionally trusting the
    // user-pinned self-signed certificate (if any). See [buildPinnedHttpClient].
    final httpClient = buildPinnedHttpClient(
      pinnedFingerprint: certFingerprint,
    );
    _httpClient = httpClient;
    try {
      final socket = await WebSocket.connect(
        resolveEndpoint().toString(),
        customClient: httpClient,
      ).timeout(const Duration(seconds: 10));
      _socket = socket;
      socket.listen(
        _onMessage,
        onError: (Object e) {
          // Reset the socket state so the next call forces a fresh
          // reconnection instead of writing to a dead socket.
          _authed = false;
          _socket = null;
          _httpClient?.close(force: true);
          _httpClient = null;
          _failAll(TrueNasException(e.toString()));
        },
        onDone: () {
          _authed = false;
          _socket = null;
          _httpClient?.close(force: true);
          _httpClient = null;
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
      _httpClient = null;
      if (e is TrueNasException) rethrow;
      throw TrueNasException('Could not connect: $e');
    }
  }

  /// Calls a JSON-RPC method, connecting/authenticating on first use.
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    await _ensureConnected();
    return _rawCall(method, params);
  }

  /// Invokes a *job* method (one that returns an integer job id) and waits for
  /// it to finish, polling `core.get_jobs` until the job reaches a terminal
  /// state. Returns the job result, or throws [TrueNasException] on failure.
  ///
  /// [onProgress] receives progress updates (percent 0..100 and an optional
  /// description) while the job runs.
  Future<dynamic> callJob(
    String method, [
    List<dynamic> params = const [],
    TrueNasJobProgress? onProgress,
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 1),
  ]) async {
    final raw = await call(method, params);
    final jobId = raw is int ? raw : intOrNull(raw);
    if (jobId == null) {
      // Method did not behave like a job; treat its result as the outcome.
      return raw;
    }

    final deadline = DateTime.now().add(timeout);
    while (true) {
      final jobs = await call('core.get_jobs', [
        [
          ['id', '=', jobId],
        ],
      ]);
      final job = (jobs is List && jobs.isNotEmpty && jobs.first is Map)
          ? jobs.first as Map
          : null;
      if (job != null) {
        final progress = job['progress'];
        if (onProgress != null && progress is Map) {
          onProgress(
            doubleOrNull(progress['percent']),
            progress['description']?.toString(),
          );
        }
        final state = job['state']?.toString().toUpperCase();
        if (state == 'SUCCESS') {
          return job['result'];
        }
        if (state == 'FAILED' || state == 'ABORTED') {
          final error = job['error']?.toString();
          throw TrueNasException(
            error?.isNotEmpty == true ? error! : 'Job $method $state',
          );
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TrueNasException('Timed out waiting for job $method');
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Returns the set of RPC method names the server exposes (via
  /// `core.get_methods`), cached for the life of the connection. Used for
  /// capability discovery so the UI can hide/disable unsupported actions.
  Future<Set<String>> getMethods() {
    final cached = _methods;
    if (cached != null) return Future.value(cached);
    return _methodsInFlight ??= _loadMethods()
      ..whenComplete(() => _methodsInFlight = null);
  }

  Future<Set<String>> _loadMethods() async {
    try {
      final result = await call('core.get_methods');
      final Set<String> names;
      if (result is Map) {
        names = result.keys.map((k) => k.toString()).toSet();
      } else if (result is List) {
        names = result.map((e) => e.toString()).toSet();
      } else {
        names = <String>{};
      }
      _methods = names;
      return names;
    } catch (_) {
      // Discovery is best-effort; cache the empty result so a failed probe is
      // not retried on every call. An empty set means "assume available".
      final empty = <String>{};
      _methods = empty;
      return empty;
    }
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
    _httpClient?.close(force: true);
    _httpClient = null;
    await socket?.close();
  }
}

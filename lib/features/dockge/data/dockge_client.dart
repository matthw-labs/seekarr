import 'dart:async';
import 'dart:io' as io;

import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:web_socket/io_web_socket.dart';
import 'package:web_socket/web_socket.dart' as ws;

import 'package:seekarr/core/network/cert_trust.dart';
import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/features/dockge/domain/models/dockge_stack.dart';
import 'package:seekarr/features/dockge/domain/models/dockge_stack_detail.dart';

/// Error surfaced by the Dockge client. Carries the [reason] so a caller
/// verifying the connection can tell an unreachable host from a rejected
/// login.
class DockgeException implements Exception, HasFailureReason {
  final String message;
  @override
  final ServiceFailureReason reason;
  const DockgeException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
  });
  @override
  String toString() => 'DockgeException: $message';
}

/// A chunk of terminal output pushed by Dockge (`terminalWrite` event).
class DockgeTerminalOutput {
  final String terminalName;
  final String data;
  const DockgeTerminalOutput(this.terminalName, this.data);
}

/// Socket.IO client for a single Dockge instance.
///
/// Dockge exposes no REST API — everything goes over Socket.IO (v4). Commands
/// are wrapped in an `agent` envelope (`emit("agent", endpoint, event, ...)`)
/// so the same protocol works for both the local instance and remote agents;
/// this client targets a single direct instance, so [_endpoint] is always the
/// empty string. Authentication is username/password → JWT, matching Dockge's
/// login flow; when Dockge runs with auth disabled (behind a reverse proxy) the
/// server emits `autoLogin` and no credentials are required.
///
/// TLS certificates are verified against the platform trust store; a self-signed
/// certificate is trusted only after the user explicitly pins it via
/// [certFingerprint], mirroring the TrueNAS client.
class DockgeClient {
  final String baseUrl;
  final String? username;
  final String? password;

  /// SHA-256 fingerprint of a self-signed certificate the user chose to trust.
  final String? certFingerprint;

  static const String _endpoint = '';

  /// How long to wait for `autoLogin` after connecting without credentials
  /// before concluding the instance requires a login.
  static const Duration _autoLoginGrace = Duration(milliseconds: 1500);

  socket_io.Socket? _socket;
  bool _authed = false;
  Completer<void>? _connecting;

  /// Server info from the `info` event (contains the Dockge version).
  Map<String, dynamic>? _serverInfo;

  List<DockgeStack> _latestStacks = const [];

  final StreamController<List<DockgeStack>> _stackListController =
      StreamController<List<DockgeStack>>.broadcast();
  final StreamController<DockgeTerminalOutput> _terminalController =
      StreamController<DockgeTerminalOutput>.broadcast();

  DockgeClient({
    required this.baseUrl,
    this.username,
    this.password,
    this.certFingerprint,
  });

  /// The most recent parsed stack list (empty until the first push).
  List<DockgeStack> get latestStacks => _latestStacks;

  /// Broadcasts the full stack list whenever Dockge pushes an update.
  Stream<List<DockgeStack>> get stackListStream => _stackListController.stream;

  /// Broadcasts terminal output (deploy/up/down logs) as it arrives.
  Stream<DockgeTerminalOutput> get terminalOutput => _terminalController.stream;

  String? get version => stringOrNull(_serverInfo?['version']);

  bool get _hasCredentials =>
      (username?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);

  /// The combined-terminal name Dockge uses for a stack's aggregated logs.
  String combinedTerminalName(String stackName) =>
      'combined-$_endpoint-$stackName';

  /// Derives the Socket.IO base origin (`http(s)://host:port`) from [baseUrl].
  Uri resolveEndpoint() {
    var raw = baseUrl.trim();
    if (raw.isEmpty) {
      throw const DockgeException('Dockge URL is empty');
    }
    // Default a scheme-less URL to HTTPS/WSS so login credentials are not sent
    // over an unencrypted socket. An explicit http:// is honoured.
    if (!raw.contains('://')) raw = 'https://$raw';
    final uri = Uri.parse(raw);
    // Secure unless the user explicitly asked for cleartext: an unrecognised
    // scheme must never downgrade the socket carrying the login credentials.
    final secure = UrlUtils.isSecureScheme(raw);
    return Uri(
      scheme: secure ? 'https' : 'http',
      host: uri.host,
      port: uri.hasPort ? uri.port : (secure ? 443 : 80),
    );
  }

  /// WebSocket connector that verifies TLS against the platform trust store,
  /// additionally trusting the user-pinned self-signed certificate (if any).
  Future<ws.WebSocket> _pinnedConnector(
    Uri uri, {
    Iterable<String>? protocols,
    Map<String, String>? headers,
  }) async {
    final httpClient = buildPinnedHttpClient(
      pinnedFingerprint: certFingerprint,
      pinnedHost: uri.host,
      pinnedPort: uri.port,
    );
    final socket = await io.WebSocket.connect(
      uri.toString(),
      protocols: protocols,
      headers: headers,
      customClient: httpClient,
    );
    return IOWebSocket.fromWebSocket(socket);
  }

  Future<void> ensureConnected() {
    if (_socket != null && _authed) return Future.value();
    final existing = _connecting;
    if (existing != null) return existing.future;

    final completer = Completer<void>();
    _connecting = completer;
    _connect()
        .then((_) {
          if (!completer.isCompleted) completer.complete();
        })
        .catchError((Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        })
        .whenComplete(() {
          if (identical(_connecting, completer)) _connecting = null;
        });
    return completer.future;
  }

  Future<void> _connect() async {
    final authCompleter = Completer<void>();

    final options = socket_io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew()
        .setReconnectionAttempts(3)
        .setWebSocketConnector(_pinnedConnector)
        .build();

    // Dispose any previous socket before replacing it: a reconnection through
    // `ensureConnected` would otherwise leak the old socket (double streams +
    // dangling reconnection timers).
    _socket?.dispose();

    final socket = socket_io.io(resolveEndpoint().toString(), options);
    _socket = socket;

    socket.onConnect((_) {
      if (!_hasCredentials) {
        // Auth-disabled instances answer `autoLogin` almost immediately. If that
        // has not arrived shortly after connect, the server wants credentials we
        // do not have — report that instead of letting the connection time out,
        // which surfaced as "check the address" and sent the user looking for a
        // network fault rather than filling in the login fields.
        Timer(_autoLoginGrace, () {
          if (_authed || authCompleter.isCompleted) return;
          authCompleter.completeError(
            const DockgeException(
              'Dockge requires a username and password',
              reason: ServiceFailureReason.unauthorized,
            ),
          );
        });
      }
      if (_hasCredentials) {
        socket.emitWithAck(
          'login',
          {'username': username, 'password': password},
          ack: (dynamic res) {
            final map = mapOrNull(res);
            if (map?['ok'] == true) {
              _authed = true;
              if (!authCompleter.isCompleted) authCompleter.complete();
            } else if (map?['tokenRequired'] == true) {
              if (!authCompleter.isCompleted) {
                authCompleter.completeError(
                  const DockgeException(
                    'Two-factor authentication is not supported',
                    reason: ServiceFailureReason.unauthorized,
                  ),
                );
              }
            } else if (!authCompleter.isCompleted) {
              authCompleter.completeError(
                DockgeException(
                  _msg(map) ?? 'Login failed',
                  reason: ServiceFailureReason.unauthorized,
                ),
              );
            }
          },
        );
      }
      // With auth disabled the server emits `autoLogin` instead, handled below.
    });

    socket.on('autoLogin', (_) {
      _authed = true;
      if (!authCompleter.isCompleted) authCompleter.complete();
    });

    socket.on('info', (dynamic data) {
      final map = mapOrNull(data);
      if (map != null) _serverInfo = map;
    });

    socket.on('agent', _onAgentEvent);
    socket.on('stackStatusList', _onStackStatusList);

    socket.onConnectError((dynamic e) {
      if (!authCompleter.isCompleted) {
        authCompleter.completeError(
          DockgeException(
            'Connection error: $e',
            // Socket.IO hands us an untyped connect error.
            reason: classifyConnectionFailure(
              e,
              fallback: ServiceFailureReason.unreachable,
            ),
          ),
        );
      }
    });

    socket.onDisconnect((_) {
      _authed = false;
    });

    // Only surface a connection error once reconnection is definitively
    // exhausted — intermediate retries must not error out the stream, or the
    // UI would flap between error and data on every transient drop.
    socket.onReconnectFailed((_) {
      _authed = false;
      if (!_stackListController.isClosed) {
        _stackListController.addError(
          const DockgeException(
            'Lost connection to Dockge (reconnection failed)',
          ),
        );
      }
    });

    socket.connect();

    try {
      await authCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const DockgeException(
          'Timed out connecting to Dockge (check URL and credentials)',
          reason: ServiceFailureReason.timeout,
        ),
      );
    } catch (e) {
      _authed = false;
      socket.dispose();
      _socket = null;
      if (e is DockgeException) rethrow;
      throw DockgeException(
        'Could not connect: $e',
        reason: classifyConnectionFailure(
          e,
          fallback: ServiceFailureReason.unreachable,
        ),
      );
    }
  }

  void _onAgentEvent(dynamic data) {
    if (data is! List || data.isEmpty) return;
    final eventName = data.first?.toString();
    final args = data.length > 1 ? data.sublist(1) : const [];
    switch (eventName) {
      case 'stackList':
        final payload = args.isNotEmpty ? mapOrNull(args.first) : null;
        if (payload != null) _handleStackList(payload);
        break;
      case 'terminalWrite':
        if (args.length >= 2) {
          _terminalController.add(
            DockgeTerminalOutput(
              args[0]?.toString() ?? '',
              args[1]?.toString() ?? '',
            ),
          );
        }
        break;
    }
  }

  void _handleStackList(Map<String, dynamic> payload) {
    final raw = mapOrNull(payload['stackList']);
    if (raw == null) return;
    final stacks = <DockgeStack>[];
    raw.forEach((name, value) {
      final map = mapOrNull(value);
      if (map != null) stacks.add(DockgeStack.fromJson(map));
    });
    stacks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _latestStacks = stacks;
    if (!_stackListController.isClosed) _stackListController.add(stacks);
  }

  /// Handles the lighter `stackStatusList` event which patches only statuses.
  void _onStackStatusList(dynamic data) {
    final map = mapOrNull(data);
    final statuses = mapOrNull(map?['stackStatusList']);
    if (statuses == null || _latestStacks.isEmpty) return;
    final patched = _latestStacks
        .map((stack) {
          if (!statuses.containsKey(stack.name)) return stack;
          return stack.copyWith(
            status: DockgeStackStatus.fromCode(intOrNull(statuses[stack.name])),
          );
        })
        .toList(growable: false);
    _latestStacks = patched;
    if (!_stackListController.isClosed) _stackListController.add(patched);
  }

  /// Emits an `agent`-wrapped command and awaits its acknowledgement.
  Future<Map<String, dynamic>> _agent(
    String event, {
    List<dynamic> args = const [],
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await ensureConnected();
    final socket = _socket;
    if (socket == null) throw const DockgeException('Not connected');

    final completer = Completer<Map<String, dynamic>>();
    socket.emitWithAck(
      'agent',
      [_endpoint, event, ...args],
      ack: (dynamic res) {
        if (completer.isCompleted) return;
        final map = mapOrNull(res) ?? <String, dynamic>{};
        if (map['ok'] == true) {
          completer.complete(map);
        } else {
          completer.completeError(
            DockgeException(_msg(map) ?? 'Dockge error ($event)'),
          );
        }
      },
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () => throw DockgeException('Timed out calling $event'),
    );
  }

  static String? _msg(Map<String, dynamic>? map) => stringOrNull(map?['msg']);

  // ---- Reads -------------------------------------------------------------

  /// Asks Dockge to (re)push the full stack list.
  Future<void> requestStackList() => _agent('requestStackList');

  Future<DockgeStackDetail> getStack(String name) async {
    final res = await _agent('getStack', args: [name]);
    final stack = mapOrNull(res['stack']);
    if (stack == null) {
      throw const DockgeException('Stack not found');
    }
    return DockgeStackDetail.fromJson(stack);
  }

  Future<List<DockgeServiceStatus>> getServiceStatusList(String name) async {
    final res = await _agent('serviceStatusList', args: [name]);
    final map = mapOrNull(res['serviceStatusList']) ?? <String, dynamic>{};
    return DockgeServiceStatus.listFromMap(map);
  }

  Future<List<String>> getDockerNetworkList() async {
    final res = await _agent('getDockerNetworkList');
    final list = res['dockerNetworkList'];
    if (list is List) {
      return list.map((e) => e.toString()).toList(growable: false);
    }
    return const [];
  }

  /// Converts a `docker run ...` command into compose YAML via Dockge.
  Future<String?> composerize(String dockerRunCommand) async {
    final res = await _agent('composerize', args: [dockerRunCommand]);
    return stringOrNull(res['composeTemplate']);
  }

  // ---- Stack lifecycle ---------------------------------------------------

  static const Duration _longOp = Duration(minutes: 10);

  Future<void> startStack(String name) =>
      _agent('startStack', args: [name], timeout: _longOp);

  Future<void> stopStack(String name) =>
      _agent('stopStack', args: [name], timeout: _longOp);

  Future<void> restartStack(String name) =>
      _agent('restartStack', args: [name], timeout: _longOp);

  Future<void> updateStack(String name) =>
      _agent('updateStack', args: [name], timeout: _longOp);

  Future<void> downStack(String name) =>
      _agent('downStack', args: [name], timeout: _longOp);

  Future<void> deleteStack(String name) => _agent('deleteStack', args: [name]);

  /// Creates or updates and deploys a stack (`docker compose up -d`).
  Future<void> deployStack({
    required String name,
    required String composeYAML,
    String composeENV = '',
    required bool isAdd,
  }) async {
    _refuseEmptyCompose(composeYAML, isAdd: isAdd, op: 'deploy');
    await _agent(
      'deployStack',
      args: [name, composeYAML, composeENV, isAdd],
      timeout: _longOp,
    );
  }

  /// Saves a stack's compose files without deploying.
  Future<void> saveStack({
    required String name,
    required String composeYAML,
    String composeENV = '',
    required bool isAdd,
  }) async {
    _refuseEmptyCompose(composeYAML, isAdd: isAdd, op: 'save');
    await _agent('saveStack', args: [name, composeYAML, composeENV, isAdd]);
  }

  /// Refuses to write an empty compose file over a stack that already exists.
  ///
  /// Dockge takes the YAML it is handed as the new truth for the stack, so a
  /// blank string is not a no-op — it is `docker-compose.yaml` replaced by
  /// nothing, and for `deployStack` it is that followed by a `compose up` on the
  /// result. The editor screen produced exactly that whenever it rendered before
  /// its detail fetch resolved, so the guard belongs here as well: this is the
  /// call that destroys the file, and any future caller inherits the protection
  /// rather than having to remember it.
  ///
  /// `isAdd` is the exemption, not an oversight — creating a stack from a blank
  /// editor overwrites nothing.
  void _refuseEmptyCompose(
    String composeYAML, {
    required bool isAdd,
    required String op,
  }) {
    if (isAdd || composeYAML.trim().isNotEmpty) return;
    throw DockgeException(
      'Refusing to $op an empty compose file over an existing stack.',
    );
  }

  // ---- Per-service actions ----------------------------------------------

  Future<void> startService(String stackName, String serviceName) =>
      _agent('startService', args: [stackName, serviceName], timeout: _longOp);

  Future<void> stopService(String stackName, String serviceName) =>
      _agent('stopService', args: [stackName, serviceName], timeout: _longOp);

  Future<void> restartService(String stackName, String serviceName) => _agent(
    'restartService',
    args: [stackName, serviceName],
    timeout: _longOp,
  );

  // ---- Terminal ----------------------------------------------------------

  /// Joins a stack's combined terminal so Dockge streams its logs. Reads and
  /// lifecycle actions join it server-side automatically, but this lets a
  /// screen (re)subscribe explicitly.
  Future<void> joinCombinedTerminal(String stackName) =>
      _agent('terminalJoin', args: [combinedTerminalName(stackName)]);

  /// Lightweight connectivity probe used by the connection health check.
  ///
  /// A genuine credential rejection throws a [DockgeException] carrying
  /// `unauthorized`, so a `false` here means only that the socket dropped
  /// between authenticating and returning — a connection problem, not a wrong
  /// password.
  Future<bool> ping() async {
    await ensureConnected();
    return _authed;
  }

  Future<void> close() async {
    _authed = false;
    // Fail any in-flight connect so `ensureConnected` callers don't hang.
    final connecting = _connecting;
    _connecting = null;
    if (connecting != null && !connecting.isCompleted) {
      connecting.completeError(const DockgeException('Client closed'));
    }
    final socket = _socket;
    _socket = null;
    socket?.dispose();
    await _stackListController.close();
    await _terminalController.close();
  }
}

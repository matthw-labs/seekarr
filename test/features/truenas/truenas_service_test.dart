import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/truenas/data/truenas_service.dart';
import 'package:seekarr/features/truenas/data/truenas_ws_client.dart';

/// A [TrueNasWsClient] that returns canned JSON-RPC results per method.
class _FakeClient extends TrueNasWsClient {
  _FakeClient(this.responses)
    : super(baseUrl: 'https://nas.local', apiKey: 'key');

  final Map<String, dynamic> responses;
  final List<String> calls = [];

  @override
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    calls.add(method);
    if (responses.containsKey(method)) return responses[method];
    throw TrueNasException('no stub for $method');
  }
}

void main() {
  group('TrueNasService.loadDashboard', () {
    test('parses system, pools, alerts and services', () async {
      final client = _FakeClient({
        'system.info': {
          'version': 'TrueNAS-SCALE-25.04.0',
          'hostname': 'nas',
          'uptime_seconds': 3600.0,
          'cores': 8,
          'physmem': 34359738368,
          'loadavg': [0.5, 0.4, 0.3],
        },
        'pool.query': [
          {
            'name': 'tank',
            'status': 'ONLINE',
            'healthy': true,
            'size': 1000,
            'allocated': 750,
          },
          {'name': 'backup', 'status': 'DEGRADED', 'healthy': false},
        ],
        'alert.list': [
          {'uuid': 'a1', 'level': 'WARNING', 'formatted': 'Disk hot', 'dismissed': false},
          {'uuid': 'a2', 'level': 'INFO', 'formatted': 'Old', 'dismissed': true},
        ],
        'service.query': [
          {'id': 1, 'service': 'smb', 'state': 'RUNNING', 'enable': true},
          {'id': 2, 'service': 'nfs', 'state': 'STOPPED', 'enable': false},
        ],
      });

      final dashboard = await TrueNasService(client).loadDashboard();

      expect(dashboard.system.version, 'TrueNAS-SCALE-25.04.0');
      expect(dashboard.system.cores, 8);
      expect(dashboard.system.loadAvg1m, 0.5);

      expect(dashboard.pools, hasLength(2));
      expect(dashboard.pools.first.name, 'tank');
      expect(dashboard.pools.first.usedFraction, closeTo(0.75, 0.001));
      expect(dashboard.pools[1].healthy, isFalse);
      expect(dashboard.pools[1].usedFraction, isNull);

      // Only non-dismissed alerts are "active".
      expect(dashboard.alerts, hasLength(2));
      expect(dashboard.activeAlerts, hasLength(1));
      expect(dashboard.activeAlerts.first.id, 'a1');

      expect(dashboard.services.where((s) => s.running).length, 1);
    });

    test('actions call the expected RPC methods', () async {
      final client = _FakeClient({
        'service.start': null,
        'service.stop': null,
        'alert.dismiss': null,
        'core.ping': true,
      });
      final service = TrueNasService(client);

      await service.startService('smb');
      await service.stopService('nfs');
      await service.dismissAlert('a1');
      expect(await service.ping(), isTrue);

      expect(
        client.calls,
        containsAll(<String>[
          'service.start',
          'service.stop',
          'alert.dismiss',
          'core.ping',
        ]),
      );
    });
  });

  group('TrueNasWsClient.resolveEndpoint', () {
    test('derives wss /api/current from an https base url', () {
      final uri = TrueNasWsClient(
        baseUrl: 'https://nas.local:444',
        apiKey: 'k',
      ).resolveEndpoint();
      expect(uri.scheme, 'wss');
      expect(uri.host, 'nas.local');
      expect(uri.port, 444);
      expect(uri.path, '/api/current');
    });

    test('uses ws for an http base url and defaults the port', () {
      final uri = TrueNasWsClient(
        baseUrl: 'http://10.0.0.5',
        apiKey: 'k',
      ).resolveEndpoint();
      expect(uri.scheme, 'ws');
      expect(uri.port, 80);
    });
  });
}

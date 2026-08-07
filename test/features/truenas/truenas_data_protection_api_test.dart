import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/data/data_protection_api.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/domain/models/data_protection.dart';

/// One recorded RPC: the method name plus the params actually sent.
typedef _Call = ({String method, List<dynamic> params, bool asJob});

/// A [TrueNasWsClient] that records every RPC instead of opening a socket.
class _RecordingClient extends TrueNasWsClient {
  _RecordingClient() : super(baseUrl: 'https://nas.local', apiKey: 'key');

  final List<_Call> calls = [];

  @override
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    calls.add((method: method, params: params, asJob: false));
    return null;
  }

  @override
  Future<dynamic> callJob(
    String method, [
    List<dynamic> params = const [],
    TrueNasJobProgress? onProgress,
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 1),
  ]) async {
    calls.add((method: method, params: params, asJob: true));
    return null;
  }
}

TrueNasProtectionTask _task(
  TrueNasTaskKind kind, {
  int id = 7,
  String? poolName,
}) => TrueNasProtectionTask(
  kind: kind,
  id: id,
  title: 'task',
  subtitle: '',
  enabled: true,
  poolName: poolName,
);

void main() {
  group('TrueNasDataProtectionApi.run', () {
    test('cloud sync runs cloudsync.sync(id) as a job', () async {
      // `cloudsync.run` is not a middleware method: the previous uniform
      // `<namespace>.run` made every cloud-sync "Run now" fail server-side.
      final client = _RecordingClient();
      await TrueNasDataProtectionApi(
        client,
      ).run(_task(TrueNasTaskKind.cloudSync));

      expect(client.calls.single.method, 'cloudsync.sync');
      expect(client.calls.single.params, [7]);
      expect(client.calls.single.asJob, isTrue);
    });

    test('scrub runs pool.scrub.run by pool name, forcing the threshold', () {
      // The real signature is `pool.scrub.run(name: str, threshold: int)` —
      // sending the task id was rejected. Threshold 0 is what makes "Run now"
      // run now instead of skipping a recently scrubbed pool.
      final client = _RecordingClient();
      TrueNasDataProtectionApi(
        client,
      ).run(_task(TrueNasTaskKind.scrub, poolName: 'tank'));

      expect(client.calls.single.method, 'pool.scrub.run');
      expect(client.calls.single.params, ['tank', 0]);
      expect(client.calls.single.asJob, isFalse);
    });

    test('scrub without a pool name throws instead of sending garbage', () {
      final client = _RecordingClient();
      expect(
        () =>
            TrueNasDataProtectionApi(client).run(_task(TrueNasTaskKind.scrub)),
        throwsA(isA<TrueNasException>()),
      );
      expect(client.calls, isEmpty);
    });

    test('replication and rsync still run by id as jobs', () async {
      final client = _RecordingClient();
      final api = TrueNasDataProtectionApi(client);
      await api.run(_task(TrueNasTaskKind.replication, id: 3));
      await api.run(_task(TrueNasTaskKind.rsync, id: 4));

      expect(client.calls[0].method, 'replication.run');
      expect(client.calls[0].params, [3]);
      expect(client.calls[0].asJob, isTrue);
      expect(client.calls[1].method, 'rsynctask.run');
      expect(client.calls[1].params, [4]);
      expect(client.calls[1].asJob, isTrue);
    });

    test('snapshot tasks stay fire-and-forget by id', () async {
      final client = _RecordingClient();
      await TrueNasDataProtectionApi(
        client,
      ).run(_task(TrueNasTaskKind.snapshot, id: 9));

      expect(client.calls.single.method, 'pool.snapshottask.run');
      expect(client.calls.single.params, [9]);
      expect(client.calls.single.asJob, isFalse);
    });
  });
}

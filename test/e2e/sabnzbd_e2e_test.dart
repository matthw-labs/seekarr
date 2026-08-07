@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';

/// Tier-6 E2E (plan §7.6). Exercises the real [SabnzbdClient] transport against
/// the Docker instance from docker-compose.e2e.yml. Auto-skipped by dart_test.yaml
/// unless `flutter test --tags e2e` is used. Connects via 127.0.0.1 so SABnzbd's
/// hostname verification passes (see the seed .ini host_whitelist).
void main() {
  late SabnzbdClient client;

  setUp(() {
    client = SabnzbdClient(url: 'http://127.0.0.1:8080', apiKey: 'test-key');
  });

  tearDown(() => client.close());

  test('getVersion returns a non-empty version', () async {
    expect(await client.getVersion(), isNotEmpty);
  });

  test('getQueue authenticates and returns a real envelope', () async {
    final queue = await client.getQueue();
    // A fresh instance has an empty queue; the point is the call round-trips
    // real HTTP + auth + JSON parsing without throwing.
    expect(queue.slots, isA<List>());
  });

  test('getServerStats round-trips over real HTTP', () async {
    final stats = await client.getServerStats();
    expect(stats.total, greaterThanOrEqualTo(0));
  });
}

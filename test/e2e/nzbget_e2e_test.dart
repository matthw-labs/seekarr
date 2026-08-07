@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/nzbget/data/nzbget_client.dart';

/// Tier-6 E2E (plan §7.6). Drives the real [NzbgetClient] against the Docker
/// instance from docker-compose.e2e.yml, validating Basic auth, positional
/// JSON-RPC and Hi/Lo parsing end-to-end. Auto-skipped unless `--tags e2e`.
void main() {
  late NzbgetClient client;

  setUp(() {
    client = NzbgetClient(
      url: 'http://127.0.0.1:6789',
      username: 'nzbget',
      password: 'tegbzn6789',
    );
  });

  tearDown(() => client.close());

  test('version authenticates with Basic auth and returns a string', () async {
    expect(await client.version(), isNotEmpty);
  });

  test('status round-trips the real JSON-RPC envelope', () async {
    final status = await client.status();
    expect(status.remainingSizeMb, greaterThanOrEqualTo(0));
  });

  test('listGroups returns a list on a fresh instance', () async {
    expect(await client.listGroups(), isA<List>());
  });
}

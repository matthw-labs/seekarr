@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';

/// Tier-6 E2E (plan §7.6). Runs the real [ReadarrService] over [ApiClient]
/// against the Docker instance from docker-compose.e2e.yml, validating the
/// X-Api-Key header auth and the *arr v1 contract end-to-end. Auto-skipped
/// unless `--tags e2e`.
void main() {
  late ApiClient client;
  late ReadarrService service;

  setUp(() {
    client = ApiClient(baseUrl: 'http://127.0.0.1:8787', apiKey: 'test-key');
    service = ReadarrService(client);
  });

  tearDown(() => client.close());

  test('getAuthors round-trips the real /api/v1/author endpoint', () async {
    // A fresh Readarr has no authors; the call succeeding proves auth + parsing.
    final authors = await service.getAuthors();
    expect(authors, isA<List>());
  });

  test('getRecentHistory returns typed items', () async {
    final history = await service.getRecentHistory(pageSize: 5);
    expect(history, isA<List>());
  });
}

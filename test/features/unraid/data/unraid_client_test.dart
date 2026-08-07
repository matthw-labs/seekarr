import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/unraid/data/unraid_client.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';

UnraidClient _client(
  CapturingHttpAdapter adapter, {
  String key = 'UNRAID-KEY',
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://unraid.local'))
    ..httpClientAdapter = adapter;
  return UnraidClient(url: 'https://unraid.local', apiKey: key, dio: dio);
}

void main() {
  group('UnraidClient', () {
    test('getInfo sends the x-api-key header and a GraphQL body', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('unraid/info.json'),
      );
      final client = _client(adapter);

      final info = await client.getInfo();

      expect(info.version, '7.0.0');
      expect(adapter.lastHeaders!['x-api-key'], 'UNRAID-KEY');
      final body = adapter.lastBody as Map<String, dynamic>;
      expect(body['query'], contains('info'));
    });

    test('getArray computes used percentage and parses disks', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('unraid/array.json'),
      );
      final array = await _client(adapter).getArray();

      expect(array.state, 'STARTED');
      expect(array.usedPercent, 60);
      expect(array.disks, hasLength(2));
      expect(array.disks[1].temp, 47);
    });

    test(
      'getDockerContainers strips the leading slash and flags running',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('unraid/docker.json'),
        );
        final containers = await _client(adapter).getDockerContainers();

        expect(containers, hasLength(2));
        expect(containers.first.name, 'plex');
        expect(containers.first.running, isTrue);
        expect(containers[1].running, isFalse);
      },
    );

    test('throws UnraidException on a GraphQL error', () async {
      final adapter = CapturingHttpAdapter(
        response: {
          'errors': [
            {'message': 'Unauthorized'},
          ],
        },
      );
      final client = _client(adapter);

      expect(client.getInfo(), throwsA(isA<UnraidException>()));
    });
  });
}

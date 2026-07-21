import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/sabnzbd/data/sabnzbd_client.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';

SabnzbdClient _client(CapturingHttpAdapter adapter, {String key = 'SECRET'}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://sab.local'))
    ..httpClientAdapter = adapter;
  return SabnzbdClient(url: 'https://sab.local', apiKey: key, dio: dio);
}

void main() {
  group('SabnzbdClient', () {
    test('getVersion uses mode=version and omits the api key', () async {
      final adapter = CapturingHttpAdapter(response: {'version': '4.2.0'});
      final client = _client(adapter);

      expect(await client.getVersion(), '4.2.0');
      expect(adapter.lastUri!.queryParameters['mode'], 'version');
      expect(adapter.lastUri!.queryParameters.containsKey('apikey'), isFalse);
    });

    test('getQueue sends apikey + output=json and parses the queue', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('sabnzbd/queue.json'),
      );
      final client = _client(adapter);

      final queue = await client.getQueue();

      expect(adapter.lastUri!.queryParameters['mode'], 'queue');
      expect(adapter.lastUri!.queryParameters['apikey'], 'SECRET');
      expect(adapter.lastUri!.queryParameters['output'], 'json');
      expect(queue.paused, isFalse);
      expect(queue.slots, hasLength(1));
      expect(queue.slots.first.percentage, 50);
      expect(queue.speedLabel, '2.0 MB/s');
      expect(queue.sizeLeftLabel, '1.5 GB');
    });

    test('getHistory parses completed and failed slots', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('sabnzbd/history.json'),
      );
      final slots = await _client(adapter).getHistory();

      expect(slots, hasLength(2));
      expect(slots.first.failed, isFalse);
      expect(slots[1].failed, isTrue);
      expect(slots[1].failMessage, contains('Unpacking failed'));
    });

    test('throws a SabnzbdException on an API error envelope', () async {
      final adapter = CapturingHttpAdapter(
        response: {'status': false, 'error': 'API Key Incorrect'},
      );
      final client = _client(adapter);

      expect(client.getQueue(), throwsA(isA<SabnzbdException>()));
    });

    test('redactSabnzbdSecrets strips the api key from any string', () {
      final redacted = redactSabnzbdSecrets(
        'https://sab.local/api?mode=queue&apikey=SECRET123&output=json',
      );
      expect(redacted, isNot(contains('SECRET123')));
      expect(redacted, contains('apikey=***'));
    });
  });
}

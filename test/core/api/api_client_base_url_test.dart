import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/api/api_client.dart';

import '../../test_helpers/capturing_http_adapter.dart';

void main() {
  group('ApiClient base URL', () {
    test('accepts a scheme-less host instead of throwing', () {
      // Regression: onboarding accepts a bare host, and `BaseOptions.baseUrl`
      // rejects one with an ArgumentError raised from the constructor — outside
      // every caller's try block. The verify button spun forever with nothing
      // on screen to explain it.
      expect(
        () => ApiClient(baseUrl: '192.168.1.100:7878', apiKey: 'k'),
        returnsNormally,
      );
    });

    test('sends a scheme-less host over https', () async {
      final adapter = CapturingHttpAdapter(response: <String, dynamic>{});
      final client = ApiClient(baseUrl: '192.168.1.100:7878', apiKey: 'k');
      client.dio.httpClientAdapter = adapter;

      await client.get('/api/v3/system/status');

      expect(
        adapter.lastUri.toString(),
        'https://192.168.1.100:7878/api/v3/system/status',
      );
    });

    test(
      'honours an explicit cleartext scheme and drops a trailing slash',
      () async {
        final adapter = CapturingHttpAdapter(response: <String, dynamic>{});
        final client = ApiClient(baseUrl: 'http://10.0.0.5:8989/', apiKey: 'k');
        client.dio.httpClientAdapter = adapter;

        await client.get('/api/v3/health');

        expect(
          adapter.lastUri.toString(),
          'http://10.0.0.5:8989/api/v3/health',
        );
      },
    );
  });
}

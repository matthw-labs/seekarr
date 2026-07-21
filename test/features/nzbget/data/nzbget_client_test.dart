import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/nzbget/domain/models/nzbget_models.dart';

import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';

NzbgetClient _client(
  CapturingHttpAdapter adapter, {
  String? user = 'nzbget',
  String? pass = 'tegbzn6789',
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://nzbget.local:6789'))
    ..httpClientAdapter = adapter;
  return NzbgetClient(
    url: 'https://nzbget.local:6789',
    username: user,
    password: pass,
    dio: dio,
  );
}

void main() {
  group('NzbgetClient', () {
    test('version sends Basic auth and positional JSON-RPC params', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('nzbget/version.json'),
      );
      final client = _client(adapter);

      expect(await client.version(), '21.1');
      final expected =
          'Basic ${base64Encode(utf8.encode('nzbget:tegbzn6789'))}';
      expect(
        adapter.lastHeaders!['authorization'] ??
            adapter.lastHeaders!['Authorization'],
        expected,
      );
      final body = adapter.lastBody as Map<String, dynamic>;
      expect(body['method'], 'version');
      expect(body['params'], isA<List<dynamic>>());
    });

    test('status parses rate, remaining size and paused', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('nzbget/status.json'),
      );
      final status = await _client(adapter).status();

      expect(status.downloadRateBytes, 2097152);
      expect(status.remainingSizeMb, 1500);
      expect(status.paused, isFalse);
      expect(status.rateLabel, '2.0 MB/s');
    });

    test('listGroups parses queue progress', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('nzbget/listgroups.json'),
      );
      final groups = await _client(adapter).listGroups();

      expect(groups, hasLength(1));
      expect(groups.first.percentage, 50);
    });

    test('history flags success and failure statuses', () async {
      final adapter = CapturingHttpAdapter(
        response: jsonFixtureMap('nzbget/history.json'),
      );
      final items = await _client(adapter).history();

      expect(items, hasLength(2));
      expect(items.first.success, isTrue);
      expect(items[1].failed, isTrue);
    });

    test('combineHiLo recomposes a 64-bit value from Hi/Lo halves', () {
      expect(combineHiLo(1, 0), 4294967296);

      final group = NzbgetGroup.fromJson({
        'NZBID': 9,
        'NZBName': 'Big.Release',
        'Status': 'QUEUED',
        'FileSizeHi': 0,
        'FileSizeLo': 3221225472,
        'RemainingSizeHi': 0,
        'RemainingSizeLo': 1610612736,
      });

      expect(group.fileSizeMb, 3072);
      expect(group.remainingSizeMb, 1536);
    });
  });
}

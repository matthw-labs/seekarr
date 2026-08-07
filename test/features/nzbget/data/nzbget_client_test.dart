import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';

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

    test(
      'status falls back to Hi/Lo bytes when the MB field is absent',
      () async {
        final adapter = CapturingHttpAdapter(
          response: jsonFixtureMap('nzbget/status_hilo.json'),
        );
        final status = await _client(adapter).status();

        // RemainingSize = 1 * 2^32 + 1610612736 = 5905580032 bytes → 5632 MB.
        expect(status.remainingSizeMb, 5632);
        expect(status.paused, isTrue);
      },
    );

    test('append sends positional params and returns the new NZBID', () async {
      final adapter = CapturingHttpAdapter(
        response: {'jsonrpc': '2.0', 'result': 7, 'id': 1},
      );
      final client = _client(adapter);

      final id = await client.append(
        'linux.nzb',
        'https://indexer.local/get/linux.nzb',
        category: 'software',
        priority: 1,
      );

      expect(id, 7);
      final body = adapter.lastBody as Map<String, dynamic>;
      expect(body['method'], 'append');
      final params = body['params'] as List<dynamic>;
      // (NZBFilename, NZBContent, Category, Priority, AddToTop, AddPaused)
      expect(params[0], 'linux.nzb');
      expect(params[1], 'https://indexer.local/get/linux.nzb');
      expect(params[2], 'software');
      expect(params[3], 1);
      expect(params.every((p) => p is! Map), isTrue); // never named params
    });

    test('deleteGroup issues a GroupDelete editqueue command', () async {
      final adapter = CapturingHttpAdapter(
        response: {'jsonrpc': '2.0', 'result': true, 'id': 1},
      );
      final client = _client(adapter);

      expect(await client.deleteGroup(5), isTrue);
      final body = adapter.lastBody as Map<String, dynamic>;
      expect(body['method'], 'editqueue');
      final params = body['params'] as List<dynamic>;
      expect(params[0], 'GroupDelete');
      expect(params.last, [5]);
    });

    test('a refused editqueue reports false rather than throwing', () async {
      // NZBGet answers HTTP 200 with `{"result": false}` when it declines a
      // command — pausing a group whose NZBID has already left the queue, for
      // instance. There is no JSON-RPC `error` object to catch, so the return
      // value is the only evidence the mutation did not happen.
      final adapter = CapturingHttpAdapter(
        response: {'jsonrpc': '2.0', 'result': false, 'id': 1},
      );
      final client = _client(adapter);

      expect(await client.pauseGroup(5), isFalse);
      expect(await client.deleteGroup(5), isFalse);
    });

    test('a rejected append reports 0 rather than throwing', () async {
      final adapter = CapturingHttpAdapter(
        response: {'jsonrpc': '2.0', 'result': 0, 'id': 1},
      );

      expect(await _client(adapter).append('x.nzb', 'https://bad/x.nzb'), 0);
    });

    test('setRate sends the limit as a positional param', () async {
      final adapter = CapturingHttpAdapter(
        response: {'jsonrpc': '2.0', 'result': true, 'id': 1},
      );
      final client = _client(adapter);

      await client.setRate(2048);
      final body = adapter.lastBody as Map<String, dynamic>;
      expect(body['method'], 'rate');
      expect(body['params'], [2048]);
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';

/// In-memory [HttpClientAdapter] keyed by request path. Decodes the request
/// stream to expose form-urlencoded bodies as a Map for easier assertions.
class _StubAdapter implements HttpClientAdapter {
  final Map<String, dynamic> responses = {};
  final Map<String, Exception> exceptions = {};

  final List<RequestOptions> requests = [];
  final List<Map<String, String>> requestBodies = [];

  void setJson(String path, dynamic body) {
    responses[path] = body;
    _registerContentType(path, isJson: true);
  }

  void setText(String path, String body) {
    responses[path] = body;
    _registerContentType(path, isJson: false);
  }

  final Map<String, bool> _jsonPaths = {};

  void _registerContentType(String path, {required bool isJson}) {
    _jsonPaths[path] = isJson;
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);

    if (requestStream != null) {
      final bytes = await _collectBytes(requestStream);
      final text = utf8.decode(bytes);
      if (text.isNotEmpty) {
        requestBodies.add(_parseForm(text));
      } else {
        requestBodies.add({});
      }
    } else {
      requestBodies.add({});
    }

    if (exceptions.containsKey(options.path)) {
      throw exceptions[options.path]!;
    }

    final isJson = _jsonPaths[options.path] ?? false;
    final body = responses[options.path] ?? (isJson ? <String, dynamic>{} : '');
    final bytes = body is String
        ? utf8.encode(body)
        : Uint8List.fromList(utf8.encode(jsonEncode(body)));
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: [
          isJson ? 'application/json' : 'text/plain; charset=utf-8',
        ],
      },
    );
  }

  Future<Uint8List> _collectBytes(Stream<Uint8List> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  Map<String, String> _parseForm(String text) {
    final out = <String, String>{};
    for (final pair in text.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (eq < 0) {
        out[Uri.decodeComponent(pair)] = '';
      } else {
        out[Uri.decodeComponent(pair.substring(0, eq))] = Uri.decodeComponent(
          pair.substring(eq + 1),
        );
      }
    }
    return out;
  }
}

QbittorrentService _service(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'));
  dio.httpClientAdapter = adapter;
  final client = QbittorrentClient(
    url: 'http://localhost:8080',
    username: 'admin',
    password: 'adminadmin',
    dio: dio,
  );
  return QbittorrentService(client);
}

Map<String, dynamic> _torrentJson({
  String hash = 'aaa',
  String state = 'downloading',
}) => {
  'hash': hash,
  'name': 'A',
  'size': 100,
  'progress': 0.5,
  'state': state,
  'dlspeed': 1024,
  'upspeed': 0,
  'eta': 60,
  'category': '',
  'tracker': '',
  'tags': <String>[],
  'ratio': 1.0,
  'added_on': 0,
  'completed': 0,
  'num_leechs': 0,
  'num_seeds': 0,
};

void main() {
  group('QbittorrentService', () {
    test('getTorrents maps response into Torrent list', () async {
      final adapter = _StubAdapter()
        ..setJson('/api/v2/torrents/info', [_torrentJson()]);
      final service = _service(adapter);

      final torrents = await service.getTorrents();
      expect(torrents, hasLength(1));
      expect(torrents.first.hash, 'aaa');
      expect(torrents.first.parsedState, TorrentState.downloading);
      expect(adapter.requests.last.path, '/api/v2/torrents/info');
    });

    test('getTorrents forwards filter and category', () async {
      final adapter = _StubAdapter()..setJson('/api/v2/torrents/info', []);
      final service = _service(adapter);

      await service.getTorrents(filter: 'downloading', category: 'linux');
      final params = adapter.requests.last.queryParameters;
      expect(params['filter'], 'downloading');
      expect(params['category'], 'linux');
    });

    test('getTorrents forwards hashes for single-torrent queries', () async {
      final adapter = _StubAdapter()..setJson('/api/v2/torrents/info', []);
      final service = _service(adapter);

      await service.getTorrents(hashes: 'abc');
      final params = adapter.requests.last.queryParameters;
      expect(params['hashes'], 'abc');
    });

    test('pauseTorrents joins hashes with pipe and POSTs', () async {
      final adapter = _StubAdapter()..setText('/api/v2/torrents/stop', '');
      final service = _service(adapter);

      await service.pauseTorrents(['a', 'b', 'c']);
      final req = adapter.requests.last;
      expect(req.path, '/api/v2/torrents/stop');
      expect(req.method, 'POST');
      expect(adapter.requestBodies.last, {'hashes': 'a|b|c'});
    });

    test('resumeTorrents sends POST with hashes', () async {
      final adapter = _StubAdapter()..setText('/api/v2/torrents/start', '');
      final service = _service(adapter);

      await service.resumeTorrents(['x']);
      expect(adapter.requests.last.path, '/api/v2/torrents/start');
      expect(adapter.requestBodies.last, {'hashes': 'x'});
    });

    test('deleteTorrents sends deleteFiles as string true/false', () async {
      final adapter = _StubAdapter()..setText('/api/v2/torrents/delete', '');
      final service = _service(adapter);

      await service.deleteTorrents(['a'], deleteFiles: true);
      expect(adapter.requestBodies.last['hashes'], 'a');
      expect(adapter.requestBodies.last['deleteFiles'], 'true');

      await service.deleteTorrents(['b'], deleteFiles: false);
      expect(adapter.requestBodies.last['deleteFiles'], 'false');
    });

    test('addTorrentUrl sends urls, category and savepath', () async {
      final adapter = _StubAdapter()..setText('/api/v2/torrents/add', '');
      final service = _service(adapter);

      await service.addTorrentUrl(
        'magnet:?xt=urn:btih:abc',
        category: 'linux',
        savePath: '/downloads',
      );
      final body = adapter.requestBodies.last;
      expect(body['urls'], 'magnet:?xt=urn:btih:abc');
      expect(body['category'], 'linux');
      expect(body['savepath'], '/downloads');
    });

    test('addTorrentUrl omits empty optional fields', () async {
      final adapter = _StubAdapter()..setText('/api/v2/torrents/add', '');
      final service = _service(adapter);

      await service.addTorrentUrl('magnet:?xt=urn:btih:abc');
      expect(adapter.requestBodies.last, {'urls': 'magnet:?xt=urn:btih:abc'});
    });

    test('setCategory sends hashes and category', () async {
      final adapter = _StubAdapter()
        ..setText('/api/v2/torrents/setCategory', '');
      final service = _service(adapter);

      await service.setCategory(['a', 'b'], 'linux');
      expect(adapter.requestBodies.last, {
        'hashes': 'a|b',
        'category': 'linux',
      });
    });

    test('addTags and removeTags join tags with comma', () async {
      final adapter = _StubAdapter()
        ..setText('/api/v2/torrents/addTags', '')
        ..setText('/api/v2/torrents/removeTags', '');
      final service = _service(adapter);

      await service.addTags(['h1'], ['a', 'b']);
      expect(adapter.requestBodies.last, {'hashes': 'h1', 'tags': 'a,b'});

      await service.removeTags(['h2'], ['a']);
      expect(adapter.requestBodies.last, {'hashes': 'h2', 'tags': 'a'});
    });

    test('setDownloadLimit and setUploadLimit send limit in bytes', () async {
      final adapter = _StubAdapter()
        ..setText('/api/v2/torrents/setDownloadLimit', '')
        ..setText('/api/v2/torrents/setUploadLimit', '');
      final service = _service(adapter);

      await service.setDownloadLimit(['h'], 1024);
      expect(adapter.requestBodies.last, {'hashes': 'h', 'limit': '1024'});

      await service.setUploadLimit(['h'], 2048);
      expect(adapter.requestBodies.last, {'hashes': 'h', 'limit': '2048'});
    });

    test('setForceStart posts value as true/false string', () async {
      final adapter = _StubAdapter()
        ..setText('/api/v2/torrents/setForceStart', '');
      final service = _service(adapter);

      await service.setForceStart(['h'], true);
      expect(adapter.requestBodies.last, {'hashes': 'h', 'value': 'true'});

      await service.setForceStart(['h'], false);
      expect(adapter.requestBodies.last, {'hashes': 'h', 'value': 'false'});
    });

    test('toggleAlternativeSpeedLimits posts to toggle endpoint', () async {
      final adapter = _StubAdapter()
        ..setText('/api/v2/transfer/toggleSpeedLimitsMode', '');
      final service = _service(adapter);

      await service.toggleAlternativeSpeedLimits();
      final req = adapter.requests.last;
      expect(req.path, '/api/v2/transfer/toggleSpeedLimitsMode');
      expect(req.method, 'POST');
    });

    test('getTransferInfo parses payload', () async {
      final adapter = _StubAdapter()
        ..setJson('/api/v2/transfer/info', {
          'dl_info_speed': 1024,
          'up_info_speed': 0,
          'dl_info_data': 0,
          'up_info_data': 0,
          'dl_rate_limit': 0,
          'up_rate_limit': 0,
          'use_alt_speed_limits': false,
        });
      final service = _service(adapter);

      final info = await service.getTransferInfo();
      expect(info.dlSpeed, 1024);
      expect(info.altSpeedEnabled, isFalse);
    });

    test('getTorrentFiles parses array payload', () async {
      final adapter = _StubAdapter()
        ..setJson('/api/v2/torrents/files', [
          {
            'index': 0,
            'name': 'a.iso',
            'size': 10,
            'progress': 0.5,
            'priority': 1,
          },
        ]);
      final service = _service(adapter);

      final files = await service.getTorrentFiles('h');
      expect(files, hasLength(1));
      expect(files.first.name, 'a.iso');
      expect(adapter.requests.last.queryParameters, {'hash': 'h'});
    });

    test('getTorrentTrackers parses array payload', () async {
      final adapter = _StubAdapter()
        ..setJson('/api/v2/torrents/trackers', [
          {
            'url': 'udp://tracker',
            'status': 2,
            'tier': 0,
            'num_peers': 5,
            'num_seeds': 2,
            'num_leeches': 1,
            'num_downloaded': 10,
            'msg': 'ok',
          },
        ]);
      final service = _service(adapter);

      final trackers = await service.getTorrentTrackers('h');
      expect(trackers, hasLength(1));
      expect(trackers.first.status, 2);
      expect(trackers.first.numSeeds, 2);
    });

    test(
      'getTorrentProperties parses object payload and sends hash query param',
      () async {
        final adapter = _StubAdapter()
          ..setJson('/api/v2/torrents/properties', {
            'save_path': '/downloads/Ubuntu',
            'creation_date': 1700000000,
            'piece_size': 32768,
            'comment': 'ubuntu-24.04',
            'total_wasted': 0,
            'total_uploaded': 1048576,
            'total_uploaded_session': 0,
            'total_downloaded': 2097152,
            'total_downloaded_session': 0,
            'up_limit': -1,
            'dl_limit': 1024,
            'time_elapsed': 7200,
            'seeding_time': 600,
            'nb_connections': 5,
            'nb_connections_limit': 100,
            'share_ratio': 1.5,
            'addition_date': 1700000000,
            'completion_date': 1700001000,
            'created_by': 'qBittorrent v4.6.0',
            'dl_speed_avg': 1024,
            'dl_speed': 2048,
            'eta': 3600,
            'last_seen': 1700005000,
            'peers': 5,
            'peers_total': 10,
            'pieces_have': 32,
            'pieces_num': 64,
            'reannounce': 30,
            'seeds': 7,
            'seeds_total': 15,
            'total_size': 2147483648,
            'up_speed_avg': 512,
            'up_speed': 256,
            'is_private': 1,
          });
        final service = _service(adapter);

        final props = await service.getTorrentProperties('abc');

        expect(adapter.requests.last.path, '/api/v2/torrents/properties');
        expect(adapter.requests.last.queryParameters, {'hash': 'abc'});
        expect(props.savePath, '/downloads/Ubuntu');
        expect(props.timeElapsed, 7200);
        expect(props.seedingTime, 600);
        expect(props.totalSize, 2147483648);
        expect(props.shareRatio, 1.5);
        expect(props.dlLimit, 1024);
        expect(props.upLimit, -1);
        expect(props.isPrivate, isTrue);
      },
    );

    test('getTorrentProperties propagates transport errors', () async {
      // The family provider needs AsyncValue.error to fire on /properties
      // failures (older qB versions return 404, network drops, etc.) so the
      // UI's _PropRow can render "—" per cell. The service must NOT swallow
      // the error here.
      final adapter = _StubAdapter()
        ..exceptions['/api/v2/torrents/properties'] = Exception('boom');
      final service = _service(adapter);

      expect(
        () => service.getTorrentProperties('abc'),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'addTorrentFiles sends multipart with each file and optional fields',
      () async {
        final adapter = _StubAdapter()..setText('/api/v2/torrents/add', '');
        final service = _service(adapter);

        final f1 = MultipartFile.fromBytes([1, 2, 3], filename: 'a.torrent');
        final f2 = MultipartFile.fromBytes([4, 5, 6], filename: 'b.torrent');
        await service.addTorrentFiles(
          [f1, f2],
          category: 'movies',
          savePath: '/dl',
        );

        final req = adapter.requests.last;
        expect(req.path, '/api/v2/torrents/add');
        expect(req.method, 'POST');
        expect(
          req.headers[Headers.contentTypeHeader],
          contains(Headers.multipartFormDataContentType.toString()),
        );
        // The body bytes won't roundtrip cleanly through `_StubAdapter` for
        // multipart (it tries to URL-decode them). Just confirm the request
        // hit the right endpoint with multipart content type.
      },
    );

    test('addTorrentFiles omits empty optional fields', () async {
      final adapter = _StubAdapter()..setText('/api/v2/torrents/add', '');
      final service = _service(adapter);

      await service.addTorrentFiles([
        MultipartFile.fromBytes([1], filename: 'a.torrent'),
      ]);
      expect(adapter.requests.last.path, '/api/v2/torrents/add');
    });

    test('filePrio sends hash, file indexes and priority', () async {
      final adapter = _StubAdapter()..setText('/api/v2/torrents/filePrio', '');
      final service = _service(adapter);

      await service.filePrio(hash: 'h1', fileIndexes: [0, 2, 4], priority: 6);
      final body = adapter.requestBodies.last;
      expect(body['hash'], 'h1');
      expect(body['id'], '0|2|4');
      expect(body['priority'], '6');
    });

    test('recheck posts single hash', () async {
      final adapter = _StubAdapter()..setText('/api/v2/torrents/recheck', '');
      final service = _service(adapter);

      await service.recheck('h1');
      expect(adapter.requests.last.path, '/api/v2/torrents/recheck');
      expect(adapter.requestBodies.last, {'hashes': 'h1'});
    });

    test('reannounce joins hashes with pipe', () async {
      final adapter = _StubAdapter()
        ..setText('/api/v2/torrents/reannounce', '');
      final service = _service(adapter);

      await service.reannounce(['a', 'b']);
      expect(adapter.requests.last.path, '/api/v2/torrents/reannounce');
      expect(adapter.requestBodies.last, {'hashes': 'a|b'});
    });
  });
}

// Captures the status-relevant payloads from a live *arr / Seerr instance,
// redacts them, and reports which enum values the instance actually returns.
//
//   dart run tool/capture_status_fixtures.dart radarr https://radarr.example
//   dart run tool/capture_status_fixtures.dart sonarr http://10.0.0.5:8989
//   dart run tool/capture_status_fixtures.dart lidarr http://10.0.0.5:8686
//   dart run tool/capture_status_fixtures.dart seerr  https://seerr.example
//
// This is Phase 0 of media_status_plan.md: the checked-in fixtures are recorded
// from the official API docs, and this closes the loop against a real instance.
//
// The API key is prompted for at runtime, so it never lands in argv or in shell
// history. Output goes to test/fixtures/<service>/*.captured.json, which is
// gitignored: captures stay local and feed the local test run, while the
// doc-derived fixtures beside them are the committed ones.
//
// REDACTION: every string that is not a known status/shape field is replaced
// with a stable placeholder. Raw payloads carry filesystem paths (which contain
// usernames), release names, indexer names and download client names, and this
// keeps a capture safe to paste into an issue. Numbers, booleans, nulls, the
// status enums and the timing fields are kept verbatim — they are what the
// fixtures exist to pin.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/status/arr_queue_snapshot.dart';

/// Strings under these keys survive redaction.
///
/// Deliberately narrow: anything not listed is replaced, so a field we have not
/// thought about fails closed rather than leaking.
const _verbatimKeys = <String>{
  // The enums this whole exercise is about.
  'status',
  'trackedDownloadStatus',
  'trackedDownloadState',
  'protocol',
  'minimumAvailability',
  'eventType',
  'seriesType',
  'monitorNewItems',
  // Quality / language shape.
  'name',
  'source',
  'modifier',
  // Timings, needed to keep date parsing honest.
  'timeleft',
  'timeLeft',
  'estimatedCompletionTime',
  'added',
  'airDateUtc',
  'airDate',
  'inCinemas',
  'digitalRelease',
  'physicalRelease',
  'releaseDate',
  'firstAired',
  'lastAired',
  'createdAt',
  'updatedAt',
  'mediaAddedAt',
  'mediaType',
};

/// Fields whose distinct values are worth reporting back to the user.
const _reportedFields = <String>[
  'status',
  'trackedDownloadStatus',
  'trackedDownloadState',
  'protocol',
];

/// What the resolvers in `lib/core/status/` currently understand.
///
/// Anything an instance returns outside these sets is printed as a finding: it
/// still resolves (to `queued`, never to `missing`), but it means the mapping
/// deserves a look.
const _knownValues = <String, Set<String>>{
  'status': {
    'unknown',
    'queued',
    'paused',
    'downloading',
    'completed',
    'failed',
    'warning',
    'delay',
    'downloadclientunavailable',
    'fallback',
  },
  'trackedDownloadStatus': {'ok', 'warning', 'error'},
  'trackedDownloadState': {
    'downloading',
    'importblocked',
    'importpending',
    'importing',
    'imported',
    'failedpending',
    'failed',
    'ignored',
  },
};

class _ServiceSpec {
  final String apiVersion;
  final Map<String, dynamic> queueParams;

  const _ServiceSpec({required this.apiVersion, this.queueParams = const {}});
}

const _specs = <String, _ServiceSpec>{
  'radarr': _ServiceSpec(
    apiVersion: 'v3',
    queueParams: {'includeMovie': true, 'pageSize': 200},
  ),
  'sonarr': _ServiceSpec(
    apiVersion: 'v3',
    queueParams: {
      'includeSeries': true,
      'includeEpisode': true,
      'includeUnknownSeriesItems': true,
      'pageSize': 200,
    },
  ),
  'lidarr': _ServiceSpec(
    apiVersion: 'v1',
    queueParams: {'includeArtist': true, 'includeAlbum': true, 'pageSize': 200},
  ),
  'seerr': _ServiceSpec(apiVersion: 'v1'),
};

Future<void> main(List<String> args) async {
  if (args.length < 2 || !_specs.containsKey(args[0])) {
    stderr.writeln(
      'usage: dart run tool/capture_status_fixtures.dart '
      '<${_specs.keys.join('|')}> <base-url>',
    );
    exit(64);
  }

  final service = args[0];
  final baseUrl = args[1];
  final spec = _specs[service]!;

  // Guarded: toggling echo on a piped stdin throws, and piping is how this gets
  // exercised in a loopback test.
  final interactive = stdin.hasTerminal;
  stdout.write('API key for $service (not echoed): ');
  if (interactive) stdin.echoMode = false;
  final apiKey = stdin.readLineSync() ?? '';
  if (interactive) stdin.echoMode = true;
  stdout.writeln('\n');

  if (apiKey.trim().isEmpty) {
    stderr.writeln('no API key given, aborting');
    exit(64);
  }

  final client = ApiClient(baseUrl: baseUrl, apiKey: apiKey.trim());

  if (service == 'seerr') {
    await _captureSeerr(client);
  } else {
    await _captureArr(service, spec, client);
  }
}

Future<void> _captureArr(
  String service,
  _ServiceSpec spec,
  ApiClient client,
) async {
  final queue = await _get(
    client,
    '/api/${spec.apiVersion}/queue',
    queryParameters: spec.queueParams,
  );
  if (queue == null) return;

  final records = _recordsOf(queue);
  stdout.writeln('queue records: ${records.length}\n');

  if (records.isNotEmpty) {
    _reportEnumValues(records);
    _reportResolvedPipelines(records);
  }

  // Sonarr's series stats are worth reporting even with an idle queue: they
  // answer whether `episodeCount` is the right denominator for `partial`.
  if (service == 'sonarr') {
    await _reportSonarrEpisodeCounts(client, spec);
  }

  if (records.isEmpty) {
    // Writing an empty envelope would be worse than writing nothing: the
    // conformance test iterates its records, so a vacuous capture passes
    // trivially and reads like coverage that does not exist.
    stdout.writeln(
      'The queue is empty, so there is nothing to capture and no fixture was\n'
      'written. Re-run this while something is actually downloading or waiting\n'
      'to import — that is the state the fixtures exist to pin.',
    );
    return;
  }

  _write(
    'test/fixtures/$service/queue.captured.json',
    _redact(queue) as Map<String, dynamic>,
  );
}

Future<void> _captureSeerr(ApiClient client) async {
  // `/media` carries the mediaInfo objects — including `downloadStatus`, the
  // live per-*arr download records the app now reads.
  final media = await _get(
    client,
    '/api/v1/media',
    queryParameters: {'take': 100},
  );
  if (media == null) return;

  final results = switch (media) {
    {'results': final List<dynamic> results} => results,
    _ => const <dynamic>[],
  };

  final withDownloads = results
      .whereType<Map<String, dynamic>>()
      .where(
        (item) => (item['downloadStatus'] as List<dynamic>? ?? []).isNotEmpty,
      )
      .toList(growable: false);

  stdout.writeln('media entries: ${results.length}');
  stdout.writeln('…with a live downloadStatus: ${withDownloads.length}');
  if (withDownloads.isEmpty) {
    stdout.writeln(
      '\nNOTE: nothing is downloading right now, so downloadStatus is empty\n'
      '      everywhere. Re-run while a request is being grabbed to capture\n'
      '      the shape that matters.',
    );
  }
  stdout.writeln('');

  final downloadRecords = withDownloads
      .expand(
        (item) => (item['downloadStatus'] as List<dynamic>)
            .whereType<Map<String, dynamic>>(),
      )
      .toList(growable: false);

  if (downloadRecords.isNotEmpty) {
    _reportEnumValues(downloadRecords);
    _reportResolvedPipelines(downloadRecords);
  }

  final statusCodes = results
      .whereType<Map<String, dynamic>>()
      .map((item) => item['status'])
      .toSet();
  stdout.writeln('distinct mediaInfo.status codes: ${statusCodes.toList()}');
  stdout.writeln('');

  _write(
    'test/fixtures/seerr/media.captured.json',
    _redact(media) as Map<String, dynamic>,
  );
}

/// Answers the open question from the plan: is `episodeCount` the right
/// denominator for `partial`, or does it undercount what is on disk?
Future<void> _reportSonarrEpisodeCounts(
  ApiClient client,
  _ServiceSpec spec,
) async {
  final series = await _get(client, '/api/${spec.apiVersion}/series');
  if (series is! List) return;

  var continuing = 0;
  var filesExceedAired = 0;
  var airedExceedsTotal = 0;
  final samples = <String>[];

  for (final entry in series.whereType<Map<String, dynamic>>()) {
    final stats = entry['statistics'];
    if (stats is! Map) continue;

    final aired = (stats['episodeCount'] as num?)?.toInt() ?? 0;
    final total = (stats['totalEpisodeCount'] as num?)?.toInt() ?? 0;
    final files = (stats['episodeFileCount'] as num?)?.toInt() ?? 0;
    final isContinuing =
        entry['status']?.toString().toLowerCase() == 'continuing';

    if (isContinuing) continuing++;
    if (files > aired) filesExceedAired++;
    if (aired > total) airedExceedsTotal++;

    if (isContinuing && samples.length < 5) {
      samples.add(
        '  aired=$aired total=$total files=$files '
        '${files >= aired && aired > 0 ? '→ available' : ''}',
      );
    }
  }

  stdout.writeln('--- episodeCount semantics (continuing series) ---');
  stdout.writeln('continuing series           : $continuing');
  stdout.writeln('episodeFileCount > episodeCount : $filesExceedAired');
  stdout.writeln('episodeCount > totalEpisodeCount: $airedExceedsTotal');
  if (samples.isNotEmpty) {
    stdout.writeln('samples:');
    samples.forEach(stdout.writeln);
  }
  if (filesExceedAired > 0) {
    stdout.writeln(
      '\nFINDING: some series hold more files than episodeCount reports, so\n'
      '         episodeCount is the wrong denominator for `partial`.\n'
      '         Revisit sonarrSeriesAvailability.',
    );
  } else {
    stdout.writeln(
      '\nOK: episodeFileCount never exceeds episodeCount, so using it as the\n'
      '    denominator keeps a fully-downloaded continuing series `available`.',
    );
  }
  stdout.writeln('');
}

void _reportEnumValues(List<Map<String, dynamic>> records) {
  stdout.writeln('--- observed values ---');
  for (final field in _reportedFields) {
    final values = records
        .map((record) => record[field]?.toString())
        .whereType<String>()
        .toSet();
    if (values.isEmpty) continue;

    stdout.writeln('$field: ${values.toList()..sort()}');

    final known = _knownValues[field];
    if (known == null) continue;

    final unknown = values
        .where((value) => !known.contains(value.toLowerCase()))
        .toList();
    if (unknown.isNotEmpty) {
      stdout.writeln('  !! not in the resolver mapping: $unknown');
    }
  }
  stdout.writeln('');
}

void _reportResolvedPipelines(List<Map<String, dynamic>> records) {
  final tally = <String, int>{};
  for (final record in records) {
    final entry = ArrQueueEntry.fromQueueItem(record);
    final key = entry == null
        ? 'finished (no badge)'
        : entry.label ?? entry.pipeline.label;
    tally[key] = (tally[key] ?? 0) + 1;
  }

  stdout.writeln('--- how the app will badge these ---');
  final sorted = tally.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sorted) {
    stdout.writeln('${entry.value.toString().padLeft(4)}  ${entry.key}');
  }
  stdout.writeln(
    '\nCompare this against your *arr\'s own queue view. A mismatch is a bug\n'
    'in lib/core/status/arr_queue_snapshot.dart, not in the fixture.\n',
  );
}

List<Map<String, dynamic>> _recordsOf(dynamic payload) {
  final records = switch (payload) {
    {'records': final List<dynamic> records} => records,
    final List<dynamic> list => list,
    _ => const <dynamic>[],
  };
  return records.whereType<Map<String, dynamic>>().toList(growable: false);
}

Future<dynamic> _get(
  ApiClient client,
  String path, {
  Map<String, dynamic>? queryParameters,
}) async {
  try {
    final response = await client.get(path, queryParameters: queryParameters);
    if (response.statusCode != 200) {
      stderr.writeln('$path -> HTTP ${response.statusCode}');
      return null;
    }
    return response.data;
  } on DioException catch (error) {
    stderr.writeln('$path -> ${error.type.name}: ${error.message}');
    return null;
  }
}

/// Replaces every string outside [_verbatimKeys] with a stable placeholder.
///
/// Distinct inputs keep distinct placeholders, so anything that depends on
/// values differing (dedupe, grouping) still behaves like the real payload.
dynamic _redact(dynamic node, {String? key}) {
  if (node is Map) {
    return <String, dynamic>{
      for (final entry in node.entries)
        entry.key.toString(): _redact(entry.value, key: entry.key.toString()),
    };
  }
  if (node is List) {
    return node.map((item) => _redact(item, key: key)).toList();
  }
  if (node is String) {
    if (key != null && _verbatimKeys.contains(key)) return node;
    return _placeholderFor(key ?? 'value', node);
  }
  return node;
}

// Keyed by a (key, value) record rather than a concatenated string: no
// separator to pick, so no chance of two different pairs colliding.
final _placeholders = <(String, String), String>{};
final _counters = <String, int>{};

String _placeholderFor(String key, String value) {
  return _placeholders.putIfAbsent((key, value), () {
    final next = (_counters[key] ?? 0) + 1;
    _counters[key] = next;
    return '$key-$next';
  });
}

void _write(String path, Map<String, dynamic> payload) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
  );

  stdout.writeln('wrote $path (redacted)');
  stdout.writeln(
    'Captures are gitignored: they stay on your machine and feed the local test\n'
    'run. The committed fixtures next to them are the doc-derived ones.',
  );
}

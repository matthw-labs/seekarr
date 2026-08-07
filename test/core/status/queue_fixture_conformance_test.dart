import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';

import '../../test_helpers/fixtures.dart';
import '../../test_helpers/model_builders.dart';

/// Runs the real resolvers over recorded `/queue` payloads.
///
/// The unit tests elsewhere pin individual mappings; this file asserts the
/// invariants that must hold for *every* record of a whole payload, which is
/// what catches a field we mis-typed or a status value we never considered.
///
/// Fixtures live in `test/fixtures/<service>/`. The ones checked in are recorded
/// from the official API docs and cover the full documented enum matrix; replace
/// them with a live capture via `dart run tool/capture_status_fixtures.dart` to
/// verify against a real instance. Optional captured files are skipped when
/// absent so CI stays green either way.
void main() {
  group('Radarr queue payload', () {
    final records = _records('radarr/queue.json');

    test('every record is either in-flight or explicitly finished', () {
      for (final record in records) {
        final trackedState = record['trackedDownloadState']
            ?.toString()
            .toLowerCase();
        final entry = ArrQueueEntry.fromQueueItem(record);
        final isFinished =
            trackedState == 'imported' || trackedState == 'ignored';

        expect(
          entry == null,
          isFinished,
          reason:
              'record ${record['id']} (trackedDownloadState=$trackedState) '
              'resolved to ${entry?.pipeline.name ?? 'null'}',
        );
      }
    });

    test('progress stays a real fraction or stays absent', () {
      for (final record in records) {
        final progress = ArrQueueEntry.fromQueueItem(record)?.progress;
        if (progress == null) continue;

        expect(progress, inInclusiveRange(0.0, 1.0));
        expect(progress.isFinite, isTrue);
      }
    });

    test('nothing in the queue can resolve to Missing', () {
      // The regression guard: a movie with no file on disk, paired with any
      // record from a real queue, must never read "Missing".
      final snapshot = ArrQueueSnapshot.fromQueueItems(
        records,
        idsFor: (item) => [
          ?intOrNull(mapOrNull(item['movie'])?['id'] ?? item['movieId']),
        ],
      );

      expect(snapshot.isNotEmpty, isTrue);

      for (final id in snapshot.entriesById.keys) {
        final status = radarrMovieStatus(
          buildMovie(id: id, hasFile: false, status: 'released'),
          queueEntry: snapshot.entryFor(id),
        );

        expect(status.isInPipeline, isTrue, reason: 'movie $id');
        expect(status.label, isNot('Missing'), reason: 'movie $id');
      }
    });

    test('finished records are left out of the snapshot entirely', () {
      final snapshot = ArrQueueSnapshot.fromQueueItems(
        records,
        idsFor: (item) => [
          ?intOrNull(mapOrNull(item['movie'])?['id'] ?? item['movieId']),
        ],
      );

      // Movie J is `imported`, Movie K is `ignored` — neither is in flight, so
      // their real availability must show through instead.
      expect(snapshot.entryFor(110), isNull);
      expect(snapshot.entryFor(111), isNull);
    });

    test('a warning on the record surfaces on the resolved status', () {
      final blocked = records.firstWhere((record) => record['id'] == 6);
      final status = radarrMovieStatus(
        buildMovie(hasFile: false, status: 'released'),
        queueEntry: ArrQueueEntry.fromQueueItem(blocked),
      );

      // "Not a Custom Format upgrade for existing movie file" is the canonical
      // reason an \*arr blocks an import: it needs a person to decide. It used to
      // render as "Import Pending", the state that clears itself in seconds.
      expect(status.label, 'Import Blocked');
      expect(status.hasWarning, isTrue);
      expect(status.tone, StatusTone.warning);
      expect(
        status.detail,
        contains('Not a Custom Format upgrade for existing movie file'),
      );
    });

    test(
      'Activity renders a label for every record, finished ones included',
      () {
        for (final record in records) {
          final label = queueDisplayLabel(resolveQueueDisplayStatus(record));

          expect(label, isNotEmpty, reason: 'record ${record['id']}');
          expect(label, isNot('Unknown'), reason: 'record ${record['id']}');
        }
      },
    );
  });

  group('Sonarr queue payload', () {
    final records = _records('sonarr/queue.json');

    ArrQueueSnapshot snapshot() => ArrQueueSnapshot.fromQueueItems(
      records,
      idsFor: (item) => [
        ?intOrNull(mapOrNull(item['series'])?['id'] ?? item['seriesId']),
      ],
    );

    test('several episodes of one series collapse onto the series', () {
      // Series A has two downloading episodes and one queued; the headline is
      // the download, averaged over the two that share it.
      final entry = snapshot().entryFor(201);

      expect(entry?.pipeline, MediaPipeline.downloading);
      expect(entry?.progress, closeTo((0.2 + 0.8) / 2, 1e-9));
    });

    test('unknown-series records are dropped, not crashed on', () {
      // `includeUnknownSeriesItems=true` yields records with a null series.
      final unknown = records.firstWhere((record) => record['series'] == null);

      expect(ArrQueueEntry.fromQueueItem(unknown), isNotNull);
      expect(snapshot().entriesById.keys, isNot(contains(0)));
    });

    test('a partial series in the queue reports the download, not the gap', () {
      final status = sonarrSeriesStatus(
        buildSeries(
          id: 201,
          statistics: const {
            'episodeCount': 30,
            'totalEpisodeCount': 40,
            'episodeFileCount': 28,
          },
        ),
        queueEntry: snapshot().entryFor(201),
      );

      expect(status.availability, MediaAvailability.partial);
      expect(status.label, 'Downloading');
    });

    test('nothing in the queue can resolve to Missing', () {
      final resolved = snapshot();

      for (final id in resolved.entriesById.keys) {
        final status = sonarrSeriesStatus(
          buildSeries(
            id: id,
            statistics: const {'episodeCount': 10, 'episodeFileCount': 0},
          ),
          queueEntry: resolved.entryFor(id),
        );

        expect(status.label, isNot('Missing'), reason: 'series $id');
      }
    });
  });

  group('Lidarr queue payload', () {
    final records = _records('lidarr/queue.json');

    test('albums index independently of artists', () {
      final byAlbum = ArrQueueSnapshot.fromQueueItems(
        records,
        idsFor: (item) => [
          ?intOrNull(mapOrNull(item['album'])?['id'] ?? item['albumId']),
        ],
      );

      expect(byAlbum.entryFor(401)?.pipeline, MediaPipeline.downloading);
      expect(byAlbum.entryFor(402)?.pipeline, MediaPipeline.queued);
      expect(byAlbum.entryFor(403)?.pipeline, MediaPipeline.importPending);
      // Album D is already imported.
      expect(byAlbum.entryFor(404), isNull);
    });

    test(
      'a record naming only its album still resolves via album.artistId',
      () {
        final byArtist = ArrQueueSnapshot.fromQueueItems(
          records,
          idsFor: (item) => [
            ?intOrNull(
              mapOrNull(item['artist'])?['id'] ??
                  mapOrNull(item['album'])?['artistId'] ??
                  item['artistId'],
            ),
          ],
        );

        expect(byArtist.entryFor(302)?.pipeline, MediaPipeline.queued);
      },
    );
  });

  group('Seerr media payloads', () {
    test(
      'a processing movie reports the live download from downloadStatus',
      () {
        final details = jsonFixtureMap('seerr/movie_details.json');
        final status = seerrMediaStatus(mapOrNull(details['mediaInfo']));

        expect(status.label, 'Downloading');
        expect(status.progress, closeTo(0.75, 1e-9));
        expect(status.availability, MediaAvailability.missing);
      },
    );

    test('the 4k axis of the same payload has nothing in flight', () {
      final details = jsonFixtureMap('seerr/movie_details.json');
      final status = seerrMediaStatus(
        mapOrNull(details['mediaInfo']),
        is4k: true,
      );

      expect(status.pipeline, isNull);
      expect(status.label, 'Unknown');
    });

    test(
      'a partially available series reports the episode that needs a person',
      () {
        final details = jsonFixtureMap('seerr/tv_details_partial.json');
        final status = seerrMediaStatus(mapOrNull(details['mediaInfo']));

        // Two records in this payload: S02E04 downloading healthily, S02E05
        // `importBlocked`. The headline used to be "Downloading" with a bare
        // warning marker — the actionable episode hidden behind the healthy one,
        // and no way to tell why the marker was there. Gravity ranking surfaces the
        // blocked one, which is the only one that will still be stuck tomorrow.
        expect(status.availability, MediaAvailability.partial);
        expect(status.label, 'Import Blocked');
        expect(status.hasWarning, isTrue);
      },
    );
  });

  group('captured payloads', () {
    // Populated by `dart run tool/capture_status_fixtures.dart`. Absent in a
    // clean checkout, so these are skipped rather than failed.
    for (final path in const [
      'radarr/queue.captured.json',
      'sonarr/queue.captured.json',
      'lidarr/queue.captured.json',
    ]) {
      test(
        '$path holds up against the resolvers',
        () {
          final records = _records(path);

          for (final record in records) {
            final entry = ArrQueueEntry.fromQueueItem(record);
            if (entry == null) continue;

            final progress = entry.progress;
            if (progress != null) {
              expect(progress, inInclusiveRange(0.0, 1.0));
            }
            expect(
              queueDisplayLabel(resolveQueueDisplayStatus(record)),
              isNotEmpty,
            );
          }
        },
        skip: _missing(path) ? 'no capture at test/fixtures/$path' : false,
      );
    }
  });
}

bool _missing(String path) => !File('test/fixtures/$path').existsSync();

/// Reads the `records` array out of an \*arr paged envelope.
List<Map<String, dynamic>> _records(String path) {
  if (_missing(path)) return const [];

  final payload = jsonFixture(path);
  final records = payload is Map<String, dynamic>
      ? payload['records'] as List<dynamic>
      : payload as List<dynamic>;

  return records
      .map(mapOrNull)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

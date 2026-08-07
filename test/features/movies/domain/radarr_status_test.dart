import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';

RadarrMovie _movie({
  bool hasFile = false,
  bool monitored = true,
  String status = 'released',
  bool? isAvailable,
}) {
  return RadarrMovie(
    id: 1,
    title: 'Dune',
    sortTitle: 'dune',
    sizeOnDisk: 0,
    status: status,
    hasFile: hasFile,
    monitored: monitored,
    year: 2021,
    images: const [],
    tmdbId: 438631,
    runtime: 155,
    genres: const [],
    isAvailable: isAvailable,
  );
}

void main() {
  group('radarrMovieAvailability', () {
    test('a file on disk is available', () {
      expect(
        radarrMovieAvailability(_movie(hasFile: true)),
        MediaAvailability.available,
      );
    });

    test('deleted outranks a file on disk', () {
      expect(
        radarrMovieAvailability(_movie(hasFile: true, status: 'deleted')),
        MediaAvailability.deleted,
      );
    });

    test("Radarr's isAvailable decides missing versus unreleased", () {
      expect(
        radarrMovieAvailability(_movie(isAvailable: true)),
        MediaAvailability.missing,
      );
      expect(
        radarrMovieAvailability(_movie(isAvailable: false)),
        MediaAvailability.unavailable,
      );
    });

    test('isAvailable wins over the release status', () {
      // Radarr weighs minimumAvailability, so a released movie can still be
      // "not available to grab".
      expect(
        radarrMovieAvailability(_movie(status: 'released', isAvailable: false)),
        MediaAvailability.unavailable,
      );
    });

    final statusFallbacks = <String, MediaAvailability>{
      'released': MediaAvailability.missing,
      'inCinemas': MediaAvailability.missing,
      'announced': MediaAvailability.unavailable,
      'tba': MediaAvailability.unavailable,
    };

    statusFallbacks.forEach((status, availability) {
      test(
        'without isAvailable, "$status" falls back to ${availability.name}',
        () {
          expect(radarrMovieAvailability(_movie(status: status)), availability);
        },
      );
    });
  });

  group('radarrMovieStatus', () {
    test('a movie in the queue never reads Missing', () {
      // The exact bug: no file on disk, released, and downloading.
      final status = radarrMovieStatus(
        _movie(status: 'released', isAvailable: true),
        queueEntry: const ArrQueueEntry(
          pipeline: MediaPipeline.downloading,
          progress: 0.4,
        ),
      );

      expect(status.label, 'Downloading');
      expect(status.progress, 0.4);
      expect(status.availability, MediaAvailability.missing);
    });

    test('without a queue entry a released movie is Missing', () {
      final status = radarrMovieStatus(
        _movie(status: 'released', isAvailable: true),
      );

      expect(status.label, 'Missing');
    });

    test('an unmonitored movie with no file is not flagged as an error', () {
      final status = radarrMovieStatus(
        _movie(status: 'released', isAvailable: true, monitored: false),
      );

      expect(status.label, 'Unmonitored');
      expect(status.tone, StatusTone.neutral);
    });

    test('an unreleased movie reads Not Released, not Missing', () {
      final status = radarrMovieStatus(
        _movie(status: 'announced', isAvailable: false),
      );

      expect(status.label, 'Not Released');
      expect(status.tone, StatusTone.neutral);
    });
  });

  group('RadarrMovie.fromJson', () {
    test('parses isAvailable when present and leaves it null otherwise', () {
      expect(
        RadarrMovie.fromJson({'id': 1, 'isAvailable': true}).isAvailable,
        isTrue,
      );
      expect(RadarrMovie.fromJson({'id': 1}).isAvailable, isNull);
      // A non-boolean payload must not be coerced.
      expect(
        RadarrMovie.fromJson({'id': 1, 'isAvailable': 'yes'}).isAvailable,
        isNull,
      );
    });
  });
}

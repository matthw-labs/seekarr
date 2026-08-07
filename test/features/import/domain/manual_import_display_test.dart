import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/import/domain/manual_import_display.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

ManualImportItem _item(Map<String, dynamic> json) =>
    ManualImportItem.fromJson({'path': '/downloads/x.mkv', ...json});

void main() {
  group('manualImportIsSupportedFile', () {
    test('a video file is importable by the video arrs', () {
      final item = _item({'path': '/downloads/Boruto.S01E12.mkv'});
      expect(manualImportIsSupportedFile(ServiceKey.sonarr, item), isTrue);
      expect(manualImportIsSupportedFile(ServiceKey.radarr, item), isTrue);
    });

    test('a playlist is not a Sonarr episode', () {
      // The real complaint: a downloads folder full of M3U playlists and music
      // reported 26 files "needing a match" when only a few were episodes.
      final playlist = _item({'path': '/downloads/200-linkin_park.m3u'});
      expect(manualImportIsSupportedFile(ServiceKey.sonarr, playlist), isFalse);
    });

    test('music is not importable by Sonarr, and video not by Lidarr', () {
      final song = _item({'path': '/downloads/Green Day - Smooth.mp3'});
      expect(manualImportIsSupportedFile(ServiceKey.sonarr, song), isFalse);
      expect(manualImportIsSupportedFile(ServiceKey.lidarr, song), isTrue);

      final video = _item({'path': '/downloads/Wicked.2025.mkv'});
      expect(manualImportIsSupportedFile(ServiceKey.lidarr, video), isFalse);
    });
  });

  group('manualImportFileNamesTitle', () {
    test('a release-named file names its title', () {
      for (final path in const [
        '/downloads/Target Movie.mkv',
        '/downloads/Target.Movie.2024.1080p.BluRay.x264-GRP.mkv',
        '/downloads/target_movie_2024.mkv',
      ]) {
        expect(
          manualImportFileNamesTitle('Target Movie', _item({'path': path})),
          isTrue,
          reason: path,
        );
      }
    });

    test('the release folder counts as the name too', () {
      // The case the whole feature exists for: the service could not parse the
      // file, but the folder it arrived in says plainly what it is.
      final item = _item({
        'path': '/downloads/Target Movie (2024)/a1b2c3.mkv',
        'folderName': 'Target Movie (2024)',
        'relativePath': 'a1b2c3.mkv',
      });
      expect(manualImportFileNamesTitle('Target Movie', item), isTrue);
    });

    test('a leading article on either side is not a difference', () {
      final item = _item({'path': '/downloads/Batman.2022.1080p.mkv'});
      expect(manualImportFileNamesTitle('The Batman', item), isTrue);
    });

    test('a different film does not name the target', () {
      for (final path in const [
        '/downloads/Some Other Movie.mkv',
        '/downloads/Target.mkv',
        '/downloads/Movie Target.mkv',
        '/downloads/a1b2c3.mkv',
      ]) {
        expect(
          manualImportFileNamesTitle('Target Movie', _item({'path': path})),
          isFalse,
          reason: path,
        );
      }
    });

    test('the scan root never vouches for what is under it', () {
      // Checking the absolute path would make every file in `/media/The Matrix`
      // a Matrix file, which is precisely the over-reach being guarded against.
      final item = _item({
        'path': '/media/The Matrix/unrelated.mkv',
        'folderName': 'unrelated-release',
        'relativePath': 'unrelated.mkv',
      });
      expect(manualImportFileNamesTitle('The Matrix', item), isFalse);
    });

    test('an empty title matches nothing', () {
      final item = _item({'path': '/downloads/Target Movie.mkv'});
      expect(manualImportFileNamesTitle('   ', item), isFalse);
    });
  });

  group('manualImportGroupTitle', () {
    test('groups by the matched media title per service', () {
      expect(
        manualImportGroupTitle(
          ServiceKey.sonarr,
          _item({
            'series': {'id': 1, 'title': 'Boruto'},
          }),
        ),
        'Boruto',
      );
      expect(
        manualImportGroupTitle(
          ServiceKey.radarr,
          _item({
            'movie': {'id': 1, 'title': 'Inception'},
          }),
        ),
        'Inception',
      );
      expect(
        manualImportGroupTitle(
          ServiceKey.lidarr,
          _item({
            'artist': {'id': 1, 'artistName': 'Linkin Park'},
          }),
        ),
        'Linkin Park',
      );
    });

    test('falls back to Unmatched with no match', () {
      expect(manualImportGroupTitle(ServiceKey.sonarr, _item({})), 'Unmatched');
    });
  });

  group('manualImportIdentityFor', () {
    test('sonarr carries the episode code and title', () {
      final identity = manualImportIdentityFor(
        ServiceKey.sonarr,
        _item({
          'series': {'id': 1, 'title': 'The Pitt'},
          'episodes': [
            {
              'id': 5,
              'seasonNumber': 2,
              'episodeNumber': 1,
              'title': '7:00 A.M.',
            },
          ],
          'quality': {
            'quality': {'id': 3, 'name': 'WEBDL-2160p'},
          },
        }),
      );
      expect(identity.code, 'S02E01');
      expect(identity.title, '7:00 A.M.');
      expect(identity.quality, 'WEBDL-2160p');
    });

    test('a multi-episode file spans its range', () {
      final identity = manualImportIdentityFor(
        ServiceKey.sonarr,
        _item({
          'series': {'id': 1, 'title': 'Boruto'},
          'episodes': [
            {'id': 1, 'seasonNumber': 1, 'episodeNumber': 11, 'title': 'A'},
            {'id': 2, 'seasonNumber': 1, 'episodeNumber': 12, 'title': 'B'},
          ],
        }),
      );
      expect(identity.code, 'S01E11-E12');
      expect(identity.title, 'A + B');
    });

    test('radarr carries the year', () {
      final identity = manualImportIdentityFor(
        ServiceKey.radarr,
        _item({
          'movie': {'id': 1, 'title': 'Inception', 'year': 2010},
        }),
      );
      expect(identity.code, '2010');
      expect(identity.title, isNull);
    });

    test('lidarr carries the track range and the album', () {
      final identity = manualImportIdentityFor(
        ServiceKey.lidarr,
        _item({
          'artist': {'id': 1, 'artistName': 'Linkin Park'},
          'album': {'id': 2, 'title': 'From Zero'},
          'tracks': [
            {'id': 1, 'trackNumber': 3, 'title': 'A'},
            {'id': 2, 'trackNumber': 5, 'title': 'B'},
          ],
        }),
      );
      expect(identity.code, 'Tracks 3–5');
      expect(identity.title, 'From Zero');
    });
  });

  group('the identity is matched data, never parsed data', () {
    test('the episode code comes from the matched episode, not the file', () {
      // The \*arr payload carries both: a top-level `seasonNumber` parsed out of
      // the release name, and the matched library episode records. They can
      // disagree — an absolute-numbered anime file parses as season 1 while the
      // matched episode is season 3 — and the chip must show the match.
      final identity = manualImportIdentityFor(
        ServiceKey.sonarr,
        _item({
          'path': '/downloads/Boruto - 293 [1080p].mkv',
          'name': 'Boruto - 293 [1080p]',
          'seasonNumber': 1,
          'series': {'id': 1, 'title': 'Boruto'},
          'episodes': [
            {
              'id': 9,
              'seasonNumber': 3,
              'episodeNumber': 7,
              'title': 'DOG & CHAINSAW',
            },
          ],
        }),
      );
      expect(identity.code, 'S03E07');
      expect(identity.code, isNot(contains('S01')));
      expect(identity.title, 'DOG & CHAINSAW');
    });

    test('no matched episode means no code and no title at all', () {
      // Rather than fall back to anything inferred from the filename.
      final identity = manualImportIdentityFor(
        ServiceKey.sonarr,
        _item({
          'path': '/downloads/Chainsaw.Man.S01E01.1080p.mkv',
          'name': 'Chainsaw.Man.S01E01.1080p',
          'seasonNumber': 1,
          'series': {'id': 1, 'title': 'Chainsaw Man'},
        }),
      );
      expect(identity.code, isNull);
      expect(identity.title, isNull);
    });

    test('radarr takes the year from the matched movie record', () {
      final identity = manualImportIdentityFor(
        ServiceKey.radarr,
        _item({
          'path': '/downloads/Blade.Runner.2049.2017.mkv',
          'name': 'Blade.Runner.2049.2017',
          'movie': {'id': 1, 'title': 'Blade Runner 2049', 'year': 2017},
        }),
      );
      // Not 2049, which is what the title looks like in the filename.
      expect(identity.code, '2017');
    });

    test('lidarr takes the track numbers from the matched tracks', () {
      final identity = manualImportIdentityFor(
        ServiceKey.lidarr,
        _item({
          'path': '/downloads/09 - Somewhere I Belong.flac',
          'name': '09 - Somewhere I Belong',
          'artist': {'id': 1, 'artistName': 'Linkin Park'},
          'album': {'id': 2, 'title': 'Meteora'},
          'tracks': [
            {'id': 3, 'trackNumber': 4, 'title': 'Somewhere I Belong'},
          ],
        }),
      );
      // The filename says 09; the matched track is 4.
      expect(identity.code, 'Track 4');
      expect(identity.title, 'Meteora');
    });
  });

  group('fileName is the raw file on disk', () {
    test('ignores the service name field, which drops the extension', () {
      final item = _item({
        'path': '/downloads/Boruto.S01E12.1080p.WEB-DL.x264-GROUP.mkv',
        'name': 'Boruto.S01E12.1080p.WEB-DL.x264-GROUP',
      });
      expect(item.fileName, 'Boruto.S01E12.1080p.WEB-DL.x264-GROUP.mkv');
    });

    test('the filter searches the rendered filename, extension included', () {
      final item = _item({
        'path': '/downloads/Boruto.S01E12.mkv',
        'name': 'Boruto.S01E12',
      });
      expect(manualImportMatchesQuery(ServiceKey.sonarr, item, '.mkv'), isTrue);
    });
  });

  group('manualImportMatchesQuery', () {
    final boruto = _item({
      'path': '/downloads/Boruto.S01E12.1080p.mkv',
      'name': 'Boruto.S01E12.1080p.mkv',
      'series': {'id': 1, 'title': 'Boruto: Naruto Next Generations'},
      'episodes': [
        {'id': 1, 'seasonNumber': 1, 'episodeNumber': 12, 'title': 'The Pain'},
      ],
    });

    test('matches on the series title, case-insensitively', () {
      expect(
        manualImportMatchesQuery(ServiceKey.sonarr, boruto, 'boruto'),
        isTrue,
      );
    });

    test('matches on the episode code, title and filename', () {
      for (final query in ['S01E12', 'the pain', '1080p']) {
        expect(
          manualImportMatchesQuery(ServiceKey.sonarr, boruto, query),
          isTrue,
          reason: 'expected "$query" to match',
        );
      }
    });

    test('does not match an unrelated query', () {
      expect(
        manualImportMatchesQuery(ServiceKey.sonarr, boruto, 'supergirl'),
        isFalse,
      );
    });

    test('an empty query matches everything', () {
      expect(manualImportMatchesQuery(ServiceKey.sonarr, boruto, '  '), isTrue);
    });

    test('finds an unmatched file by its filename', () {
      final unmatched = _item({
        'path': '/downloads/Boruto.S01E13.mkv',
        'name': 'Boruto.S01E13.mkv',
      });
      expect(
        manualImportMatchesQuery(ServiceKey.sonarr, unmatched, 'boruto'),
        isTrue,
      );
    });
  });
}

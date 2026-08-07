import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/models/arr_release.dart';

void main() {
  group('ArrRelease', () {
    group('fromJson', () {
      test('parses complete release data correctly', () {
        final json = {
          'title': 'Movie.2024.1080p.BluRay.x264',
          'indexer': 'TestIndexer',
          'indexerId': 5,
          'guid': 'abc-123-guid',
          'size': 5368709120, // 5GB
          'seeders': 50,
          'leechers': 10,
          'ageMinutes': 1440,
          'customFormatScore': 150,
          'customFormats': [
            {'name': 'Bluray', 'score': 100},
            {'name': 'x264', 'score': 50},
          ],
          'rejections': ['Size too large'],
          'quality': {
            'quality': {'name': '1080p BluRay'},
          },
          'approved': false,
        };

        final release = ArrRelease.fromJson(json);

        expect(release.title, 'Movie.2024.1080p.BluRay.x264');
        expect(release.indexer, 'TestIndexer');
        expect(release.indexerId, 5);
        expect(release.guid, 'abc-123-guid');
        expect(release.size, 5368709120);
        expect(release.seeders, 50);
        expect(release.leechers, 10);
        expect(release.ageMinutes, 1440);
        expect(release.customFormatScore, 150);
        expect(release.customFormats.length, 2);
        expect(release.customFormats[0].name, 'Bluray');
        expect(release.customFormats[0].score, 100);
        expect(release.rejections, ['Size too large']);
        expect(release.qualityName, '1080p BluRay');
        expect(release.approved, false);
        expect(release.isRejected, true);
      });

      test('handles null and missing fields with defaults', () {
        final json = <String, dynamic>{};

        final release = ArrRelease.fromJson(json);

        expect(release.title, 'Unknown');
        expect(release.indexer, 'Unknown');
        expect(release.indexerId, 0);
        expect(release.guid, '');
        expect(release.size, 0);
        expect(release.seeders, 0);
        expect(release.leechers, 0);
        expect(release.ageMinutes, 0);
        expect(release.customFormatScore, 0);
        expect(release.customFormats, isEmpty);
        expect(release.rejections, isEmpty);
        expect(release.qualityName, '');
        expect(release.approved, false);
        expect(release.isRejected, false);
      });

      test('handles double values for numeric fields', () {
        final json = {
          'size': 5368709120.5,
          'seeders': 50.0,
          'ageMinutes': 1440.7,
          'customFormatScore': 150.9,
        };

        final release = ArrRelease.fromJson(json);

        expect(release.size, 5368709120);
        expect(release.seeders, 50);
        expect(release.ageMinutes, 1440);
        expect(release.customFormatScore, 150);
      });
    });

    group('rejections parsing', () {
      test('handles string rejections', () {
        final json = {
          'rejections': ['Bad quality', 'Size too small'],
        };

        final release = ArrRelease.fromJson(json);

        expect(release.rejections, ['Bad quality', 'Size too small']);
      });

      test('handles object rejections with reason field', () {
        final json = {
          'rejections': [
            {'reason': 'Bad quality'},
            {'reason': 'Size too small'},
          ],
        };

        final release = ArrRelease.fromJson(json);

        expect(release.rejections, ['Bad quality', 'Size too small']);
      });

      test('handles mixed rejection formats', () {
        final json = {
          'rejections': [
            'String rejection',
            {'reason': 'Object rejection'},
          ],
        };

        final release = ArrRelease.fromJson(json);

        expect(release.rejections, ['String rejection', 'Object rejection']);
      });

      test('handles null rejections', () {
        final json = {'rejections': null};

        final release = ArrRelease.fromJson(json);

        expect(release.rejections, isEmpty);
      });
    });

    group('quality name parsing', () {
      test('parses nested quality name', () {
        final json = {
          'quality': {
            'quality': {'name': 'HDTV-1080p'},
          },
        };

        final release = ArrRelease.fromJson(json);

        expect(release.qualityName, 'HDTV-1080p');
      });

      test('handles missing quality object', () {
        final json = {'quality': null};

        final release = ArrRelease.fromJson(json);

        expect(release.qualityName, '');
      });

      test('handles missing inner quality', () {
        final json = {
          'quality': {'quality': null},
        };

        final release = ArrRelease.fromJson(json);

        expect(release.qualityName, '');
      });
    });

    group('toJson', () {
      test('converts back to compatible JSON format', () {
        final release = ArrRelease(
          title: 'Test Release',
          indexer: 'Indexer1',
          indexerId: 1,
          guid: 'guid-123',
          size: 1000,
          seeders: 10,
          leechers: 5,
          ageMinutes: 60,
          customFormatScore: 100,
          customFormats: [CustomFormat(name: 'HD', score: 50)],
          rejections: ['Reason 1'],
          qualityName: '1080p',
          approved: true,
        );

        final json = release.toJson();

        expect(json['title'], 'Test Release');
        expect(json['indexer'], 'Indexer1');
        expect(json['indexerId'], 1);
        expect(json['guid'], 'guid-123');
        expect(json['size'], 1000);
        expect(json['customFormats'], isA<List>());
        expect(json['quality']['quality']['name'], '1080p');
      });
    });
  });

  group('CustomFormat', () {
    test('parses from JSON correctly', () {
      final json = {'name': 'Bluray', 'score': 100};

      final cf = CustomFormat.fromJson(json);

      expect(cf.name, 'Bluray');
      expect(cf.score, 100);
    });

    test('handles missing fields', () {
      final json = <String, dynamic>{};

      final cf = CustomFormat.fromJson(json);

      expect(cf.name, 'Unknown');
      expect(cf.score, 0);
    });

    test('converts to JSON correctly', () {
      final cf = CustomFormat(name: 'x264', score: 50);

      final json = cf.toJson();

      expect(json['name'], 'x264');
      expect(json['score'], 50);
    });
  });
}

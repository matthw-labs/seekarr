import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/utils/release_utils.dart';

void main() {
  group('formatReleaseSize', () {
    // Delegates to the shared precise ladder: three significant digits above
    // bytes, whole bytes, and every rung up to PB. The old private copy spent
    // one decimal at KB/MB and two at GB, and had no rung above GB at all.
    const cases = {
      0: '0 B',
      512: '512 B',
      1024: '1.00 KB',
      1536: '1.50 KB',
      1048576: '1.00 MB',
      1073741824: '1.00 GB',
      2147483648: '2.00 GB',
      // Resolution where releases are actually compared: two candidates a few
      // hundred MB apart stay distinguishable.
      4700000000: '4.38 GB',
      27917287424: '26.0 GB',
      837000000: '798 MB',
    };
    for (final entry in cases.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(formatReleaseSize(entry.key), entry.value);
      });
    }

    test('a season pack past a terabyte promotes instead of printing GB', () {
      // The private copy bottomed out at GB and rendered this as "2048.00 GB".
      expect(formatReleaseSize(2199023255552), '2.00 TB');
    });
  });

  group('formatReleaseAge', () {
    const cases = {
      0: '0m',
      30: '30m',
      60: '1h',
      120: '2h',
      1440: '1d',
      2880: '2d',
    };
    for (final entry in cases.entries) {
      test('${entry.key}min -> ${entry.value}', () {
        expect(formatReleaseAge(entry.key), entry.value);
      });
    }
  });

  group('filterAndSortReleases - sorting', () {
    // A:score=100,size=5G,seeders=50,age=1440
    // B:score=200,size=3G,seeders=100,age=60
    // C:score=150,size=8G,seeders=25,age=2880
    final testReleases = <Map<String, dynamic>>[
      {
        'title': 'A',
        'customFormatScore': 100,
        'size': 5000000000,
        'seeders': 50,
        'ageMinutes': 1440,
        'indexer': 'I1',
        'rejections': <dynamic>[],
      },
      {
        'title': 'B',
        'customFormatScore': 200,
        'size': 3000000000,
        'seeders': 100,
        'ageMinutes': 60,
        'indexer': 'I2',
        'rejections': <dynamic>[],
      },
      {
        'title': 'C',
        'customFormatScore': 150,
        'size': 8000000000,
        'seeders': 25,
        'ageMinutes': 2880,
        'indexer': 'I1',
        'rejections': <dynamic>['bad'],
      },
    ];

    // Expected title order for (sortType, sortAscending).
    // Note: for age, default (sortAscending=false) yields newest-first
    // because the utility negates the comparison.
    final cases = <(ReleaseSortType, bool, List<String>)>[
      (ReleaseSortType.score, false, ['B', 'C', 'A']),
      (ReleaseSortType.score, true, ['A', 'C', 'B']),
      (ReleaseSortType.size, false, ['C', 'A', 'B']),
      (ReleaseSortType.size, true, ['B', 'A', 'C']),
      (ReleaseSortType.seeders, false, ['B', 'A', 'C']),
      (ReleaseSortType.seeders, true, ['C', 'A', 'B']),
      (ReleaseSortType.age, false, ['B', 'A', 'C']),
      (ReleaseSortType.age, true, ['C', 'A', 'B']),
    ];

    for (final (sortType, asc, expected) in cases) {
      test('${sortType.name} ascending=$asc -> $expected', () {
        final sorted = filterAndSortReleases(
          testReleases,
          sortType: sortType,
          sortAscending: asc,
          hideRejected: false,
        );
        expect(sorted.map((r) => r['title']).toList(), expected);
      });
    }

    test('null numeric fields treated as 0', () {
      final releases = [
        {'title': 'With', 'customFormatScore': 50, 'rejections': []},
        {'title': 'Null', 'customFormatScore': null, 'rejections': []},
        {'title': 'Missing', 'rejections': []},
      ];
      final sorted = filterAndSortReleases(
        releases,
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: false,
      );
      expect(sorted[0]['title'], 'With');
      expect(sorted.sublist(1).map((r) => r['title']).toSet(), {
        'Null',
        'Missing',
      });
    });

    test('stable sort for equal values', () {
      final releases = List.generate(
        3,
        (i) => {
          'title': ['First', 'Second', 'Third'][i],
          'customFormatScore': 100,
          'rejections': [],
        },
      );
      final sorted = filterAndSortReleases(
        releases,
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: false,
      );
      expect(sorted.map((r) => r['title']).toList(), [
        'First',
        'Second',
        'Third',
      ]);
    });

    test('empty and single release inputs', () {
      expect(
        filterAndSortReleases(
          [],
          sortType: ReleaseSortType.score,
          sortAscending: false,
          hideRejected: false,
        ),
        isEmpty,
      );

      final single = filterAndSortReleases(
        [
          {'title': 'X', 'customFormatScore': 1, 'rejections': []},
        ],
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: false,
      );
      expect(single, hasLength(1));
    });

    test('all-null release does not throw', () {
      final sorted = filterAndSortReleases(
        [
          <String, dynamic>{
            'title': 'Null',
            'customFormatScore': null,
            'size': null,
            'seeders': null,
            'ageMinutes': null,
            'indexer': null,
            'rejections': null,
          },
        ],
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: false,
      );
      expect(sorted, hasLength(1));
    });
  });

  group('filterAndSortReleases - filtering', () {
    final releases = <Map<String, dynamic>>[
      {
        'title': 'Ok1',
        'indexer': 'I1',
        'rejections': <dynamic>[],
        'customFormatScore': 100,
      },
      {
        'title': 'BadI2',
        'indexer': 'I2',
        'rejections': <dynamic>['bad'],
        'customFormatScore': 50,
      },
      {
        'title': 'Ok2',
        'indexer': 'I1',
        'rejections': <dynamic>[],
        'customFormatScore': 75,
      },
      {
        'title': 'BadI1',
        'indexer': 'I1',
        'rejections': <dynamic>['bad'],
        'customFormatScore': 25,
      },
    ];

    test('hideRejected=false shows all', () {
      expect(
        filterAndSortReleases(
          releases,
          sortType: ReleaseSortType.score,
          sortAscending: false,
          hideRejected: false,
        ),
        hasLength(4),
      );
    });

    test('hideRejected=true filters out rejections', () {
      final filtered = filterAndSortReleases(
        releases,
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: true,
      );
      expect(filtered, hasLength(2));
      expect(filtered.every((r) => (r['rejections'] as List).isEmpty), isTrue);
    });

    test('null/missing rejections treated as empty', () {
      final filtered = filterAndSortReleases(
        [
          {'title': 'NoField', 'customFormatScore': 100},
        ],
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: true,
      );
      expect(filtered, hasLength(1));
    });

    // The QA finding: "approved" was defined three different ways. The filter
    // and the count dropped only releases with rejections, while the row badge
    // required `approved == true`. A release with `approved: false` and no
    // rejections therefore passed "Approved only", was counted as approved, and
    // still rendered an amber "Not approved" badge.
    group('one definition of approved', () {
      const unapprovedNoRejections = {
        'title': 'Unapproved but unrejected',
        'approved': false,
        'rejections': <dynamic>[],
        'customFormatScore': 10,
      };

      test('an unapproved release without rejections is not approved', () {
        expect(releaseIsApproved(unapprovedNoRejections), isFalse);
      });

      test('the filter and the count agree with the badge', () {
        final input = [
          unapprovedNoRejections,
          {
            'title': 'Approved',
            'approved': true,
            'rejections': <dynamic>[],
            'customFormatScore': 20,
          },
          {
            'title': 'Rejected',
            'approved': false,
            'rejections': <dynamic>['too big'],
            'customFormatScore': 30,
          },
        ];

        final filtered = filterAndSortReleases(
          input,
          sortType: ReleaseSortType.score,
          sortAscending: false,
          hideRejected: true,
        );

        expect(filtered, hasLength(1));
        expect(filtered.single['title'], 'Approved');
        expect(countApprovedReleases(input), 1);
        expect(countApprovedReleases(input), filtered.length);
      });

      test('a missing approved field falls back to "no rejections"', () {
        // Radarr/Sonarr v3 always send the field; tolerating its absence keeps
        // the filter from silently emptying the list on any API that does not.
        expect(
          releaseIsApproved({'title': 'X', 'rejections': <dynamic>[]}),
          isTrue,
        );
        expect(releaseIsApproved({'title': 'X'}), isTrue);
      });
    });

    test('indexer filter matches exact name', () {
      final filtered = filterAndSortReleases(
        releases,
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: false,
        selectedIndexer: 'I1',
      );
      expect(filtered, hasLength(3));
      expect(filtered.every((r) => r['indexer'] == 'I1'), isTrue);
    });

    test('indexer filter returns empty when not found', () {
      final filtered = filterAndSortReleases(
        releases,
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: false,
        selectedIndexer: 'missing',
      );
      expect(filtered, isEmpty);
    });

    test('combined filters + sort: hideRejected + indexer', () {
      final filtered = filterAndSortReleases(
        releases,
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: true,
        selectedIndexer: 'I1',
      );
      expect(filtered.map((r) => r['title']).toList(), ['Ok1', 'Ok2']);
    });
  });

  group('extractAvailableIndexers', () {
    test('unique names, null/missing -> Unknown', () {
      final indexers = extractAvailableIndexers([
        {'indexer': 'I1'},
        {'indexer': 'I2'},
        {'indexer': 'I1'},
        {'indexer': null},
        {'title': 'no indexer field'},
      ]);
      expect(indexers, {'I1', 'I2', 'Unknown'});
    });

    test('empty input returns empty set', () {
      expect(extractAvailableIndexers([]), isEmpty);
    });
  });

  group('filterAndSortReleases - query', () {
    final releases = [
      {'title': 'Movie.2024.1080p.WEB-DL'},
      {'title': 'Movie.2024.2160p.REMUX'},
      {'title': 'Other.Show.S01E01.1080p'},
    ];

    List<dynamic> filter(String query) => filterAndSortReleases(
      releases,
      sortType: ReleaseSortType.score,
      sortAscending: false,
      hideRejected: false,
      query: query,
    );

    test('matches case-insensitively', () {
      expect(filter('remux').single['title'], 'Movie.2024.2160p.REMUX');
    });

    test('requires every whitespace-separated term', () {
      expect(filter('movie 1080').single['title'], 'Movie.2024.1080p.WEB-DL');
      expect(filter('movie s01e01'), isEmpty);
    });

    test('blank queries do not filter', () {
      expect(filter('   '), hasLength(3));
    });
  });

  group('protocol helpers', () {
    final releases = [
      {'protocol': 'torrent'},
      {'protocol': 'usenet'},
      {'protocol': 'USENET'},
      {'title': 'unknown protocol'},
    ];

    test('releaseProtocolOf parses case-insensitively', () {
      expect(releaseProtocolOf(releases[0]), ReleaseProtocol.torrent);
      expect(releaseProtocolOf(releases[2]), ReleaseProtocol.usenet);
      expect(releaseProtocolOf(releases[3]), isNull);
    });

    test(
      'extractAvailableProtocols returns present protocols in enum order',
      () {
        expect(extractAvailableProtocols(releases), [
          ReleaseProtocol.usenet,
          ReleaseProtocol.torrent,
        ]);
      },
    );

    test('filters by protocol', () {
      final result = filterAndSortReleases(
        releases,
        sortType: ReleaseSortType.score,
        sortAscending: false,
        hideRejected: false,
        selectedProtocol: ReleaseProtocol.usenet,
      );
      expect(result, hasLength(2));
    });
  });

  group('rejection helpers', () {
    test('normalises string and map rejections', () {
      expect(
        releaseRejectionReasons({
          'rejections': [
            'Too big',
            {'reason': 'Wrong language'},
          ],
        }),
        ['Too big', 'Wrong language'],
      );
    });

    test('releaseIsRejected and countApprovedReleases agree', () {
      final releases = [
        {'rejections': const []},
        {
          'rejections': const ['Too big'],
        },
        <String, dynamic>{},
      ];
      expect(releaseIsRejected(releases[1]), isTrue);
      expect(releaseIsRejected(releases[2]), isFalse);
      expect(countApprovedReleases(releases), 2);
    });
  });
}

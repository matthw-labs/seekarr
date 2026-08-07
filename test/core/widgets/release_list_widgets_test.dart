import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/release_list_widgets.dart';

void main() {
  group('InfoChip', () {
    testWidgets('renders its icon and text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InfoChip(icon: Icons.dns_outlined, text: 'NZBgeek'),
          ),
        ),
      );

      expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
      expect(find.text('NZBgeek'), findsOneWidget);
    });
  });

  group('CustomFormatChip', () {
    testWidgets('renders positive scores with a plus sign', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CustomFormatChip(name: 'HDR', score: 10)),
        ),
      );

      expect(find.text('HDR'), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);
    });

    testWidgets('renders negative scores without a plus sign', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CustomFormatChip(name: 'BR-DISK', score: -5)),
        ),
      );

      expect(find.text('BR-DISK'), findsOneWidget);
      expect(find.text('-5'), findsOneWidget);
    });

    testWidgets('treats zero as a positive score', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CustomFormatChip(name: 'x265', score: 0)),
        ),
      );

      expect(find.text('+0'), findsOneWidget);
    });
  });

  group('ReleaseListItem', () {
    testWidgets('renders the title and subtitle metadata', (tester) async {
      await _pumpReleaseItem(
        tester,
        release: buildRelease(
          title: 'My.Movie.2024.1080p',
          indexer: 'NZBgeek',
          size: 1073741824,
          seeders: 42,
          quality: {
            'quality': {'name': 'Bluray-1080p'},
          },
          ageMinutes: 2880,
        ),
      );

      expect(find.text('My.Movie.2024.1080p'), findsOneWidget);
      expect(find.text('NZBgeek'), findsOneWidget);
      expect(find.text('1.00 GB'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Bluray-1080p'), findsOneWidget);
      expect(find.text('2d'), findsOneWidget);
      expect(find.text('+0'), findsOneWidget);
      expect(find.text('CF'), findsOneWidget);
    });

    testWidgets('falls back to Unknown when the title is missing', (
      tester,
    ) async {
      await _pumpReleaseItem(tester, release: buildRelease(title: null));

      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets('calls onGrab when the download button is tapped', (
      tester,
    ) async {
      var grabbed = false;

      await _pumpReleaseItem(
        tester,
        release: buildRelease(),
        onGrab: () => grabbed = true,
      );

      await tester.tap(find.byTooltip('Grab Release'));
      await tester.pump();

      expect(grabbed, isTrue);
    });

    testWidgets('uses the success tone for approved releases', (tester) async {
      await _pumpReleaseItem(
        tester,
        release: buildRelease(approved: true, rejections: const []),
      );

      expect(_grabButtonColor(tester), AppColors.success);
    });

    testWidgets('uses the warning tone for pending releases', (tester) async {
      await _pumpReleaseItem(
        tester,
        release: buildRelease(approved: false, rejections: const []),
      );

      expect(_grabButtonColor(tester), AppColors.warning);
    });

    testWidgets('shows a spinner instead of the grab button while grabbing', (
      tester,
    ) async {
      await _pumpReleaseItem(
        tester,
        release: buildRelease(),
        isGrabbing: true,
        settle: false,
      );

      expect(find.byTooltip('Grab Release'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the protocol and peer counts for torrents', (
      tester,
    ) async {
      await _pumpReleaseItem(
        tester,
        release: {
          ...buildRelease(seeders: 12),
          'protocol': 'torrent',
          'leechers': 3,
        },
      );

      expect(find.text('Torrent'), findsOneWidget);
      expect(find.text('12 / 3'), findsOneWidget);
    });

    testWidgets('shows string rejection reasons for rejected releases', (
      tester,
    ) async {
      await _pumpReleaseItem(
        tester,
        release: buildRelease(
          approved: false,
          rejections: const ['Minimum seeders not met'],
        ),
      );

      await _expandRelease(tester);

      expect(_grabButtonColor(tester), AppColors.error);
      expect(find.text('REJECTION REASONS'), findsOneWidget);
      expect(find.text('Minimum seeders not met'), findsOneWidget);
    });

    testWidgets('shows object rejection reasons for rejected releases', (
      tester,
    ) async {
      await _pumpReleaseItem(
        tester,
        release: buildRelease(
          approved: false,
          rejections: const [
            {'reason': 'Protocol not allowed'},
          ],
        ),
      );

      await _expandRelease(tester);

      expect(find.text('Protocol not allowed'), findsOneWidget);
    });

    testWidgets('shows custom formats and a score badge when expanded', (
      tester,
    ) async {
      await _pumpReleaseItem(
        tester,
        release: buildRelease(
          customFormatScore: 4,
          customFormats: const [
            {'name': 'HDR', 'score': 5},
            {'name': 'DV', 'score': -1},
          ],
        ),
      );

      await _expandRelease(tester);

      expect(find.text('CUSTOM FORMATS'), findsOneWidget);
      expect(find.text('Score: +4'), findsOneWidget);
      expect(find.text('HDR'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);
      expect(find.text('DV'), findsOneWidget);
      expect(find.text('-1'), findsOneWidget);
    });

    testWidgets('shows an empty custom format message when appropriate', (
      tester,
    ) async {
      await _pumpReleaseItem(
        tester,
        release: buildRelease(customFormats: const [], rejections: const []),
      );

      await _expandRelease(tester);

      expect(find.text('No custom format data available'), findsOneWidget);
    });

    testWidgets('does not overflow on a narrow screen with long labels', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpReleaseItem(
        tester,
        release: {
          ...buildRelease(
            title:
                'Avatar.2009.Extended.Collectors.Edition.2160p.BluRay.DV.HDR.'
                '10.bit.Encode.AV1.DTS.5.1-R and H',
            indexer: 'Treasure Maps (Prowlarr)',
            quality: {
              'quality': {'name': 'Bluray-2160p Remux'},
            },
            customFormatScore: 2500,
            rejections: const ['Italian is wanted, but found English'],
            approved: false,
          ),
          'protocol': 'usenet',
        },
      );

      expect(tester.takeException(), isNull);

      await _expandRelease(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('formats file sizes across units', (tester) async {
      await _pumpReleaseItem(tester, release: buildRelease(size: 500));
      expect(find.text('500 B'), findsOneWidget);

      // Three significant digits on every rung above bytes, from the shared
      // formatter — the row used to carry its own ladder that printed one
      // decimal at KB/MB, two at GB, and never reached TB at all.
      await _pumpReleaseItem(tester, release: buildRelease(size: 1536));
      expect(find.text('1.50 KB'), findsOneWidget);

      await _pumpReleaseItem(tester, release: buildRelease(size: 5242880));
      expect(find.text('5.00 MB'), findsOneWidget);

      await _pumpReleaseItem(
        tester,
        release: buildRelease(size: 2199023255552),
      );
      expect(find.text('2.00 TB'), findsOneWidget);
    });

    testWidgets('formats ages across minutes, hours, and days', (tester) async {
      await _pumpReleaseItem(tester, release: buildRelease(ageMinutes: 30));
      expect(find.text('30m'), findsOneWidget);

      await _pumpReleaseItem(tester, release: buildRelease(ageMinutes: 120));
      expect(find.text('2h'), findsOneWidget);

      await _pumpReleaseItem(tester, release: buildRelease(ageMinutes: 4320));
      expect(find.text('3d'), findsOneWidget);
    });
  });
}

Map<String, dynamic> buildRelease({
  String? title = 'Test Release',
  String indexer = 'NZBgeek',
  num size = 1073741824,
  num seeders = 10,
  Map<String, dynamic>? quality,
  num ageMinutes = 60,
  int customFormatScore = 0,
  List<dynamic> customFormats = const [],
  List<dynamic> rejections = const [],
  bool approved = true,
}) {
  return {
    'title': title,
    'indexer': indexer,
    'size': size,
    'seeders': seeders,
    'quality':
        quality ??
        {
          'quality': {'name': 'Bluray-1080p'},
        },
    'ageMinutes': ageMinutes,
    'customFormatScore': customFormatScore,
    'customFormats': customFormats,
    'rejections': rejections,
    'approved': approved,
  };
}

Future<void> _pumpReleaseItem(
  WidgetTester tester, {
  required Map<String, dynamic> release,
  VoidCallback onGrab = _noop,
  bool isGrabbing = false,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReleaseListItem(
            release: release,
            onGrab: onGrab,
            isGrabbing: isGrabbing,
          ),
        ),
      ),
    ),
  );
  // A busy row spins forever, so settling is opt-out.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Taps the card body (anywhere but the grab button) to expand the details.
Future<void> _expandRelease(WidgetTester tester) async {
  await tester.tap(find.byType(InkWell).first);
  await tester.pumpAndSettle();
}

Color? _grabButtonColor(WidgetTester tester) {
  return tester
      .widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Grab Release'),
          matching: find.byType(IconButton),
        ),
      )
      .color;
}

void _noop() {}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/media_detail_header_metrics.dart';
import 'package:seekarr/core/widgets/media_detail_poster_row.dart';
import 'package:seekarr/core/widgets/media_detail_slot.dart';
import 'package:seekarr/core/widgets/media_detail_view.dart';
import 'package:seekarr/core/widgets/media_poster_card.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/core/widgets/tag_chip.dart';

/// The worst realistic hero copy: a title that needs both its lines, a full
/// metadata line, and three long genre chips that wrap into multiple runs.
const _kTitle = 'The Lord of the Rings: The Fellowship of the Ring';
const _kTopPadding = 59.0;

/// Every reading size the hero has to survive, including the two iOS
/// accessibility sizes where the status badge used to be clipped away entirely.
const _kScales = [1.0, 1.3, 1.6, 2.0, 3.0];

Widget _wrap(Widget home, {required double textScale}) {
  return MaterialApp(
    theme: AppTheme.darkTheme(),
    home: home,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(top: _kTopPadding),
      ),
      child: child!,
    ),
  );
}

MediaDetailView _detailView() {
  return MediaDetailView(
    title: _kTitle,
    accent: Colors.amber,
    posterRow: const MediaDetailPosterRow(
      statusBadge: StatusBadge(
        info: MediaStatusInfo(availability: MediaAvailability.available),
      ),
      title: _kTitle,
      metadataItems: ['2001', '2h 58m', 'PG-13'],
      tags: [
        GenreChip(genre: 'Adventure'),
        GenreChip(genre: 'Fantasy'),
        GenreChip(genre: 'Action'),
      ],
      posterCard: MediaPosterCard(heroTag: 'poster_1'),
    ),
    heroFallbackIcon: Icons.movie_outlined,
    body: const MediaDetailBody(
      deck: SizedBox(height: 2000, width: double.infinity),
    ),
  );
}

Rect _headerRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(SliverPersistentHeader),
        matching: find.byType(ClipRect),
      )
      .first,
);

Rect _heroTitleRect(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(MediaDetailPosterRow),
    matching: find.text(_kTitle),
  ),
);

void main() {
  /// A phone, not the 800x600 default: the chip `Wrap` breaks into more runs at
  /// a phone measure, which is the case that overflowed the band.
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  group('expanded hero at accessibility reading sizes', () {
    for (final scale in _kScales) {
      testWidgets('keeps the status badge inside the header at ${scale}x', (
        tester,
      ) async {
        usePhoneViewport(tester);
        await tester.pumpWidget(_wrap(_detailView(), textScale: scale));
        await tester.pump();

        // No RenderFlex stripe anywhere in the hero copy.
        expect(tester.takeException(), isNull);

        final header = _headerRect(tester);
        final badge = tester.getRect(find.byType(StatusBadge));

        expect(
          badge.top,
          greaterThanOrEqualTo(header.top + _kTopPadding),
          reason:
              'the status badge collided with the safe-area inset / Dynamic '
              'Island at ${scale}x',
        );
        expect(
          badge.bottom,
          lessThanOrEqualTo(header.bottom),
          reason: 'the status badge fell out of the header band at ${scale}x',
        );
        expect(badge.height, greaterThan(0));
      });

      testWidgets('keeps the hero title inside the header at ${scale}x', (
        tester,
      ) async {
        usePhoneViewport(tester);
        await tester.pumpWidget(_wrap(_detailView(), textScale: scale));
        await tester.pump();

        final header = _headerRect(tester);
        final title = _heroTitleRect(tester);

        expect(
          title.top,
          greaterThanOrEqualTo(header.top + _kTopPadding),
          reason: 'the hero title was clipped off the top at ${scale}x',
        );
        expect(title.bottom, lessThanOrEqualTo(header.bottom));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('hero copy lays out on the band\'s own clamp, not the ambient '
        'scaler', (tester) async {
      usePhoneViewport(tester);

      Future<double> titleHeightAt(double scale) async {
        await tester.pumpWidget(_wrap(_detailView(), textScale: scale));
        await tester.pump();
        return _heroTitleRect(tester).height;
      }

      final atDefault = await titleHeightAt(1.0);
      final atCeiling = await titleHeightAt(
        MediaDetailHeaderMetrics.heroMaxScaleFactor,
      );
      final atDouble = await titleHeightAt(2.0);
      final atTriple = await titleHeightAt(3.0);

      // It follows the reading size...
      expect(atCeiling, greaterThan(atDefault));
      // ...up to the clamp the band was grown by, and no further: past it the
      // two-line title ellipsises instead of pushing the badge out of frame.
      expect(atDouble, atCeiling);
      expect(atTriple, atCeiling);
    });
  });

  testWidgets('loading skeleton clears the floating nav bar', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      _wrap(const MediaDetailLoadingView(), textScale: 1),
    );
    await tester.pump();

    final shimmerBody = find.descendant(
      of: find.byType(SliverToBoxAdapter),
      matching: find.byType(Padding),
    );
    final padding = tester
        .widget<Padding>(shimmerBody.first)
        .padding
        .resolve(TextDirection.ltr);

    // The bar floats over the skeleton exactly as it floats over the loaded
    // page: 60pt of bar plus its own insets, never a bare AppSpacing constant.
    expect(padding.bottom, greaterThan(padding.top));
    expect(padding.bottom, greaterThan(60));
  });
}

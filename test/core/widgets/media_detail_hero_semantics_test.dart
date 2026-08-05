import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/media_detail_header_metrics.dart';
import 'package:seekarr/core/widgets/media_detail_hero_summary.dart';
import 'package:seekarr/core/widgets/media_detail_poster_row.dart';
import 'package:seekarr/core/widgets/media_detail_slot.dart';
import 'package:seekarr/core/widgets/media_detail_view.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/core/widgets/tag_chip.dart';

const _kTitle = 'The Lord of the Rings: The Fellowship of the Ring';
const _kTopPadding = 59.0;

/// The collapse position where the hero hands the spoken title to the collapsed
/// bar. `MediaDetailHeroPhase.barReveal` is
/// `easeOutCubic(seg(t, 0.62, 0.92))`, and the hand-off fires at `barReveal >=
/// 0.5`; inverting `easeOutCubic` gives x = 1 - cbrt(0.5) = 0.2063, so t sits
/// here. Sampled either side because a hand-off implemented with two
/// independent thresholds would double- or un-speak the title in the gap.
const _kHandoffT = 0.62 + 0.2063 * (0.92 - 0.62);

Widget _wrap(Widget home) => MaterialApp(
  theme: AppTheme.darkTheme(),
  themeAnimationDuration: Duration.zero,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(padding: const EdgeInsets.only(top: _kTopPadding)),
      child: home,
    ),
  ),
);

MediaDetailView _detailView({Widget? posterCard}) => MediaDetailView(
  title: _kTitle,
  accent: const Color(0xFF8B5CF6),
  staggerSections: false,
  heroFallbackIcon: Icons.tv_rounded,
  posterRow: MediaDetailPosterRow(
    posterCard: posterCard ?? const SizedBox.shrink(),
    statusBadge: const StatusBadge.animated(
      info: MediaStatusInfo(availability: MediaAvailability.available),
    ),
    title: _kTitle,
    metadataItems: const ['2001', '2h 58m'],
    tags: const [GenreChip(genre: 'Fantasy')],
  ),
  body: const MediaDetailBody(
    deck: SizedBox(height: 2000, width: double.infinity),
  ),
);

/// Labels in the order assistive tech would walk them, blanks dropped.
List<String> _spokenOrder(WidgetTester tester) => tester.semantics
    .simulatedAccessibilityTraversal()
    .map((node) => node.label)
    .where((label) => label.isNotEmpty)
    .toList();

void main() {
  group('one spoken title', () {
    testWidgets('holds across the whole collapse range', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final handle = tester.ensureSemantics();

      const range =
          MediaDetailHeaderMetrics.baseExpandedHeight -
          MediaDetailHeaderMetrics.baseCollapsedHeight;

      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _wrap(
          PrimaryScrollController(controller: controller, child: _detailView()),
        ),
      );
      await tester.pump();

      for (final t in <double>[
        0,
        0.3,
        0.62,
        _kHandoffT - 0.01,
        _kHandoffT,
        _kHandoffT + 0.01,
        0.8,
        0.92,
        1.0,
      ]) {
        controller.jumpTo(t * range);
        await tester.pump();

        expect(
          find.semantics.byLabel(_kTitle),
          findsOne,
          reason:
              'the hero title and the collapsed bar title must never both be '
              'spoken, nor both silent, at t=$t',
        );
      }
      handle.dispose();
    });

    testWidgets('is a heading in both poses, so the rotor never blinks out', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final handle = tester.ensureSemantics();

      const range =
          MediaDetailHeaderMetrics.baseExpandedHeight -
          MediaDetailHeaderMetrics.baseCollapsedHeight;

      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _wrap(
          PrimaryScrollController(controller: controller, child: _detailView()),
        ),
      );
      await tester.pump();

      for (final t in <double>[0, _kHandoffT, 1.0]) {
        controller.jumpTo(t * range);
        await tester.pump();

        final headings = tester.semantics
            .simulatedAccessibilityTraversal()
            .where((node) => node.flagsCollection.isHeader)
            .map((node) => node.label)
            .toList();
        expect(
          headings,
          contains(_kTitle),
          reason: 'the page name is the page heading at t=$t',
        );
      }
      handle.dispose();
    });
  });

  group('the hero region', () {
    testWidgets('treats the poster as decoration, not a stop', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          Scaffold(
            body: MediaDetailPosterRow(
              // Stands in for `MediaPosterCard`, whose `CachedNetworkImage`
              // publishes an `image`-flagged node with an empty label. Anything
              // the poster slot has to say would land ahead of the title.
              posterCard: Semantics(
                label: 'poster artwork',
                child: const SizedBox.expand(),
              ),
              statusBadge: const StatusBadge.animated(
                info: MediaStatusInfo(
                  availability: MediaAvailability.available,
                ),
              ),
              title: _kTitle,
              metadataItems: const ['2001'],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.semantics.byLabel('poster artwork'), findsNothing);
      expect(find.semantics.byLabel(_kTitle), findsOne);
      handle.dispose();
    });

    testWidgets('announces the status, then the name, then the facts', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: MediaDetailPosterRow(
              posterCard: SizedBox.shrink(),
              statusBadge: StatusBadge.animated(
                info: MediaStatusInfo(
                  availability: MediaAvailability.available,
                ),
              ),
              title: _kTitle,
              metadataItems: ['2001', '2h 58m'],
              tags: [GenreChip(genre: 'Fantasy')],
            ),
          ),
        ),
      );
      await tester.pump();

      final order = _spokenOrder(tester);
      // Status first because it is the one thing that changes about a title the
      // user already recognises; the chips last because they are the least
      // decisive thing in the band.
      expect(order.indexOf('Available'), 0);
      expect(order.indexOf(_kTitle), 1);
      expect(
        order.indexWhere((label) => label.contains('2001')),
        greaterThan(order.indexOf(_kTitle)),
      );
      expect(
        order.indexWhere((label) => label.contains('Fantasy')),
        greaterThan(order.indexWhere((label) => label.contains('2001'))),
      );
      handle.dispose();
    });

    testWidgets('speaks the status in words, never by tone alone', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      // The one status whose tone carries information the label does not: a
      // stalled transfer is a warning, and `semanticLabel` is where that word
      // gets written down.
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: MediaDetailPosterRow(
              posterCard: SizedBox.shrink(),
              statusBadge: StatusBadge.animated(
                info: MediaStatusInfo(
                  availability: MediaAvailability.missing,
                  pipeline: MediaPipeline.stalled,
                  progress: 0.42,
                  hasWarning: true,
                ),
              ),
              title: _kTitle,
            ),
          ),
        ),
      );
      await tester.pump();

      final order = _spokenOrder(tester);
      expect(order.first, contains('Stalled'));
      expect(order.first, contains('42 percent'));
      expect(
        order.first,
        contains('warning'),
        reason: 'the amber tone is not readable; the word is',
      );
      // And the same words are painted, so a sighted user reading at 3x is not
      // relying on the amber either.
      expect(find.text('Stalled'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      handle.dispose();
    });
  });

  group('MediaDetailHeroSummary', () {
    testWidgets('drops an empty metadata line and an empty chip row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: MediaDetailHeroSummary(
              title: _kTitle,
              metadataItems: ['   ', ''],
            ),
          ),
        ),
      );

      expect(find.byType(Wrap), findsNothing);
      expect(find.text(_kTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

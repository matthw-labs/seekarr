import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/media_chip_section.dart';
import 'package:seekarr/core/widgets/media_detail_body_metrics.dart';
import 'package:seekarr/core/widgets/media_detail_figure_plate.dart';
import 'package:seekarr/core/widgets/media_detail_section_label.dart';
import 'package:seekarr/core/widgets/media_detail_sections.dart';
import 'package:seekarr/core/widgets/media_prose_section.dart';
import 'package:seekarr/core/widgets/tag_chip.dart';

const _kSonarr = Color(0xFF8B5CF6);

Widget _wrap(
  Widget child, {
  double textScale = 1.0,
  bool reduceMotion = false,
  Brightness brightness = Brightness.dark,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? AppTheme.darkTheme()
        : AppTheme.lightTheme(),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 358, child: child),
        ),
      ),
    ),
  );
}

/// Relative luminance / contrast, the WCAG way, so the label's accent treatment
/// is asserted rather than eyeballed.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('MediaDetailMetrics', () {
    test('is the screen gutter on a phone and centres on a wide window', () {
      expect(MediaDetailMetrics.gutterOf(390), AppSpacing.lg);
      expect(MediaDetailMetrics.gutterOf(720), AppSpacing.lg);
      expect(
        MediaDetailMetrics.gutterOf(1400),
        AppSpacing.lg + (1400 - MediaDetailMetrics.bodyMaxWidth) / 2,
      );
      // The column never gets wider than its measure.
      expect(
        1400 - 2 * MediaDetailMetrics.gutterOf(1400),
        MediaDetailMetrics.bodyMaxWidth - 2 * AppSpacing.lg,
      );
    });

    test('prose measure nests inside the body column', () {
      expect(
        MediaDetailMetrics.proseMaxWidth,
        lessThan(MediaDetailMetrics.bodyMaxWidth),
      );
    });
  });

  group('MediaDetailSectionLabel', () {
    testWidgets('publishes one heading node with the original-case label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MediaDetailSectionLabel(
            label: 'Episodes',
            accent: _kSonarr,
            count: '41 of 48 · 5 seasons',
          ),
        ),
      );

      // Uppercase in the eye...
      expect(find.text('EPISODES'), findsOneWidget);
      // ...original case in the ear, with the count folded into the sentence.
      expect(
        tester.getSemantics(find.byType(MediaDetailSectionLabel)),
        containsSemantics(
          label: 'Episodes, 41 of 48 · 5 seasons',
          isHeader: true,
        ),
      );
    });

    testWidgets('keeps an action reachable outside the silenced region', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(
          MediaDetailSectionLabel(
            label: 'Episodes',
            accent: _kSonarr,
            action: TextButton(
              onPressed: () => tapped++,
              child: const Text('S3 of 40'),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(TextButton)),
        containsSemantics(label: 'S3 of 40', isButton: true),
      );
      await tester.tap(find.text('S3 of 40'));
      expect(tapped, 1);
    });

    testWidgets('stacks the action under the label past 1.4x reading size', (
      tester,
    ) async {
      Widget labelWith(double scale) => _wrap(
        MediaDetailSectionLabel(
          label: 'Missing subtitles',
          accent: _kSonarr,
          action: TextButton(onPressed: () {}, child: const Text('Refresh')),
        ),
        textScale: scale,
      );

      await tester.pumpWidget(labelWith(1.0));
      final rowTop = tester.getTopLeft(find.text('Refresh')).dy;
      final rowLabelTop = tester.getTopLeft(find.text('MISSING SUBTITLES')).dy;
      // One line: the action sits beside the label, not below it.
      expect((rowTop - rowLabelTop).abs(), lessThan(24));

      await tester.pumpWidget(labelWith(2.0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('Refresh')).dy,
        greaterThan(tester.getTopLeft(find.text('MISSING SUBTITLES')).dy),
      );
      // Full width when stacked, so a trailing that wraps internally can.
      expect(tester.getSize(find.byType(TextButton)).width, greaterThan(200));
    });

    testWidgets('walks the accent to a legible tone in BOTH themes', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _wrap(
            const MediaDetailSectionLabel(label: 'Details', accent: _kSonarr),
            brightness: brightness,
          ),
        );

        final context = tester.element(find.text('DETAILS'));
        final surface = Theme.of(context).colorScheme.surface;
        final style = tester.widget<Text>(find.text('DETAILS')).style!;

        expect(
          _contrast(style.color!, surface),
          greaterThanOrEqualTo(4.5),
          reason:
              'an 11pt eyebrow is not large text; raw Sonarr violet on '
              'surface-light measures about 3.96:1',
        );
      }
    });

    testWidgets('draws no pipe, no fill and no border', (tester) async {
      await tester.pumpWidget(
        _wrap(const MediaDetailSectionLabel(label: 'Scores', accent: _kSonarr)),
      );

      // The three arbitrary 3x16pt accent pipes are gone: five identical
      // kickers read as a rhythm, three pipes read as tick marks.
      expect(
        find.descendant(
          of: find.byType(MediaDetailSectionLabel),
          matching: find.byType(DecoratedBox),
        ),
        findsNothing,
      );
    });
  });

  group('MediaProseSection', () {
    const longText =
        'A computer hacker learns from mysterious rebels about the true nature '
        'of his reality and his role in the war against its controllers. '
        'Neo meets Morpheus, takes the red pill, and wakes up in a vat of pink '
        'goo aboard the Nebuchadnezzar, where the crew explain that the world '
        'he knew was a shared simulation maintained by machines farming human '
        'bioelectricity. He begins to train, and to doubt.';

    testWidgets('clamps, expands and collapses in place', (tester) async {
      await tester.pumpWidget(_wrap(const MediaProseSection(text: longText)));

      final clampedHeight = tester.getSize(find.text(longText)).height;
      expect(find.text('Show more'), findsOneWidget);

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      expect(find.text('Show less'), findsOneWidget);
      expect(
        tester.getSize(find.text(longText)).height,
        greaterThan(clampedHeight),
      );

      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('offers no toggle when the clamp does not bite', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const MediaProseSection(text: 'One short line.')),
      );

      expect(find.text('One short line.'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('renders nothing at all for blank prose', (tester) async {
      await tester.pumpWidget(_wrap(const MediaProseSection(text: '   ')));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('removes the animator under Reduce Motion, never zeroes it', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const MediaProseSection(text: longText)));
      expect(find.byType(AnimatedSize), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const MediaProseSection(text: longText), reduceMotion: true),
      );
      // A zero-duration AnimatedSize re-dirties inside its own performLayout
      // and the framework asserts, so the fix is removal.
      expect(find.byType(AnimatedSize), findsNothing);

      await tester.tap(find.text('Show more'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('holds prose to its own measure inside a wide column', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: SizedBox(
              width: 1000,
              child: MediaProseSection(text: longText),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.text(longText)).width,
        lessThanOrEqualTo(MediaDetailMetrics.proseMaxWidth),
      );
    });
  });

  group('MediaChipSection', () {
    testWidgets('neutral genres get no colour at all', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MediaChipSection.neutral(values: ['Action', 'Sci-Fi', '  ']),
        ),
      );

      expect(find.byType(GenreChip), findsNWidgets(2));
      expect(find.byType(TagChip), findsNothing);
    });

    testWidgets('accented tags resolve their label through onTint', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _wrap(
            const MediaChipSection.accented(
              values: ['anime'],
              accent: _kSonarr,
            ),
            brightness: brightness,
          ),
        );

        final chip = tester.widget<TagChip>(find.byType(TagChip));
        final context = tester.element(find.byType(TagChip));
        final surface = Theme.of(context).colorScheme.surface;
        final composite = Color.alphaBlend(
          chip.color!.withValues(alpha: 0.12),
          surface,
        );

        expect(
          _contrast(chip.color!, composite),
          greaterThanOrEqualTo(4.5),
          reason: 'a tag label sits on a 12% tint of its own colour',
        );
      }
    });

    testWidgets('renders nothing when every value is blank', (tester) async {
      await tester.pumpWidget(
        _wrap(const MediaChipSection.neutral(values: ['', '  '])),
      );
      expect(find.byType(Wrap), findsNothing);
    });
  });

  group('MediaDetailFigurePlate', () {
    testWidgets('carries the figure and stays silent', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 82,
            height: 123,
            child: MediaDetailFigurePlate(
              value: '12',
              label: 'missing',
              accent: _kSonarr,
            ),
          ),
        ),
      );

      expect(find.text('12'), findsOneWidget);
      expect(find.text('MISSING'), findsOneWidget);
      // The deck says it in words one region below; a reader does not need it
      // twice.
      expect(find.semantics.byLabel('12'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives the hero band clamp at 1.6x in an 82x123 box', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 82,
            height: 123,
            child: MediaDetailFigurePlate(
              value: '148',
              label: 'missing',
              accent: _kSonarr,
            ),
          ),
          textScale: 1.6,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('148'), findsOneWidget);
      expect(find.text('MISSING'), findsOneWidget);
    });
  });

  group('MediaDetailUnavailableSection', () {
    testWidgets('is headless — the slot owns the heading', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MediaDetailUnavailableSection(
            message: 'Radarr is tracking this but no file has been imported.',
          ),
        ),
      );

      expect(find.textContaining('no file has been imported'), findsOneWidget);
      expect(find.byType(MediaDetailSectionLabel), findsNothing);
    });
  });
}

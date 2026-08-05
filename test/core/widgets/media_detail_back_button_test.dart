import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/header_action_row.dart';
import 'package:seekarr/core/widgets/media_detail_back_button.dart';
import 'package:seekarr/core/widgets/media_detail_header_metrics.dart';

/// The two extremes of photographic artwork. Every real backdrop composites
/// somewhere between them, and the plate's guarantee is monotonic in the
/// backdrop's luminance, so clearing both ends clears everything in between.
const _kBrightArtwork = Color(0xFFFFFFFF);
const _kDarkArtwork = Color(0xFF000000);

/// WCAG 2.x AA for text. Deliberately stricter than 1.4.11's 3:1 floor for a
/// graphical object: the chevron is a thin stroke over unknown photography, and
/// the reported defect ("washes out over a lit wall") measured 3.35:1 — i.e. it
/// was *passing* 1.4.11 and still unusable.
const _kMinRatio = 4.5;

double _channel(double v) {
  final s = v.clamp(0.0, 1.0);
  return s <= 0.04045
      ? s / 12.92
      : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Straight-alpha source-over, which is what the plate does to the artwork.
Color _composite(Color top, Color bottom) {
  final a = top.a;
  return Color.from(
    alpha: 1,
    red: top.r * a + bottom.r * (1 - a),
    green: top.g * a + bottom.g * (1 - a),
    blue: top.b * a + bottom.b * (1 - a),
  );
}

ColorScheme _scheme(Brightness brightness) =>
    (brightness == Brightness.dark
            ? AppTheme.darkTheme()
            : AppTheme.lightTheme())
        .colorScheme;

const _kProbeKey = ValueKey('back_button_probe');
const _kProbeSize = 60.0;
const _kProbeRatio = 3.0;

Widget _probeApp({
  required Brightness brightness,
  required Color artwork,
  required double reveal,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? AppTheme.darkTheme()
        : AppTheme.lightTheme(),
    // `MaterialApp` wraps its child in an `AnimatedTheme`, so re-pumping with a
    // different theme inside one test *interpolates* for 200ms — a single
    // `pump()` then samples pixels from the previous theme and the assertion
    // silently measures the wrong scheme.
    themeAnimationDuration: Duration.zero,
    home: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: _kProbeKey,
        child: SizedBox.square(
          dimension: _kProbeSize,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: artwork)),
              Center(
                child: MediaDetailBackButton(reveal: reveal, onBack: () {}),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The real painted contrast inside the plate: the extreme luminances found in a
/// square inscribed well within the disc, so the artwork outside its rounded
/// edge cannot be mistaken for either the glyph or the plate.
///
/// Measuring painted extremes rather than the analytic pair is deliberately the
/// stricter test — antialiasing on a 22pt chevron can only pull the two closer
/// together than the colours the widget asked for.
Future<double> _paintedContrast(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_kProbeKey),
  );
  late ByteData pixels;
  late int width;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _kProbeRatio);
    width = image.width;
    pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
  });

  // 20pt square centred on the 36pt plate: comfortably inside the disc, and it
  // straddles the 22pt chevron so both glyph and plate pixels are present.
  const inset = (_kProbeSize - 20) / 2;
  final lo = (inset * _kProbeRatio).round();
  final hi = ((_kProbeSize - inset) * _kProbeRatio).round();

  Color? lightest;
  Color? darkest;
  for (var y = lo; y < hi; y++) {
    for (var x = lo; x < hi; x++) {
      final i = ((y * width) + x) * 4;
      final c = Color.fromARGB(
        255,
        pixels.getUint8(i),
        pixels.getUint8(i + 1),
        pixels.getUint8(i + 2),
      );
      if (lightest == null || _luminance(c) > _luminance(lightest)) {
        lightest = c;
      }
      if (darkest == null || _luminance(c) < _luminance(darkest)) darkest = c;
    }
  }
  return _contrast(lightest!, darkest!);
}

void main() {
  group('contrast over arbitrary artwork', () {
    testWidgets('reads over a synthetic bright and dark backdrop, as painted', (
      tester,
    ) async {
      // The table in the widget's doc comment, held to reality. Antialiasing on
      // the chevron means these are the *painted* ratios, not the analytic pair.
      const expected = <String, double>{
        'dark/bright': 4.98,
        'dark/dark': 17.99,
        'light/bright': 16.71,
        'light/dark': 6.08,
      };

      for (final brightness in Brightness.values) {
        for (final artwork in <Color>[_kBrightArtwork, _kDarkArtwork]) {
          // Torn down between cases on purpose. Re-pumping a differently-themed
          // tree over the same elements leaves `ButtonStyleButton`'s own
          // `animationDuration` mid-flight, and one `pump()` then samples a
          // light plate carrying the *previous* theme's glyph — which measured
          // 1.05:1 and looked like a real failure.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            _probeApp(brightness: brightness, artwork: artwork, reveal: 0),
          );
          await tester.pump();
          final ratio = await _paintedContrast(tester);
          expect(
            ratio,
            greaterThanOrEqualTo(_kMinRatio),
            reason:
                'back button glyph vs plate measured $ratio:1 in $brightness '
                'over $artwork',
          );
          expect(
            ratio,
            closeTo(
              expected['${brightness == Brightness.dark ? 'dark' : 'light'}/'
                  '${artwork == _kBrightArtwork ? 'bright' : 'dark'}']!,
              0.05,
            ),
            reason: 'restate the doc table if this moves',
          );
        }
      }
    });

    test('never dips below AA anywhere the plate owns the ground', () {
      // The old pose inverted (white glyph → onSurface glyph) and so had to
      // cross 1:1 somewhere; the measured floor mid-morph was 2.07:1. Sweep the
      // whole plate-owned range against both artwork extremes, plus mid-grey and
      // artwork that happens to match the plate's own tone.
      for (final brightness in Brightness.values) {
        final scheme = _scheme(brightness);
        final glyph = MediaDetailBackButton.glyphColorFor(scheme);
        for (final artwork in <Color>[
          _kBrightArtwork,
          _kDarkArtwork,
          const Color(0xFF808080),
          scheme.surface,
        ]) {
          for (var step = 0; step <= 41; step++) {
            final reveal = step / 41 * MediaDetailBackButton.plateReleaseStart;
            final plate = MediaDetailBackButton.plateColorFor(scheme, reveal);
            final ratio = _contrast(glyph, _composite(plate, artwork));
            expect(
              ratio,
              greaterThanOrEqualTo(_kMinRatio),
              reason:
                  '$brightness, artwork $artwork, reveal $reveal → $ratio:1',
            );
          }
        }
      }
    });

    test('the plate alone carries the worst case, with no scrim credit', () {
      // The numbers quoted in the widget's doc comment. Locked so a future
      // change to `plateAlpha` has to restate them.
      const cases = <(Brightness, Color, double)>[
        (Brightness.dark, _kBrightArtwork, 4.9),
        (Brightness.dark, _kDarkArtwork, 17.0),
        (Brightness.light, _kDarkArtwork, 6.0),
        (Brightness.light, _kBrightArtwork, 16.0),
      ];
      for (final (brightness, artwork, floor) in cases) {
        final scheme = _scheme(brightness);
        final ratio = _contrast(
          MediaDetailBackButton.glyphColorFor(scheme),
          _composite(MediaDetailBackButton.plateColorFor(scheme, 0), artwork),
        );
        expect(ratio, greaterThanOrEqualTo(floor), reason: '$brightness');
      }
    });
  });

  group('the two poses', () {
    test('never invert, in either theme', () {
      // The reason there is no dip to find: an inverting foreground has to pass
      // through equal luminance. This is the invariant that forbids one.
      for (final brightness in Brightness.values) {
        final scheme = _scheme(brightness);
        expect(
          MediaDetailBackButton.glyphColorFor(scheme),
          scheme.onSurface,
          reason: 'the glyph is the theme pair, at every reveal',
        );
      }
    });

    test('hold the plate, then hand the ground to the chrome', () {
      final scheme = _scheme(Brightness.dark);
      double alphaAt(double reveal) =>
          MediaDetailBackButton.plateColorFor(scheme, reveal).a;

      expect(alphaAt(0), closeTo(MediaDetailBackButton.plateAlpha, 0.001));
      expect(
        alphaAt(MediaDetailBackButton.plateReleaseStart),
        closeTo(MediaDetailBackButton.plateAlpha, 0.001),
        reason: 'full strength right up to the release point',
      );
      expect(alphaAt(1), 0, reason: 'pose 1 is bare chrome, as documented');

      var previous = double.infinity;
      for (var step = 0; step <= 50; step++) {
        final alpha = alphaAt(step / 50);
        expect(
          alpha,
          lessThanOrEqualTo(previous + 0.001),
          reason: 'the plate only ever releases, never re-thickens',
        );
        previous = alpha;
      }
    });

    test('release only once the hero scrim can take over the ground', () {
      // `plateReleaseStart` is derived from the hero's own phase curves, and the
      // hero is frozen — so this locks the coupling instead of the number. If
      // `barReveal`'s interval or `scrimDepth`'s ramp is ever retuned, this fails
      // and forces the release point to be re-derived rather than left stale.
      var releaseT = 1.0;
      for (var i = 0; i <= 1000; i++) {
        final t = i / 1000;
        if (MediaDetailHeroPhase(t: t).barReveal >=
            MediaDetailBackButton.plateReleaseStart) {
          releaseT = t;
          break;
        }
      }
      expect(
        MediaDetailHeroPhase(t: releaseT).scrimDepth,
        greaterThanOrEqualTo(0.9),
        reason:
            'the plate may only start releasing where the scrim is deep enough '
            'to be the ground itself (t=$releaseT)',
      );
    });

    test('take every colour from the scheme', () {
      // This file used to be the codebase's documented `Colors.black` /
      // `Colors.white` exception. It no longer needs one.
      for (final brightness in Brightness.values) {
        final scheme = _scheme(brightness);
        final plate = MediaDetailBackButton.plateColorFor(scheme, 0);
        expect(plate.r, scheme.surface.r);
        expect(plate.g, scheme.surface.g);
        expect(plate.b, scheme.surface.b);
      }
    });
  });

  group('target', () {
    testWidgets('is a real 44pt at both poses, not just a 44pt box', (
      tester,
    ) async {
      for (final reveal in <double>[0, 1]) {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: MediaDetailBackButton(
                  reveal: reveal,
                  onBack: () => taps++,
                ),
              ),
            ),
          ),
        );

        final rect = tester.getRect(find.byType(MediaDetailBackButton));
        expect(rect.size, const Size.square(MediaDetailBackButton.targetSize));

        // The regression: a tight inner `SizedBox(36)` capped the padded hit box
        // at 36, so the outer 8pt of the documented target was decoration and a
        // near-miss tap did nothing.
        await tester.tapAt(rect.topLeft + const Offset(1, 1));
        await tester.pump();
        await tester.tapAt(rect.bottomRight - const Offset(1, 1));
        await tester.pump();
        expect(
          taps,
          2,
          reason: 'corners of the 44pt target must hit, reveal $reveal',
        );
      }
    });

    testWidgets('lands the plate on the content gutter at its host inset', (
      tester,
    ) async {
      // Hosted exactly the way the hero and the placeholder pages host it.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: MediaDetailBackButton.gutterAlignedLeftInset,
                  child: MediaDetailBackButton(reveal: 0),
                ),
              ],
            ),
          ),
        ),
      );

      final plate = tester.getRect(
        find
            .descendant(
              of: find.byType(IconButton),
              matching: find.byType(Material),
            )
            .first,
      );

      // The plate stays a painted 36 even though the target is 48: a 48pt disc
      // over artwork reads as a button competing with the poster.
      expect(plate.size, const Size.square(MediaDetailBackButton.discSize));

      // The invariant that actually matters, measured rather than arithmetic:
      // the plate's leading edge sits on the same column as the hero copy and
      // every body slot. Asserted through the derived inset, so a future change
      // to either size has to keep the alignment or fail here.
      expect(plate.left, AppSpacing.lg);
      expect(
        MediaDetailBackButton.gutterAlignedLeftInset +
            (MediaDetailBackButton.targetSize -
                    MediaDetailBackButton.discSize) /
                2,
        AppSpacing.lg,
      );
    });

    testWidgets('clears the larger of the two platform target floors', (
      tester,
    ) async {
      // iOS documents 44pt and Android 48dp. The app used to carry both answers
      // for one floor — 44 here, 48 on the action band — so the shared numbers
      // are asserted equal rather than merely adequate.
      expect(
        MediaDetailBackButton.targetSize,
        greaterThanOrEqualTo(48),
        reason: 'must clear Android 48dp, not just iOS 44pt',
      );
      expect(
        MediaDetailBackButton.targetSize,
        HeaderActionRow.buttonHeight,
        reason:
            'one floor, one constant: the detail chrome has one target size',
      );
    });

    testWidgets('publishes a named, tappable button at every pose', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      for (final reveal in <double>[0, 0.5, 1]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme(),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: MediaDetailBackButton(reveal: reveal, onBack: () {}),
              ),
            ),
          ),
        );
        await tester.pump();

        // The pose is a paint change only: the control keeps its button role and
        // its localised name whether it is floating on artwork or sitting in the
        // bar, so assistive tech never sees it appear or disappear mid-scroll.
        expect(
          tester.getSemantics(find.byType(IconButton)),
          containsSemantics(
            isButton: true,
            isEnabled: true,
            hasTapAction: true,
            tooltip: const DefaultMaterialLocalizations().backButtonTooltip,
          ),
          reason: 'reveal $reveal',
        );
      }
      handle.dispose();
    });
  });
}

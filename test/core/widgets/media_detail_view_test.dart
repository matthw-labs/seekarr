import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/ambient_background.dart';
import 'package:seekarr/core/widgets/media_detail_body_metrics.dart';
import 'package:seekarr/core/widgets/media_detail_header_metrics.dart';
import 'package:seekarr/core/widgets/media_detail_poster_row.dart';
import 'package:seekarr/core/widgets/media_detail_section_label.dart';
import 'package:seekarr/core/widgets/media_detail_slot.dart';
import 'package:seekarr/core/widgets/media_detail_view.dart';
import 'package:seekarr/core/widgets/media_poster_card.dart';

const _kTitle = 'The Matrix';
const _kTopPadding = 59.0;

Widget _wrap(Widget home, {double textScale = 1.0, bool reduceMotion = false}) {
  return MaterialApp(
    home: home,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(top: _kTopPadding),
        disableAnimations: reduceMotion,
      ),
      child: child!,
    ),
  );
}

/// A body with only the required region, which is the shape every hero test
/// wants: one tall filler so the page scrolls.
MediaDetailBody _fillerBody() =>
    const MediaDetailBody(deck: SizedBox(height: 2000, width: double.infinity));

MediaDetailView _detailView({
  String heroTag = 'poster_1',
  MediaDetailBody? body,
  Future<void> Function()? onRefresh,
  bool staggerSections = true,
}) {
  return MediaDetailView(
    title: _kTitle,
    accent: Colors.amber,
    heroFallbackIcon: Icons.movie_outlined,
    onRefresh: onRefresh,
    staggerSections: staggerSections,
    posterRow: MediaDetailPosterRow(
      title: _kTitle,
      metadataItems: const ['2h 16m', '1999'],
      posterCard: MediaPosterCard(heroTag: heroTag),
    ),
    body: body ?? _fillerBody(),
  );
}

double _headerHeight(WidgetTester tester) => tester
    .getSize(
      find
          .descendant(
            of: find.byType(SliverPersistentHeader),
            matching: find.byType(ClipRect),
          )
          .first,
    )
    .height;

/// A distinguishable row type so the laziness test can count what was built
/// without matching every `SizedBox` in the tree.
class _LazyRow extends StatelessWidget {
  const _LazyRow();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 56);
}

void main() {
  testWidgets('renders expanded hero with a hidden collapsed bar at rest', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_detailView()));
    await tester.pump();

    // Title appears in the hero summary and (invisibly) in the collapsed bar.
    expect(find.text(_kTitle), findsNWidgets(2));
    // The header child is laid out at the full expanded extent.
    expect(
      _headerHeight(tester),
      _kTopPadding + MediaDetailHeaderMetrics.baseExpandedHeight,
    );
  });

  testWidgets('speaks exactly one title, scrolled and unscrolled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_detailView()));
    await tester.pump();

    expect(find.semantics.byLabel(_kTitle), findsOne);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();

    expect(find.semantics.byLabel(_kTitle), findsOne);
    handle.dispose();
  });

  testWidgets('back button stays tappable at both scroll extremes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(CupertinoPageRoute<void>(builder: (_) => _detailView())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    final backTooltip = const DefaultMaterialLocalizations().backButtonTooltip;

    // Expanded: back pops.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(backTooltip));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);

    // Collapsed: back still pops.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(backTooltip));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero flight lands in and returns from the pinned header', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: GestureDetector(
                onTap: () => Navigator.of(
                  context,
                ).push(CupertinoPageRoute<void>(builder: (_) => _detailView())),
                child: const SizedBox(
                  width: 130,
                  height: 195,
                  child: MediaPosterCard(heroTag: 'poster_1'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Outbound flight into the header.
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150)); // mid-flight
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text(_kTitle), findsNWidgets(2));

    // Return flight while the header is collapsed: the poster is clipped, not
    // opacity-zero, so the flight must not throw and must land on the source.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final backTooltip = const DefaultMaterialLocalizations().backButtonTooltip;
    await tester.tap(find.byTooltip(backTooltip));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150)); // mid-flight
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text(_kTitle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a 2.0x reading size without exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_detailView(), textScale: 2.0));
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(
      _headerHeight(tester),
      greaterThan(_kTopPadding + MediaDetailHeaderMetrics.baseExpandedHeight),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('disables overscroll stretch under Reduce Motion', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_detailView(), reduceMotion: true));
    await tester.pump();

    final header = tester.widget<SliverPersistentHeader>(
      find.byType(SliverPersistentHeader),
    );
    expect(header.delegate.stretchConfiguration, isNull);

    await tester.pumpWidget(_wrap(_detailView()));
    await tester.pump();
    final animatedHeader = tester.widget<SliverPersistentHeader>(
      find.byType(SliverPersistentHeader),
    );
    expect(animatedHeader.delegate.stretchConfiguration, isNotNull);
  });

  testWidgets('loading and loaded headers share identical geometry', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const MediaDetailLoadingView()));
    await tester.pump();
    final loadingHeight = _headerHeight(tester);

    await tester.pumpWidget(_wrap(_detailView()));
    await tester.pump();
    final loadedHeight = _headerHeight(tester);

    expect(loadingHeight, loadedHeight);
  });

  group('ambient wiring', () {
    // The highest-risk line in the whole composition change: get the Material
    // wrong and the ambient move is a silent no-op that still looks right in
    // dark theme, because an opaque `surface` fill and a glow over `surface`
    // are nearly the same colour there.
    testWidgets('publishes an AmbientBackground carrying the page accent', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_detailView()));
      await tester.pump();

      final ambient = find.ancestor(
        of: find.byType(CustomScrollView),
        matching: find.byType(AmbientBackground),
      );
      expect(ambient, findsOneWidget);
      expect(tester.widget<AmbientBackground>(ambient).accent, Colors.amber);
    });

    testWidgets('keeps its Material transparent so the glow is not occluded', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_detailView()));
      await tester.pump();

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AmbientBackground),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.type, MaterialType.transparency);
      expect(material.color, isNull);
    });

    testWidgets('lights the loading skeleton from the same accent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const MediaDetailLoadingView(accent: Colors.amber)),
      );
      await tester.pump();

      final ambient = find.ancestor(
        of: find.byType(CustomScrollView),
        matching: find.byType(AmbientBackground),
      );
      expect(ambient, findsOneWidget);
      expect(tester.widget<AmbientBackground>(ambient).accent, Colors.amber);

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AmbientBackground),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.type, MaterialType.transparency);
    });
  });

  group('region order', () {
    /// A body with every region filled, each holding one short labelled box, so
    /// all six land inside one tall viewport and are therefore all built.
    MediaDetailBody sixRegions() => const MediaDetailBody(
      deck: SizedBox(key: ValueKey('deck'), height: 40, width: double.infinity),
      readout: SizedBox(
        key: ValueKey('readout'),
        height: 40,
        width: double.infinity,
      ),
      operate: [
        MediaDetailSlot.box(
          label: 'Episodes',
          count: '41 of 48',
          child: SizedBox(height: 40, width: double.infinity),
        ),
      ],
      synopsis: [
        MediaDetailSlot.box(
          label: 'Overview',
          child: SizedBox(height: 40, width: double.infinity),
        ),
      ],
      reference: [
        MediaDetailSlot.box(
          label: 'Details',
          child: SizedBox(height: 40, width: double.infinity),
        ),
        MediaDetailSlot.box(
          label: 'Genres',
          child: SizedBox(height: 40, width: double.infinity),
        ),
      ],
      related: [
        MediaDetailSlot.box(
          label: 'Cast',
          child: SizedBox(height: 40, width: double.infinity),
        ),
      ],
    );

    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('emits deck, readout, then the four slot regions in order', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        _wrap(_detailView(body: sixRegions(), staggerSections: false)),
      );
      await tester.pump();

      final labels = tester
          .widgetList<MediaDetailSectionLabel>(
            find.byType(MediaDetailSectionLabel),
          )
          .map((label) => label.label)
          .toList();

      // Canonical order, and a variant may omit a region but never reorder one.
      expect(labels, ['Episodes', 'Overview', 'Details', 'Genres', 'Cast']);

      // The two unlabelled regions come first, in their own order.
      final deckY = tester.getTopLeft(find.byKey(const ValueKey('deck'))).dy;
      final readoutY = tester
          .getTopLeft(find.byKey(const ValueKey('readout')))
          .dy;
      final firstLabelY = tester.getTopLeft(find.text('EPISODES')).dy;
      expect(deckY, lessThan(readoutY));
      expect(readoutY, lessThan(firstLabelY));
    });

    testWidgets('renders the manifest before the synopsis, laid out', (
      tester,
    ) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        _wrap(_detailView(body: sixRegions(), staggerSections: false)),
      );
      await tester.pump();

      // The one ordering regression this whole API exists to make impossible:
      // a lazy child list used to be emitted after every content section, so
      // Lidarr's albums landed below its genre chips.
      expect(
        tester.getTopLeft(find.text('EPISODES')).dy,
        lessThan(tester.getTopLeft(find.text('GENRES')).dy),
      );
      expect(
        tester.getTopLeft(find.text('OVERVIEW')).dy,
        lessThan(tester.getTopLeft(find.text('DETAILS')).dy),
      );
    });

    testWidgets(
      'a lazy sliver region lands above later regions and stays lazy',
      (tester) async {
        useTallViewport(tester);
        await tester.pumpWidget(
          _wrap(
            _detailView(
              staggerSections: false,
              body: MediaDetailBody(
                deck: const SizedBox(height: 40, width: double.infinity),
                operate: [
                  MediaDetailSlot.lazy(
                    label: 'Episodes',
                    sliver: SliverList.builder(
                      itemCount: 250,
                      itemBuilder: (context, index) => const _LazyRow(),
                    ),
                  ),
                ],
                reference: const [
                  MediaDetailSlot.box(
                    label: 'Genres',
                    child: SizedBox(height: 40, width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        // A 250-episode season builds the rows on screen, not 250 of them.
        final built = tester.widgetList<_LazyRow>(find.byType(_LazyRow)).length;
        expect(built, greaterThan(0));
        expect(
          built,
          lessThan(60),
          reason:
              'the lazy slot was flattened into a Column and lost its laziness',
        );

        // And it is still region 3: `Genres` is below it, off screen.
        expect(find.text('EPISODES'), findsOneWidget);
        expect(find.text('GENRES'), findsNothing);
      },
    );
  });

  group('gutter', () {
    testWidgets('insets a box slot by the resolved gutter', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          _detailView(
            staggerSections: false,
            body: const MediaDetailBody(
              deck: SizedBox(
                key: ValueKey('deck'),
                height: 40,
                width: double.infinity,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final deck = tester.getRect(find.byKey(const ValueKey('deck')));
      expect(deck.left, MediaDetailMetrics.gutterOf(390));
      expect(deck.right, 390 - MediaDetailMetrics.gutterOf(390));
    });

    testWidgets('centres the column on a wide macOS window', (tester) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          _detailView(
            staggerSections: false,
            body: const MediaDetailBody(
              deck: SizedBox(
                key: ValueKey('deck'),
                height: 40,
                width: double.infinity,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final deck = tester.getRect(find.byKey(const ValueKey('deck')));
      expect(deck.width, MediaDetailMetrics.bodyMaxWidth - 2 * AppSpacing.lg);
      expect(deck.center.dx, closeTo(700, 0.01));
    });

    testWidgets('lands the readout rail on the column at both widths', (
      tester,
    ) async {
      // The readout is built above this view and cannot see the resolved
      // gutter, so it arrives pre-padded with the screen gutter and the spine
      // adds the centring surplus. A rail starting at the window edge while
      // every other section is centred is the failure this locks out.
      Widget withReadout() => _wrap(
        _detailView(
          staggerSections: false,
          body: const MediaDetailBody(
            deck: SizedBox(height: 40, width: double.infinity),
            readout: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SizedBox(
                key: ValueKey('cell'),
                height: 40,
                width: double.infinity,
              ),
            ),
          ),
        ),
      );

      tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(withReadout());
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('cell'))).left,
        MediaDetailMetrics.gutterOf(390),
      );

      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(withReadout());
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('cell'))).left,
        MediaDetailMetrics.gutterOf(1400),
      );
    });

    testWidgets('hands the gutter to a rail so it can bleed past the column', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      EdgeInsets? captured;
      await tester.pumpWidget(
        _wrap(
          _detailView(
            staggerSections: false,
            body: MediaDetailBody(
              deck: const SizedBox(height: 40, width: double.infinity),
              related: [
                MediaDetailSlot.rail(
                  label: 'Cast',
                  builder: (padding) {
                    captured = padding;
                    return const SizedBox(height: 40, width: double.infinity);
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(captured?.left, MediaDetailMetrics.gutterOf(390));
      expect(captured?.right, MediaDetailMetrics.gutterOf(390));
    });
  });

  group('header seam', () {
    // The hero's lower edge, measured rather than eyeballed.
    //
    // `AppGradients.heroScrim` bottoms out on *opaque* `surface`, which occludes
    // the page's ambient accent radials while the body one row below shows them.
    // Before the seam band, that put a hard single-row step across the full
    // width at every collapse position, in both themes — summed |dRGB| of 15 at
    // rest, 31 mid-collapse and 37 pinned (390x844, violet accent, x=195). An
    // opaque strip cutting the room's gradient is exactly what
    // `AmbientBackground` + `GlassSurface` exist to prevent.
    const seamTolerance = 10;

    const probeKey = ValueKey('seam_probe');

    /// No copy and no bar title on purpose: the hero's summary block slides
    /// *down* out of the band as it collapses and is hard-clipped at the same
    /// edge, so leaving it in would measure that (separate, hero-frozen) effect
    /// instead of the scrim/ambient boundary this band owns.
    Widget seamApp(Brightness brightness, ScrollController controller) =>
        MaterialApp(
          theme: brightness == Brightness.dark
              ? AppTheme.darkTheme()
              : AppTheme.lightTheme(),
          home: RepaintBoundary(
            key: probeKey,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(padding: const EdgeInsets.only(top: _kTopPadding)),
                child: PrimaryScrollController(
                  controller: controller,
                  child: MediaDetailView(
                    accent: const Color(0xFF8B5CF6),
                    heroFallbackIcon: Icons.tv_rounded,
                    staggerSections: false,
                    posterRow: const MediaDetailPosterRow(
                      posterCard: SizedBox.shrink(),
                    ),
                    body: const MediaDetailBody(
                      deck: SizedBox(height: 2000, width: double.infinity),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('meets the body on a gradient across the whole collapse range', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const maxExtent =
          _kTopPadding + MediaDetailHeaderMetrics.baseExpandedHeight;
      const minExtent =
          _kTopPadding + MediaDetailHeaderMetrics.baseCollapsedHeight;
      const range = maxExtent - minExtent;

      for (final brightness in Brightness.values) {
        // Endpoints are not enough: the boundary travels up the screen into the
        // hotter part of the glow as the header shrinks, so the step grew with
        // `t`. Sample across the range.
        for (final t in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
          final controller = ScrollController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(seamApp(brightness, controller));
          await tester.pump();
          controller.jumpTo(t * range);
          await tester.pump();

          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(probeKey),
          );
          late ByteData pixels;
          late int width;
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            width = image.width;
            pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            image.dispose();
          });

          final edge = (maxExtent - t * range).round();
          int channel(int x, int y, int c) =>
              pixels.getUint8(((y * width + x) * 4) + c);
          int step(int x, int y) => List.generate(
            3,
            (c) => (channel(x, y, c) - channel(x, y - 1, c)).abs(),
          ).reduce((a, b) => a + b);

          // Two boundaries, not one. The band fixes the hero/body seam by
          // clipping the art group a gutter short, which *introduces* a second
          // boundary at the top of the band — so a fix that only moved the step
          // 16pt up the screen would pass on the first pair and fail here.
          final rows = <int>[
            edge - AppSpacing.lg.round(), // art group → band
            edge - AppSpacing.lg.round() + 1,
            edge, // band → body
            edge + 1,
          ];

          // Columns clear of the 82pt poster slot and the back button.
          for (final x in <int>[195, 300, 370]) {
            for (final y in rows) {
              expect(
                step(x, y),
                lessThan(seamTolerance),
                reason:
                    'hard edge at the hero/body boundary: $brightness, t=$t, '
                    'x=$x, row $y',
              );
            }
          }

          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });
  });

  group('pull to refresh', () {
    testWidgets('is absent without onRefresh', (tester) async {
      await tester.pumpWidget(_wrap(_detailView()));
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsNothing);
      // Deliberately no assertion that `physics` is null: `ScrollView`'s own
      // constructor substitutes `AlwaysScrollableScrollPhysics` for any primary
      // vertical scroll view, so the field is never null here and asserting it
      // would only be testing the framework.
    });

    testWidgets('wires the indicator below the pinned bar when given', (
      tester,
    ) async {
      var refreshed = 0;
      await tester.pumpWidget(
        _wrap(
          _detailView(
            onRefresh: () async {
              refreshed++;
            },
          ),
        ),
      );
      await tester.pump();

      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      expect(indicator.color, Colors.amber);
      // Below the collapsed bar, so the spinner and the hero's overscroll
      // stretch are not two claimants on one gesture.
      expect(indicator.edgeOffset, greaterThan(_kTopPadding));
      expect(
        tester.widget<CustomScrollView>(find.byType(CustomScrollView)).physics,
        isA<AlwaysScrollableScrollPhysics>(),
      );

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 320),
        1000,
      );
      await tester.pumpAndSettle();
      expect(refreshed, 1);
    });
  });
}

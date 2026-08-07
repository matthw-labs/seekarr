import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/media_detail_slot.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/presentation/arr_media_extras_provider.dart';
import 'package:cupola/features/discover/presentation/discover_detail_view_model.dart';
import 'package:cupola/features/discover/presentation/widgets/arr_media_extras_section.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_cast_list.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_collection_banner.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_watch_providers.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Dynamic Type coverage for the Discover/extras widgets.
///
/// Every one of these pairs a fixed-size visual (an avatar, a provider logo, a
/// backdrop band) with one or two lines of label, which is the shape that clips
/// at an accessibility reading size. The assertions are deliberately not
/// goldens: a `RenderFlex`/`RenderBox` overflow is reported as an exception, so
/// `takeException()` returning null *is* the "nothing clipped" assertion, and
/// the height comparisons prove the box grew with the text and stopped at the
/// clamp instead of growing forever.
void main() {
  // No image paths anywhere in these fixtures on purpose: it keeps
  // `CachedNetworkImage` (and the network) out of the widget tree.
  const cast = <DiscoverCastMember>[
    (
      id: 1,
      name: 'Mena Massoud',
      character: 'Genie / Mariner / Merchant',
      profilePath: null,
    ),
    (
      id: 2,
      name: 'Naomi Scott',
      character: 'Princess Jasmine',
      profilePath: null,
    ),
    (id: 0, name: 'Marwan Kenzari', character: 'Jafar', profilePath: null),
  ];

  const providers = WatchProviderRegion(
    iso3166: 'US',
    flatrate: [
      WatchProviderEntry(id: 8, name: 'Netflix basic with Ads'),
      WatchProviderEntry(id: 9, name: 'Amazon Prime Video'),
    ],
  );

  const collection = CollectionInfo(
    id: 86311,
    name: 'The Lord of the Rings Collection',
  );

  /// A phone-sized host at [textScale]. The `MediaQuery` goes *inside*
  /// `MaterialApp`, which installs one of its own from the view.
  Widget host({required double textScale, required Widget child}) {
    return MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
  }

  void usePhoneView(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('DiscoverCastList', () {
    Future<double> pumpRail(WidgetTester tester, double scale) async {
      usePhoneView(tester);
      await tester.pumpWidget(
        host(
          textScale: scale,
          child: const DiscoverCastList(cast: cast),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Mena Massoud'), findsOneWidget);
      expect(find.text('Genie / Mariner / Merchant'), findsOneWidget);
      return tester.getSize(find.byType(ListView)).height;
    }

    testWidgets('rail grows with the reading size and never clips', (
      tester,
    ) async {
      final base = await pumpRail(tester, 1.0);
      final double2x = await pumpRail(tester, 2.0);
      final double3x = await pumpRail(tester, 3.0);

      expect(double2x, greaterThan(base));
      // Compact chrome clamps at 1.6x and ellipsises past it, so 3x must not
      // grow the rail any further than 2x already did.
      expect(double3x, double2x);
    });

    testWidgets('labels fit inside the grown rail at 2x and 3x', (
      tester,
    ) async {
      for (final scale in [2.0, 3.0]) {
        final railHeight = await pumpRail(tester, scale);
        final tileHeight = tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Mena Massoud'),
                    matching: find.byType(Column),
                  )
                  .first,
            )
            .height;
        expect(
          tileHeight,
          lessThanOrEqualTo(railHeight),
          reason: 'cast tile overflowed its rail at ${scale}x',
        );
      }
    });
  });

  group('DiscoverWatchProviders', () {
    Future<double> pumpProviders(WidgetTester tester, double scale) async {
      usePhoneView(tester);
      await tester.pumpWidget(
        host(
          textScale: scale,
          child: const DiscoverWatchProviders(
            providers: providers,
            region: 'US',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Netflix basic with Ads'), findsOneWidget);
      return tester.getSize(find.byType(ListView).first).height;
    }

    testWidgets('pills grow with the reading size and never clip', (
      tester,
    ) async {
      final base = await pumpProviders(tester, 1.0);
      final double2x = await pumpProviders(tester, 2.0);
      final double3x = await pumpProviders(tester, 3.0);

      expect(double2x, greaterThan(base));
      expect(double3x, double2x);
    });

    testWidgets('pill is a stadium, not a hand-computed half-height', (
      tester,
    ) async {
      await pumpProviders(tester, 2.0);

      final pill = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Netflix basic with Ads'),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = pill.decoration as BoxDecoration;

      expect(decoration.borderRadius, AppRadius.borderRadiusFull);
      // The pill grew past its old 34pt, so a hand-computed half-height would
      // no longer be half of anything.
      expect(tester.getSize(find.byWidget(pill)).height, greaterThan(34));
    });
  });

  group('DiscoverCollectionBanner', () {
    Future<double> pumpBanner(WidgetTester tester, double scale) async {
      usePhoneView(tester);
      await tester.pumpWidget(
        host(
          textScale: scale,
          child: const DiscoverCollectionBanner(collection: collection),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('Part of The Lord of the Rings Collection'),
        findsOneWidget,
      );
      return tester
          .getSize(
            find
                .ancestor(
                  of: find.byType(Stack),
                  matching: find.byType(SizedBox),
                )
                .first,
          )
          .height;
    }

    testWidgets('banner grows with the reading size and never clips', (
      tester,
    ) async {
      final base = await pumpBanner(tester, 1.0);
      final double2x = await pumpBanner(tester, 2.0);
      final double3x = await pumpBanner(tester, 3.0);

      expect(double2x, greaterThan(base));
      expect(double3x, double2x);
    });

    testWidgets('caption sits on a themed gradient scrim, not a black wash', (
      tester,
    ) async {
      await pumpBanner(tester, 1.0);
      final colorScheme = AppTheme.darkTheme().colorScheme;

      final gradients = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.gradient)
          .whereType<LinearGradient>()
          .toList();

      expect(gradients, isNotEmpty);
      expect(
        gradients.any(
          (g) => g.colors.any(
            (c) => c.withValues(alpha: 1) == colorScheme.surfaceContainerHigh,
          ),
        ),
        isTrue,
        reason: 'scrim should be built from a surface token',
      );

      final caption = tester.widget<Text>(
        find.text('Part of The Lord of the Rings Collection'),
      );
      expect(caption.style?.color, colorScheme.onSurface);
      expect(caption.maxLines, 2);
    });
  });

  group('arrMediaExtrasSlots', () {
    /// Resolves the slot list and renders each slot's own content.
    ///
    /// The spine draws the headings, so the labels are asserted on the returned
    /// slots rather than found as text: that is the contract this composition
    /// exists to restore, and rendering a slot's `box`/`railBuilder` here keeps
    /// the Dynamic Type coverage the old single-widget host had.
    Future<List<MediaDetailSlot>> pumpSlots(
      WidgetTester tester,
      double scale, {
      required ArrMediaExtras? extras,
    }) async {
      usePhoneView(tester);
      // Tear the previous tree down first. Re-pumping a differently-overridden
      // `ProviderScope` reuses the element and keeps the old container, so a
      // second case in the same test reads the first case's data.
      await tester.pumpWidget(const SizedBox.shrink());
      var slots = const <MediaDetailSlot>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            arrMediaExtrasProvider.overrideWith((ref, key) async => extras),
          ],
          child: host(
            textScale: scale,
            child: Consumer(
              builder: (context, ref, _) {
                slots = arrMediaExtrasSlots(
                  ref,
                  tmdbId: 1,
                  mediaType: 'movie',
                  accent: ServiceKey.radarr.accent,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final slot in slots)
                      slot.box ??
                          slot.railBuilder!(
                            const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                            ),
                          ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      return slots;
    }

    testWidgets('cast + collection render without clipping at 2x and 3x', (
      tester,
    ) async {
      for (final scale in [2.0, 3.0]) {
        final slots = await pumpSlots(
          tester,
          scale,
          extras: (cast: cast, collection: collection),
        );
        expect(find.text('Mena Massoud'), findsOneWidget);
        expect(
          find.text('Part of The Lord of the Rings Collection'),
          findsOneWidget,
        );
        // Sentence case, because the spine uppercases for the eye and hands the
        // string through unchanged to `Semantics(label:)`.
        expect(slots.map((s) => s.label), ['Cast', 'Collection']);
      }
    });

    testWidgets('the cast rail takes the resolved gutter, the banner a box', (
      tester,
    ) async {
      final slots = await pumpSlots(
        tester,
        1.0,
        extras: (cast: cast, collection: collection),
      );

      // `.rail` so the first face aligns to the content column while the row
      // bleeds past it; `.box` would inset both ends and crop the rail.
      expect(slots.first.railBuilder, isNotNull);
      expect(slots.first.box, isNull);
      expect(slots.last.box, isNotNull);
      expect(slots.last.railBuilder, isNull);
    });

    testWidgets('a title with no cast and no collection spends no slot', (
      tester,
    ) async {
      final slots = await pumpSlots(
        tester,
        1.0,
        extras: (cast: <DiscoverCastMember>[], collection: null),
      );

      // Omitted, not empty: a labelled slot with nothing in it would leave an
      // accent heading over 24pt of air on every -arr page.
      expect(slots, isEmpty);
    });

    testWidgets('only the region that has data is labelled', (tester) async {
      final castOnly = await pumpSlots(
        tester,
        1.0,
        extras: (cast: cast, collection: null),
      );
      expect(castOnly.map((s) => s.label), ['Cast']);

      final collectionOnly = await pumpSlots(
        tester,
        1.0,
        extras: (cast: <DiscoverCastMember>[], collection: collection),
      );
      expect(collectionOnly.map((s) => s.label), ['Collection']);
    });

    testWidgets('Connect Seerr is one unlabelled slot lit by the host accent', (
      tester,
    ) async {
      final slots = await pumpSlots(tester, 1.0, extras: null);

      // Unlabelled: it is a prompt about a missing integration, not a region of
      // this title's record.
      expect(slots.single.label, isNull);
      expect(find.text('Connect'), findsOneWidget);

      // The card's subject is Seerr but the page is Radarr's, and one screen
      // gets one accent — this used to paint `AppColors.seerr` on an amber page.
      final tile = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(Icons.people_alt_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (tile.decoration as BoxDecoration).color,
        ServiceKey.radarr.accent.withValues(alpha: 0.14),
      );
    });

    testWidgets('Connect Seerr card stacks its action at large reading sizes', (
      tester,
    ) async {
      await pumpSlots(tester, 1.0, extras: null);
      final inlineWidth = tester.getSize(find.byType(FilledButton)).width;

      await pumpSlots(tester, 3.0, extras: null);
      expect(find.text('Cast & collections'), findsOneWidget);
      expect(
        find.text('Connect Seerr to see cast, collections and more.'),
        findsOneWidget,
      );
      final stackedWidth = tester.getSize(find.byType(FilledButton)).width;

      // Stacked, the action owns the full card width instead of squeezing the
      // copy beside it into a column narrower than its longest word.
      expect(stackedWidth, greaterThan(inlineWidth));
    });

    testWidgets('the card never pads itself — the spine owns the gutter', (
      tester,
    ) async {
      await pumpSlots(tester, 1.0, extras: null);

      // A slot child that insets itself compounds with the spine's gutter and
      // sits 32pt in on a page where every other region sits at 16.
      final card = find.byType(AppCard);
      expect(tester.getTopLeft(card).dx, 0);
      expect(tester.getSize(card).width, 390);
    });
  });
}

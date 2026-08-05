import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/services/domain/recently_added.dart';
import 'package:seekarr/features/services/domain/service_signal.dart';
import 'package:seekarr/features/services/domain/service_summary.dart';
import 'package:seekarr/features/services/domain/services_semantics.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/service_matrix_collapse_provider.dart';
import 'package:seekarr/features/services/presentation/services_alert_band.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/services/presentation/services_screen.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

/// How many services the more-services hint has left to offer, derived rather
/// than written down.
///
/// [_providerOverrides] configures four, so the remainder tracks the registry.
/// This was a literal — "Set up 9 more services", asserted in eight places — and
/// it rotted the moment the Stream domain took `ServiceKey` from thirteen
/// entries to fifteen. Deriving it means the next service to land changes this
/// file not at all, and the strings come from the same
/// [servicesUnconfiguredCellLabel] the widget calls, so a copy change cannot
/// pass here and fail on screen.
final int _unconfiguredServiceCount = ServiceKey.values.length - 4;
final String _moreServicesLabel = servicesUnconfiguredCellLabel(
  count: _unconfiguredServiceCount,
);
final String _dismissMoreServicesTooltip = servicesDismissMoreServicesLabel(
  count: _unconfiguredServiceCount,
);

void main() {
  testWidgets('renders the stack matrix and every region in order', (
    tester,
  ) async {
    await _pumpServices(tester);
    await _pumpDashboard(tester);

    expect(find.text('Services'), findsOneWidget);

    // Domain bands, not a sideways scroller.
    expect(find.text('MEDIA'), findsOneWidget);
    for (final title in ['Seerr', 'Radarr', 'Sonarr', 'Lidarr']) {
      expect(find.text(title), findsWidgets);
    }

    // The matrix opens folded, and a folded card paints no figure at all —
    // just the name and a connection dot. What survives the fold is the band
    // header's rollup: one attention figure (the first among its services) and
    // the down count, so a closed band never swallows its news entirely.
    // Radarr's "12 missing" is second in line and stays covered until the
    // band opens.
    expect(
      find.textContaining('3 pending', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('1 down', findRichText: true), findsOneWidget);
    expect(find.textContaining('missing', findRichText: true), findsNothing);

    // Reachability on a folded card is a coloured dot, not a state word —
    // there is no tier left on a 36pt row to paint "Offline" on. It is still
    // never colour alone: the dot is reinforcement over `serviceSummaryProvider`
    // and the same fact is in the alert band and in the spoken value.
    expect(find.text('Offline'), findsNothing);
    expect(find.text('MISSING'), findsNothing);
    expect(find.text('ONLINE'), findsNothing);

    // Nine of thirteen unconfigured, offered once rather than as nine dimmed
    // cells — and named with the verb, since a bare count reads as a truncated
    // list rather than as somewhere to go.
    expect(find.text(_moreServicesLabel), findsOneWidget);
  });

  testWidgets('an expanded card paints the figure, the host and the state', (
    tester,
  ) async {
    // What compact drops. Covered separately from the default render above
    // because the matrix opens folded and none of this paints there.
    await _pumpServices(tester, expandedDomains: const ['media']);
    await _pumpDashboard(tester);

    expect(find.textContaining('3 pending', findRichText: true), findsWidgets);
    expect(find.textContaining('12 missing', findRichText: true), findsWidgets);
    expect(find.text('radarr.local:7878'), findsOneWidget);

    // Set in plain body, not the eyebrow. One tracked uppercase overline per
    // cell across a thirteen-cell grid is the "eyebrow everywhere" noise
    // DESIGN.md's Eyebrow Rule exists to prevent.
    expect(find.text('MISSING'), findsNothing);

    // Reachability is a word, never colour alone, on the expanded card.
    // 'Online' is not printed: a live figure can only have come from a service
    // that answered, and the old card's 'ONLINE' next to a green dot said the
    // same thing twice.
    expect(find.text('Offline'), findsWidgets);
    expect(find.text('ONLINE'), findsNothing);
  });

  testWidgets('the matrix never scrolls sideways', (tester) async {
    await _pumpServices(tester);
    await _pumpDashboard(tester);

    // The Recently Added rail is still a horizontal scroller — that is what a
    // browse rail is for. The matrix must not be one, so the only horizontal
    // scrollable on screen must not contain a matrix cell.
    final horizontal = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    );

    for (final scroller in horizontal.evaluate()) {
      expect(
        find.descendant(
          of: find.byWidget(scroller.widget),
          matching: find.byKey(const ValueKey('service-matrix-cell-radarr')),
        ),
        findsNothing,
      );
    }
  });

  group('alert band', () {
    testWidgets('names the offenders and offers one retry', (tester) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      // Lidarr is the only configured-but-unreachable service in the fixture.
      expect(find.text("Lidarr isn't answering"), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('services-alert-band'))),
        containsSemantics(label: "Lidarr isn't answering"),
      );
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    });

    testWidgets('is absent entirely when the whole stack answers', (
      tester,
    ) async {
      await _pumpServices(
        tester,
        summaryBuilder: (ref, service) async => _summary(service, online: true),
      );
      await _pumpDashboard(tester);

      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
      expect(find.textContaining("isn't answering"), findsNothing);
    });

    testWidgets('stays quiet while summaries are still loading', (
      tester,
    ) async {
      // A band that appears during the first second of every cold open is a
      // band that cried wolf. The old grid had the matching bug in reverse: it
      // fabricated an offline summary while checking, so every card flashed a
      // red border before a single request came back.
      // Expanded, because "Checking" is a word the expanded card paints — the
      // compact card carries it as an amber dot instead, which this test
      // cannot assert on by text.
      await _pumpServices(
        tester,
        summaryBuilder: (ref, service) =>
            Future.delayed(const Duration(seconds: 5), () => _summary(service)),
        expandedDomains: const ['media'],
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
      // Checking is its own state, and it says so.
      expect(find.text('Checking'), findsWidgets);
      expect(find.text('Offline'), findsNothing);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('can be acknowledged, and stays acknowledged', (tester) async {
      // A notice you cannot silence about a box you knowingly left down is a
      // permanent banner. Dismissing is scoped to the outage, not to the notice.
      await _pumpServices(tester);
      await _pumpDashboard(tester);
      expect(find.text("Lidarr isn't answering"), findsOneWidget);

      await tester.tap(find.byTooltip("Dismiss: Lidarr isn't answering"));
      await _pumpDashboard(tester);

      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
    });
  });

  group('acknowledging an outage', () {
    // Unit-level, because the interesting behaviour is the *scope* of a
    // dismissal over time, and driving three sequential outage states through
    // a widget fixture would test the fixture.
    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('an acknowledgement is spent when the service recovers', () {
      // So the next failure is news again. Persisting it, or keeping it after
      // recovery, is how a notice about a genuinely broken box goes unsaid.
      final c = container();
      final notifier = c.read(dismissedOutagesProvider.notifier);

      notifier.dismiss([ServiceKey.lidarr]);
      expect(c.read(dismissedOutagesProvider), {ServiceKey.lidarr});

      notifier.retainOnly(const {});
      expect(c.read(dismissedOutagesProvider), isEmpty);
    });

    test('it covers the outage it was given for, not the whole band', () {
      // Dismissing "Lidarr isn't answering" says nothing about Sonarr, so a
      // later Sonarr failure is still unacknowledged and still raises the band.
      final c = container();
      final notifier = c.read(dismissedOutagesProvider.notifier);

      notifier.dismiss([ServiceKey.lidarr]);
      notifier.retainOnly({ServiceKey.lidarr, ServiceKey.sonarr});

      expect(c.read(dismissedOutagesProvider), {ServiceKey.lidarr});
    });
  });

  group('folding a domain band', () {
    testWidgets('a folded card is one line: the name and a connection dot', (
      tester,
    ) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      // Folded is the default now, and folded is still a card — but the
      // shortest form this app has: no figure, no host, just what the
      // service is called and whether it is answering. That is a deliberate
      // narrowing from the first compact card, which carried the same live
      // figure the expanded card does and only fit two to a row for it.
      expect(
        find.byKey(const ValueKey('service-matrix-cell-radarr')),
        findsOneWidget,
      );
      expect(find.text('Radarr'), findsWidgets);
      expect(find.textContaining('missing', findRichText: true), findsNothing);
      expect(find.text('radarr.local:7878'), findsNothing);
      expect(find.text('Offline'), findsNothing);

      // The connection dot itself: green under Radarr (online), the
      // surface's error tone under Lidarr (offline) — the same three-state
      // reachability the expanded card spells out as a word, carried by
      // colour where a 32pt row has no room for a sentence.
      expect(
        _dotColorIn(tester, 'service-matrix-cell-radarr'),
        AppColors.success,
      );
      expect(
        _dotColorIn(tester, 'service-matrix-cell-lidarr'),
        Theme.of(tester.element(find.byType(ServicesScreen))).colorScheme.error,
      );
    });

    testWidgets('expanding adds the host', (tester) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      await tester.tap(find.text('MEDIA'));
      await _pumpFold(tester);

      expect(find.text('radarr.local:7878'), findsOneWidget);
      expect(
        find.textContaining('12 missing', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('the header carries its state, its size and its rollup', (
      tester,
    ) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      // Folded, the header speaks the band's rollup too — the figure and the
      // down count its cards can no longer paint. Seerr's "3 pending" is the
      // first attention signal in the band; Lidarr is the one service down.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Media')),
        containsSemantics(
          label: 'Media',
          value: '4 services, 3 pending, 1 down',
          isButton: true,
          isExpanded: false,
        ),
      );

      await tester.tap(find.text('MEDIA'));
      await _pumpFold(tester);

      // Open, the rollup hands off to the cards and the value drops back to
      // the count — the expanded cells announce their own figures, so saying
      // them twice would be noise.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Media')),
        containsSemantics(
          label: 'Media',
          value: '4 services',
          isButton: true,
          isExpanded: true,
        ),
      );
    });

    testWidgets('a stored expansion arrives open', (tester) async {
      // Persisted, not per-visit: a fold that springs back on every cold open is
      // a control you press once and never trust again.
      SharedPreferences.setMockInitialValues({
        'services_expanded_domains': ['media'],
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._providerOverrides(),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(home: ServicesScreen()),
        ),
      );
      await _pumpDashboard(tester);

      expect(find.text('radarr.local:7878'), findsOneWidget);
    });

    testWidgets('everything is folded by default', (tester) async {
      // The inverse of what shipped before. A folded band is no longer a hidden
      // band, so the hub can open short and let the user pull open the third of
      // the stack they actually watch.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._providerOverrides(),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(home: ServicesScreen()),
        ),
      );
      await _pumpDashboard(tester);

      expect(find.text('MEDIA'), findsOneWidget);
      expect(find.text('radarr.local:7878'), findsNothing);
    });

    testWidgets('a stale collapse list from the old key is ignored', (
      tester,
    ) async {
      // The polarity flipped. Reading the old set would fold open exactly the
      // bands the user had shut, which is worse than starting from the default.
      SharedPreferences.setMockInitialValues({
        'services_collapsed_domains': ['media'],
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._providerOverrides(),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(home: ServicesScreen()),
        ),
      );
      await _pumpDashboard(tester);

      expect(find.text('radarr.local:7878'), findsNothing);
    });
  });

  group('the fold demo', () {
    // The matrix opens folded, so nothing on screen says the cards get
    // taller. Once per launch, the first band demonstrates it in reverse: it
    // mounts open and folds itself shut with the real close animation, so
    // the expanded state is shown existing and the default is what remains.
    Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    Widget app(
      SharedPreferences prefs, {
      bool reduceMotion = false,
      bool demoPlayed = false,
      bool show = true,
    }) => ProviderScope(
      overrides: [
        ..._providerOverrides(demoPlayed: demoPlayed),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          home: show ? const ServicesScreen() : const SizedBox.shrink(),
        ),
      ),
    );

    // How much room the Media band occupies, measured from its own header
    // down to the next thing on the page.
    double bandExtent(WidgetTester tester) =>
        tester.getTopLeft(find.text(_moreServicesLabel)).dy -
        tester.getTopLeft(find.text('MEDIA')).dy;

    Future<void> pumpFor(WidgetTester tester, Duration total) async {
      const step = Duration(milliseconds: 50);
      for (var spent = Duration.zero; spent < total; spent += step) {
        await tester.pump(step);
      }
    }

    // Past the demo entirely: the 1100ms hold plus the close animation.
    Future<void> pumpPastDemo(WidgetTester tester) =>
        pumpFor(tester, const Duration(milliseconds: 1800));

    testWidgets('starts open and folds itself shut', (tester) async {
      final prefs = await prefsWith({});

      await tester.pumpWidget(app(prefs));
      await _pumpDashboard(tester);
      final held = bandExtent(tester);

      await pumpPastDemo(tester);
      final folded = bandExtent(tester);

      expect(
        held,
        greaterThan(folded),
        reason:
            'the band should mount at its expanded size and settle folded — '
            'the demo is the real close animation, not a partial growth',
      );
    });

    testWidgets('plays once per launch, not once per landing', (tester) async {
      final prefs = await prefsWith({});

      await tester.pumpWidget(app(prefs));
      await _pumpDashboard(tester);
      await pumpPastDemo(tester);
      final folded = bandExtent(tester);

      // Leave the tab and come back: the screen remounts under the same
      // ProviderScope, exactly as the ShellRoute remounts it in the app.
      await tester.pumpWidget(app(prefs, show: false));
      await tester.pumpWidget(app(prefs));
      await _pumpDashboard(tester);

      expect(
        bandExtent(tester),
        folded,
        reason: 'a second landing in the same launch starts settled',
      );
      await pumpFor(tester, const Duration(milliseconds: 700));
      expect(bandExtent(tester), folded);
    });

    testWidgets('a rebuild mid-demo does not restart it', (tester) async {
      // The guard is on the mount, not the lifetime: a pull-to-refresh or a
      // summary arriving must not rewind the fold.
      final prefs = await prefsWith({});

      await tester.pumpWidget(app(prefs));
      await _pumpDashboard(tester);
      await pumpPastDemo(tester);
      final settled = bandExtent(tester);

      await tester.pumpWidget(app(prefs));
      await pumpFor(tester, const Duration(milliseconds: 700));
      expect(bandExtent(tester), settled);
    });

    testWidgets('the first touch folds it early', (tester) async {
      // A control still moving while the user reaches for it is worse than
      // one that never moved: any touch in the band ends the hold and folds
      // now.
      final prefs = await prefsWith({});

      await tester.pumpWidget(app(prefs));
      await _pumpDashboard(tester);
      final held = bandExtent(tester);

      // Well inside the 1100ms hold. The touch lands on the header, and its
      // tap must NOT toggle the persisted state — pointer-down only ends the
      // demo. Use a bare pointer down/up away from any control.
      await pumpFor(tester, const Duration(milliseconds: 200));
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('service-matrix-cell-radarr')),
        ),
      );
      await gesture.cancel();

      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(
        bandExtent(tester),
        lessThan(held),
        reason: 'a touch during the hold starts the fold immediately',
      );
    });

    testWidgets('does not play under Reduce Motion', (tester) async {
      // Degrading to an instant state rather than a slower animation is the
      // Reduce Motion Rule, and a teaching animation is decoration by
      // definition — it carries nothing the layout does not already say.
      final prefs = await prefsWith({});

      await tester.pumpWidget(app(prefs, reduceMotion: true));
      await _pumpDashboard(tester);
      final folded = bandExtent(tester);
      await pumpFor(tester, const Duration(milliseconds: 700));

      expect(bandExtent(tester), folded);
    });

    testWidgets('does not play on a band that is already open', (tester) async {
      // Nothing to demonstrate: the band is open, and folding it shut would
      // discard the user's own persisted choice for a demonstration.
      final prefs = await prefsWith({
        'services_expanded_domains': ['media'],
      });

      await tester.pumpWidget(app(prefs));
      await _pumpDashboard(tester);
      final open = bandExtent(tester);
      await pumpFor(tester, const Duration(milliseconds: 1800));

      expect(bandExtent(tester), open);
    });

    testWidgets('does not play when it already played this launch', (
      tester,
    ) async {
      final prefs = await prefsWith({});

      await tester.pumpWidget(app(prefs, demoPlayed: true));
      await _pumpDashboard(tester);
      final folded = bandExtent(tester);
      await pumpFor(tester, const Duration(milliseconds: 700));

      expect(bandExtent(tester), folded);
    });
  });

  group('the more-services hint', () {
    testWidgets('dismisses, and stays dismissed', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Widget app() => ProviderScope(
        overrides: [
          ..._providerOverrides(),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: ServicesScreen()),
      );

      await tester.pumpWidget(app());
      await _pumpDashboard(tester);
      expect(find.text(_moreServicesLabel), findsOneWidget);

      // By tooltip, which is the button's own accessible name — the semantics
      // node it produces is not the tappable widget.
      await tester.tap(find.byTooltip(_dismissMoreServicesTooltip));
      await _pumpFold(tester);
      expect(find.text(_moreServicesLabel), findsNothing);

      // Persisted, not per-visit. A nudge you have to decline once per launch
      // is not a nudge.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app());
      await _pumpDashboard(tester);
      expect(find.text(_moreServicesLabel), findsNothing);
    });

    testWidgets('comes back if the registry grows past the dismissed count', (
      tester,
    ) async {
      // Dismissing said "not these nine". A release that adds a fourteenth
      // service is a different statement, and worth one line to make once.
      SharedPreferences.setMockInitialValues({
        'services_more_services_dismissed_at': 8,
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._providerOverrides(),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MaterialApp(home: ServicesScreen()),
        ),
      );
      await _pumpDashboard(tester);

      expect(find.text(_moreServicesLabel), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('a matrix cell is one labelled button, not four fragments', (
      tester,
    ) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('service-matrix-cell-radarr')),
        ),
        containsSemantics(
          label: 'Radarr',
          // Reachability, then the live signal phrased for the ear rather than
          // in the cell's visual "12 MISSING" order, then the host.
          value: 'Online, Missing 12, radarr.local:7878',
          isButton: true,
          hasTapAction: true,
        ),
      );

      // Unreachable: no signal to report, so the value stops at the state.
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('service-matrix-cell-lidarr')),
        ),
        containsSemantics(
          label: 'Lidarr',
          value: 'Offline, lidarr.local:8686',
          isButton: true,
        ),
      );

      // The metric word is a fragment of the composed value above, never a stop
      // of its own.
      expect(find.semantics.byValue('missing'), findsNothing);
    });

    testWidgets('the more-services hint is two separate controls', (
      tester,
    ) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      // Navigating and dismissing sit on one line and do opposite things, so
      // they have to be two nodes with two names. A single row labelled "Set up
      // 9 more services" with an unnamed × inside it is a coin flip.
      expect(
        tester.getSemantics(find.bySemanticsLabel(_moreServicesLabel)),
        containsSemantics(
          label: _moreServicesLabel,
          isButton: true,
          hasTapAction: true,
        ),
      );
      // `byTooltip`, which is how the rest of the suite asserts on icon-only
      // buttons: the tooltip is this button's accessible name.
      expect(find.byTooltip(_dismissMoreServicesTooltip), findsOneWidget);
    });

    testWidgets('a download row announces progress with the row', (
      tester,
    ) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      await _scrollTo(tester, find.text('Furiosa'));

      expect(
        find.semantics.byLabel('Furiosa'),
        containsSemantics(
          value: '75% downloaded, Movie, Furiosa.2024.2160p.WEB-DL-GROUP',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(find.text('75%'), findsOneWidget);
      expect(find.semantics.byLabel('75%'), findsNothing);
    });
  });

  group('Requests region', () {
    testWidgets('sorts pending first and attaches the decisions to it', (
      tester,
    ) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      await _scrollTo(tester, find.text('Requests'));

      // The header counts what is waiting, over the whole set rather than the
      // visible slice.
      expect(find.text('1 PENDING'), findsOneWidget);

      // 'A Quiet Place' is `pendingApproval` whose media is already available,
      // so `displayStatus` reads "Available". Keying the actionable set off
      // that would drop exactly this row — see `isAwaitingApproval`.
      expect(
        find.byKey(const ValueKey('services-pending-request-1')),
        findsOneWidget,
      );

      // Both decisions are reachable inside the row and each names its media,
      // because five pending rows would otherwise offer five identical
      // "Approve" buttons.
      expect(find.byTooltip('Approve A Quiet Place'), findsOneWidget);
      expect(find.byTooltip('Decline A Quiet Place'), findsOneWidget);

      // And the row itself is still one labelled button that says it is pending
      // rather than echoing displayStatus.
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('services-pending-request-1')),
        ),
        containsSemantics(
          label: 'A Quiet Place',
          value: 'Movie, requested by sarah, Pending approval',
          isButton: true,
        ),
      );
    });

    testWidgets('resolved requests stay visible alongside pending ones', (
      tester,
    ) async {
      // The whole reason this is one region and not two: a pending request must
      // not hide the recent ones.
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      await _scrollTo(tester, find.text('Requests'));

      expect(find.text('A Quiet Place'), findsOneWidget);
      expect(find.text('Past Lives'), findsOneWidget);
    });

    testWidgets('drops the badge and the actions when nothing is pending', (
      tester,
    ) async {
      // A user with auto-approvals never sees the pending half, and must not be
      // shown an empty region or a control to dismiss.
      await _pumpServices(
        tester,
        requestsBuilder: (ref) async => const [_resolvedRequest],
      );
      await _pumpDashboard(tester);

      await _scrollTo(tester, find.text('Requests'));

      expect(find.text('Past Lives'), findsOneWidget);
      // The header badge specifically. Not `textContaining('PENDING')`: Seerr's
      // matrix cell legitimately carries a PENDING eyebrow on its live line, and
      // matching that would make this pass or fail for the wrong reason.
      expect(find.text('1 PENDING'), findsNothing);
      expect(
        find.byKey(const ValueKey('services-pending-request-2')),
        findsNothing,
      );
      expect(find.byTooltip('Approve Past Lives'), findsNothing);
      expect(find.text('No requests yet'), findsNothing);
    });
  });

  group('Recently Added', () {
    testWidgets('is one rail across services, newest first', (tester) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      await _scrollTo(tester, find.text('Recently Added'));

      // Provider order is honoured by the section; the sort itself is unit
      // tested. What matters here is that one rail carries all three services.
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('The Boys'), findsOneWidget);
      expect(find.text('Aphex Twin'), findsOneWidget);

      // The two rails this replaced no longer exist.
      expect(find.text('Recently Added · Movies'), findsNothing);
      expect(find.text('Recently Added · Series'), findsNothing);
    });

    testWidgets('speaks which library each item came from', (tester) async {
      // On a single-service rail the accent dot stays silent, because the header
      // named the service. Here it varies per tile and is the only carrier of
      // that fact, so it has to be spoken.
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      await _scrollTo(tester, find.text('Recently Added'));

      expect(
        find.semantics.byLabel('Dune'),
        containsSemantics(value: 'Radarr, 2021', isButton: true),
      );
      expect(
        find.semantics.byLabel('Aphex Twin'),
        containsSemantics(value: 'Lidarr, 4 albums', isButton: true),
      );
    });
  });

  testWidgets('Trending is gone from the hub', (tester) async {
    await _pumpServices(tester);
    await _pumpDashboard(tester);

    expect(find.text('Trending'), findsNothing);
  });

  testWidgets('the download region reports an empty queue without alarm', (
    tester,
  ) async {
    await _pumpServices(
      tester,
      queueBuilder: (ref) async => const <ServiceQueueItem>[],
    );
    await _pumpDashboard(tester);

    // One word for one thing: the region was headed with the "In Flight"
    // metaphor while its own empty copy and its row semantics both said
    // "downloading".
    await _scrollTo(tester, find.text('Downloading'));
    expect(find.text('In Flight'), findsNothing);

    // Lidarr is a configured download source that is not answering, so the empty
    // region says so rather than claiming the queue is empty. This is the case
    // the old single-service `attributeEmptyTo` could not express: a merged
    // region had to stay silent, and "Nothing downloading" for an unreachable
    // client sends the user hunting for missing media.
    expect(find.text("Lidarr isn't answering"), findsWidgets);
  });

  testWidgets('an empty queue whose sources all answer names the queue', (
    tester,
  ) async {
    await _pumpServices(
      tester,
      queueBuilder: (ref) async => const <ServiceQueueItem>[],
      summaryBuilder: (ref, service) async => _summary(service, online: true),
    );
    await _pumpDashboard(tester);

    await _scrollTo(tester, find.text('Downloading'));
    // Not "Nothing downloading", which only repeats the header.
    expect(find.text('The queue is empty'), findsOneWidget);
  });

  group('both themes and reading sizes', () {
    testWidgets('the matrix survives an accessibility text size', (
      tester,
    ) async {
      // A small phone at a large reading size is where the matrix overflows
      // first: each cell packs an identity row, a live line and a host row into
      // a fixed height, which is exactly the shape `TextScaleMetrics` exists for.
      tester.view.physicalSize = const Size(750, 1334); // iPhone SE class
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _providerOverrides(),
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: MaterialApp(home: ServicesScreen()),
          ),
        ),
      );
      await _pumpDashboard(tester);

      // `takeException` catches the overflow assertion Flutter throws when a
      // fixed box cannot hold its text — the stripe PRODUCT.md forbids.
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('service-matrix-cell-radarr')),
        findsOneWidget,
      );
    });

    testWidgets('renders in the light theme without exception', (tester) async {
      // Light is not an inverted afterthought, and it is where a tone-coloured
      // figure goes wrong: the saturated amber measures about 2:1 on a light
      // card, which is why the live line resolves through `ServiceTheme.onTint`.
      // Media expanded so the figure this test checks is actually painted —
      // the matrix opens folded, and a folded card carries no figure at all.
      SharedPreferences.setMockInitialValues({
        'services_expanded_domains': ['media'],
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._providerOverrides(),
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme(),
            home: const ServicesScreen(),
          ),
        ),
      );
      await _pumpDashboard(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('12 missing', findRichText: true),
        findsWidgets,
      );
      expect(find.text("Lidarr isn't answering"), findsOneWidget);
    });

    testWidgets("a rail's offline state is not clipped by the poster box", (
      tester,
    ) async {
      // The rail's height is fixed around a 138pt poster and grows by the 34pt
      // of label a *tile* carries. Its empty state is a wrapped sentence plus a
      // 44pt button, which is a different budget entirely — sizing the second by
      // the first put the message and its Retry through the bottom of the box at
      // an accessibility reading size.
      tester.view.physicalSize = const Size(750, 1334); // iPhone SE class
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _providerOverrides(
            recentlyAddedBuilder: (ref) async => const <RecentlyAddedItem>[],
            // Every source dark, so the message has to name three services and
            // the header has to find room for a wrapped sentence.
            summaryBuilder: (ref, service) async => ServiceSummary(
              service: service,
              status: ServiceSummaryStatus.offline,
              host: '',
              version: null,
            ),
          ),
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: MaterialApp(home: ServicesScreen()),
          ),
        ),
      );
      await _pumpDashboard(tester);
      await _scrollTo(tester, find.text('Recently Added'));

      expect(tester.takeException(), isNull);
      // The Retry has to be reachable, not merely present: it is the only way
      // out of this state, and it was the part that fell off the bottom.
      expect(
        find.text("Radarr, Sonarr and 1 other aren't answering"),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Retry Radarr, Sonarr, Lidarr'),
        findsOneWidget,
      );
    });

    testWidgets('the unconfigured empty state scrolls rather than clipping', (
      tester,
    ) async {
      // A 72pt icon well, a wrapped title, a two-line message and a button, at
      // three times the reading size, on the shortest phone this ships to. The
      // page owns the viewport precisely so this can grow past it — see the
      // contract on `AppEmptyState`.
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _providerOverrides(settings: const SettingsModel()),
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(3.0)),
            child: MaterialApp(home: ServicesScreen()),
          ),
        ),
      );
      await _pumpDashboard(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('No services connected'), findsOneWidget);
      await _scrollTo(tester, find.text('Set up a service'));
      expect(find.text('Set up a service'), findsOneWidget);
    });
  });

  testWidgets('pull-to-refresh holds the indicator until the data is back', (
    tester,
  ) async {
    // The old `onRefresh` was `() async => _invalidate(...)`, whose future
    // completes on the same microtask — so the spinner retracted while thirteen
    // summaries and three merged lists were still in flight, and the stale
    // figure underneath read as the fresh one.
    final gates = <Completer<void>>[];

    await _pumpServices(
      tester,
      queueBuilder: (ref) async {
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        return const <ServiceQueueItem>[];
      },
    );
    await _pumpDashboard(tester);
    gates.single.complete();
    await _pumpDashboard(tester);

    await tester.fling(find.byType(ListView), const Offset(0, 320), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(gates, hasLength(2), reason: 'the refresh re-ran the queue');
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);

    gates.last.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  testWidgets('a matrix cell opens its service dashboard', (tester) async {
    final router = GoRouter(
      initialLocation: '/services',
      routes: [
        GoRoute(
          path: '/services',
          builder: (context, state) => const ServicesScreen(),
        ),
        GoRoute(
          path: '/services/radarr',
          builder: (context, state) =>
              const Scaffold(body: Text('Radarr Home')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _providerOverrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpDashboard(tester);

    await tester.tap(find.byKey(const ValueKey('service-matrix-cell-radarr')));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/services/radarr');
    expect(find.text('Radarr Home'), findsOneWidget);
  });
}

Future<void> _pumpServices(
  WidgetTester tester, {
  Future<List<ServiceQueueItem>> Function(Ref ref)? queueBuilder,
  Future<List<SeerrRequest>> Function(Ref ref)? requestsBuilder,
  Future<ServiceSummary> Function(Ref ref, ServiceKey service)? summaryBuilder,
  Future<List<RecentlyAddedItem>> Function(Ref ref)? recentlyAddedBuilder,
  SettingsModel? settings,
  // The matrix opens folded by default, so a test that needs the expanded
  // card's host and figure — text a compact card no longer paints at all —
  // has to ask for a band open explicitly rather than relying on the old
  // all-expanded default.
  List<String>? expandedDomains,
}) async {
  final overrides = _providerOverrides(
    queueBuilder: queueBuilder,
    requestsBuilder: requestsBuilder,
    summaryBuilder: summaryBuilder,
    recentlyAddedBuilder: recentlyAddedBuilder,
    settings: settings,
  );

  if (expandedDomains != null) {
    SharedPreferences.setMockInitialValues({
      'services_expanded_domains': expandedDomains,
    });
    final prefs = await SharedPreferences.getInstance();
    overrides.add(sharedPreferencesProvider.overrideWithValue(prefs));
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: ServicesScreen()),
    ),
  );
}

/// Past the band's 200ms fold. Not `pumpAndSettle`: the Recently Added rail's
/// network-image placeholders never settle in a widget test.
Future<void> _pumpFold(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _pumpDashboard(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// The colour of the small circular reachability dot inside the cell keyed
/// [cellKey]. Matches on the `Container` itself rather than a widget type,
/// since the dot has no public class of its own — it is private to
/// `service_matrix.dart`, on purpose: it is anatomy of that one screen, not a
/// reusable component.
Color _dotColorIn(WidgetTester tester, String cellKey) {
  final dot = tester.widget<Container>(
    find.descendant(
      of: find.byKey(ValueKey(cellKey)),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
    ),
  );
  return ((dot.decoration! as BoxDecoration).color)!;
}

Future<void> _scrollTo(WidgetTester tester, Finder target) {
  return tester.scrollUntilVisible(
    target,
    300,
    scrollable: find.byType(Scrollable).first,
  );
}

const _pendingRequest = SeerrRequest(
  id: 1,
  status: RequestStatus.pendingApproval,
  media: RequestMedia(
    title: 'A Quiet Place',
    tmdbId: 123,
    posterPath: '/quiet-place.jpg',
    // Deliberately available: this is the `displayStatus` trap. The request is
    // still awaiting approval, but `displayStatus` reports "Available".
    status: SeerrMediaAvailability.available,
  ),
  createdAt: '2024-01-01',
  type: 'movie',
  requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
);

const _resolvedRequest = SeerrRequest(
  id: 2,
  status: RequestStatus.completed,
  media: RequestMedia(
    title: 'Past Lives',
    tmdbId: 456,
    posterPath: '/past-lives.jpg',
    status: SeerrMediaAvailability.available,
  ),
  createdAt: '2024-02-01',
  type: 'movie',
  requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
);

/// Marks the launch fold demo as already played, so the matrix under test
/// starts settled. Tests that exercise the demo itself pass `demoPlayed: false`
/// to [_providerOverrides].
class _DemoAlreadyPlayed extends ServicesFoldDemoPlayedNotifier {
  @override
  bool build() => true;
}

List<Override> _providerOverrides({
  Future<List<ServiceQueueItem>> Function(Ref ref)? queueBuilder,
  Future<List<SeerrRequest>> Function(Ref ref)? requestsBuilder,
  Future<ServiceSummary> Function(Ref ref, ServiceKey service)? summaryBuilder,
  Future<List<RecentlyAddedItem>> Function(Ref ref)? recentlyAddedBuilder,
  SettingsModel? settings,
  bool demoPlayed = true,
}) {
  return [
    if (demoPlayed)
      servicesFoldDemoPlayedProvider.overrideWith(_DemoAlreadyPlayed.new),
    currentSettingsProvider.overrideWith(
      (ref) =>
          settings ??
          const SettingsModel(
            seerrUrl: 'http://seerr.local:5055',
            seerrApiKey: 'key',
            radarrUrl: 'http://radarr.local:7878',
            radarrApiKey: 'key',
            sonarrUrl: 'http://sonarr.local:8989',
            sonarrApiKey: 'key',
            lidarrUrl: 'http://lidarr.local:8686',
            lidarrApiKey: 'key',
          ),
    ),
    serviceSummaryProvider.overrideWith(
      summaryBuilder ?? (ref, service) async => _summary(service),
    ),
    serviceSignalProvider.overrideWith(
      (ref, service) async => switch (service) {
        ServiceKey.seerr => const ServiceSignal(
          label: 'pending',
          value: '3',
          icon: Icons.hourglass_top_rounded,
          tone: StatusTone.warning,
        ),
        ServiceKey.radarr => const ServiceSignal(
          label: 'missing',
          value: '12',
          icon: Icons.report_gmailerrorred_rounded,
          tone: StatusTone.warning,
        ),
        ServiceKey.sonarr => const ServiceSignal(
          label: 'series',
          value: '7',
          icon: Icons.tv_rounded,
          tone: StatusTone.neutral,
        ),
        _ => null,
      },
    ),
    servicesRequestsProvider.overrideWith(
      requestsBuilder ??
          (ref) async => const [_pendingRequest, _resolvedRequest],
    ),
    servicesRecentlyAddedProvider.overrideWith(
      recentlyAddedBuilder ??
          (ref) async => [
            RecentlyAddedItem(
              service: ServiceKey.radarr,
              id: 10,
              title: 'Dune',
              subtitle: '2021',
              posterUrl: 'https://example.com/dune.jpg',
              addedAt: DateTime.utc(2024, 3, 3),
            ),
            RecentlyAddedItem(
              service: ServiceKey.sonarr,
              id: 20,
              title: 'The Boys',
              subtitle: '2019',
              posterUrl: 'https://example.com/boys.jpg',
              addedAt: DateTime.utc(2024, 2, 2),
            ),
            RecentlyAddedItem(
              service: ServiceKey.lidarr,
              id: 30,
              title: 'Aphex Twin',
              subtitle: '4 albums',
              posterUrl: 'https://example.com/aphex.jpg',
              addedAt: DateTime.utc(2024, 1, 1),
            ),
          ],
    ),
    servicesQueueProvider.overrideWith(
      queueBuilder ??
          (ref) async => const [
            ServiceQueueItem(
              service: ServiceKey.radarr,
              title: 'Furiosa',
              subtitle: 'Movie · Furiosa.2024.2160p.WEB-DL-GROUP',
              progress: 0.75,
              warning: null,
            ),
          ],
    ),
  ];
}

/// Seerr, Radarr and Sonarr answer; Lidarr is the configured service that does
/// not, so the fixture exercises the alert band and a drained cell at once.
/// Everything unconfigured reports offline with no host, as the real provider
/// does.
ServiceSummary _summary(ServiceKey service, {bool online = false}) {
  const hosts = {
    ServiceKey.seerr: 'seerr.local:5055',
    ServiceKey.radarr: 'radarr.local:7878',
    ServiceKey.sonarr: 'sonarr.local:8989',
    ServiceKey.lidarr: 'lidarr.local:8686',
  };

  final isUp =
      online ||
      const {
        ServiceKey.seerr,
        ServiceKey.radarr,
        ServiceKey.sonarr,
      }.contains(service);

  return ServiceSummary(
    service: service,
    status: isUp ? ServiceSummaryStatus.online : ServiceSummaryStatus.offline,
    host: hosts[service] ?? '',
    version: isUp ? '1.0.0' : null,
  );
}

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
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/services/presentation/services_screen.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

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

    // The live line: a figure and its label, per service — the thing the old
    // card spent on a static library total.
    // One text run with two spans, not a figure and a word in a `Row` — so they
    // cannot be found separately, which is exactly what stops the pair from
    // eliding the word away while the number sits in half an empty cell.
    expect(find.textContaining('3 pending', findRichText: true), findsWidgets);
    expect(find.textContaining('12 missing', findRichText: true), findsWidgets);

    // Set in plain body, not the eyebrow. One tracked uppercase overline per
    // cell across a thirteen-cell grid is the "eyebrow everywhere" noise
    // DESIGN.md's Eyebrow Rule exists to prevent.
    expect(find.text('MISSING'), findsNothing);

    // Reachability is a word, never colour alone. 'Online' is not printed: a
    // live figure can only have come from a service that answered, and the old
    // card's 'ONLINE' next to a green dot said the same thing twice.
    expect(find.text('Offline'), findsWidgets);
    expect(find.text('ONLINE'), findsNothing);

    // Nine of thirteen unconfigured, offered once rather than as nine dimmed
    // cells — and named with the verb, since a bare count reads as a truncated
    // list rather than as somewhere to go.
    expect(find.text('Set up 9 more services'), findsOneWidget);
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
      await _pumpServices(
        tester,
        summaryBuilder: (ref, service) =>
            Future.delayed(const Duration(seconds: 5), () => _summary(service)),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);
      // Checking is its own state, and it says so.
      expect(find.text('Checking'), findsWidgets);
      expect(find.text('Offline'), findsNothing);

      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('folding a domain band', () {
    testWidgets('collapsing takes its cells out of the tree', (tester) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      expect(
        find.byKey(const ValueKey('service-matrix-cell-radarr')),
        findsOneWidget,
      );

      await tester.tap(find.text('MEDIA'));
      await _pumpFold(tester);

      // Removed, not hidden. `CollapsibleDomainSection`'s `AnimatedCrossFade`
      // keeps both children built, which for this grid would mean a folded band
      // still watching `serviceSignalProvider` — a library fetch per invisible
      // cell on every refresh, to paint nothing.
      expect(
        find.byKey(const ValueKey('service-matrix-cell-radarr')),
        findsNothing,
      );
      // The strip that replaces them keeps each service's identity mark, so the
      // fold does not cost the "is anything dark in here" reading.
      expect(find.byIcon(ServiceKey.radarr.icon), findsWidgets);
    });

    testWidgets('the header carries its state and what it folded away', (
      tester,
    ) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      // Expanded: the cells speak for themselves, so the header adds no value.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Media')),
        containsSemantics(label: 'Media', isButton: true, isExpanded: true),
      );

      await tester.tap(find.text('MEDIA'));
      await _pumpFold(tester);

      // Folded: the unlit tiles in the strip are invisible to a screen reader,
      // so the health they carry moves onto the header instead.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Media')),
        containsSemantics(
          label: 'Media',
          value: "4 services, Lidarr isn't answering",
          isButton: true,
          isExpanded: false,
        ),
      );
    });

    testWidgets('a stored fold arrives collapsed', (tester) async {
      // Persisted, not per-visit: a fold that springs back on every cold open is
      // a control you press once and never trust again.
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

      expect(find.text('MEDIA'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('service-matrix-cell-radarr')),
        findsNothing,
      );
    });

    testWidgets('nothing is folded by default', (tester) async {
      // Compaction is opt-in. A hub that arrives folded shut hides the one thing
      // the screen exists to show.
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

      expect(
        find.byKey(const ValueKey('service-matrix-cell-radarr')),
        findsOneWidget,
      );
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

    testWidgets('the unconfigured cell names where it goes', (tester) async {
      await _pumpServices(tester);
      await _pumpDashboard(tester);

      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('services-unconfigured-cell')),
        ),
        containsSemantics(
          label: 'Set up 9 more services',
          isButton: true,
          hasTapAction: true,
        ),
      );
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: _providerOverrides(),
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _providerOverrides(
        queueBuilder: queueBuilder,
        requestsBuilder: requestsBuilder,
        summaryBuilder: summaryBuilder,
        recentlyAddedBuilder: recentlyAddedBuilder,
        settings: settings,
      ),
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

List<Override> _providerOverrides({
  Future<List<ServiceQueueItem>> Function(Ref ref)? queueBuilder,
  Future<List<SeerrRequest>> Function(Ref ref)? requestsBuilder,
  Future<ServiceSummary> Function(Ref ref, ServiceKey service)? summaryBuilder,
  Future<List<RecentlyAddedItem>> Function(Ref ref)? recentlyAddedBuilder,
  SettingsModel? settings,
}) {
  return [
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

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/interactive_search_sheet.dart';

void main() {
  group('InteractiveSearchSheet.showAsync', () {
    testWidgets('cancels the in-flight fetch when the sheet is dismissed', (
      tester,
    ) async {
      final completer = Completer<List<dynamic>>();
      final navigatorKey = GlobalKey<NavigatorState>();
      CancelToken? capturedToken;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: _InteractiveSearchSheetLauncher(
            fetchReleases: (token) {
              capturedToken = token;
              return completer.future;
            },
          ),
        ),
      );
      await _pumpSheetEntrance(tester);

      expect(find.text('Searching for releases…'), findsOneWidget);
      expect(capturedToken, isNotNull);
      expect(capturedToken!.isCancelled, isFalse);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(capturedToken!.isCancelled, isTrue);
      expect(find.text('LauncherPage'), findsOneWidget);

      completer.complete(const []);
      await tester.pump();
    });

    testWidgets('withholds the elapsed readout until the search is slow', (
      tester,
    ) async {
      // A clock on a search that answers in two seconds is noise, so the
      // readout arms itself at three. Note the explicit `pump(Duration)`:
      // `pumpAndSettle` cannot be used while the ticker is running, because a
      // periodic setState means there is always another frame scheduled.
      final completer = Completer<List<dynamic>>();

      await tester.pumpWidget(
        MaterialApp(
          home: _InteractiveSearchSheetLauncher(
            fetchReleases: (_) => completer.future,
          ),
        ),
      );
      await _pumpSheetEntrance(tester);

      expect(find.text('Searching for releases…'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:02'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:03'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:04'), findsOneWidget);
      expect(find.text('0:03'), findsNothing);

      completer.complete(const []);
      await tester.pumpAndSettle();
    });

    testWidgets('the readout stops once the search resolves', (tester) async {
      final completer = Completer<List<dynamic>>();

      await tester.pumpWidget(
        MaterialApp(
          home: _InteractiveSearchSheetLauncher(
            fetchReleases: (_) => completer.future,
          ),
        ),
      );
      await _pumpSheetEntrance(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('0:04'), findsOneWidget);

      completer.complete(const []);
      // Settling at all proves the ticker was cancelled: a live periodic
      // setState would keep scheduling frames and time this out.
      await tester.pumpAndSettle();

      expect(find.text('Searching for releases…'), findsNothing);
    });

    testWidgets('Cancel closes the sheet and cancels the fetch', (
      tester,
    ) async {
      final completer = Completer<List<dynamic>>();
      CancelToken? capturedToken;

      await tester.pumpWidget(
        MaterialApp(
          home: _InteractiveSearchSheetLauncher(
            fetchReleases: (token) {
              capturedToken = token;
              return completer.future;
            },
          ),
        ),
      );
      await _pumpSheetEntrance(tester);

      expect(capturedToken!.isCancelled, isFalse);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Dismissing already cancelled the fetch; Cancel only makes that exit
      // visible, so the observable outcome has to be identical.
      expect(capturedToken!.isCancelled, isTrue);
      expect(find.text('LauncherPage'), findsOneWidget);

      completer.complete(const []);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('suppresses fetch errors after the sheet is dismissed', (
      tester,
    ) async {
      final completer = Completer<List<dynamic>>();
      final navigatorKey = GlobalKey<NavigatorState>();
      CancelToken? capturedToken;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: _InteractiveSearchSheetLauncher(
            fetchReleases: (token) {
              capturedToken = token;
              return completer.future;
            },
          ),
        ),
      );
      await _pumpSheetEntrance(tester);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      completer.completeError(Exception('boom'));
      await tester.pump();

      expect(capturedToken, isNotNull);
      expect(capturedToken!.isCancelled, isTrue);
      expect(find.textContaining('Failed to load releases'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a retry action when the fetch fails', (tester) async {
      var attempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: _InteractiveSearchSheetLauncher(
            fetchReleases: (_) async {
              attempts++;
              if (attempts == 1) throw Exception('boom');
              return [_release(title: 'Recovered.Release')];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Recovered.Release'), findsOneWidget);
    });
  });

  group('InteractiveSearchSheet filtering', () {
    testWidgets('summarises the result counts', (tester) async {
      await _pumpSheet(tester, releases: _sampleReleases);

      expect(find.text('3 releases · 2 approved'), findsOneWidget);
    });

    testWidgets('filters by title query', (tester) async {
      await _pumpSheet(tester, releases: _sampleReleases);

      await tester.enterText(find.byType(TextField), 'remux');
      await tester.pumpAndSettle();

      expect(find.text('Movie.2024.2160p.REMUX'), findsOneWidget);
      expect(find.text('Movie.2024.1080p.WEB-DL'), findsNothing);
      expect(find.text('1 of 3 releases · 2 approved'), findsOneWidget);
    });

    testWidgets('hides rejected releases behind the Approved only chip', (
      tester,
    ) async {
      await _pumpSheet(tester, releases: _sampleReleases);

      await tester.tap(find.text('Approved only'));
      await tester.pumpAndSettle();

      expect(find.text('Movie.2024.720p.Rejected'), findsNothing);
      expect(find.text('2 of 3 releases · 2 approved'), findsOneWidget);
    });

    testWidgets('offers a way back when filters exclude everything', (
      tester,
    ) async {
      await _pumpSheet(tester, releases: _sampleReleases);

      await tester.enterText(find.byType(TextField), 'nothing matches this');
      await tester.pumpAndSettle();

      expect(find.text('No releases match filters'), findsOneWidget);

      await tester.tap(find.text('Clear Filters'));
      await tester.pumpAndSettle();

      expect(find.text('3 releases · 2 approved'), findsOneWidget);
    });

    testWidgets('shows an empty state when no release was returned', (
      tester,
    ) async {
      await _pumpSheet(tester, releases: const []);

      expect(find.text('No releases found'), findsOneWidget);
    });

    testWidgets('every empty branch scrolls with the sheet controller', (
      tester,
    ) async {
      // A `Center` here detaches the controller `AppBottomSheet.showScrollable`
      // handed in, and drag-to-resize and flick-to-close stop working the moment
      // a filter empties the list.
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await _pumpSheet(
        tester,
        releases: const [],
        scrollController: controller,
      );
      expect(
        _listViewAround(tester, 'No releases found').controller,
        controller,
      );

      await _pumpSheet(
        tester,
        releases: _sampleReleases,
        scrollController: controller,
      );
      await tester.enterText(find.byType(TextField), 'nothing matches this');
      await tester.pumpAndSettle();

      expect(
        _listViewAround(tester, 'No releases match filters').controller,
        controller,
      );
    });
  });

  group('InteractiveSearchSheet grabbing', () {
    testWidgets('a grab closes the sheet and reports the download', (
      tester,
    ) async {
      final grabbed = <String>[];
      await _showSheet(
        tester,
        releases: _sampleReleases,
        onGrabRelease: (guid, _) async => grabbed.add(guid),
      );

      await _grabFirstRelease(tester);

      expect(grabbed, hasLength(1));
      expect(find.text('Download started'), findsOneWidget);
      expect(find.byType(InteractiveSearchSheet), findsNothing);
    });

    testWidgets('an abandoned grab leaves the sheet open and silent', (
      tester,
    ) async {
      // The release-search sheet's expired-list prompt returns without grabbing
      // when it is cancelled. Reported as a normal return, that closed the sheet
      // under a green "Download started" for a download nobody started.
      var attempts = 0;
      await _showSheet(
        tester,
        releases: _sampleReleases,
        onGrabRelease: (_, __) async {
          attempts++;
          throw const ReleaseGrabAbandoned();
        },
      );

      await _grabFirstRelease(tester);

      expect(attempts, 1);
      expect(find.byType(InteractiveSearchSheet), findsOneWidget);
      expect(find.text('Download started'), findsNothing);
      // Not a failure either: the caller has already said why.
      expect(find.byType(SnackBar), findsNothing);

      // And the list is re-armed rather than dead for the life of the sheet.
      expect(find.byTooltip('Another download is starting'), findsNothing);
      await _grabFirstRelease(tester);
      expect(attempts, 2);
    });

    testWidgets('a grab that outlives its row still closes and confirms', (
      tester,
    ) async {
      final completer = Completer<void>();
      await _showSheet(
        tester,
        releases: _sampleReleases,
        onGrabRelease: (_, __) => completer.future,
      );

      await _startGrabInFlight(tester);
      expect(find.byTooltip('Another download is starting'), findsWidgets);

      // The toolbar stays live during a grab, so a filter can empty the list
      // and take the grabbing row's element with it while the request runs on.
      await _emptyTheList(tester);

      completer.complete();
      await tester.pumpAndSettle();

      // The download *did* start. Reporting through the row's dead element
      // skipped the pop and the confirmation and quietly re-armed every button
      // instead — nothing on screen said anything had happened, and tapping the
      // same release again grabbed it twice.
      expect(find.byType(InteractiveSearchSheet), findsNothing);
      expect(find.text('Download started'), findsOneWidget);
    });

    testWidgets('a failed grab that outlives its row still re-arms the sheet', (
      tester,
    ) async {
      // The other half: a failure keeps the sheet open, so the busy state has
      // to clear and the reason has to be shown — and neither can depend on the
      // row that started it still being in the tree.
      final completer = Completer<void>();
      await _showSheet(
        tester,
        releases: _sampleReleases,
        onGrabRelease: (_, __) => completer.future,
      );

      await _startGrabInFlight(tester);
      await _emptyTheList(tester);

      completer.completeError(Exception('indexer said no'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);

      await tester.tap(find.text('Clear Filters'));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveSearchSheet), findsOneWidget);
      expect(find.byTooltip('Another download is starting'), findsNothing);
      expect(find.byTooltip('Grab Release'), findsNWidgets(3));
    });
  });
}

/// Confirms a grab and leaves it in flight.
///
/// Deliberately no `pumpAndSettle` after the confirmation: the grabbing row
/// spins on an indeterminate indicator, so nothing ever settles while the
/// request is outstanding.
Future<void> _startGrabInFlight(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Grab Release').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Download'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Filters the list down to nothing, which deactivates the grabbing row.
Future<void> _emptyTheList(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'nothing matches this');
  await tester.pumpAndSettle();
  expect(find.text('No releases match filters'), findsOneWidget);
}

/// The nearest [ListView] above [text], which is what proves an empty branch is
/// a scrollable rather than a `Center`.
ListView _listViewAround(WidgetTester tester, String text) =>
    tester.widget<ListView>(
      find.ancestor(of: find.text(text), matching: find.byType(ListView)).first,
    );

Future<void> _grabFirstRelease(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Grab Release').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Download'));
  await tester.pumpAndSettle();
}

final _sampleReleases = [
  _release(title: 'Movie.2024.1080p.WEB-DL', protocol: 'usenet'),
  _release(title: 'Movie.2024.2160p.REMUX', protocol: 'torrent', seeders: 20),
  _release(
    title: 'Movie.2024.720p.Rejected',
    protocol: 'usenet',
    rejections: const ['Quality below cutoff'],
  ),
];

Map<String, dynamic> _release({
  required String title,
  String indexer = 'NZBgeek',
  String protocol = 'usenet',
  int seeders = 0,
  List<dynamic> rejections = const [],
}) {
  return {
    'guid': title,
    'indexerId': 1,
    'title': title,
    'indexer': indexer,
    'protocol': protocol,
    'seeders': seeders,
    'size': 1073741824,
    'ageMinutes': 60,
    'quality': {
      'quality': {'name': '1080p'},
    },
    'customFormatScore': 0,
    'customFormats': const [],
    'rejections': rejections,
    'approved': rejections.isEmpty,
  };
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required List<dynamic> releases,
  ScrollController? scrollController,
}) async {
  final controller = scrollController ?? ScrollController();
  if (scrollController == null) {
    addTearDown(controller.dispose);
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InteractiveSearchSheet(
          releases: releases,
          title: 'Releases',
          onGrabRelease: (_, __) async {},
          scrollController: controller,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the sheet on a real modal route, which is what a grab needs: it pops
/// the route it is on and reports through the messenger above it.
Future<void> _showSheet(
  WidgetTester tester, {
  required List<dynamic> releases,
  required Future<void> Function(String guid, int indexerId) onGrabRelease,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _InteractiveSearchSheetLauncher(
        releases: releases,
        onGrabRelease: onGrabRelease,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSheetEntrance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _InteractiveSearchSheetLauncher extends StatefulWidget {
  const _InteractiveSearchSheetLauncher({
    this.fetchReleases,
    this.releases,
    this.onGrabRelease,
  }) : assert(fetchReleases != null || releases != null);

  /// Opens the async variant, which fetches before it lists.
  final Future<List<dynamic>> Function(CancelToken token)? fetchReleases;

  /// Opens the plain variant on an already-resolved list.
  final List<dynamic>? releases;

  final Future<void> Function(String guid, int indexerId)? onGrabRelease;

  @override
  State<_InteractiveSearchSheetLauncher> createState() =>
      _InteractiveSearchSheetLauncherState();
}

class _InteractiveSearchSheetLauncherState
    extends State<_InteractiveSearchSheetLauncher> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final releases = widget.releases;
      final onGrabRelease = widget.onGrabRelease ?? (String _, int __) async {};

      if (releases != null) {
        InteractiveSearchSheet.show(
          context: context,
          releases: releases,
          title: 'Interactive Search',
          onGrabRelease: onGrabRelease,
        );
        return;
      }

      InteractiveSearchSheet.showAsync(
        context: context,
        title: 'Interactive Search',
        fetchReleases: widget.fetchReleases!,
        onGrabRelease: onGrabRelease,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('LauncherPage')));
  }
}

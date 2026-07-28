import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/interactive_search_sheet.dart';

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

      expect(find.text('Searching for releases...'), findsOneWidget);
      expect(capturedToken, isNotNull);
      expect(capturedToken!.isCancelled, isFalse);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(capturedToken!.isCancelled, isTrue);
      expect(find.text('LauncherPage'), findsOneWidget);

      completer.complete(const []);
      await tester.pump();
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
  });
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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InteractiveSearchSheet(
          releases: releases,
          title: 'Releases',
          onGrabRelease: (_, __) async {},
          scrollController: ScrollController(),
        ),
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
  const _InteractiveSearchSheetLauncher({required this.fetchReleases});

  final Future<List<dynamic>> Function(CancelToken token) fetchReleases;

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

      InteractiveSearchSheet.showAsync(
        context: context,
        title: 'Interactive Search',
        fetchReleases: widget.fetchReleases,
        onGrabRelease: (_, __) async {},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('LauncherPage')));
  }
}

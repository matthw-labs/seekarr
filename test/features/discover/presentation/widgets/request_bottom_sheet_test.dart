import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';

import '../../../../test_helpers/fake_services.dart' as shared;

void main() {
  group('RequestBottomSheet rendering', () {
    testWidgets('shows loading indicator while form is initializing', (
      tester,
    ) async {
      await _pumpSheetDirect(tester, service: _DelayedFakeSeerr());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Submit Request'), findsNothing);
    });

    testWidgets('shows error when no servers are configured', (tester) async {
      await _pumpSheetDirect(
        tester,
        service: _FakeSeerr(radarrServers: const []),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No Radarr servers configured in Seerr'),
        findsOneWidget,
      );
      expect(find.text('Submit Request'), findsNothing);
    });

    testWidgets('renders quality profile dropdown and submit button', (
      tester,
    ) async {
      await _pumpSheetDirect(tester, service: _movieService());
      await tester.pumpAndSettle();

      expect(find.text('Request Movie'), findsOneWidget);
      expect(find.text('Quality Profile'), findsOneWidget);
      expect(find.text('Submit Request'), findsOneWidget);
    });

    testWidgets('hides server dropdown when only one server exists', (
      tester,
    ) async {
      await _pumpSheetDirect(tester, service: _movieService());
      await tester.pumpAndSettle();

      expect(find.text('Server'), findsNothing);
      expect(find.text('Quality Profile'), findsOneWidget);
    });

    testWidgets('shows server dropdown when multiple servers exist', (
      tester,
    ) async {
      await _pumpSheetDirect(
        tester,
        service: _movieService(multipleServers: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server'), findsOneWidget);
    });

    testWidgets('shows root folder dropdown when root folders are available', (
      tester,
    ) async {
      await _pumpSheetDirect(tester, service: _movieService());
      await tester.pumpAndSettle();

      expect(find.text('Root Folder'), findsOneWidget);
    });
  });

  group('RequestBottomSheet interactions', () {
    testWidgets('calls onRequestComplete after successful submit', (
      tester,
    ) async {
      var requestCompleteCount = 0;

      await _pumpSheetOnRoute(
        tester,
        service: _movieService(),
        onRequestComplete: () => requestCompleteCount += 1,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      expect(requestCompleteCount, 1);
      expect(find.text('LauncherPage'), findsOneWidget);
    });

    testWidgets('shows a snackbar when submit fails', (tester) async {
      await _pumpSheetDirect(
        tester,
        service: _FakeSeerr(
          radarrServers: const [
            {'id': 1, 'name': 'Main'},
          ],
          radarrProfilesByServer: const {
            1: {
              'profiles': [
                {'id': 5, 'name': 'HD-1080p'},
              ],
              'rootFolders': [
                {'path': '/movies'},
              ],
            },
          },
          throwOnCreateRequest: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit Request'));
      await tester.pumpAndSettle();

      expect(
        find.text('Request failed: Exception: request failed'),
        findsOneWidget,
      );
    });

    testWidgets('shows the tv request title for tv media', (tester) async {
      await _pumpSheetDirect(tester, service: _tvService(), mediaType: 'tv');
      await tester.pumpAndSettle();

      expect(find.text('Request TV Show'), findsOneWidget);
    });
  });
}

_FakeSeerr _movieService({bool multipleServers = false}) {
  return _FakeSeerr(
    radarrServers: multipleServers
        ? const [
            {'id': 1, 'name': 'Main'},
            {'id': 2, 'name': 'Backup'},
          ]
        : const [
            {'id': 1, 'name': 'Main'},
          ],
    radarrProfilesByServer: const {
      1: {
        'profiles': [
          {'id': 5, 'name': 'HD-1080p'},
        ],
        'rootFolders': [
          {'path': '/movies'},
        ],
      },
      2: {
        'profiles': [
          {'id': 8, 'name': '4K'},
        ],
        'rootFolders': [
          {'path': '/movies-4k'},
        ],
      },
    },
  );
}

_FakeSeerr _tvService() {
  return _FakeSeerr(
    sonarrServers: const [
      {'id': 9, 'name': 'TV Main'},
    ],
    sonarrProfilesByServer: const {
      9: {
        'profiles': [
          {'id': 11, 'name': 'HD-TV'},
        ],
        'rootFolders': [
          {'path': '/tv'},
        ],
      },
    },
  );
}

Future<void> _pumpSheetDirect(
  WidgetTester tester, {
  required SeerrService service,
  int mediaId = 123,
  String mediaType = 'movie',
  VoidCallback? onRequestComplete,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [seerrServiceProvider.overrideWith((ref) => service)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 800,
            // Mirror real usage: the title lives in the shared AppBottomSheet
            // header (per media type), not inside RequestBottomSheet.
            child: AppBottomSheet(
              title: mediaType == 'tv' ? 'Request TV Show' : 'Request Movie',
              child: RequestBottomSheet(
                mediaId: mediaId,
                mediaType: mediaType,
                onRequestComplete: onRequestComplete ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpSheetOnRoute(
  WidgetTester tester, {
  required SeerrService service,
  int mediaId = 123,
  String mediaType = 'movie',
  VoidCallback? onRequestComplete,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [seerrServiceProvider.overrideWith((ref) => service)],
      child: MaterialApp(
        home: _RequestSheetRouteLauncher(
          mediaId: mediaId,
          mediaType: mediaType,
          onRequestComplete: onRequestComplete ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _RequestSheetRouteLauncher extends StatefulWidget {
  const _RequestSheetRouteLauncher({
    required this.mediaId,
    required this.mediaType,
    required this.onRequestComplete,
  });

  final int mediaId;
  final String mediaType;
  final VoidCallback onRequestComplete;

  @override
  State<_RequestSheetRouteLauncher> createState() =>
      _RequestSheetRouteLauncherState();
}

class _RequestSheetRouteLauncherState
    extends State<_RequestSheetRouteLauncher> {
  bool _pushed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pushed) return;
    _pushed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: SizedBox(
              height: 800,
              child: RequestBottomSheet(
                mediaId: widget.mediaId,
                mediaType: widget.mediaType,
                onRequestComplete: widget.onRequestComplete,
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('LauncherPage')));
  }
}

class _DelayedFakeSeerr extends _FakeSeerr {
  @override
  Future<List<Map<String, dynamic>>> getRadarrServers() {
    return Completer<List<Map<String, dynamic>>>().future;
  }
}

class _FakeSeerr extends shared.FakeSeerrService {
  _FakeSeerr({
    this.radarrServers = const <Map<String, dynamic>>[],
    this.sonarrServers = const <Map<String, dynamic>>[],
    this.radarrProfilesByServer = const <int, Map<String, dynamic>>{},
    this.sonarrProfilesByServer = const <int, Map<String, dynamic>>{},
    this.throwOnCreateRequest = false,
  });

  final List<Map<String, dynamic>> radarrServers;
  final List<Map<String, dynamic>> sonarrServers;
  final Map<int, Map<String, dynamic>> radarrProfilesByServer;
  final Map<int, Map<String, dynamic>> sonarrProfilesByServer;
  final bool throwOnCreateRequest;

  Map<String, Object?>? lastCreateRequestCall;

  @override
  Future<List<Map<String, dynamic>>> getRadarrServers() async => radarrServers;

  @override
  Future<List<Map<String, dynamic>>> getSonarrServers() async => sonarrServers;

  @override
  Future<Map<String, dynamic>> getRadarrProfiles(int serverId) async {
    return radarrProfilesByServer[serverId] ??
        {'profiles': const [], 'rootFolders': const []};
  }

  @override
  Future<Map<String, dynamic>> getSonarrProfiles(int serverId) async {
    return sonarrProfilesByServer[serverId] ??
        {'profiles': const [], 'rootFolders': const []};
  }

  @override
  Future<void> createRequest({
    required String mediaType,
    required int mediaId,
    int? profileId,
    String? rootFolder,
    int? serverId,
    bool is4k = false,
    List<int>? seasons,
  }) async {
    if (throwOnCreateRequest) throw Exception('request failed');
    lastCreateRequestCall = {
      'mediaType': mediaType,
      'mediaId': mediaId,
      'profileId': profileId,
      'rootFolder': rootFolder,
      'serverId': serverId,
      'is4k': is4k,
      'seasons': seasons,
    };
  }
}

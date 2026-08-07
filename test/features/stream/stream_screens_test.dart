import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_dashboard_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';

const _configured = SettingsModel(
  jellyfinUrl: 'http://jelly.local:8096',
  jellyfinApiKey: 'key',
  jellyfinUserId: 'viewer-1',
);

StreamSession _session({
  String id = 's1',
  String user = 'Matt',
  String title = 'The Fellowship of the Ring',
  StreamPlayMethod method = StreamPlayMethod.directPlay,
  List<String> reasons = const [],
  int? bitrate = 24305112,
  bool nominal = true,
  double? progress = 0.34,
  bool paused = false,
}) => StreamSession(
  id: id,
  userName: user,
  title: title,
  subtitle: null,
  deviceLabel: 'Infuse on Apple TV',
  posterPath: null,
  playMethod: method,
  transcodeReasons: reasons,
  bitrate: bitrate,
  bitrateIsNominal: nominal,
  progress: progress,
  isPaused: paused,
);

const _library = StreamLibrary(
  id: 'lib-1',
  name: 'Films',
  kind: StreamLibraryKind.movies,
  itemCount: 412,
  lastScannedAt: null,
  isRefreshing: false,
);

Future<void> _pumpBoard(
  WidgetTester tester, {
  List<StreamSession> sessions = const [],
  List<StreamLibrary> libraries = const [_library],
  SettingsModel settings = _configured,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        jellyfinSessionsProvider.overrideWith((ref) async => sessions),
        jellyfinLibrariesProvider.overrideWith((ref) async => libraries),
        serviceKpiProvider.overrideWith((ref, service) async => const []),
      ],
      child: const MaterialApp(
        home: StreamDashboardScreen(service: ServiceKey.jellyfin),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the Stream board', () {
    testWidgets('idle is a quiet line, not an error and not an empty state', (
      tester,
    ) async {
      await _pumpBoard(tester);

      // Nobody watching is the majority state on a home server and the normal
      // daily condition, so it must not read as a failure.
      expect(find.text('Nobody is watching right now'), findsOneWidget);
      expect(find.textContaining('Couldn\'t load'), findsNothing);
      // The page's weight falls to the libraries, which is the only region with
      // content either way.
      expect(find.text('Films'), findsOneWidget);
    });

    testWidgets('never prints an aggregate outbound total', (tester) async {
      await _pumpBoard(
        tester,
        sessions: [
          _session(bitrate: 8000000),
          _session(id: 's2', user: 'Sara', bitrate: 12000000),
        ],
      );

      // Neither server reports measured throughput, so summing the two rows and
      // presenting 20 Mbps as the box's egress would be a fabricated figure. The
      // per-session values are shown; no total exists anywhere on the page.
      expect(find.textContaining('20 Mbps'), findsNothing);
      expect(find.byType(StreamSessionCard), findsNWidgets(2));
    });

    testWidgets('a nominal rate is hedged rather than stated as measured', (
      tester,
    ) async {
      await _pumpBoard(tester, sessions: [_session(bitrate: 8400000)]);

      // "~" carries the same hedge the spoken form says as "about": this is the
      // file's own bitrate, not what is on the wire.
      expect(find.text('~8.4 Mbps'), findsOneWidget);
      expect(find.text('8.4 Mbps'), findsNothing);
    });

    testWidgets('a transcode names why, in the warning tone', (tester) async {
      await _pumpBoard(
        tester,
        sessions: [
          _session(
            method: StreamPlayMethod.transcode,
            reasons: const ["client can't decode HEVC"],
            nominal: false,
          ),
        ],
      );

      // The focal moment of the whole surface: both web UIs bury this, and it is
      // the fact that turns "the box is busy" into something actionable.
      expect(find.text("client can't decode HEVC"), findsOneWidget);
      expect(find.text('Transcode'), findsOneWidget);

      final reason = tester.widget<Text>(find.text("client can't decode HEVC"));
      expect(reason.style?.color, AppColors.warning);
    });

    testWidgets('a direct play is not painted as a problem', (tester) async {
      await _pumpBoard(tester, sessions: [_session()]);

      final label = tester.widget<Text>(find.text('Direct play'));
      expect(label.style?.color, isNot(AppColors.warning));
    });

    testWidgets('the transcode reason survives an accessibility text size', (
      tester,
    ) async {
      // The reason is the longest string on the card and the one an earlier
      // single-line design would have ellipsised first — which would have eaten
      // exactly the string the surface exists to show.
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            jellyfinSessionsProvider.overrideWith(
              (ref) async => [
                _session(
                  method: StreamPlayMethod.transcode,
                  reasons: const [
                    'client cannot decode HEVC · audio downmix to stereo',
                  ],
                ),
              ],
            ),
            jellyfinLibrariesProvider.overrideWith((ref) async => [_library]),
            serviceKpiProvider.overrideWith((ref, service) async => const []),
          ],
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: MaterialApp(
              home: StreamDashboardScreen(service: ServiceKey.jellyfin),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('client cannot decode HEVC · audio downmix to stereo'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unconfigured server placeholders rather than erroring', (
      tester,
    ) async {
      await _pumpBoard(tester, settings: const SettingsModel());

      expect(find.byType(StreamSessionCard), findsNothing);
      expect(find.textContaining('Jellyfin'), findsWidgets);
    });

    testWidgets('renders in the light theme without exception', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _configured),
            jellyfinSessionsProvider.overrideWith(
              (ref) async => [_session(method: StreamPlayMethod.transcode)],
            ),
            jellyfinLibrariesProvider.overrideWith((ref) async => [_library]),
            serviceKpiProvider.overrideWith((ref, service) async => const []),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme(),
            home: const StreamDashboardScreen(service: ServiceKey.jellyfin),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('the library lens vocabulary', () {
    test('A–Z is last, so it can never be the landing lens', () {
      // The idle-month test in code: if the browse opened on an alphabetical wall
      // it would be Radarr rendered twice. Every lens before `all` needs watch
      // history to render at all.
      expect(StreamLibraryLens.values.last, StreamLibraryLens.all);
      expect(
        StreamLibraryLens.values.first,
        StreamLibraryLens.continueWatching,
      );
    });

    test('only the watch-state lenses are viewer-scoped', () {
      // Jellyfin can answer the per-viewer lenses for any household member; Plex
      // cannot answer them for anyone but the token owner.
      //
      // Recently added and A–Z are not among them, and A–Z is the one that used
      // to be: an alphabetical wall is the same wall whoever is looking, and
      // `/Items?parentId=…&sortBy=SortName` takes `userId` as strictly optional.
      // Scoping it to a viewer made the client refuse a request that works and
      // told a connected-but-unpicked user their library was empty.
      const viewerScoped = {
        StreamLibraryLens.continueWatching,
        StreamLibraryLens.nextUp,
        StreamLibraryLens.unplayed,
      };
      for (final lens in StreamLibraryLens.values) {
        expect(
          lens.isPerViewer,
          viewerScoped.contains(lens),
          reason: '${lens.name} viewer-scoping is wrong',
        );
      }
    });
  });
}

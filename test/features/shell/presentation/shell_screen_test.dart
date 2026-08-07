import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';

import '../../../test_helpers/semantics_announcements.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ShellScreen', () {
    testWidgets('renders the floating nav bar with four destinations', (
      tester,
    ) async {
      await _pumpShell(tester);

      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(_navItem('Services'), findsOneWidget);
      expect(_navItem('Activity'), findsOneWidget);
      expect(_navItem('Search'), findsOneWidget);
      expect(_navItem('Settings'), findsOneWidget);
    });

    testWidgets('selects Services for the /services route', (tester) async {
      await _pumpShell(tester, initialLocation: '/services');

      expect(find.text('ServicesPage'), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
      expect(find.byIcon(Icons.view_list_outlined), findsNothing);
    });

    testWidgets('selects Services for legacy detail routes', (tester) async {
      await _pumpShell(tester, initialLocation: '/services/radarr/movie/42');

      expect(find.text('MovieDetailPage'), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    });

    testWidgets('selects Settings for the /settings route', (tester) async {
      await _pumpShell(tester, initialLocation: '/settings');

      expect(find.text('SettingsPage'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });

    testWidgets('does not select a tab for unmatched shell routes', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: '/outside');

      expect(find.text('OutsidePage'), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsNothing);
      expect(find.byIcon(Icons.monitor_heart_rounded), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsNothing);
      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets('tapping Search navigates to /search', (tester) async {
      final harness = await _pumpShell(tester);

      await tester.tap(_navItem('Search'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/search');
      expect(find.text('SearchPage'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('tapping the current Services tab triggers a refresh', (
      tester,
    ) async {
      final harness = await _pumpShell(tester, initialLocation: '/services');

      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.services),
        ),
        0,
      );

      await tester.tap(_navItem('Services'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/services');
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.services),
        ),
        1,
      );
    });

    testWidgets(
      'tapping selected Services from a nested services route returns to root without refreshing',
      (tester) async {
        final harness = await _pumpShell(
          tester,
          initialLocation: '/services/radarr/movie/42',
        );

        await tester.tap(_navItem('Services'));
        await tester.pumpAndSettle();

        expect(harness.router.state.uri.path, '/services');
        expect(find.text('ServicesPage'), findsOneWidget);
        expect(
          harness.container.read(
            navigationRefreshProvider(NavigationSection.services),
          ),
          0,
        );
      },
    );

    testWidgets('re-tapping the active Services tab announces the refresh', (
      tester,
    ) async {
      // A re-tap refresh changes nothing on screen — no spinner, no route
      // change — so without this the tap is indistinguishable from a no-op for a
      // screen-reader user.
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      final harness = await _pumpShell(tester, initialLocation: '/services');

      await tester.tap(_navItem('Services'));
      await tester.pumpAndSettle();

      expect(announcements.messages, ['Refreshing Services']);
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.services),
        ),
        1,
      );
    });

    testWidgets('switching tabs does not announce', (tester) async {
      // Replacing the whole screen is its own feedback, and an announcement
      // interrupts the reader's speech queue. This guards an over-eager
      // announce() in the navigate branch.
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      await _pumpShell(tester, initialLocation: '/services');

      await tester.tap(_navItem('Search'));
      await tester.pumpAndSettle();

      expect(announcements.messages, isEmpty);
    });

    testWidgets('switching tabs fires one selection haptic, not two', (
      tester,
    ) async {
      // The bar used to fire a selection click of its own on top of the shell's,
      // so a tab change buzzed twice.
      final haptics = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments as String);
            }
            return null;
          });

      await _pumpShell(tester, initialLocation: '/services');
      haptics.clear();

      await tester.tap(_navItem('Search'));
      await tester.pumpAndSettle();

      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('tapping the current Settings tab does not trigger refresh', (
      tester,
    ) async {
      final harness = await _pumpShell(tester, initialLocation: '/settings');

      await tester.tap(_navItem('Settings'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/settings');
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.services),
        ),
        0,
      );
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.activity),
        ),
        0,
      );
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.search),
        ),
        0,
      );
    });
  });

  group('ShellScreen at rail width', () {
    testWidgets('still observes the app lifecycle', (tester) async {
      // The rail branch used to return a bare Scaffold outside
      // ReleaseSearchLifecycle, so on macOS and tablet nothing observed the
      // lifecycle at all: appInForegroundProvider stayed permanently true, and a
      // search the OS killed while the app was away was blamed on the network
      // instead of on leaving Cupola.
      final harness = await _pumpShell(tester, viewport: _railViewport);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(ReleaseSearchLifecycle), findsOneWidget);
      expect(harness.container.read(appInForegroundProvider), isTrue);

      await _sendLifecycle(tester, AppLifecycleState.paused);
      expect(harness.container.read(appInForegroundProvider), isFalse);

      await _sendLifecycle(tester, AppLifecycleState.resumed);
      expect(harness.container.read(appInForegroundProvider), isTrue);
    });

    testWidgets('crossing the breakpoint keeps one observer, not two', (
      tester,
    ) async {
      // The lifecycle wrapper sits above the layout branch precisely so that
      // dragging a window past 840pt does not mount or unmount the observer
      // mid-session.
      final harness = await _pumpShell(tester, viewport: _railViewport);
      expect(find.byType(ReleaseSearchLifecycle), findsOneWidget);

      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpAndSettle();

      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(find.byType(ReleaseSearchLifecycle), findsOneWidget);

      await _sendLifecycle(tester, AppLifecycleState.paused);
      expect(harness.container.read(appInForegroundProvider), isFalse);
    });

    testWidgets('shows the finished-search badge the bottom bar shows', (
      tester,
    ) async {
      // The badge is the channel that has to keep working when notifications
      // are denied, off, or missed — and the rail was the one surface where it
      // never appeared, because it built its destinations itself.
      await _pumpShell(
        tester,
        viewport: _railViewport,
        overrides: [unseenReleaseSearchCountProvider.overrideWithValue(3)],
      );

      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byType(Badge),
        ),
        findsOneWidget,
      );
      // A number painted on an icon is invisible to a screen reader, so it has
      // to reach the spoken label too — the same string the bottom bar speaks.
      final activityLabel = tester.widget<Text>(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Activity'),
        ),
      );
      expect(
        activityLabel.semanticsLabel,
        'Activity, 3 finished searches to look at',
      );
    });

    testWidgets('no waiting searches means no badge', (tester) async {
      await _pumpShell(tester, viewport: _railViewport);

      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byType(Badge),
        ),
        findsNothing,
      );
    });
  });
}

/// Wide enough for the rail: the breakpoint is Material's 840pt expanded window.
const Size _railViewport = Size(1200, 900);

/// Drives the real lifecycle channel rather than calling the binding's
/// protected handler, so the test exercises the same path the platform uses.
Future<void> _sendLifecycle(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
  await tester.pumpAndSettle();
}

Future<_ShellHarness> _pumpShell(
  WidgetTester tester, {
  String initialLocation = '/services',
  // Phone width by default, so the shell renders the FloatingBottomNavBar rather
  // than the wide-window NavigationRail (the rail breakpoint is 840).
  Size viewport = const Size(400, 900),
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(overrides: overrides);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/services',
            builder: (_, __) => const Scaffold(body: Text('ServicesPage')),
          ),
          GoRoute(
            path: '/activity',
            builder: (_, __) => const Scaffold(body: Text('ActivityPage')),
          ),
          GoRoute(
            path: '/search',
            builder: (_, __) => const Scaffold(body: Text('SearchPage')),
          ),
          GoRoute(
            path: '/services/radarr/movie/:id',
            builder: (_, __) => const Scaffold(body: Text('MovieDetailPage')),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Scaffold(body: Text('SettingsPage')),
          ),
          GoRoute(
            path: '/outside',
            builder: (_, __) => const Scaffold(body: Text('OutsidePage')),
          ),
        ],
      ),
    ],
  );

  addTearDown(() {
    router.dispose();
    container.dispose();
  });

  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  return _ShellHarness(container: container, router: router);
}

Finder _navItem(String label) {
  return find.descendant(
    of: find.byType(FloatingBottomNavBar),
    matching: find.byKey(ValueKey('floating-nav-item-${label.toLowerCase()}')),
  );
}

class _ShellHarness {
  const _ShellHarness({required this.container, required this.router});

  final ProviderContainer container;
  final GoRouter router;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/features/shell/presentation/shell_screen.dart';

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
}

Future<_ShellHarness> _pumpShell(
  WidgetTester tester, {
  String initialLocation = '/services',
}) async {
  final container = ProviderContainer();
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

  // Use a phone-width viewport so the shell renders the FloatingBottomNavBar
  // rather than the wide-screen NavigationRail (rail breakpoint is 600).
  tester.view.physicalSize = const Size(400, 900);
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

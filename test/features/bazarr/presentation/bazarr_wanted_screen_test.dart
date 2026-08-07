import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';

void main() {
  group('BazarrWantedScreen when Bazarr is not configured', () {
    // Wanted is deep-linkable, so it is reachable with Bazarr unconfigured
    // without ever passing the dashboard. It used to answer with a bare
    // sentence — no icon, no button, no route — while the dashboard one screen
    // over offered the shared placeholder and its deep link.
    testWidgets('renders the shared placeholder rather than a private notice', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
          ],
          child: const MaterialApp(home: BazarrWantedScreen()),
        ),
      );
      await tester.pump();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.textContaining("isn't set up"), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets('its button lands on the Bazarr settings page', (tester) async {
      // `.forService` and the generic constructor paint the same strings; the
      // deep link is the only thing that separates them, and the dead end this
      // replaced is precisely the absence of one.
      final router = GoRouter(
        initialLocation: '/services/bazarr/wanted',
        routes: [
          GoRoute(
            path: '/services/bazarr/wanted',
            builder: (context, state) => const BazarrWantedScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SizedBox.shrink(),
            routes: [
              GoRoute(
                path: 'service/:service',
                builder: (context, state) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/settings/service/${ServiceKey.bazarr.routeParam}',
      );
    });
  });
}

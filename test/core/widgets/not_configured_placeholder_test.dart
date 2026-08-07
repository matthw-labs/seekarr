import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Where the "isn't set up" button lands.
///
/// This is the invariant that was silently lost when five dashboards' private
/// not-configured cards were collapsed onto the shared widget: each private copy
/// deep-linked to `/settings/service/<routeParam>`, and the generic constructor
/// goes to the Settings root. A user who taps "Open Settings" from the SABnzbd
/// dashboard should land on the SABnzbd form, not on a list to search.
void main() {
  Future<String> pumpAndTap(WidgetTester tester, Widget placeholder) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (context, state) => placeholder),
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

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    return router.state.uri.toString();
  }

  testWidgets('the service form opens that service settings page', (
    tester,
  ) async {
    final location = await pumpAndTap(
      tester,
      NotConfiguredPlaceholder.forService(ServiceKey.sabnzbd),
    );

    expect(location, '/settings/service/${ServiceKey.sabnzbd.routeParam}');
  });

  testWidgets('the service form names the service it was given', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: NotConfiguredPlaceholder.forService(ServiceKey.nzbget)),
    );

    expect(find.textContaining(ServiceKey.nzbget.title), findsOneWidget);
  });

  testWidgets('the generic form falls back to the settings root', (
    tester,
  ) async {
    // AsyncValueWidget and MediaDetailPlaceholderView reach this state from a
    // `<Service> not configured` throw and hold only the name, so the root is
    // the only honest destination for them.
    final location = await pumpAndTap(
      tester,
      const NotConfiguredPlaceholder(serviceName: 'Radarr'),
    );

    expect(location, '/settings');
  });
}

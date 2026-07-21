import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/presentation/settings_services_screen.dart';

void main() {
  group('SettingsServicesScreen', () {
    testWidgets('renders services in a grouped settings card', (tester) async {
      await _pumpServicesScreen(
        tester,
        settings: const SettingsModel(
          seerrUrl: 'https://seerr.local',
          radarrUrl: 'https://radarr.local:7878',
        ),
      );

      expect(find.text('Services'), findsOneWidget);
      // One grouped card per service domain (media, downloads, infrastructure).
      expect(find.byType(SettingsGroupCard), findsNWidgets(3));
      expect(find.byType(SettingsCard), findsNWidgets(13));
      expect(find.text('seerr.local'), findsOneWidget);
      expect(find.text('radarr.local:7878'), findsOneWidget);
      expect(find.text('Not configured'), findsNWidgets(11));
      expect(_textColor(tester, 'radarr.local:7878'), isNot(AppColors.radarr));
    });

    testWidgets('tapping a service row navigates to the service route', (
      tester,
    ) async {
      await _pumpServicesScreen(tester);

      await tester.tap(find.text('Lidarr'));
      await tester.pumpAndSettle();

      expect(find.text('ServicePage:lidarr'), findsOneWidget);
    });
  });
}

Color? _textColor(WidgetTester tester, String text) {
  final textWidget = tester.widget<Text>(find.text(text));
  return textWidget.style?.color;
}

Future<void> _pumpServicesScreen(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
}) async {
  final router = GoRouter(
    initialLocation: '/settings/services',
    routes: [
      GoRoute(
        path: '/settings/services',
        builder: (_, __) => const SettingsServicesScreen(),
      ),
      GoRoute(
        path: '/settings/service/:service',
        builder: (context, state) {
          final service = state.pathParameters['service'] ?? 'unknown';
          return Scaffold(body: Text('ServicePage:$service'));
        },
      ),
    ],
  );

  addTearDown(router.dispose);

  // The screen is a lazy ListView; use a tall viewport so every domain card and
  // service row is built and counted, independent of scroll position.
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentSettingsProvider.overrideWith((ref) => settings)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

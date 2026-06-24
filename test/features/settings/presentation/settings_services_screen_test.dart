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
      expect(find.byType(SettingsGroupCard), findsOneWidget);
      expect(find.byType(SettingsCard), findsNWidgets(6));
      expect(find.text('seerr.local'), findsOneWidget);
      expect(find.text('radarr.local:7878'), findsOneWidget);
      expect(find.text('Not configured'), findsNWidgets(4));
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

  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentSettingsProvider.overrideWith((ref) => settings)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

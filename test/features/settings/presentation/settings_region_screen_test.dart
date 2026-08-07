import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/regions.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/settings_region_screen.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_choice_row.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

void main() {
  group('SettingsRegionScreen', () {
    testWidgets('renders the title, description, and all common regions', (
      tester,
    ) async {
      await _pumpRegionScreen(tester);

      expect(find.text('Region'), findsOneWidget);
      expect(find.textContaining('Release dates'), findsOneWidget);

      expect(find.byType(SettingsChoiceRow), findsWidgets);
      expect(find.text('Russia (RU)'), findsOneWidget);
    });

    // No ensureSemantics()/dispose() ceremony in these: testWidgets already
    // enables semantics and owns the handle. Doing it by hand here was the
    // pattern the next author would copy, and it would fail under addTearDown —
    // handle verification runs before tearDowns.
    testWidgets('selects US by default', (tester) async {
      await _pumpRegionScreen(tester);

      expect(
        tester.getSemantics(_regionTile('US')),
        containsSemantics(hasCheckedState: true, isChecked: true),
      );
    });

    testWidgets('normalizes configured regions to uppercase', (tester) async {
      await _pumpRegionScreen(
        tester,
        settings: const SettingsModel(region: 'jp'),
      );

      expect(
        tester.getSemantics(_regionTile('JP')),
        containsSemantics(hasCheckedState: true, isChecked: true),
      );
    });

    testWidgets('renders region labels in the expected format', (tester) async {
      await _pumpRegionScreen(tester);

      expect(find.text('United States (US)'), findsOneWidget);
      expect(find.text('United Kingdom (GB)'), findsOneWidget);

      expect(find.text('Japan (JP)'), findsOneWidget);
    });

    testWidgets('tapping a region updates settings state', (tester) async {
      final harness = await _pumpRegionScreen(tester);

      await tester.tap(find.text('Japan (JP)'));
      await tester.pumpAndSettle();

      expect(harness.container.read(settingsProvider).region, 'JP');

      expect(
        tester.getSemantics(_regionTile('JP')),
        containsSemantics(hasCheckedState: true, isChecked: true),
      );
    });
  });
}

Future<_SettingsHarness> _pumpRegionScreen(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = SettingsService(prefs, FakeSecureSettingsStore());

  final container = ProviderContainer(
    overrides: [
      initialSettingsProvider.overrideWith((ref) => settings),
      settingsServiceProvider.overrideWith((ref) => service),
    ],
  );

  addTearDown(container.dispose);

  // Thirty regions in a lazy ListView: a tall viewport keeps every row built,
  // so the tests assert on content rather than on scroll position.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsRegionScreen()),
    ),
  );
  await tester.pumpAndSettle();

  return _SettingsHarness(container);
}

Finder _regionTile(String code) {
  final label = '${commonRegions[code]} ($code)';
  return find.byWidgetPredicate(
    (widget) => widget is SettingsChoiceRow && widget.label == label,
    skipOffstage: false,
  );
}

class _SettingsHarness {
  const _SettingsHarness(this.container);

  final ProviderContainer container;
}

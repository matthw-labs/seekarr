import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _configured = SettingsModel(nzbgetUrl: 'http://nzbget.local:6789');

/// See the SABnzbd screen test: `FilledButton.tonalIcon` builds a private
/// subclass, which `find.byType` cannot see.
Finder _buttonWithText(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is FilledButton),
);

List<Override> _ambient() => [
  serviceSummaryProvider.overrideWith(
    (ref, service) async => ServiceSummary(
      service: service,
      status: ServiceSummaryStatus.online,
      host: 'nzbget.local:6789',
      version: '21.1',
    ),
  ),
  serviceKpiProvider.overrideWith((ref, service) async => const <ServiceKpi>[]),
  nzbgetQueueProvider.overrideWith((ref) async => const <NzbgetGroup>[]),
  nzbgetHistoryProvider.overrideWith(
    (ref) async => const <NzbgetHistoryItem>[],
  ),
];

void main() {
  testWidgets('an unconfigured NZBGet renders the shared placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: const MaterialApp(home: NzbgetScreen()),
      ),
    );

    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
  });

  testWidgets('the pause toggle is inert until the status is known', (
    tester,
  ) async {
    // Regression: `asData?.value.paused ?? false` rendered "Pause all" for the
    // whole first load, so a tap in that window sent `pausedownload()` to a
    // client that was already paused.
    final gate = Completer<NzbgetStatus>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          nzbgetStatusProvider.overrideWith((ref) => gate.future),
        ],
        child: const MaterialApp(home: NzbgetScreen()),
      ),
    );
    await tester.pump();

    final toggle = _buttonWithText('Pause all');
    expect(toggle, findsOneWidget);
    expect(tester.widget<FilledButton>(toggle).onPressed, isNull);

    gate.complete(
      const NzbgetStatus(
        downloadRateBytes: 0,
        remainingSizeMb: 0,
        paused: true,
      ),
    );
    await tester.pumpAndSettle();

    final resume = _buttonWithText('Resume all');
    expect(resume, findsOneWidget);
    expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
  });
}

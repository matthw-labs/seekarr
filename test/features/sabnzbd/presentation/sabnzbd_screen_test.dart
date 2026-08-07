import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _configured = SettingsModel(
  sabnzbdUrl: 'http://sab.local:8080',
  sabnzbdApiKey: 'key',
);

SabnzbdQueue _queue({bool paused = false}) => SabnzbdQueue(
  paused: paused,
  status: paused ? 'Paused' : 'Downloading',
  kbPerSec: 2048,
  mbLeft: 1500,
  mb: 3000,
  timeLeft: '0:12:30',
  slots: const [],
);

/// Finds the queue toggle by its label.
///
/// `find.widgetWithText(FilledButton, …)` cannot see it: `FilledButton.tonalIcon`
/// builds a private subclass, and `find.byType` matches the exact runtime type.
Finder _buttonWithText(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is FilledButton),
);

/// The dashboard's ambient dependencies, stubbed so the screen under test is
/// the only thing doing any work.
List<Override> _ambient() => [
  serviceSummaryProvider.overrideWith(
    (ref, service) async => ServiceSummary(
      service: service,
      status: ServiceSummaryStatus.online,
      host: 'sab.local:8080',
      version: '4.2.0',
    ),
  ),
  serviceKpiProvider.overrideWith((ref, service) async => const <ServiceKpi>[]),
  sabnzbdHistoryProvider.overrideWith(
    (ref) async => const <SabnzbdHistorySlot>[],
  ),
];

void main() {
  testWidgets('an unconfigured SABnzbd renders the shared placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );

    // The private copy this replaced was one of four near-identical cards; the
    // shared widget is the state's single home.
    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
  });

  testWidgets('the pause toggle is inert until the queue state is known', (
    tester,
  ) async {
    // Regression: `queueAsync.asData?.value.paused ?? false` meant an
    // already-paused queue rendered "Pause all" for the whole first load, and a
    // tap in that window sent pause() to a queue that was already paused.
    final gate = Completer<SabnzbdQueue>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          sabnzbdQueueProvider.overrideWith((ref) => gate.future),
          sabnzbdCategoriesProvider.overrideWith(
            (ref) async => const <String>[],
          ),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );
    await tester.pump();

    final toggle = _buttonWithText('Pause all');
    expect(toggle, findsOneWidget);
    expect(tester.widget<FilledButton>(toggle).onPressed, isNull);

    // Once the queue answers, the toggle tells the truth and becomes live.
    gate.complete(_queue(paused: true));
    await tester.pumpAndSettle();

    final resume = _buttonWithText('Resume all');
    expect(resume, findsOneWidget);
    expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
  });

  testWidgets('the add-NZB dialog shows categories the moment they arrive', (
    tester,
  ) async {
    // Regression: the dialog did `ref.read(sabnzbdCategoriesProvider)
    // .asData?.value` on a provider nothing else watches, so on first open it
    // was cold — the read returned AsyncLoading with no value, the dropdown was
    // hidden entirely, and the NZB was submitted with no category. The captured
    // local was never re-read either, so the dropdown stayed hidden even when
    // the fetch landed while the dialog was still open.
    final gate = Completer<List<String>>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          sabnzbdQueueProvider.overrideWith((ref) async => _queue()),
          sabnzbdCategoriesProvider.overrideWith((ref) => gate.future),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add NZB'));
    await tester.pumpAndSettle();

    // Cold on open: the dialog says so rather than silently dropping the field.
    expect(find.text('Loading categories…'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    // The fetch lands while the dialog is still open — and the dialog notices.
    gate.complete(const ['*', 'movies', 'tv']);
    await tester.pumpAndSettle();

    expect(find.text('Loading categories…'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });

  testWidgets('a category-less SABnzbd shows no dropdown at all', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _configured),
          ..._ambient(),
          sabnzbdQueueProvider.overrideWith((ref) async => _queue()),
          sabnzbdCategoriesProvider.overrideWith(
            (ref) async => const <String>[],
          ),
        ],
        child: const MaterialApp(home: SabnzbdScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add NZB'));
    await tester.pumpAndSettle();

    expect(find.text('Add NZB by URL'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Loading categories…'), findsNothing);
  });
}

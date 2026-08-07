import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_movie_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_bazarr_service.dart';

const _settings = SettingsModel(
  bazarrUrl: 'http://bazarr.local',
  bazarrApiKey: 'key',
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeBazarrService fake,
  SettingsModel settings = _settings,
  int radarrId = 42,
  BazarrWantedItem? initialWanted,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      // Disable Riverpod's automatic retry so a thrown provider settles into
      // AsyncError instead of looping through retry-loading in the test.
      retry: (retryCount, error) => null,
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        bazarrServiceProvider.overrideWith((ref) => fake),
      ],
      child: MaterialApp(
        home: BazarrMovieDetailScreen(
          radarrId: radarrId,
          initialWanted: initialWanted,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

FakeBazarrService _fakeWithMovie() {
  return FakeBazarrService()
    ..movieByIdOverride = const BazarrMovie(
      radarrId: 42,
      title: 'Dune',
      year: 2021,
      monitored: true,
      profileId: 1,
      path: '/movies/Dune',
      tags: ['scifi'],
    )
    ..wantedMovieByIdOverride = const BazarrWantedItem(
      title: 'Dune',
      radarrId: 42,
      missingLanguages: [
        BazarrSubtitleLanguage(code2: 'it', name: 'Italian'),
        BazarrSubtitleLanguage(code2: 'en', name: 'English'),
      ],
    );
}

void main() {
  testWidgets('shows the shared loading view while the lookup runs', (
    tester,
  ) async {
    final never = Completer<BazarrMovie?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _settings),
          bazarrServiceProvider.overrideWith((ref) => FakeBazarrService()),
          bazarrMovieByIdProvider.overrideWith((ref, arg) => never.future),
        ],
        child: const MaterialApp(home: BazarrMovieDetailScreen(radarrId: 42)),
      ),
    );
    await tester.pump();
    expect(find.byType(MediaDetailLoadingView), findsOneWidget);
  });

  testWidgets('renders the shared detail scaffold with movie data', (
    tester,
  ) async {
    await _pumpScreen(tester, fake: _fakeWithMovie());

    expect(find.byType(MediaDetailView), findsOneWidget);
    // Hero summary + collapsed bar both carry the title.
    expect(find.text('Dune'), findsWidgets);
    expect(find.text('MISSING SUBTITLES'), findsOneWidget);
    expect(find.text('IT'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('Italian'), findsOneWidget);
    expect(find.text('DETAILS'), findsOneWidget);
    expect(find.text('Monitored'), findsWidgets);
    // The one page in the app where "Tags" is true: these are real Bazarr tags.
    expect(find.text('TAGS'), findsOneWidget);
    expect(find.text('scifi'), findsOneWidget);
    // Exactly one claimant on the pull gesture: the spine owns the indicator
    // now, so this screen no longer wraps a second one of its own around a view
    // that also stretches its hero backdrop on the same overscroll.
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('speaks the language name, not the uppercase code', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpScreen(tester, fake: _fakeWithMovie());

    expect(find.semantics.byLabel('Italian'), findsOne);
    handle.dispose();
  });

  testWidgets('celebrates full coverage when nothing is wanted', (
    tester,
  ) async {
    final fake = FakeBazarrService()
      ..movieByIdOverride = const BazarrMovie(
        radarrId: 42,
        title: 'Dune',
        monitored: true,
      );
    await _pumpScreen(tester, fake: fake);

    expect(find.text('All languages covered'), findsOneWidget);
  });

  testWidgets('falls back to the wanted item while the lookup misses', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      fake: FakeBazarrService(),
      radarrId: 999,
      initialWanted: const BazarrWantedItem(title: 'Custom Movie'),
    );

    expect(find.text('Custom Movie'), findsWidgets);
    expect(find.byType(MediaDetailLoadingView), findsNothing);
  });

  testWidgets('shows the not-found empty state for an unknown id', (
    tester,
  ) async {
    await _pumpScreen(tester, fake: FakeBazarrService(), radarrId: 999);

    expect(find.text('Movie not found in Bazarr'), findsOneWidget);
    expect(find.byType(AppEmptyState), findsOneWidget);
  });

  testWidgets('shows the not-configured placeholder without settings', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      fake: FakeBazarrService(),
      settings: const SettingsModel(),
    );

    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
  });

  testWidgets('retries the wanted section from its error state', (
    tester,
  ) async {
    final fake = _fakeWithMovie()..throwOnWanted = Exception('boom');
    await _pumpScreen(tester, fake: fake);

    expect(find.byType(AppErrorState), findsOneWidget);
    final callsBefore = fake.wantedMoviesCalls;

    fake.throwOnWanted = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.wantedMoviesCalls, greaterThan(callsBefore));
    expect(find.text('IT'), findsOneWidget);
  });

  testWidgets('the hero lead carries the page figure, not a fake poster', (
    tester,
  ) async {
    await _pumpScreen(tester, fake: _fakeWithMovie());

    // Bazarr has no poster and no backdrop *by definition*, so the 82x123 slot
    // used to hold a poster card with no image, rendering a film reel above the
    // only question the page answers. It now holds the answer.
    final plate = tester.widget<MediaDetailFigurePlate>(
      find.byType(MediaDetailFigurePlate),
    );
    expect(plate.label, 'Missing');

    // No Hero in this lead: a Bazarr list row has no poster to fly from, and an
    // orphan flight materialises out of nothing.
    expect(
      find.descendant(
        of: find.byType(MediaDetailFigurePlate),
        matching: find.byType(Hero),
      ),
      findsNothing,
    );
  });

  testWidgets('the refresh control names the side it re-reads', (tester) async {
    await _pumpScreen(tester, fake: _fakeWithMovie());

    // A bare "Refresh" on a page whose whole subject is what another service
    // has not done yet leaves the user guessing whether it re-checks Bazarr or
    // asks Bazarr to go hunting.
    final refresh = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.refresh_rounded),
    );
    expect(refresh.tooltip, 'Refresh from Bazarr');
  });

  testWidgets('a wanted movie with no languages says whose gap it is', (
    tester,
  ) async {
    final fake = FakeBazarrService()
      ..movieByIdOverride = const BazarrMovie(
        radarrId: 42,
        title: 'Dune',
        monitored: true,
      )
      ..wantedMovieByIdOverride = const BazarrWantedItem(
        title: 'Dune',
        radarrId: 42,
        missingLanguages: [],
      );
    await _pumpScreen(tester, fake: fake);

    // "No language data available" reported the app's own gap rather than the
    // server's, and gave a self-hoster nothing to go and check.
    expect(find.text('No languages listed'), findsOneWidget);
    expect(find.text('No language data available'), findsNothing);
    expect(find.textContaining('language profile'), findsOneWidget);
  });
}

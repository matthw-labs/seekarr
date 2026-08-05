import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/bazarr/data/bazarr_service.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_series_detail_screen.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/bazarr/presentation/widgets/bazarr_detail_sections.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_bazarr_service.dart';

const _settings = SettingsModel(
  bazarrUrl: 'http://bazarr.local',
  bazarrApiKey: 'key',
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required FakeBazarrService fake,
  SettingsModel settings = _settings,
  int sonarrSeriesId = 7,
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
        home: BazarrSeriesDetailScreen(
          sonarrSeriesId: sonarrSeriesId,
          initialWanted: initialWanted,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}

FakeBazarrService _fakeWithSeries({List<BazarrWantedItem>? wanted}) {
  return FakeBazarrService()
    ..seriesByIdOverride = const BazarrSeries(
      sonarrSeriesId: 7,
      title: 'Foundation',
      year: 2021,
      monitored: true,
      episodeMissingCount: 2,
      episodeCount: 10,
      profileId: 1,
    )
    ..wantedEpisodesForSeriesResult =
        wanted ??
        const [
          BazarrWantedItem(
            seriesTitle: 'Foundation',
            episodeTitle: 'The Emperor',
            episodeNumber: '1x01',
            sonarrSeriesId: 7,
            missingLanguages: [BazarrSubtitleLanguage(code2: 'en')],
          ),
        ];
}

/// Counts the paged series lookup so a retry can be observed re-running it.
class _CountingBazarrService extends FakeBazarrService {
  int getSeriesCalls = 0;

  @override
  Future<BazarrPagedResult<BazarrSeries>> getSeries({
    int start = 0,
    int length = 50,
  }) {
    getSeriesCalls++;
    return super.getSeries(start: start, length: length);
  }
}

void main() {
  testWidgets('renders the shared detail scaffold with series data', (
    tester,
  ) async {
    await _pumpScreen(tester, fake: _fakeWithSeries());

    expect(find.byType(MediaDetailView), findsOneWidget);
    expect(find.text('Foundation'), findsWidgets);
    expect(find.text('MISSING SUBTITLES'), findsOneWidget);
    expect(find.text('The Emperor'), findsOneWidget);

    // On the shared dense-row primitive now, so the episode code is the ordinal
    // column rather than a second line reading "Episode 1x01", and the missing
    // languages are stated in words instead of as a colour-only badge.
    expect(find.text('1x01'), findsOneWidget);
    expect(find.textContaining('Missing'), findsWidgets);
    expect(
      tester.getSemantics(find.byType(BazarrWantedEpisodeTile)),
      containsSemantics(label: 'Episode 1x01, The Emperor, Missing en'),
    );
    // The uppercase `EN` badge is gone with the hand-rolled row: the language is
    // now part of the row's own facts line, which a sighted low-vision user can
    // read and a screen reader speaks.
    expect(find.text('EN'), findsNothing);
    expect(find.text('Missing en'), findsOneWidget);
    expect(find.text('DETAILS'), findsOneWidget);
    // The missing count is stated once in words, in the hero's chip slot — the
    // figure plate beside it is the same fact as a glanceable numeral and is
    // silent to assistive technology.
    expect(find.text('2 missing'), findsOneWidget);
  });

  testWidgets('falls back to the wanted item while the lookup misses', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      fake: FakeBazarrService(),
      sonarrSeriesId: 999,
      initialWanted: const BazarrWantedItem(
        seriesTitle: 'Custom Series',
        episodeNumber: '1x01',
        sonarrSeriesId: 999,
      ),
    );

    expect(find.text('Custom Series'), findsWidgets);
  });

  testWidgets('shows the not-found empty state for an unknown id', (
    tester,
  ) async {
    final fake = _CountingBazarrService();
    await _pumpScreen(tester, fake: fake, sonarrSeriesId: 999);

    expect(find.text('Series not found in Bazarr'), findsOneWidget);

    // Bazarr learns about a series on its next Sonarr sync, so the page offers
    // a way to look again instead of ending the road here.
    final callsBefore = fake.getSeriesCalls;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.getSeriesCalls, greaterThan(callsBefore));
  });

  testWidgets('a failed series lookup is retryable, not a dead end', (
    tester,
  ) async {
    final fake = FakeBazarrService()..throwOnCall = Exception('boom');
    await _pumpScreen(tester, fake: fake, sonarrSeriesId: 7);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text("Couldn't load Bazarr"), findsOneWidget);

    fake
      ..throwOnCall = null
      ..seriesByIdOverride = const BazarrSeries(
        sonarrSeriesId: 7,
        title: 'Foundation',
        year: 2021,
        monitored: true,
        episodeMissingCount: 2,
        episodeCount: 10,
        profileId: 1,
      );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Foundation'), findsWidgets);
  });

  testWidgets('celebrates full coverage when nothing is wanted', (
    tester,
  ) async {
    await _pumpScreen(tester, fake: _fakeWithSeries(wanted: const []));

    expect(find.text('All languages covered'), findsOneWidget);
  });

  testWidgets('builds the wanted list lazily in a sliver', (tester) async {
    final many = [
      for (var i = 1; i <= 40; i++)
        BazarrWantedItem(
          seriesTitle: 'Foundation',
          episodeTitle: 'Episode title $i',
          episodeNumber: '1x$i',
          sonarrSeriesId: 7,
          missingLanguages: const [BazarrSubtitleLanguage(code2: 'en')],
        ),
    ];
    await _pumpScreen(tester, fake: _fakeWithSeries(wanted: many));

    final built = find.byType(BazarrWantedEpisodeTile);
    expect(built, findsWidgets);
    expect(
      tester.widgetList(built).length,
      lessThan(40),
      reason: 'off-screen wanted episodes must not be built eagerly',
    );
  });

  testWidgets('retries the wanted section from its error state', (
    tester,
  ) async {
    final fake = _fakeWithSeries()..throwOnWanted = Exception('boom');
    await _pumpScreen(tester, fake: fake);

    expect(find.byType(AppErrorState), findsOneWidget);
    final callsBefore = fake.wantedEpisodesCalls;

    fake.throwOnWanted = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.wantedEpisodesCalls, greaterThan(callsBefore));
    expect(find.text('The Emperor'), findsOneWidget);
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
}

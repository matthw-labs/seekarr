import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_detail_view_model.dart';

void main() {
  group('BazarrDetailViewModel.forMovie', () {
    test('resolves display fields from the library record', () {
      final vm = BazarrDetailViewModel.forMovie(
        const BazarrMovie(
          radarrId: 42,
          title: 'Dune',
          year: 2021,
          monitored: true,
          profileId: 3,
          path: '/movies/Dune',
          tags: ['scifi'],
          missingLanguages: [BazarrSubtitleLanguage(code2: 'it')],
        ),
        null,
      );

      expect(vm.title, 'Dune');
      expect(vm.profileLabel, 'Profile #3');
      expect(vm.tags, ['scifi']);
      expect(vm.found, isTrue);
      expect(vm.facts.map((f) => f.label), contains('Path'));
    });

    test('owns the missing count both screens read three times over', () {
      // Previously each screen re-derived this from the same
      // `movie ?? fallback` cascade the view model already runs — two copies of
      // one rule, feeding the figure plate, the hero chip and the empty state.
      final fromMovie = BazarrDetailViewModel.forMovie(
        const BazarrMovie(
          radarrId: 42,
          title: 'Dune',
          monitored: true,
          missingLanguages: [
            BazarrSubtitleLanguage(code2: 'it'),
            BazarrSubtitleLanguage(code2: 'fr'),
            BazarrSubtitleLanguage(code2: 'de'),
          ],
        ),
        null,
      );
      expect(fromMovie.missing, 3);

      // The fallback carries it when there is no library record yet.
      final fromFallback = BazarrDetailViewModel.forMovie(
        null,
        const BazarrWantedItem(
          title: 'Fallback',
          missingLanguages: [
            BazarrSubtitleLanguage(code2: 'it'),
            BazarrSubtitleLanguage(code2: 'fr'),
          ],
        ),
      );
      expect(fromFallback.missing, 2);

      expect(BazarrDetailViewModel.forMovie(null, null).missing, 0);
    });

    test('cascades to the wanted fallback, then the constant', () {
      final fromFallback = BazarrDetailViewModel.forMovie(
        null,
        const BazarrWantedItem(title: 'Fallback Movie'),
      );
      expect(fromFallback.title, 'Fallback Movie');
      expect(fromFallback.found, isTrue);

      final fromNothing = BazarrDetailViewModel.forMovie(null, null);
      expect(fromNothing.title, 'Unknown movie');
      expect(fromNothing.found, isFalse);
    });
  });

  group('BazarrDetailViewModel.forSeries', () {
    test('resolves display fields including episode facts', () {
      final vm = BazarrDetailViewModel.forSeries(
        const BazarrSeries(
          sonarrSeriesId: 7,
          title: 'Foundation',
          year: 2021,
          monitored: true,
          episodeMissingCount: 2,
          episodeCount: 10,
          profileId: 1,
        ),
        null,
      );

      expect(vm.title, 'Foundation');
      expect(vm.missing, 2);
      expect(vm.facts.map((f) => f.label), contains('Episodes'));
    });

    test('uses seriesTitle from the wanted fallback', () {
      final vm = BazarrDetailViewModel.forSeries(
        null,
        const BazarrWantedItem(seriesTitle: 'Custom Series'),
      );
      expect(vm.title, 'Custom Series');
      expect(vm.missing, 0);
    });
  });
}

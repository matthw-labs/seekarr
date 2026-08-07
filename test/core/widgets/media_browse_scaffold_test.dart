import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

final testSearchQueryProvider = StateProvider<String>((ref) => '');
final testLibraryProvider = FutureProvider<List<String>>(
  (ref) async => ['Alpha', 'Beta'],
);
final testSearchResultsProvider = FutureProvider<List<String>?>(
  (ref) async => null,
);

void main() {
  group('mediaBrowseFilterMatches', () {
    test('every availability answers to a chip, the unreleased one aside', () {
      for (final availability in MediaAvailability.values) {
        final status = MediaStatusInfo(availability: availability);
        final underAvailable = mediaBrowseFilterMatches(
          MediaBrowseFilter.available,
          status,
        );
        final underMissing = mediaBrowseFilterMatches(
          MediaBrowseFilter.missing,
          status,
        );

        if (availability == MediaAvailability.unavailable) {
          // The one deliberate exception: an unreleased title is not a gap
          // anyone can close, so it answers to `All` alone.
          expect(underAvailable, isFalse, reason: '$availability');
          expect(underMissing, isFalse, reason: '$availability');
          continue;
        }

        // Exactly one, never both and never neither — otherwise an item is
        // either double-counted or invisible under every chip but `All`.
        expect(underAvailable ^ underMissing, isTrue, reason: '$availability');
      }
    });

    test('an unresolved or departed item is a gap, not nothing at all', () {
      // `sonarrSeriesAvailability` returns `unknown` whenever the server omits
      // `statistics`, which is what a freshly added series looks like.
      for (final availability in const [
        MediaAvailability.unknown,
        MediaAvailability.deleted,
        MediaAvailability.notTracked,
        MediaAvailability.missing,
      ]) {
        expect(
          mediaBrowseBucketOf(MediaStatusInfo(availability: availability)),
          MediaBrowseBucket.gap,
          reason: '$availability',
        );
      }
    });

    test('a partial manifest counts as on disk', () {
      for (final availability in const [
        MediaAvailability.available,
        MediaAvailability.upgradable,
        MediaAvailability.partial,
      ]) {
        expect(
          mediaBrowseBucketOf(MediaStatusInfo(availability: availability)),
          MediaBrowseBucket.onDisk,
          reason: '$availability',
        );
      }
    });

    test('a screen with no status extractor sees gaps', () {
      expect(mediaBrowseFilterMatches(MediaBrowseFilter.all, null), isTrue);
      expect(mediaBrowseFilterMatches(MediaBrowseFilter.missing, null), isTrue);
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.available, null),
        isFalse,
      );
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.inQueue, null),
        isFalse,
      );
    });

    test('what is moving is a different question from what is on disk', () {
      const downloading = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
      );
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.inQueue, downloading),
        isTrue,
      );
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.missing, downloading),
        isTrue,
      );
    });
  });

  group('MediaBrowseScaffold', () {
    testWidgets('renders title in AppBar', (tester) async {
      await tester.pumpWidget(_buildTestApp());

      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('renders SearchBarHeader', (tester) async {
      await tester.pumpWidget(_buildTestApp());

      expect(find.byType(SearchBarHeader), findsOneWidget);
    });

    testWidgets('shows activity button', (tester) async {
      await tester.pumpWidget(_buildTestApp());

      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('shows grouped browse content and filters by default', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.byType(MediaGrid<String>), findsNothing);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);
      expect(find.text('In Queue'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('media-browse-section-A')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('media-browse-section-B')),
        findsOneWidget,
      );
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('shows back arrow when searching', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);
      container.read(testSearchQueryProvider.notifier).state = 'test query';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: _buildTestScaffold()),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets(
      'switches from library mode to search results when query becomes non-empty',
      (tester) async {
        final searchQueryProvider = StateProvider<String>((ref) => '');
        final libraryProvider = FutureProvider<List<String>>(
          (ref) async => ['Library Item'],
        );
        final searchResultsProvider = FutureProvider<List<String>?>((
          ref,
        ) async {
          final query = ref.watch(searchQueryProvider);
          return query.isEmpty ? null : ['Search Result'];
        });
        final container = ProviderContainer(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
          ],
        );
        addTearDown(container.dispose);

        String? tappedItem;
        String? tappedHeroTag;

        await tester.pumpWidget(
          _buildCustomTestApp(
            container: container,
            libraryProvider: libraryProvider,
            searchQueryProvider: searchQueryProvider,
            searchResultsProvider: searchResultsProvider,
            titleExtractor: (item) => item,
            onItemTap: (_, item, heroTag) {
              tappedItem = item;
              tappedHeroTag = heroTag;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Library Item'));
        await tester.pump();

        expect(tappedItem, 'Library Item');
        expect(tappedHeroTag, contains('test_'));

        container.read(searchQueryProvider.notifier).state = 'matrix';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.arrow_back), findsOneWidget);

        tappedItem = null;
        tappedHeroTag = null;

        await tester.tap(_gridItemGestureDetectorFinder());
        await tester.pump();

        expect(tappedItem, 'Search Result');
        expect(tappedHeroTag, contains('test_search_'));
      },
    );

    testWidgets('filters grouped browse content by availability', (
      tester,
    ) async {
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Available Item', 'Missing Item'],
      );
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: libraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          titleExtractor: (item) => item,
          statusExtractor: (item) => switch (item) {
            'Available Item' => const MediaStatusInfo(
              availability: MediaAvailability.available,
            ),
            _ => const MediaStatusInfo(availability: MediaAvailability.missing),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Available'));
      await tester.pumpAndSettle();

      expect(find.text('Available Item'), findsOneWidget);
      expect(find.text('Missing Item'), findsNothing);

      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(find.text('Available Item'), findsNothing);
      expect(find.text('Missing Item'), findsOneWidget);
    });

    testWidgets('lists a series the server never resolved under Missing', (
      tester,
    ) async {
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Available Item', 'Unresolved Item'],
      );
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: libraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          titleExtractor: (item) => item,
          statusExtractor: (item) => switch (item) {
            'Available Item' => const MediaStatusInfo(
              availability: MediaAvailability.available,
            ),
            // Sonarr omitting `statistics` on a freshly added series, which
            // used to leave the row visible under `All` and under nothing else.
            _ => const MediaStatusInfo(availability: MediaAvailability.unknown),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(find.text('Unresolved Item'), findsOneWidget);
      expect(find.text('Available Item'), findsNothing);

      await tester.tap(find.text('Available'));
      await tester.pumpAndSettle();

      expect(find.text('Unresolved Item'), findsNothing);
      expect(find.text('Available Item'), findsOneWidget);
    });

    testWidgets('filters grouped browse content by pipeline state', (
      tester,
    ) async {
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Queued Item', 'Available Item'],
      );
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: libraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          titleExtractor: (item) => item,
          statusExtractor: (item) => switch (item) {
            'Available Item' => const MediaStatusInfo(
              availability: MediaAvailability.available,
            ),
            // Nothing on disk *and* in the queue — the case that used to be
            // flattened to "Missing".
            _ => const MediaStatusInfo(
              availability: MediaAvailability.missing,
              pipeline: MediaPipeline.queued,
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('In Queue'));
      await tester.pumpAndSettle();

      expect(find.text('Queued Item'), findsOneWidget);
      expect(find.text('Available Item'), findsNothing);
    });

    testWidgets('shows empty search state when search returns no results', (
      tester,
    ) async {
      final searchQueryProvider = StateProvider<String>((ref) => 'query');
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Library Item'],
      );
      final searchResultsProvider = FutureProvider<List<String>?>((ref) async {
        final query = ref.watch(searchQueryProvider);
        return query.isEmpty ? null : <String>[];
      });
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: libraryProvider,
          searchQueryProvider: searchQueryProvider,
          searchResultsProvider: searchResultsProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No results found'), findsOneWidget);
      expect(find.byType(MediaGrid<String>), findsNothing);
    });

    testWidgets(
      'navigation refresh clears search query and invalidates library provider',
      (tester) async {
        var libraryLoadCount = 0;
        final searchQueryProvider = StateProvider<String>((ref) => '');
        final libraryProvider = FutureProvider<List<String>>((ref) async {
          libraryLoadCount++;
          return ['Library $libraryLoadCount'];
        });
        final searchResultsProvider = FutureProvider<List<String>?>((
          ref,
        ) async {
          final query = ref.watch(searchQueryProvider);
          return query.isEmpty ? null : ['Search Result'];
        });
        final container = ProviderContainer(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _buildCustomTestApp(
            container: container,
            libraryProvider: libraryProvider,
            searchQueryProvider: searchQueryProvider,
            searchResultsProvider: searchResultsProvider,
          ),
        );
        await tester.pumpAndSettle();

        expect(libraryLoadCount, 1);

        container.read(searchQueryProvider.notifier).state = 'searching';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(libraryLoadCount, 1);

        container
            .read(
              navigationRefreshProvider(NavigationSection.services).notifier,
            )
            .state++;
        await tester.pump();
        await tester.pumpAndSettle();

        expect(container.read(searchQueryProvider), '');
        expect(find.byIcon(Icons.arrow_back), findsNothing);
        expect(libraryLoadCount, 2);
      },
    );
  });
}

Widget _buildTestApp() {
  return ProviderScope(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
    ],
    child: MaterialApp(home: _buildTestScaffold()),
  );
}

Widget _buildTestScaffold() {
  return MediaBrowseScaffold<String>(
    title: 'Test Title',
    searchHint: 'Search test...',
    activityRoute: '/activity/test',
    navigationSection: NavigationSection.services,
    serviceName: 'Test Service',
    heroTagPrefix: 'test',
    searchHeroTagPrefix: 'test_search',
    libraryProvider: testLibraryProvider,
    searchQueryProvider: testSearchQueryProvider,
    searchResultsProvider: testSearchResultsProvider,
    titleExtractor: (item) => item,
    subtitleExtractor: (_) => '',
    imagesExtractor: (_) => null,
    idExtractor: (item) => item.hashCode,
    settingsSelector: (settings) => (settings.radarrUrl, settings.radarrApiKey),
    onItemTap: (_, __, ___) {},
  );
}

Widget _buildCustomTestApp({
  required ProviderContainer container,
  required FutureProvider<List<String>> libraryProvider,
  required StateProvider<String> searchQueryProvider,
  required FutureProvider<List<String>?> searchResultsProvider,
  String Function(String item)? titleExtractor,
  String Function(String item)? subtitleExtractor,
  StatusExtractor<String>? statusExtractor,
  void Function(BuildContext context, String item, String heroTag)? onItemTap,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: MediaBrowseScaffold<String>(
        title: 'Test Title',
        searchHint: 'Search test...',
        activityRoute: '/activity/test',
        navigationSection: NavigationSection.services,
        serviceName: 'Test Service',
        heroTagPrefix: 'test',
        searchHeroTagPrefix: 'test_search',
        libraryProvider: libraryProvider,
        searchQueryProvider: searchQueryProvider,
        searchResultsProvider: searchResultsProvider,
        titleExtractor: titleExtractor ?? (item) => item,
        subtitleExtractor: subtitleExtractor ?? (_) => '',
        imagesExtractor: (_) => null,
        idExtractor: (item) => item.hashCode,
        statusExtractor: statusExtractor,
        settingsSelector: (settings) =>
            (settings.radarrUrl, settings.radarrApiKey),
        onItemTap: onItemTap ?? (_, __, ___) {},
      ),
    ),
  );
}

Finder _gridItemGestureDetectorFinder() {
  return find
      .descendant(
        of: find.byType(MediaGrid<String>),
        matching: find.byType(GestureDetector),
      )
      .first;
}

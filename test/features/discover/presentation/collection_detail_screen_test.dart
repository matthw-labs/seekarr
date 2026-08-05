import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/domain/models/collection_detail.dart';
import 'package:seekarr/features/discover/presentation/collection_detail_screen.dart';
import 'package:seekarr/features/discover/presentation/discover_details_provider.dart';

const _collectionId = 42;

CollectionDetail _collection({List<MediaPreview> parts = const []}) =>
    CollectionDetail(
      id: _collectionId,
      name: 'The Trilogy',
      overview: 'Three films.',
      parts: parts,
    );

Future<void> _pump(
  WidgetTester tester,
  FutureOr<CollectionDetail> Function(Ref ref, int id) builder,
) async {
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on its own backoff schedule, which
      // would make the load count non-deterministic. Switched off so the test
      // measures only what the retry button does.
      retry: (retryCount, error) => null,
      overrides: [collectionDetailProvider.overrideWith(builder)],
      child: const MaterialApp(
        home: CollectionDetailScreen(collectionId: _collectionId),
      ),
    ),
  );
}

void main() {
  group('CollectionDetailScreen', () {
    testWidgets('a failed lookup names Seerr and is not a dead end', (
      tester,
    ) async {
      var loads = 0;
      await _pump(tester, (ref, id) {
        loads++;
        return Future<CollectionDetail>.error(Exception('Connection refused'));
      });
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text("Couldn't load Seerr"), findsOneWidget);
      expect(find.textContaining('Connection refused'), findsOneWidget);
      // The empty-title bar is gone: the failure wears the same chrome as the
      // loaded page.
      expect(find.byType(GlassAppBar), findsOneWidget);
      expect(loads, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      // The retry re-runs the very lookup that failed, in place.
      expect(loads, 2);
    });

    testWidgets('an empty collection is not dressed as a failure', (
      tester,
    ) async {
      await _pump(
        tester,
        (ref, id) async => const CollectionDetail(id: 0, name: ''),
      );
      await tester.pumpAndSettle();

      // Empty-state voice, and copy that says which nothing this is — it must
      // not read like the network error above.
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.text('No collection here'), findsOneWidget);
      expect(find.text("Couldn't load Seerr"), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a loaded collection renders its movies rail', (tester) async {
      await _pump(
        tester,
        (ref, id) async => _collection(
          parts: const [
            MediaPreview(
              id: 7,
              mediaType: 'movie',
              title: 'Part One',
              posterPath: null,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsNothing);
      expect(find.byType(AppEmptyState), findsNothing);
      expect(find.text('The Trilogy'), findsAtLeastNWidgets(1));
      // Pull-to-refresh reaches every variant now, not only the two Bazarr
      // screens; elsewhere the gesture was accepted by the hero's overscroll
      // stretch and then did nothing.
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('a collection with no titles filed under it says so', (
      tester,
    ) async {
      await _pump(tester, (ref, id) async => _collection());
      await tester.pumpAndSettle();

      // A valid collection with zero parts used to render a full hero over an
      // empty rail that collapsed to nothing.
      expect(find.text('MOVIES'), findsOneWidget);
      expect(find.text('No movies listed'), findsOneWidget);
    });
  });
}

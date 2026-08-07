import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_library_screen.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';

ProwlarrIndexer _indexer({
  required int id,
  required String name,
  bool enable = true,
  String protocol = 'torrent',
  List<int> tags = const [],
}) {
  return ProwlarrIndexer.fromJson({
    'id': id,
    'name': name,
    'enable': enable,
    'protocol': protocol,
    'privacy': 'private',
    'priority': 25,
    'tags': tags,
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required List<ProwlarrIndexer> indexers,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prowlarrIndexersProvider.overrideWith((ref) async => indexers),
        prowlarrIndexerStatusProvider.overrideWith(
          (ref) async => const <ProwlarrIndexerStatus>[],
        ),
        prowlarrTagsProvider.overrideWith(
          (ref) async => const [ProwlarrTag(id: 4, label: 'italian')],
        ),
      ],
      child: const MaterialApp(home: ProwlarrLibraryScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterSelectMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select indexers'));
  await tester.pumpAndSettle();
}

/// The bulk "Edit" button of the selection bar. Found by subtype because
/// `OutlinedButton.icon` may build a private subclass, which `find.byType`
/// (exact-type only) would miss.
OutlinedButton _bulkEditButton(WidgetTester tester) {
  return tester.widget<OutlinedButton>(
    find.ancestor(
      of: find.text('Edit'),
      matching: find.bySubtype<OutlinedButton>(),
    ),
  );
}

void main() {
  testWidgets('filters the list by the search field', (tester) async {
    await _pumpLibrary(
      tester,
      indexers: [
        _indexer(id: 1, name: 'ItaTorrents'),
        _indexer(id: 2, name: 'NZBgeek', protocol: 'usenet'),
      ],
    );

    expect(find.text('ItaTorrents'), findsOneWidget);
    expect(find.text('NZBgeek'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'geek');
    await tester.pumpAndSettle();

    expect(find.text('ItaTorrents'), findsNothing);
    expect(find.text('NZBgeek'), findsOneWidget);
  });

  testWidgets('renders tag labels for an indexer', (tester) async {
    await _pumpLibrary(
      tester,
      indexers: [
        _indexer(id: 1, name: 'ItaTorrents', tags: [4]),
      ],
    );

    expect(find.text('italian'), findsOneWidget);
  });

  testWidgets('selection mode exposes the bulk actions', (tester) async {
    await _pumpLibrary(
      tester,
      indexers: [
        _indexer(id: 1, name: 'ItaTorrents'),
        _indexer(id: 2, name: 'NZBgeek', protocol: 'usenet'),
      ],
    );

    // Bulk actions only exist once selection mode is on.
    expect(find.text('Edit'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select indexers'));
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsOneWidget);
    // With nothing picked yet the actions are inert.
    expect(_bulkEditButton(tester).onPressed, isNull);

    await tester.tap(find.text('ItaTorrents'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(_bulkEditButton(tester).onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('"Select all" selects what is on screen, not by count', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      indexers: [
        _indexer(id: 1, name: 'ItaTorrents'),
        _indexer(id: 2, name: 'NZBgeek', protocol: 'usenet'),
        _indexer(id: 3, name: 'NZBplanet', protocol: 'usenet'),
        _indexer(id: 4, name: 'NZBfinder', protocol: 'usenet'),
      ],
    );

    await _enterSelectMode(tester);
    // Pick the one torrent indexer, then filter it out of view.
    await tester.tap(find.text('ItaTorrents'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nzb');
    await tester.pumpAndSettle();

    // Pruned: a row the filter hides can no longer be acted on, so the count
    // names only what the user can see.
    expect(find.text('0 selected'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pumpAndSettle();

    // Size equality used to make this a no-op turned clear: one hidden
    // selection against three visible rows selected nothing at all.
    expect(find.text('3 selected'), findsOneWidget);

    // Tapping again clears exactly the visible set.
    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('narrowing the filter drops the rows it hides', (tester) async {
    await _pumpLibrary(
      tester,
      indexers: [
        _indexer(id: 1, name: 'ItaTorrents'),
        _indexer(id: 2, name: 'NZBgeek', protocol: 'usenet'),
      ],
    );

    await _enterSelectMode(tester);
    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'geek');
    await tester.pumpAndSettle();

    // The torrent indexer is off screen; a bulk delete must not be able to
    // take it, and the header must not claim it either.
    expect(find.text('1 selected'), findsOneWidget);

    // Widening again does not resurrect it: the selection was spent, not
    // hidden.
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('the delete confirmation names the indexers it will take', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      indexers: [
        _indexer(id: 1, name: 'ItaTorrents'),
        _indexer(id: 2, name: 'NZBgeek', protocol: 'usenet'),
      ],
    );

    await _enterSelectMode(tester);
    await tester.tap(find.byIcon(Icons.select_all_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Delete 2 indexers?'), findsOneWidget);
    // A bare count is unverifiable — the user has to be able to read what is
    // about to go.
    expect(find.textContaining('ItaTorrents, NZBgeek'), findsOneWidget);
  });

  testWidgets('an empty instance offers to add an indexer', (tester) async {
    await _pumpLibrary(tester, indexers: const []);

    expect(find.text('No indexers configured yet.'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Add indexer'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
      findsOneWidget,
    );
  });
}

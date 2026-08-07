import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_app_profiles_screen.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider_list_screen.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_settings_screen.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_tags_screen.dart';

ProwlarrProviderResource _resource(Map<String, dynamic> json) =>
    ProwlarrProviderResource.fromJson(json);

/// Every provider these screens read, overridden exactly once — Riverpod
/// asserts on a container that overrides the same provider twice, so the
/// defaults are merged with the per-test data rather than appended to it.
Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Map<ProwlarrProviderKind, List<ProwlarrProviderResource>> providers =
      const {},
  List<ProwlarrAppProfile> profiles = const [],
  List<ProwlarrTagDetail> tagDetails = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        for (final kind in ProwlarrProviderKind.values)
          prowlarrProvidersProvider(kind).overrideWith(
            (ref) async =>
                providers[kind] ?? const <ProwlarrProviderResource>[],
          ),
        prowlarrAppProfilesProvider.overrideWith((ref) async => profiles),
        prowlarrTagsProvider.overrideWith((ref) async => const <ProwlarrTag>[]),
        prowlarrTagDetailsProvider.overrideWith((ref) async => tagDetails),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the settings hub lists every section with its count', (
    tester,
  ) async {
    await _pump(
      tester,
      const ProwlarrSettingsScreen(),
      providers: {
        ProwlarrProviderKind.application: [
          _resource({'id': 1, 'name': 'Sonarr', 'syncLevel': 'fullSync'}),
          _resource({'id': 2, 'name': 'Radarr', 'syncLevel': 'addOnly'}),
        ],
      },
    );

    for (final kind in ProwlarrProviderKind.values) {
      expect(find.text(kind.title), findsOneWidget);
    }
    expect(find.text('Sync profiles'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Sync app indexers'), findsOneWidget);
  });

  testWidgets('an app row summarises its sync level', (tester) async {
    await _pump(
      tester,
      const ProwlarrProviderListScreen(kind: ProwlarrProviderKind.application),
      providers: {
        ProwlarrProviderKind.application: [
          _resource({
            'id': 1,
            'name': 'Sonarr',
            'implementationName': 'Sonarr',
            'syncLevel': 'addOnly',
          }),
        ],
      },
    );

    expect(find.text('Sonarr'), findsOneWidget);
    expect(find.textContaining('Add only'), findsOneWidget);
  });

  testWidgets('a notification row says which events it will fire', (
    tester,
  ) async {
    await _pump(
      tester,
      const ProwlarrProviderListScreen(kind: ProwlarrProviderKind.notification),
      providers: {
        ProwlarrProviderKind.notification: [
          _resource({
            'id': 1,
            'name': 'Telegram',
            'implementationName': 'Telegram',
            'onGrab': true,
            'onHealthIssue': true,
          }),
          _resource({
            'id': 2,
            'name': 'Quiet',
            'implementationName': 'Webhook',
          }),
        ],
      },
    );

    expect(find.textContaining('grabs, health'), findsOneWidget);
    expect(find.textContaining('no events'), findsOneWidget);
  });

  testWidgets('an empty section offers to add one', (tester) async {
    await _pump(
      tester,
      const ProwlarrProviderListScreen(kind: ProwlarrProviderKind.indexerProxy),
    );

    expect(find.text('No indexer proxies configured.'), findsOneWidget);
    expect(find.text('Add indexer proxy'), findsWidgets);
  });

  testWidgets('sync profiles summarise what they enable', (tester) async {
    await _pump(
      tester,
      const ProwlarrAppProfilesScreen(),
      profiles: const [
        ProwlarrAppProfile(
          id: 1,
          name: 'Standard',
          enableRss: true,
          enableAutomaticSearch: true,
          minimumSeeders: 2,
        ),
      ],
    );

    expect(find.text('Standard'), findsOneWidget);
    expect(
      find.textContaining('RSS, automatic search · min 2 seeders'),
      findsOneWidget,
    );
  });

  testWidgets('the tag manager separates used tags from unused ones', (
    tester,
  ) async {
    await _pump(
      tester,
      const ProwlarrTagsScreen(),
      tagDetails: const [
        ProwlarrTagDetail(
          id: 1,
          label: 'italian',
          indexerIds: [3, 4],
          applicationIds: [1],
        ),
        ProwlarrTagDetail(id: 2, label: 'spare'),
      ],
    );

    expect(find.text('italian'), findsOneWidget);
    expect(find.text('Used by 2 indexers, 1 apps'), findsOneWidget);
    expect(find.text('Unused'), findsOneWidget);
  });
}

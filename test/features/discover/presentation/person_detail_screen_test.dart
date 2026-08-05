import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/domain/models/person_detail.dart';
import 'package:seekarr/features/discover/presentation/discover_details_provider.dart';
import 'package:seekarr/features/discover/presentation/person_detail_screen.dart';

const _personId = 9;

Future<void> _pump(
  WidgetTester tester,
  FutureOr<PersonDetail> Function(Ref ref, int id) builder,
) async {
  await tester.pumpWidget(
    ProviderScope(
      // See the collection screen's test: Riverpod 3's own backoff retry would
      // make the load count non-deterministic.
      retry: (retryCount, error) => null,
      overrides: [
        personDetailProvider.overrideWith(builder),
        personCreditsProvider.overrideWith(
          (ref, id) async => const <MediaPreview>[],
        ),
      ],
      child: const MaterialApp(home: PersonDetailScreen(personId: _personId)),
    ),
  );
}

void main() {
  group('PersonDetailScreen', () {
    testWidgets('a failed lookup names Seerr and can be retried in place', (
      tester,
    ) async {
      var loads = 0;
      await _pump(tester, (ref, id) {
        loads++;
        return Future<PersonDetail>.error(Exception('Connection refused'));
      });
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text("Couldn't load Seerr"), findsOneWidget);
      expect(loads, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(loads, 2);
    });

    testWidgets('a person Seerr has no record of gets the empty-state voice', (
      tester,
    ) async {
      await _pump(
        tester,
        (ref, id) async => const PersonDetail(id: 0, name: ''),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.text('No details for this person'), findsOneWidget);
      expect(find.text("Couldn't load Seerr"), findsNothing);
    });

    testWidgets('dates speak the detail pages one date voice', (tester) async {
      await _pump(
        tester,
        (ref, id) async => const PersonDetail(
          id: _personId,
          name: 'Robert Downey Jr.',
          knownForDepartment: 'Acting',
          birthday: '1965-04-04',
          deathday: '2099-01-09',
          placeOfBirth: 'Manhattan, New York, USA',
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('DETAILS'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // TMDB answers with `1965-04-04`; the page used to print it raw, on a
      // surface where the Seerr title one tap away said `Apr 4, 1965`.
      expect(find.text('Apr 4, 1965'), findsOneWidget);
      expect(find.text('Jan 9, 2099'), findsOneWidget);
      expect(find.text('1965-04-04'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/core/widgets/header_action_row.dart';
import 'package:seekarr/core/widgets/library_detail_actions.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

void main() {
  group('resolveMediaAction', () {
    const all = MediaActionCapabilities(
      canSearch: true,
      canInteractiveSearch: true,
      canImport: true,
      canMonitor: true,
      canOpenQueue: true,
      canRequest: true,
      canAdd: true,
      canRefresh: true,
    );
    const none = MediaActionCapabilities();

    MediaPrimaryAction resolve(
      MediaStatusInfo status, [
      MediaActionCapabilities caps = all,
    ]) => resolveMediaAction(status, caps, serviceName: 'Radarr');

    test('an unreachable download client promotes the queue', () {
      final action = resolve(
        const MediaStatusInfo(pipeline: MediaPipeline.clientUnavailable),
      );
      expect(action.kind, MediaActionKind.openQueue);
      expect(
        action.consequence,
        'Nothing moves until the download client answers.',
      );
    });

    test('a failed transfer promotes another release', () {
      final action = resolve(
        const MediaStatusInfo(
          pipeline: MediaPipeline.failed,
          detail: 'No files found',
        ),
      );
      expect(action.kind, MediaActionKind.interactiveSearch);
      expect(action.label, 'Interactive search');
      expect(
        action.consequence,
        "This release won't finish. Radarr reports: No files found.",
      );
    });

    test('a blocked import promotes the manual import', () {
      final action = resolve(
        const MediaStatusInfo(pipeline: MediaPipeline.importBlocked),
      );
      expect(action.kind, MediaActionKind.manualImport);
      expect(action.label, 'Finish import');
      expect(action.consequence, contains('Radarr'));
    });

    test('a blocked import falls back to the queue without an import path', () {
      final action = resolve(
        const MediaStatusInfo(pipeline: MediaPipeline.importBlocked),
        const MediaActionCapabilities(canOpenQueue: true),
      );
      expect(action.kind, MediaActionKind.openQueue);
    });

    test('a stalled transfer keeps its frozen percentage', () {
      final action = resolve(
        const MediaStatusInfo(pipeline: MediaPipeline.stalled, progress: 0.43),
      );
      expect(action.kind, MediaActionKind.interactiveSearch);
      expect(
        action.consequence,
        'No bytes are moving right now; it sits at 43%.',
      );
    });

    test('an in-flight download promotes the queue with its progress', () {
      final action = resolve(
        const MediaStatusInfo(
          availability: MediaAvailability.missing,
          pipeline: MediaPipeline.downloading,
          progress: 0.6,
        ),
      );
      expect(action.kind, MediaActionKind.openQueue);
      expect(action.consequence, 'The download client has it, 60% through.');
    });

    test('a queued item does not advertise its undrawn progress', () {
      final action = resolve(
        const MediaStatusInfo(
          availability: MediaAvailability.missing,
          pipeline: MediaPipeline.queued,
          progress: 0.6,
        ),
      );
      expect(action.kind, MediaActionKind.openQueue);
      expect(
        action.consequence,
        'This title is waiting its turn; no bytes have moved yet.',
      );
    });

    test('the pipeline beats being unmonitored', () {
      final action = resolve(
        const MediaStatusInfo(
          availability: MediaAvailability.missing,
          pipeline: MediaPipeline.downloading,
          unmonitored: true,
        ),
      );
      expect(action.kind, MediaActionKind.openQueue);
    });

    test('an unmonitored item promotes monitoring', () {
      final action = resolve(
        const MediaStatusInfo(
          availability: MediaAvailability.missing,
          unmonitored: true,
        ),
      );
      expect(action.kind, MediaActionKind.monitor);
      expect(action.consequence, "Radarr isn't searching for this title.");
    });

    test('an untracked item prefers a request over an add', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.notTracked),
      );
      expect(action.kind, MediaActionKind.request);

      final adding = resolve(
        const MediaStatusInfo(availability: MediaAvailability.notTracked),
        const MediaActionCapabilities(canAdd: true),
      );
      expect(adding.kind, MediaActionKind.add);
      expect(adding.label, 'Add to Radarr');
    });

    test('an untracked item with no add path yields a sentence', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.notTracked),
        none,
      );
      expect(action.kind, MediaActionKind.none);
      expect(
        action.consequence,
        'Nothing happens until Radarr is tracking this title.',
      );
    });

    test('a missing item promotes a search', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.missing),
      );
      expect(action.kind, MediaActionKind.search);
      expect(action.label, 'Auto search');
    });

    test('a partial item promotes a search for the gap', () {
      final action = resolveMediaAction(
        const MediaStatusInfo(availability: MediaAvailability.partial),
        all,
        serviceName: 'Sonarr',
        partialSummary: '41 of 48 episodes on disk.',
      );
      expect(action.kind, MediaActionKind.search);
      expect(action.label, 'Auto search');
      expect(action.consequence, '41 of 48 episodes on disk.');
    });

    test('an upgradable item promotes an interactive search', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.upgradable),
      );
      expect(action.kind, MediaActionKind.interactiveSearch);
      expect(action.label, 'Interactive search');
    });

    test('an available item promotes nothing at all', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.available),
      );
      expect(action.kind, MediaActionKind.none);
      expect(
        action.consequence,
        "Radarr has everything it expects, so it isn't searching.",
      );
    });

    test('an unreleased item can carry its own date', () {
      final action = resolveMediaAction(
        const MediaStatusInfo(availability: MediaAvailability.unavailable),
        all,
        serviceName: 'Radarr',
        consequenceOverride: 'Jul 17, 2026',
      );
      expect(action.kind, MediaActionKind.none);
      expect(
        action.consequence,
        "There's nothing to search for until Jul 17, 2026.",
      );
    });

    test('a deleted item names the service it left', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.deleted),
      );
      expect(action.kind, MediaActionKind.none);
      expect(
        action.consequence,
        'Nothing changes here until this title is back in Radarr.',
      );
    });

    test('an unknown status falls back to what the service said', () {
      expect(
        resolve(const MediaStatusInfo(detail: 'Nothing came back')).consequence,
        'Radarr reports: Nothing came back.',
      );
      expect(
        resolve(const MediaStatusInfo.unknown()).consequence,
        "Radarr didn't report a state for this title.",
      );
    });

    test('every capability withheld promotes nothing, never a dead button', () {
      for (final status in const [
        MediaStatusInfo(pipeline: MediaPipeline.clientUnavailable),
        MediaStatusInfo(pipeline: MediaPipeline.failed),
        MediaStatusInfo(pipeline: MediaPipeline.stalled),
        MediaStatusInfo(pipeline: MediaPipeline.downloading),
        MediaStatusInfo(availability: MediaAvailability.missing),
        MediaStatusInfo(availability: MediaAvailability.partial),
        MediaStatusInfo(availability: MediaAvailability.upgradable),
        MediaStatusInfo(
          availability: MediaAvailability.missing,
          unmonitored: true,
        ),
      ]) {
        final action = resolve(status, none);
        expect(action.kind, MediaActionKind.none, reason: '$status');
        expect(action.consequence, isNotEmpty, reason: '$status');
      }
    });
  });

  group('LibraryDetailActions', () {
    testWidgets('a missing item promotes one search and nothing else', (
      tester,
    ) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(availability: MediaAvailability.missing),
      );

      expect(find.text('Auto search'), findsOneWidget);
      expect(
        find.text('Radarr is hunting a release for this title.'),
        findsOneWidget,
      );
      expect(_primary, findsOneWidget);
      // With a primary holding the wide slot, exactly one secondary earns a
      // visible slot and it is icon-only, so its name is a semantics label and
      // never a visible caption to ellipsise.
      expect(find.bySemanticsLabel('Interactive search'), findsOneWidget);
      // Everything else stays in the sheet, unrendered until it is opened. The
      // promoted primary's own label is 'Auto search', so that one is scoped to
      // the button rather than counted globally.
      expect(find.text('Auto search'), findsOneWidget);
      expect(find.text('Interactive search'), findsNothing);
      expect(find.text('Manual import'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('an in-flight download promotes the queue', (tester) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(
          availability: MediaAvailability.missing,
          pipeline: MediaPipeline.downloading,
          progress: 0.43,
        ),
      );

      expect(find.text('Open queue'), findsOneWidget);
      expect(
        find.text('The download client has it, 43% through.'),
        findsOneWidget,
      );
      expect(find.text('Auto search'), findsNothing);
    });

    testWidgets('an available item promotes nothing and explains itself', (
      tester,
    ) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(
          availability: MediaAvailability.available,
        ),
        isMonitored: true,
      );

      // The loudest element on this page used to read "Unmonitor".
      expect(_primary, findsNothing);
      expect(find.text('Unmonitor'), findsNothing);
      expect(find.text('Stop monitoring'), findsNothing);
      expect(
        find.text("Radarr has everything it expects, so it isn't searching."),
        findsOneWidget,
      );
      // The overflow is still reachable.
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('an unmonitored item promotes monitoring', (tester) async {
      var monitored = false;
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(
          availability: MediaAvailability.missing,
          unmonitored: true,
        ),
        onMonitoredChanged: (value) => monitored = value,
      );

      expect(find.text('Monitor'), findsOneWidget);
      await tester.tap(find.text('Monitor'));
      await tester.pump();
      expect(monitored, isTrue);
    });

    testWidgets('an untracked item offers a sentence, not an Add CTA', (
      tester,
    ) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(
          availability: MediaAvailability.notTracked,
        ),
      );

      // The full-width accent CTA whose only behaviour was an info snackbar
      // reading "Add Movie is not available yet from this view."
      expect(_primary, findsNothing);
      expect(find.textContaining('Add'), findsNothing);
      expect(
        find.text('Nothing happens until Radarr is tracking this title.'),
        findsOneWidget,
      );
    });

    testWidgets('the overflow holds exactly the non-promoted actions', (
      tester,
    ) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(availability: MediaAvailability.missing),
        isMonitored: true,
        currentProfileName: 'HD-1080p',
      );

      // Interactive search won the one visible slot a primary leaves, so the
      // sheet must not offer it a second time.
      expect(find.bySemanticsLabel('Interactive search'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Stop monitoring'), findsOneWidget);
      expect(find.text('Quality profile: HD-1080p'), findsOneWidget);
      expect(find.text('Manual import'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      // Auto search is promoted; Interactive search took the visible slot.
      // Neither is a row in the sheet — the one 'Auto search' on screen is the
      // primary button behind it.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Auto search'),
        ),
        findsNothing,
      );
      expect(find.text('Interactive search'), findsNothing);
    });

    testWidgets('the promoted interactive search leaves the overflow', (
      tester,
    ) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(
          availability: MediaAvailability.upgradable,
        ),
      );
      expect(find.text('Interactive search'), findsOneWidget);

      // Promoted, so it is not a candidate at all; the next-ranked one takes
      // the single visible slot instead.
      expect(find.bySemanticsLabel('Auto search'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Interactive search'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Auto search'),
        ),
        findsNothing,
      );
    });

    testWidgets('Delete is not a peer of Import', (tester) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(
          availability: MediaAvailability.available,
        ),
      );

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      final divider = find.byType(Divider);
      expect(divider, findsOneWidget);

      final importY = tester.getCenter(find.text('Manual import')).dy;
      final dividerY = tester.getCenter(divider).dy;
      final deleteY = tester.getCenter(find.text('Delete')).dy;

      // Delete sits below a divider, last, rather than roughly ten points from
      // Import in the same group told apart by hue alone.
      expect(importY, lessThan(dividerY));
      expect(dividerY, lessThan(deleteY));
      for (final label in const [
        'Interactive search',
        'Auto search',
        'Manual import',
      ]) {
        expect(tester.getCenter(find.text(label)).dy, lessThan(deleteY));
      }
    });

    testWidgets('a destructive row is toned by the theme error colour', (
      tester,
    ) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(
          availability: MediaAvailability.available,
        ),
      );
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      final error = Theme.of(
        tester.element(find.text('Delete')),
      ).colorScheme.error;
      expect(tester.widget<Text>(find.text('Delete')).style?.color, error);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded)).color,
        error,
      );
    });

    testWidgets('every control clears the 44pt touch minimum', (tester) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(availability: MediaAvailability.missing),
      );

      final primary = tester.getSize(_primary);
      expect(primary.height, greaterThanOrEqualTo(44));

      // Every disc in the band, visible secondary and overflow alike.
      final discs = find.byType(OutlinedButton);
      expect(discs, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final disc = tester.getSize(discs.at(i));
        expect(disc.width, greaterThanOrEqualTo(44));
        expect(disc.height, greaterThanOrEqualTo(44));
      }

      // And nothing in the band crowds its neighbour.
      final rects = <Rect>[
        tester.getRect(_primary),
        tester.getRect(discs.at(0)),
        tester.getRect(discs.at(1)),
      ]..sort((a, b) => a.left.compareTo(b.left));
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left - rects[i - 1].right, greaterThanOrEqualTo(8));
      }

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      // Interactive search took the visible slot, so the sheet's own rows are
      // what is left: check the top one and the destructive one.
      for (final label in const ['Manual import', 'Delete']) {
        expect(
          tester.getSize(_rowOf(tester, label)).height,
          greaterThanOrEqualTo(44),
        );
      }
    });

    testWidgets('the promoted action spins for its own work', (tester) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(availability: MediaAvailability.missing),
        isBusy: true,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(_primary).onPressed, isNull);
    });

    testWidgets('a busy band accepts a tap on no rung at all', (tester) async {
      var searches = 0;
      var interactiveSearches = 0;

      await _pumpActions(
        tester,
        status: const MediaStatusInfo(availability: MediaAvailability.missing),
        isBusy: true,
        onSearch: () => searches++,
        onInteractiveSearch: () => interactiveSearches++,
      );
      await tester.pump(const Duration(milliseconds: 300));

      // One flag, every rung: the promoted button, the visible secondary disc
      // and the overflow trigger. Before this, only the promoted button read
      // `isBusy`, so a triple tap on the auto-search secondary sent three
      // commands to the service.
      expect(tester.widget<FilledButton>(_primary).onPressed, isNull);
      final discs = tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(discs, hasLength(2));
      for (final disc in discs) {
        expect(disc.onPressed, isNull);
      }

      await tester.tap(find.byIcon(Icons.search_rounded), warnIfMissed: false);
      await tester.tap(
        find.byIcon(Icons.more_horiz_rounded),
        warnIfMissed: false,
      );
      // Not `pumpAndSettle`: the promoted glyph spins on an indeterminate
      // indicator for as long as the band is busy, so nothing ever settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(searches, 0);
      expect(interactiveSearches, 0);
      // And the overflow sheet cannot be opened on top of a running write, so
      // Delete is out of reach while a delete is in flight.
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('a secondary fires once under a triple tap', (tester) async {
      var searches = 0;
      var busy = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => LibraryDetailActions(
                service: ServiceKey.radarr,
                status: const MediaStatusInfo(
                  availability: MediaAvailability.upgradable,
                ),
                mediaTitle: 'Inception',
                isBusy: busy,
                // Exactly what every host does: flip an in-flight flag and fire
                // the service command, with no re-entrancy guard of its own.
                onSearch: () {
                  searches++;
                  setState(() => busy = true);
                },
                onInteractiveSearch: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Interactive search is promoted on this rung, so the visible secondary
      // disc is the automatic one.
      final autoSearch = find.byIcon(Icons.saved_search_rounded);
      await tester.tap(autoSearch);
      await tester.pump();
      await tester.tap(autoSearch, warnIfMissed: false);
      await tester.tap(autoSearch, warnIfMissed: false);
      await tester.pump();

      expect(searches, 1);
    });

    testWidgets('a spent sheet goes inert while it leaves', (tester) async {
      var imports = 0;
      var deletes = 0;

      await _pumpActions(
        tester,
        status: const MediaStatusInfo(
          availability: MediaAvailability.available,
        ),
        onImport: () => imports++,
        onDelete: () => deletes++,
      );

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manual import'));
      // One frame in: the sheet has popped but is still on screen for the
      // length of its exit, and every row on it is a bare closure that pops
      // before the host learns anything. A sheet is spent on one action, so
      // nothing on it is live any more — not the row that was tapped and not
      // the destructive one beside it.
      await tester.pump();

      PressableScale row(String label) =>
          tester.widget<PressableScale>(_rowOf(tester, label));
      expect(row('Manual import').onTap, isNull);
      expect(row('Delete').onTap, isNull);

      await tester.pumpAndSettle();

      expect(imports, 1);
      expect(deletes, 0);
      // ...and the detail page underneath is still there.
      expect(find.byType(LibraryDetailActions), findsOneWidget);
    });

    testWidgets('the confirmation morph is held and announced', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(availability: MediaAvailability.missing),
        isConfirmed: true,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.saved_search_rounded), findsNothing);
      expect(find.semantics.byLabel(RegExp('Auto search complete')), findsOne);
      handle.dispose();
    });

    testWidgets('reduce motion renders the confirmation without an animator', (
      tester,
    ) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(availability: MediaAvailability.missing),
        isConfirmed: true,
        reduceMotion: true,
      );

      expect(find.byType(AnimatedSwitcher), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('the band never pads itself', (tester) async {
      await _pumpActions(
        tester,
        status: const MediaStatusInfo(availability: MediaAvailability.missing),
      );

      // The detail spine owns the gutter. A self-inset band is the mid-page jog
      // this composition exists to remove.
      final band = tester.getRect(find.byType(LibraryDetailActions));
      final row = tester.getRect(find.byType(HeaderActionRow));
      expect(row.left, band.left);
      expect(row.right, band.right);
    });
  });
}

/// `FilledButton.icon` builds a private subclass, so an exact type finder
/// misses it.
final Finder _primary = find.byWidgetPredicate(
  (widget) => widget is FilledButton,
);

Finder _rowOf(WidgetTester tester, String label) => find
    .ancestor(of: find.text(label), matching: find.byType(PressableScale))
    .first;

Future<void> _pumpActions(
  WidgetTester tester, {
  required MediaStatusInfo status,
  bool isMonitored = false,
  bool isBusy = false,
  bool isConfirmed = false,
  bool reduceMotion = false,
  String? currentProfileName,
  ValueChanged<bool>? onMonitoredChanged,
  VoidCallback? onSearch,
  VoidCallback? onInteractiveSearch,
  VoidCallback? onImport,
  VoidCallback? onDelete,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: Scaffold(
        body: LibraryDetailActions(
          service: ServiceKey.radarr,
          status: status,
          mediaTitle: 'Inception',
          isMonitored: isMonitored,
          isBusy: isBusy,
          isConfirmed: isConfirmed,
          currentProfileName: currentProfileName,
          currentProfileId: 1,
          qualityProfiles: const [
            {'id': 1, 'name': 'HD-1080p'},
            {'id': 2, 'name': 'Ultra-HD'},
          ],
          onSearch: onSearch ?? () {},
          onInteractiveSearch: onInteractiveSearch ?? () {},
          onImport: onImport ?? () {},
          onOpenQueue: () {},
          onMonitoredChanged: onMonitoredChanged ?? (_) {},
          onDelete: onDelete ?? () {},
          onProfileSelected: (_) async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

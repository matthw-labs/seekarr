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
      expect(action.consequence, 'The download client is not answering.');
    });

    test('a failed transfer promotes another release', () {
      final action = resolve(
        const MediaStatusInfo(
          pipeline: MediaPipeline.failed,
          detail: 'No files found',
        ),
      );
      expect(action.kind, MediaActionKind.interactiveSearch);
      expect(action.label, 'Find another release');
      expect(action.consequence, 'No files found');
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
      expect(action.consequence, 'Stalled at 43%.');
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
      expect(action.consequence, 'Downloading · 60%');
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
      expect(action.consequence, 'Queued');
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
      expect(action.consequence, 'Not monitored, so nothing is being hunted.');
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
      expect(action.consequence, 'Not in Radarr yet.');
    });

    test('a missing item promotes a search', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.missing),
      );
      expect(action.kind, MediaActionKind.search);
      expect(action.label, 'Find releases');
    });

    test('a partial item promotes a search for the gap', () {
      final action = resolveMediaAction(
        const MediaStatusInfo(availability: MediaAvailability.partial),
        all,
        serviceName: 'Sonarr',
        partialSummary: '41 of 48 episodes on disk.',
      );
      expect(action.kind, MediaActionKind.search);
      expect(action.label, 'Find missing');
      expect(action.consequence, '41 of 48 episodes on disk.');
    });

    test('an upgradable item promotes an interactive search', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.upgradable),
      );
      expect(action.kind, MediaActionKind.interactiveSearch);
      expect(action.label, 'Find an upgrade');
    });

    test('an available item promotes nothing at all', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.available),
      );
      expect(action.kind, MediaActionKind.none);
      expect(action.consequence, 'Everything expected is on disk.');
    });

    test('an unreleased item can carry its own date', () {
      final action = resolveMediaAction(
        const MediaStatusInfo(availability: MediaAvailability.unavailable),
        all,
        serviceName: 'Radarr',
        consequenceOverride: 'Out on Jul 17, 2026.',
      );
      expect(action.kind, MediaActionKind.none);
      expect(action.consequence, 'Out on Jul 17, 2026.');
    });

    test('a deleted item names the service it left', () {
      final action = resolve(
        const MediaStatusInfo(availability: MediaAvailability.deleted),
      );
      expect(action.kind, MediaActionKind.none);
      expect(action.consequence, 'Removed from Radarr.');
    });

    test('an unknown status falls back to what the service said', () {
      expect(
        resolve(const MediaStatusInfo(detail: 'Nothing came back')).consequence,
        'Nothing came back',
      );
      expect(resolve(const MediaStatusInfo.unknown()).consequence, 'Unknown');
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

      expect(find.text('Find releases'), findsOneWidget);
      expect(find.text('Expected on disk, nothing there.'), findsOneWidget);
      expect(_primary, findsOneWidget);
      // Nothing else is a peer of the promoted action.
      expect(find.text('Interactive search'), findsNothing);
      expect(find.text('Auto search'), findsNothing);
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
      expect(find.text('Downloading · 43%'), findsOneWidget);
      expect(find.text('Find releases'), findsNothing);
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
      expect(find.text('Everything expected is on disk.'), findsOneWidget);
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
      expect(find.text('Not in Radarr yet.'), findsOneWidget);
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

      // Auto search is promoted, so it must not appear twice.
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Interactive search'), findsOneWidget);
      expect(find.text('Stop monitoring'), findsOneWidget);
      expect(find.text('Quality profile: HD-1080p'), findsOneWidget);
      expect(find.text('Manual import'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Auto search'), findsNothing);
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
      expect(find.text('Find an upgrade'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Interactive search'), findsNothing);
      expect(find.text('Auto search'), findsOneWidget);
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
      final overflow = tester.getSize(find.byType(OutlinedButton));
      expect(overflow.width, greaterThanOrEqualTo(44));
      expect(overflow.height, greaterThanOrEqualTo(44));

      // And they stay apart.
      final primaryRect = tester.getRect(_primary);
      final overflowRect = tester.getRect(find.byType(OutlinedButton));
      expect(overflowRect.left - primaryRect.right, greaterThanOrEqualTo(8));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      for (final label in const ['Interactive search', 'Delete']) {
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
      expect(
        find.semantics.byLabel(RegExp('Find releases complete')),
        findsOne,
      );
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
          onSearch: () {},
          onInteractiveSearch: () {},
          onImport: () {},
          onOpenQueue: () {},
          onMonitoredChanged: onMonitoredChanged ?? (_) {},
          onDelete: () {},
          onProfileSelected: (_) async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

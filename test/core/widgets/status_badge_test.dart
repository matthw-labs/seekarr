import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/core/widgets/status_badge.dart';

void main() {
  group('MediaStatusInfo.label', () {
    test('the pipeline wins over availability', () {
      // The regression this whole layer exists to prevent: nothing on disk plus
      // an active download must never read "Missing".
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
      );

      expect(info.label, 'Downloading');
      expect(info.tone, StatusTone.info);
    });

    test('labelOverride wins over everything', () {
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.paused,
        labelOverride: 'Client Unavailable',
      );

      expect(info.label, 'Client Unavailable');
    });

    test('unmonitored surfaces only when nothing is on disk', () {
      const unmonitoredMissing = MediaStatusInfo(
        availability: MediaAvailability.missing,
        unmonitored: true,
      );
      const unmonitoredAvailable = MediaStatusInfo(
        availability: MediaAvailability.available,
        unmonitored: true,
      );

      expect(unmonitoredMissing.label, 'Unmonitored');
      expect(unmonitoredMissing.tone, StatusTone.neutral);
      expect(unmonitoredAvailable.label, 'Available');
      expect(unmonitoredAvailable.tone, StatusTone.success);
    });

    test('an in-flight item outranks the unmonitored flag', () {
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        unmonitored: true,
        pipeline: MediaPipeline.downloading,
      );

      expect(info.label, 'Downloading');
    });

    final availabilityLabels = <MediaAvailability, String>{
      MediaAvailability.notTracked: 'Not Requested',
      MediaAvailability.unavailable: 'Not Released',
      MediaAvailability.missing: 'Missing',
      MediaAvailability.partial: 'Partial',
      MediaAvailability.available: 'Available',
      MediaAvailability.upgradable: 'Upgrade Available',
      MediaAvailability.deleted: 'Deleted',
      MediaAvailability.unknown: 'Unknown',
    };

    availabilityLabels.forEach((availability, label) {
      test('${availability.name} reads "$label"', () {
        expect(MediaStatusInfo(availability: availability).label, label);
      });
    });
  });

  group('MediaStatusInfo.tone', () {
    test('a warning lifts a calm tone but never masks an error', () {
      const queuedWarning = MediaStatusInfo(
        pipeline: MediaPipeline.downloading,
        hasWarning: true,
      );
      const failedWarning = MediaStatusInfo(
        pipeline: MediaPipeline.failed,
        hasWarning: true,
      );

      expect(queuedWarning.tone, StatusTone.warning);
      expect(failedWarning.tone, StatusTone.error);
    });

    test('notTracked carries the accent tone as a call to action', () {
      expect(
        const MediaStatusInfo(availability: MediaAvailability.notTracked).tone,
        StatusTone.primary,
      );
    });

    test('an unreleased title is neutral, not an error', () {
      expect(
        const MediaStatusInfo(availability: MediaAvailability.unavailable).tone,
        StatusTone.neutral,
      );
      expect(
        const MediaStatusInfo(availability: MediaAvailability.missing).tone,
        StatusTone.error,
      );
    });
  });

  group('MediaPipeline.salience', () {
    test('failed outranks downloading, which outranks the waiting states', () {
      expect(
        MediaPipeline.failed.salience,
        greaterThan(MediaPipeline.downloading.salience),
      );
      expect(
        MediaPipeline.downloading.salience,
        greaterThan(MediaPipeline.queued.salience),
      );
      expect(
        MediaPipeline.queued.salience,
        greaterThan(MediaPipeline.paused.salience),
      );
    });
  });

  group('availabilityFromCounts', () {
    test('all files present is available', () {
      expect(
        availabilityFromCounts(fileCount: 10, totalCount: 10),
        MediaAvailability.available,
      );
    });

    test('more files than expected is still available', () {
      expect(
        availabilityFromCounts(fileCount: 15, totalCount: 10),
        MediaAvailability.available,
      );
    });

    test('some files present is partial', () {
      expect(
        availabilityFromCounts(fileCount: 4, totalCount: 10),
        MediaAvailability.partial,
      );
    });

    test('no files present falls back to whenEmpty', () {
      expect(
        availabilityFromCounts(fileCount: 0, totalCount: 10),
        MediaAvailability.missing,
      );
      expect(
        availabilityFromCounts(
          fileCount: 0,
          totalCount: 10,
          whenEmpty: MediaAvailability.unavailable,
        ),
        MediaAvailability.unavailable,
      );
    });

    test('a zero total falls back to file presence', () {
      expect(
        availabilityFromCounts(fileCount: 2, totalCount: 0),
        MediaAvailability.available,
      );
      expect(
        availabilityFromCounts(fileCount: 0, totalCount: 0),
        MediaAvailability.missing,
      );
    });

    test('an absent count is unknown rather than missing', () {
      expect(
        availabilityFromCounts(fileCount: null, totalCount: null),
        MediaAvailability.unknown,
      );
    });
  });

  group('statusIconFor', () {
    test('the pipeline icon wins over the availability icon', () {
      expect(
        statusIconFor(
          const MediaStatusInfo(
            availability: MediaAvailability.missing,
            pipeline: MediaPipeline.downloading,
          ),
        ),
        Icons.downloading_rounded,
      );
    });

    test('unmonitored without files gets the bookmark icon', () {
      expect(
        statusIconFor(
          const MediaStatusInfo(
            availability: MediaAvailability.missing,
            unmonitored: true,
          ),
        ),
        Icons.bookmark_border_rounded,
      );
    });
  });

  group('StatusBadge rendering', () {
    testWidgets('full mode renders the label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(availability: MediaAvailability.available),
            ),
          ),
        ),
      );

      expect(find.text('Available'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('compact mode renders no label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(availability: MediaAvailability.available),
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Available'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('an active download renders a progress ring and percentage', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(
                availability: MediaAvailability.missing,
                pipeline: MediaPipeline.downloading,
                progress: 0.42,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('42%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.downloading_rounded), findsNothing);
    });

    testWidgets('a waiting state shows its icon, not a ring', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(
                availability: MediaAvailability.missing,
                pipeline: MediaPipeline.queued,
                progress: 0.42,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Queued'), findsOneWidget);
      expect(find.text('42%'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    });

    testWidgets('iconOnly renders a bare dot', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(availability: MediaAvailability.missing),
              iconOnly: true,
            ),
          ),
        ),
      );

      expect(find.text('Missing'), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });
  });

  group('MediaStatusInfo.semanticLabel', () {
    test('spells out the percentage the badge only draws as a ring', () {
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
        progress: 0.42,
      );

      expect(info.semanticLabel, 'Downloading, 42 percent');
    });

    test('spells out a warning carried only by the tone colour', () {
      // hasWarning replaced a "… (Warning)" text suffix, so since then nothing
      // writes it down — the amber tone is the whole signal.
      const info = MediaStatusInfo(
        availability: MediaAvailability.available,
        hasWarning: true,
      );

      expect(info.tone, StatusTone.warning);
      expect(info.semanticLabel, 'Available, warning');
    });

    test('stays silent about progress that is not being drawn', () {
      // A queued item carries a progress value the badge deliberately hides.
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.queued,
        progress: 0.42,
      );

      expect(info.progressPercent, isNull);
      expect(info.semanticLabel, 'Queued');
    });
  });

  group('StatusBadge semantics', () {
    testWidgets('all three variants announce the same status', (tester) async {
      const info = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
        progress: 0.42,
      );

      for (final variant in [
        const StatusBadge(info: info),
        const StatusBadge(info: info, compact: true),
        const StatusBadge(info: info, iconOnly: true),
      ]) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: variant)));

        expect(
          find.semantics.byLabel('Downloading, 42 percent'),
          findsOneWidget,
          reason: 'compact=${variant.compact} iconOnly=${variant.iconOnly}',
        );
      }
    });

    testWidgets('excludeFromSemantics leaves the badge silent', (tester) async {
      // Set by tiles that speak the status themselves, so the badge is not a
      // second stop for the same information.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              info: MediaStatusInfo(availability: MediaAvailability.available),
              iconOnly: true,
              excludeFromSemantics: true,
            ),
          ),
        ),
      );

      expect(find.semantics.byLabel('Available'), findsNothing);
    });
  });
}

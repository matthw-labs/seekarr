import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/domain/service_signal.dart';

ServiceKpi _kpi(String label, String value, {Color? accent}) =>
    ServiceKpi(label: label, value: value, icon: Icons.circle, accent: accent);

void main() {
  group('resolveServiceSignal', () {
    test('returns null when a service reports no KPIs', () {
      expect(resolveServiceSignal(const []), isNull);
    });

    test('falls back to the headline metric when nothing is flagged', () {
      final signal = resolveServiceSignal([
        _kpi('Movies', '312'),
        _kpi('Monitored', '300'),
        _kpi('Missing', '0'),
      ]);

      expect(signal!.label, 'movies');
      expect(signal.value, '312');
      expect(signal.tone, StatusTone.neutral);
      expect(signal.needsAttention, isFalse);
    });

    test('prefers the first flagged KPI over the headline', () {
      // The KPI builders mark their own noteworthy metric with a non-null
      // accent — `_warnIf(missing > 0)`. That flag is the domain's judgment about
      // its own data, so this reads it instead of restating a per-service table.
      final signal = resolveServiceSignal([
        _kpi('Movies', '312'),
        _kpi('Monitored', '300'),
        _kpi('Missing', '7', accent: AppColors.warning),
      ]);

      expect(signal!.label, 'missing');
      expect(signal.value, '7');
      expect(signal.needsAttention, isTrue);
    });

    test('takes the earliest flag when several are raised', () {
      final signal = resolveServiceSignal([
        _kpi('Pools', '2'),
        _kpi('Used', '91%', accent: AppColors.warning),
        _kpi('Alerts', '3', accent: AppColors.warning),
      ]);

      expect(signal!.label, 'used');
    });

    group('tone', () {
      test('an active transfer reads as activity, not as a warning', () {
        final signal = resolveServiceSignal([
          _kpi('Down', '2.4 MB/s', accent: AppColors.warning),
          _kpi('Queue', '3'),
        ]);

        expect(signal!.tone, StatusTone.info);
        expect(signal.needsAttention, isTrue);
      });

      test('a fault reads as an error, not as a backlog', () {
        // An exited stack and a failing indexer were meant to be running and are
        // not — distinct from work that simply has not happened yet.
        for (final label in ['Exited', 'Fails']) {
          final signal = resolveServiceSignal([
            _kpi('Stacks', '9'),
            _kpi(label, '2', accent: AppColors.warning),
          ]);
          expect(signal!.tone, StatusTone.error, reason: label);
        }
      });

      test('everything else flagged reads as a warning', () {
        final signal = resolveServiceSignal([
          _kpi('Wanted', '14', accent: AppColors.warning),
        ]);

        expect(signal!.tone, StatusTone.warning);
      });
    });

    test('spoken form puts the label before the figure', () {
      // The cell paints "2.4 MB/s incoming" because the eye scans a column of
      // figures. Read back in that order it is nonsense.
      final signal = resolveServiceSignal([
        _kpi('Down', '2.4 MB/s', accent: AppColors.warning),
      ]);

      expect(signal!.spoken, 'Incoming 2.4 MB/s');
    });

    group('the matrix vocabulary', () {
      test('a download rate never says "down" on a reachability grid', () {
        // The one word this screen cannot borrow: the cell's other possible live
        // line is literally "Offline", so "2.4 MB/s down" reads as a service that
        // is down rather than as bytes arriving.
        final signal = resolveServiceSignal([
          _kpi('Down', '2.4 MB/s', accent: AppColors.warning),
        ]);

        // And short enough to survive a 168pt cell: "downloading" ellipsised to
        // "downloa…" at the default reading size.
        expect(signal!.label, 'incoming');
      });

      test('a state word carries no label after it', () {
        // SABnzbd and NZBGet report their paused queue as `Status: Paused`, and
        // the cell paints value-then-label — so keeping the label printed
        // "Paused status".
        final signal = resolveServiceSignal([
          _kpi('Status', 'Paused', accent: AppColors.warning),
        ]);

        expect(signal!.label, isEmpty);
        expect(signal.spoken, 'Paused');
      });

      test("Prowlarr's truncation becomes a noun", () {
        final signal = resolveServiceSignal([
          _kpi('Fails', '3', accent: AppColors.warning),
        ]);

        expect(signal!.label, 'failures');
      });

      test('a label agrees in number with its own figure', () {
        expect(
          resolveServiceSignal([
            _kpi('Alerts', '1', accent: AppColors.warning),
          ])!.label,
          'alert',
        );
        expect(
          resolveServiceSignal([
            _kpi('Alerts', '4', accent: AppColors.warning),
          ])!.label,
          'alerts',
        );
      });

      test('a figure that is not a count is left alone', () {
        // `85%`, `4/6` and `2.4 MB/s` all parse to null, which is correct: those
        // labels are not counts and must not be singularized by a stray "1".
        for (final value in ['85%', '4/6', '1.0 MB/s']) {
          expect(
            resolveServiceSignal([
              _kpi('Pools', value, accent: AppColors.warning),
            ])!.label,
            'pools',
            reason: value,
          );
        }
      });

      test('"series" reads the same for one and for many', () {
        expect(resolveServiceSignal([_kpi('Series', '1')])!.label, 'series');
        expect(resolveServiceSignal([_kpi('Series', '9')])!.label, 'series');
      });
    });
  });
}

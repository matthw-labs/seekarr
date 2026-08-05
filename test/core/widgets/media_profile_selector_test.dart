import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/widgets/header_action_row.dart';
import 'package:seekarr/core/widgets/media_profile_selector.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

const _profiles = <Map<String, dynamic>>[
  {'id': 1, 'name': 'HD-1080p'},
  {'id': 2, 'name': 'Ultra-HD'},
];

void main() {
  group('MediaProfileSelector', () {
    testWidgets('the default variant does not hand-roll its own gesture', (
      tester,
    ) async {
      await _pump(
        tester,
        MediaProfileSelector(
          currentProfileName: 'HD-1080p',
          currentProfileId: 1,
          qualityProfiles: _profiles,
          onProfileSelected: (_) async {},
          accent: ServiceKey.sonarr.accent,
        ),
      );

      // PressableScale is the sole home of the press-scale, the haptic, the
      // Reduce Motion check and the button role; a raw InkWell drops all four.
      // (The two button variants reach ink through Material's own buttons, which
      // is the sanctioned route.)
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(PressableScale), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the default variant is a named button target', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        MediaProfileSelector(
          currentProfileName: 'HD-1080p',
          currentProfileId: 1,
          qualityProfiles: _profiles,
          onProfileSelected: (_) async {},
          accent: ServiceKey.sonarr.accent,
        ),
      );

      expect(find.byType(PressableScale), findsOneWidget);
      expect(find.semantics.byLabel('Quality profile: HD-1080p'), findsOne);
      expect(
        tester.getSize(find.byType(PressableScale)).height,
        greaterThanOrEqualTo(44),
      );
      handle.dispose();
    });

    // `.iconOnly` and `.split` are gone — both had zero call sites in `lib/`
    // once the overflow sheet's "Quality profile: <name>" row replaced the
    // icon-only button and `MediaManagementRow` was deleted. The assertion they
    // carried — that the control is sized off the ONE shared floor rather than a
    // local number — moves onto the surviving variant.
    testWidgets('the only variant is sized off the shared action floor', (
      tester,
    ) async {
      await _pump(
        tester,
        MediaProfileSelector(
          currentProfileName: 'HD-1080p',
          currentProfileId: 1,
          qualityProfiles: _profiles,
          onProfileSelected: (_) async {},
          accent: ServiceKey.sonarr.accent,
        ),
      );

      expect(
        tester.getSize(find.byType(PressableScale)).height,
        greaterThanOrEqualTo(HeaderActionRow.buttonHeight),
      );
    });
  });

  group('showMediaProfileSelector', () {
    testWidgets('every row is a PressableScale target of at least 44pt', (
      tester,
    ) async {
      await _pumpPicker(tester);

      expect(find.byType(PressableScale), findsNWidgets(_profiles.length));
      expect(find.byType(ListTile), findsNothing);
      for (final name in const ['HD-1080p', 'Ultra-HD']) {
        final row = find
            .ancestor(
              of: find.text(name),
              matching: find.byType(PressableScale),
            )
            .first;
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('the selected row is announced, not only coloured', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpPicker(tester);

      expect(
        find.semantics.byLabel('HD-1080p').first,
        containsSemantics(value: 'Selected'),
      );
      handle.dispose();
    });

    testWidgets('the selected row takes the page accent, not primary', (
      tester,
    ) async {
      await _pumpPicker(tester, accent: ServiceKey.sonarr.accent);

      final check = tester.widget<Icon>(
        find.byIcon(Icons.check_circle_rounded),
      );
      final context = tester.element(find.text('HD-1080p'));
      expect(check.color, isNot(Theme.of(context).colorScheme.primary));
    });

    testWidgets('re-picking the current profile writes nothing', (
      tester,
    ) async {
      var writes = 0;
      await _pumpPicker(tester, onProfileSelected: (_) async => writes++);

      await tester.tap(find.text('HD-1080p'));
      await tester.pumpAndSettle();
      // A no-op write to a quality profile can still queue an upgrade sweep.
      expect(writes, 0);
    });

    testWidgets('picking a different profile writes once', (tester) async {
      var written = <int>[];
      await _pumpPicker(
        tester,
        onProfileSelected: (id) async => written.add(id),
      );

      await tester.tap(find.text('Ultra-HD'));
      await tester.pumpAndSettle();
      expect(written, [2]);
    });
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  Color? accent,
  Future<void> Function(int profileId)? onProfileSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMediaProfileSelector(
              context,
              currentProfileName: 'HD-1080p',
              currentProfileId: 1,
              qualityProfiles: _profiles,
              onProfileSelected: onProfileSelected ?? (_) async {},
              accent: accent,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/domain_section.dart';
import 'package:cupola/core/widgets/media_detail_section_label.dart';
import 'package:cupola/core/widgets/section_header.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('SectionHeader', () {
    testWidgets('is one heading, not a title plus a nameless chevron', (
      tester,
    ) async {
      await _pump(
        tester,
        SectionHeader(
          title: 'Authors',
          subtitle: '42 in library',
          semanticHint: 'See all',
          onTap: () {},
        ),
      );

      expect(
        find.semantics.byLabel('Authors, 42 in library'),
        containsSemantics(
          isHeader: true,
          isButton: true,
          hasTapAction: true,
          hint: 'See all',
        ),
      );
      // Title and subtitle used to be two separate stops, and the subtitle has
      // no context read on its own.
      expect(find.semantics.byLabel('42 in library'), findsNothing);
    });

    testWidgets('a non-tappable header is a heading and not a button', (
      tester,
    ) async {
      await _pump(tester, const SectionHeader(title: 'Topology'));

      expect(
        find.semantics.byLabel('Topology'),
        containsSemantics(isHeader: true, isButton: false),
      );
    });

    testWidgets('.action keeps an interactive trailing reachable', (
      tester,
    ) async {
      // The regression guard for the whole nested-control design: silencing the
      // subtree wholesale would delete this button from the tree, and it is the
      // only interaction the section has.
      var pressed = false;
      await _pump(
        tester,
        SectionHeader.action(
          title: 'Snapshots',
          trailing: TextButton(
            onPressed: () => pressed = true,
            child: const Text('New'),
          ),
        ),
      );

      expect(
        find.semantics.byLabel('Snapshots'),
        containsSemantics(isHeader: true),
      );
      expect(
        find.semantics.byLabel('New'),
        containsSemantics(isButton: true, hasTapAction: true),
      );

      await tester.tap(find.text('New'));
      expect(pressed, isTrue);
    });

    testWidgets('semanticLabel carries a trailing the header silences', (
      tester,
    ) async {
      await _pump(
        tester,
        const SectionHeader(
          title: 'Radarr',
          semanticLabel: 'Radarr, 7 items',
          trailing: Text('7'),
        ),
      );

      expect(
        find.semantics.byLabel('Radarr, 7 items'),
        containsSemantics(isHeader: true),
      );
      expect(find.semantics.byLabel('7'), findsNothing);
    });
  });

  group('MediaDetailSectionLabel', () {
    // The detail pages' heading widget. Registered here beside [SectionHeader]
    // because it makes the same three promises — one heading node, the
    // original-case string in the ear, and an interactive trailing that survives
    // the silencing — and a seven-region page had no heading rotor at all until
    // it did.
    testWidgets('is one heading node with the count folded in', (tester) async {
      await _pump(
        tester,
        const MediaDetailSectionLabel(
          label: 'Missing subtitles',
          accent: Color(0xFF8B5CF6),
          count: '3 missing · 2 languages',
        ),
      );

      expect(
        find.semantics.byLabel('Missing subtitles, 3 missing · 2 languages'),
        containsSemantics(isHeader: true),
      );
      // Uppercase belongs in the eye, not in the ear.
      expect(find.semantics.byLabel('MISSING SUBTITLES'), findsNothing);
      expect(find.semantics.byLabel('3 missing · 2 languages'), findsNothing);
    });

    testWidgets('an action stays reachable inside the heading', (tester) async {
      var pressed = false;
      await _pump(
        tester,
        MediaDetailSectionLabel(
          label: 'Episodes',
          accent: const Color(0xFF8B5CF6),
          action: TextButton(
            onPressed: () => pressed = true,
            child: const Text('S3 of 40'),
          ),
        ),
      );

      expect(
        find.semantics.byLabel('S3 of 40'),
        containsSemantics(isButton: true, hasTapAction: true),
      );
      await tester.tap(find.text('S3 of 40'));
      expect(pressed, isTrue);
    });
  });

  group('AppCard', () {
    testWidgets('an unlabelled tappable card is left alone', (tester) async {
      // No label means no wrapper: the InkWell keeps its own tap semantics, so
      // existing call sites are unaffected until they opt in.
      await _pump(
        tester,
        AppCard.outlined(onTap: () {}, child: const Text('Body')),
      );

      expect(find.semantics.byLabel('Body'), findsOneWidget);
    });

    testWidgets('a labelled card is one named button with a tap action', (
      tester,
    ) async {
      var tapped = false;
      await _pump(
        tester,
        AppCard.outlined(
          key: const ValueKey('card'),
          onTap: () => tapped = true,
          semanticLabel: 'Radarr',
          semanticValue: 'Online',
          excludeChildSemantics: true,
          child: const Column(
            children: [Text('Radarr'), Text('ONLINE'), Text('radarr.local')],
          ),
        ),
      );

      // hasTapAction is the load-bearing assertion: excludeSemantics drops the
      // InkWell's action along with its labels, so the wrapper must forward it.
      expect(
        tester.getSemantics(find.byKey(const ValueKey('card'))),
        containsSemantics(
          label: 'Radarr',
          value: 'Online',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(find.semantics.byLabel('ONLINE'), findsNothing);
      expect(find.semantics.byLabel('radarr.local'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('card')));
      expect(tapped, isTrue);
    });

    testWidgets('a nested control stays reachable when not excluded', (
      tester,
    ) async {
      var menuPressed = false;
      await _pump(
        tester,
        AppCard.outlined(
          onTap: () {},
          semanticLabel: 'Furiosa, downloading',
          child: Row(
            children: [
              const Expanded(child: ExcludeSemantics(child: Text('Furiosa'))),
              IconButton(
                tooltip: 'Search options',
                onPressed: () => menuPressed = true,
                icon: const Icon(Icons.search),
              ),
            ],
          ),
        ),
      );

      expect(
        find.semantics.byLabel('Furiosa, downloading'),
        containsSemantics(isButton: true),
      );

      // An icon button's accessible name comes from its tooltip, which lands in
      // SemanticsData.tooltip rather than label. Asserting on it is also the
      // discriminator that matters: getSemantics walks up past merged nodes, so
      // if the card had absorbed this button we would get the card's node back —
      // and the card has no tooltip.
      expect(
        tester.getSemantics(find.byTooltip('Search options')),
        containsSemantics(
          tooltip: 'Search options',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.byTooltip('Search options'));
      expect(menuPressed, isTrue);
    });
  });

  group('SettingsCard', () {
    testWidgets('composes title, status icon meaning and subtitle', (
      tester,
    ) async {
      // subtitleLeading is a bare glyph whose whole meaning is its shape, so
      // without subtitleLeadingLabel the connection state is simply unreadable.
      await _pump(
        tester,
        const SettingsGroupCard(
          children: [
            SettingsCard.grouped(
              leading: Icon(Icons.movie),
              title: 'Radarr',
              subtitle: 'radarr.local:7878',
              subtitleLeading: Icon(Icons.cloud_done_rounded),
              subtitleLeadingLabel: 'Connected',
              semanticHint: 'opens Radarr settings',
            ),
          ],
        ),
      );

      expect(
        find.semantics.byLabel('Radarr, Connected, radarr.local:7878'),
        containsSemantics(isHeader: false),
      );
      expect(find.semantics.byLabel('radarr.local:7878'), findsNothing);
    });

    testWidgets('a row with a delete button keeps both reachable', (
      tester,
    ) async {
      var deleted = false;
      var opened = false;
      await _pump(
        tester,
        SettingsGroupCard(
          children: [
            SettingsCard.grouped(
              title: 'Radarr',
              subtitle: 'radarr.local:7878',
              onTap: () => opened = true,
              trailing: IconButton(
                tooltip: 'Remove credentials',
                onPressed: () => deleted = true,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ),
          ],
        ),
      );

      expect(
        find.semantics.byLabel('Radarr, radarr.local:7878'),
        containsSemantics(isButton: true, hasTapAction: true),
      );

      // `trailing` is the one slot SettingsCard does not silence, so the delete
      // button must still be its own node. If the row had absorbed it,
      // getSemantics would return the row's node, which carries no tooltip.
      expect(
        tester.getSemantics(find.byTooltip('Remove credentials')),
        containsSemantics(
          tooltip: 'Remove credentials',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.byTooltip('Remove credentials'));
      expect(deleted, isTrue);
      expect(opened, isFalse);
    });
  });

  group('AsyncValueWidget', () {
    testWidgets('a loading skeleton says so instead of reading as empty', (
      tester,
    ) async {
      await _pump(
        tester,
        const AsyncValueWidget<int>(
          value: AsyncValue.loading(),
          serviceName: 'Radarr',
          skeleton: SizedBox(width: 100, height: 100),
          data: _neverBuilt,
        ),
      );

      expect(find.semantics.byLabel('Loading Radarr'), findsOneWidget);
    });

    testWidgets('loadingLabel overrides the default', (tester) async {
      await _pump(
        tester,
        const AsyncValueWidget<int>(
          value: AsyncValue.loading(),
          serviceName: 'Radarr',
          loadingLabel: 'Searching for releases',
          data: _neverBuilt,
        ),
      );

      expect(find.semantics.byLabel('Searching for releases'), findsOneWidget);
    });
  });

  group('CollapsibleDomainSection', () {
    testWidgets('exposes expanded state and the un-uppercased label', (
      tester,
    ) async {
      await _pump(
        tester,
        const CollapsibleDomainSection(
          label: 'Media',
          trailing: Text('3/4'),
          child: Text('Body'),
        ),
      );

      // The chevron rotation is the visual cue; without `expanded:` there is no
      // way to tell whether a tap will open or close the group.
      expect(
        find.semantics.byLabel('Media'),
        containsSemantics(
          isHeader: true,
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ),
      );
      // '.toUpperCase()' is typography and must not reach the label.
      expect(find.semantics.byLabel('MEDIA'), findsNothing);
      // The trailing count keeps a node of its own.
      expect(find.semantics.byLabel('3/4'), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(
        find.semantics.byLabel('Media'),
        containsSemantics(hasExpandedState: true, isExpanded: true),
      );
    });
  });

  group('DomainSectionHeader', () {
    testWidgets('is marked as a heading with the spoken label', (tester) async {
      await _pump(tester, const DomainSectionHeader(label: 'Downloads'));

      expect(
        find.semantics.byLabel('Downloads'),
        containsSemantics(isHeader: true),
      );
      expect(find.semantics.byLabel('DOWNLOADS'), findsNothing);
    });
  });
}

Widget _neverBuilt(int _) =>
    throw StateError('data builder must not run while loading');

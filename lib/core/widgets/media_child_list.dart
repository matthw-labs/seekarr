/// The one `container -> children` vocabulary: a dense child row
/// ([MediaChildTile]) and the lazy sliver region that hosts a set of them
/// ([MediaChildGroupSliver]).
///
/// It replaces three implementations of the same idea that had drifted apart —
/// a `_SeasonPill` + panel in `series_seasons_list.dart`, a near-duplicate of it
/// in `discover_seasons_list.dart`, and an `ExpansionTile` in
/// `music_albums_list.dart`. Between them they had five defects worth naming,
/// because each is a class of mistake rather than a one-off:
///
/// - **State by colour alone.** Both episode and track rows drew a 7pt circle
///   filled `colorScheme.primary` or `colorScheme.outline` — the same eight
///   lines copied into two files, in files with *zero* `Semantics`. Nothing on
///   the page said what the fill meant, and a screen reader got nothing at all.
///   Here the state is a resolved [MediaStatusInfo]: the tile speaks
///   [MediaStatusInfo.semanticLabel] as its value, draws it through
///   [StatusBadge], and the caller is required to put a status *word* in [facts]
///   for anything that is not plainly available.
/// - **A second accent.** That `primary` indigo landed on a violet Sonarr page
///   and a pink Lidarr page. Every colour here is either the page accent handed
///   in once, or the resolved status tone via [statusToneColor].
/// - **Nothing to decide with.** A row was a number, a one-line truncated title
///   and — twenty-five times over — the same magnifier glyph. [facts] is the
///   slot that fixes that, and both text runs wrap to two lines instead of
///   eliding at the first accessibility step.
/// - **250 rows built to show 8.** The old lists were a `Column` inside one
///   `SliverToBoxAdapter`. [MediaChildGroupSliver] is a real sliver, so its
///   children go through `SliverList.builder` and stay lazy while still landing
///   mid-page.
/// - **Three "this one is selected" languages.** The season pills were
///   `ChoiceChip`s: full radius on an *interactive* control, which the
///   Pill-for-Metadata Rule reserves for metadata, and a selected state
///   (a small check plus a slightly different fill) distinct from the browse
///   filters directly above them. The selector is [SelectionPills] now — the
///   same 20dp accent-tinted treatment as the navigation bar and the Activity
///   segments.
library;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/media_metadata_line.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// The status as a word for a child row's [MediaChildTile.facts] line, or null
/// when the row needs none.
///
/// A [StatusBadge] in a dense row is a tone-coloured dot or glyph and nothing
/// more, so its meaning reaches a screen reader (through the tile's spoken
/// value) but not a sighted low-vision user. A wall of twenty-five quiet green
/// dots is correct and wants no text; the exceptions have to carry some. So this
/// returns the pipeline state while something is in flight, the status label
/// while anything is outstanding, and null once the row is simply on disk.
String? mediaStatusWord(MediaStatusInfo? status) {
  if (status == null) return null;
  final pipeline = status.pipeline;
  if (pipeline != null) {
    final percent = status.progressPercent;
    return percent == null ? pipeline.label : '${pipeline.label} $percent%';
  }
  if (status.availability == MediaAvailability.available) return null;
  return status.label;
}

/// One dense row inside a `container -> children` region: an episode, a track,
/// an album, a season in the picker sheet.
///
/// Two shapes, as named constructors rather than a flag:
/// [MediaChildTile.numbered] leads with a tabular ordinal column, and
/// [MediaChildTile.stacked] leads with artwork and can draw its own progress
/// bar.
class MediaChildTile extends StatelessWidget {
  /// Base width of the ordinal column at the default reading size.
  ///
  /// Grown by the clamped reading scale rather than fixed, and applied as a
  /// *minimum* so a long ordinal widens the column instead of clipping in it.
  /// Tabular figures then keep `E09` and `E10` on the same advance width.
  static const double _ordinalBaseWidth = 30;

  final String? ordinal;

  /// What [ordinal] is, in words. `E04` reads as "E zero four" otherwise.
  ///
  /// Pass an empty string to drop it from the spoken name entirely — the season
  /// picker does that, because its title already says "Season 3".
  final String? ordinalLabel;

  final Widget? leading;
  final String title;

  /// Decidable metadata: an air date, a duration, counts, and — per
  /// [mediaStatusWord] — the status in words whenever the row is not plainly
  /// available. A row without at least one of these is the arr-web-UI table
  /// this region exists to replace.
  final List<String> facts;

  /// The resolved status, from the feature's `domain/` layer.
  ///
  /// Nullable on purpose. Seerr models availability per *season* and not per
  /// episode, so a Seerr episode row genuinely has no status of its own and
  /// inventing one would be worse than omitting it.
  final MediaStatusInfo? status;

  /// Completion in `0..1`, drawn tinted by [status]'s tone.
  final double? progress;

  final VoidCallback? onTap;

  /// A control — a search menu — that stays reachable: it is the one slot this
  /// row does not silence.
  final Widget? trailing;

  final String? semanticHint;

  final bool _stacked;

  const MediaChildTile.numbered({
    super.key,
    required this.ordinal,
    required this.title,
    this.ordinalLabel,
    this.facts = const <String>[],
    this.status,
    this.onTap,
    this.trailing,
    this.semanticHint,
  }) : leading = null,
       progress = null,
       _stacked = false;

  const MediaChildTile.stacked({
    super.key,
    required this.leading,
    required this.title,
    this.facts = const <String>[],
    this.status,
    this.progress,
    this.onTap,
    this.trailing,
    this.semanticHint,
  }) : ordinal = null,
       ordinalLabel = null,
       _stacked = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedStatus = status;
    final resolvedProgress = progress;

    final spokenLabel = <String>[
      if (ordinalLabel != null)
        ordinalLabel!
      else if (ordinal != null)
        ordinal!,
      title,
      ...facts,
    ].where((part) => part.trim().isNotEmpty).join(', ');

    return AppCard.filled(
      // A ~56pt row floods its own splash, and a flooded ripple reads as
      // selection rather than as a touch — the Ripple-Needs-Room Rule. So the
      // row dips instead.
      pressFeedback: AppCardPressFeedback.scale,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: onTap,
      semanticLabel: spokenLabel,
      semanticValue: resolvedStatus?.semanticLabel,
      semanticHint: semanticHint,
      child: Row(
        children: [
          if (ordinal != null) ...[
            ExcludeSemantics(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: TextScaleMetrics.clampedScalerOf(
                    context,
                  ).scale(_ordinalBaseWidth),
                ),
                child: Text(
                  ordinal!,
                  // A fixed-width column of ordinals: tabular figures are what
                  // keep 09 and 10 aligned down the list.
                  style: theme.textTheme.labelSmall!
                      .weight(FontWeight.w700)
                      .tabular
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (leading != null) ...[
            ExcludeSemantics(child: leading!),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    // Two lines, not one: "a one-line truncated title" was the
                    // observed defect, and the row has no fixed height to
                    // protect.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
                  ),
                  if (facts.isNotEmpty)
                    MediaMetadataLine(items: facts, maxLines: 2),
                  if (resolvedProgress != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    ClipRRect(
                      borderRadius: AppRadius.borderRadiusXs,
                      child: LinearProgressIndicator(
                        value: resolvedProgress.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          resolvedStatus == null
                              ? colorScheme.onSurfaceVariant
                              : statusToneColor(
                                  colorScheme,
                                  resolvedStatus.tone,
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (resolvedStatus != null) ...[
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(
              info: resolvedStatus,
              iconOnly: !_stacked,
              compact: _stacked,
              // The tile's own node already speaks the status as its value;
              // without this the row and the badge are two stops for one fact.
              excludeFromSemantics: true,
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// One resolved container in a [MediaChildGroupSliver] — a season.
///
/// A plain value type on purpose: the status arrives already resolved from the
/// feature's `domain/` layer, so the widget renders a decision rather than
/// making one. `discover_seasons_list.dart` used to map a raw
/// `Map<String, dynamic>` into per-season availability inside `build`.
@immutable
class MediaChildGroup {
  /// Stable identity — a season number.
  final int id;

  /// One-line pill label: `S3`, `Sp`.
  final String shortLabel;

  /// Full name for the summary line, the picker and assistive technology.
  final String label;

  final MediaStatusInfo status;

  /// The manifest gap in words: `8 of 10 episodes`.
  final String? summary;

  /// Completion in `0..1`, drawn only when it is strictly between the ends.
  final double? progress;

  const MediaChildGroup({
    required this.id,
    required this.shortLabel,
    required this.label,
    required this.status,
    this.summary,
    this.progress,
  });
}

/// A lazy `container -> children` region: a selector rail over the selected
/// container's summary, then its children built on demand.
///
/// Returns **slivers**, so it must be handed to a sliver slot —
/// `MediaDetailSlot.lazy(sliver: ...)`. That is what makes the child list lazy
/// *and* keeps it mid-page: a 250-episode season builds the rows on screen
/// instead of all 250.
class MediaChildGroupSliver extends StatefulWidget {
  /// Containers in display order. The caller sorts; this widget never reorders.
  final List<MediaChildGroup> groups;

  /// The page accent. The only accent this region uses.
  final Color accent;

  final int Function(MediaChildGroup group) childCount;

  final Widget Function(BuildContext context, MediaChildGroup group, int index)
  childBuilder;

  /// Returns a non-null widget to replace the child list entirely — a shimmer,
  /// a named failure with a retry, an empty state.
  final Widget? Function(BuildContext context, MediaChildGroup group)?
  childOverride;

  /// A control for the selected container's summary line (a search menu).
  final Widget? Function(BuildContext context, MediaChildGroup group)?
  groupAction;

  /// Rendered instead of everything else when there are no containers at all.
  final Widget emptyState;

  /// Label of the picker control, count included: `All 40 seasons`.
  ///
  /// The answer to an unbounded horizontal rail that had neither a count nor a
  /// way to reach season 40 without scrubbing. Built by the caller so the noun
  /// and its plural stay in the feature's own voice.
  final String pickerLabel;

  /// Title of the picker sheet: `Seasons`.
  final String pickerTitle;

  /// The feature's own plural for a child: `episodes`, `tracks`.
  ///
  /// Supplied by the caller so the collapse control can name what it is hiding —
  /// "Show all 25 episodes", never "Show all items". The visible label carries
  /// it too, because a count without its noun is a number floating under a list.
  final String childNoun;

  const MediaChildGroupSliver({
    super.key,
    required this.groups,
    required this.accent,
    required this.childCount,
    required this.childBuilder,
    required this.emptyState,
    required this.pickerLabel,
    required this.pickerTitle,
    required this.childNoun,
    this.childOverride,
    this.groupAction,
  });

  /// Children shown before the collapse control takes over.
  ///
  /// Eight is a season of a limited series in full, roughly a phone's worth of
  /// rows, and enough of a 25-episode season to establish the shape of the list
  /// before the page hands the scroll back to everything below it. Lower and a
  /// four-track album would collapse for no reason; higher and a 250-episode
  /// season still buries the regions under it.
  static const int collapsedChildCount = 8;

  @override
  State<MediaChildGroupSliver> createState() => _MediaChildGroupSliverState();
}

class _MediaChildGroupSliverState extends State<MediaChildGroupSliver> {
  int? _selectedId;

  MediaChildGroup get _selectedGroup {
    final selectedId = _selectedId;
    if (selectedId != null) {
      for (final group in widget.groups) {
        if (group.id == selectedId) return group;
      }
    }

    return widget.groups.first;
  }

  /// Whether the selected container's children are fully shown.
  ///
  /// Deliberately reset on every [_select]: expanding season 1 and then tapping
  /// season 2 must not drop the user into 25 rows they never asked for.
  bool _expanded = false;

  void _select(int id) {
    // Compared against the *effective* selection, not against `_selectedId`.
    // Until the first tap `_selectedId` is null while the rail already highlights
    // `groups.first`, and `SelectionPills` fires `onSelected` unconditionally —
    // so tapping the already-selected first pill fell straight through this
    // guard and reset `_expanded`, silently collapsing an expanded 25-episode
    // season back to eight rows.
    // The emptiness test comes first because `_selectedGroup` reads
    // `groups.first`: the picker awaits a sheet, and the containers can be gone
    // by the time it answers.
    if (widget.groups.isEmpty || _selectedGroup.id == id) return;
    setState(() {
      _selectedId = id;
      _expanded = false;
    });
  }

  Future<void> _openPicker(BuildContext context) async {
    final chosen = await AppBottomSheet.show<int>(
      context: context,
      title: widget.pickerTitle,
      icon: Icons.playlist_play_rounded,
      accent: widget.accent,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final group in widget.groups)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: MediaChildTile.numbered(
                ordinal: group.shortLabel,
                // The title already says "Season 3"; the ordinal column is a
                // scannable rail for the eye, not a second announcement.
                ordinalLabel: '',
                title: group.label,
                facts: <String>[
                  if (group.summary != null) group.summary!,
                  if (mediaStatusWord(group.status) != null)
                    mediaStatusWord(group.status)!,
                ],
                status: group.status,
                onTap: () => Navigator.of(sheetContext).pop(group.id),
              ),
            ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;
    _select(chosen);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return SliverToBoxAdapter(child: widget.emptyState);
    }

    final selected = _selectedGroup;
    final override = widget.childOverride?.call(context, selected);
    final totalCount = widget.childCount(selected);
    final shownCount = _expanded
        ? totalCount
        : totalCount.clamp(0, MediaChildGroupSliver.collapsedChildCount);

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _GroupSelector(
            groups: widget.groups,
            selected: selected,
            accent: widget.accent,
            pickerLabel: widget.pickerLabel,
            action: widget.groupAction?.call(context, selected),
            onSelected: _select,
            onOpenPicker: () => _openPicker(context),
          ),
        ),
        if (override != null)
          SliverToBoxAdapter(child: override)
        else ...[
          SliverList.builder(
            // Keyed by container so switching seasons swaps the list outright
            // instead of updating 250 elements in place.
            key: ValueKey<int>(selected.id),
            // Capping the count is what keeps the collapse lazy: a collapsed
            // 250-episode season builds eight rows, not 250 with 242 hidden.
            itemCount: shownCount,
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.xs),
              child: widget.childBuilder(context, selected, index),
            ),
          ),
          if (totalCount > MediaChildGroupSliver.collapsedChildCount)
            SliverToBoxAdapter(
              child: _CollapseToggle(
                expanded: _expanded,
                totalCount: totalCount,
                childNoun: widget.childNoun,
                accent: widget.accent,
                onToggle: () => setState(() => _expanded = !_expanded),
              ),
            ),
        ],
      ],
    );
  }
}

/// The footer control that reveals the rest of a container's children.
///
/// A plain rebuild rather than an animated reveal: an implicit `AnimatedSize`
/// around a rebuilt list is what the project bans outright, and a zero-duration
/// one re-dirties itself inside its own `performLayout` and trips a framework
/// assert — so there is no animator here to gate on Reduce Motion.
class _CollapseToggle extends StatelessWidget {
  final bool expanded;
  final int totalCount;
  final String childNoun;
  final Color accent;
  final VoidCallback onToggle;

  const _CollapseToggle({
    required this.expanded,
    required this.totalCount,
    required this.childNoun,
    required this.accent,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // "Show fewer" and not "Collapse": collapse is a chrome word, and this
    // control is about quantity, not geometry. The visible label stays short
    // because it sits under a full-width list at any reading size, while the
    // accessible name carries the noun so a reader hears what shrinks.
    final label = expanded ? 'Show fewer' : 'Show all $totalCount $childNoun';
    final semanticLabel = expanded ? 'Show fewer $childNoun' : label;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: ExcludeSemantics(
          child: TextButton.icon(
            onPressed: onToggle,
            icon: Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
            ),
            label: Text(label, maxLines: 2, textAlign: TextAlign.center),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              // A floor rather than a fixed height, so the label may still grow
              // with the reading size.
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
      ),
    );
  }
}

/// The picker control, the pill rail and the selected container's summary.
class _GroupSelector extends StatelessWidget {
  final List<MediaChildGroup> groups;
  final MediaChildGroup selected;
  final Color accent;
  final String pickerLabel;
  final Widget? action;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenPicker;

  const _GroupSelector({
    required this.groups,
    required this.selected,
    required this.accent,
    required this.pickerLabel,
    required this.action,
    required this.onSelected,
    required this.onOpenPicker,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dimText =
        theme.extension<CupolaThemeColors>()?.dimText ??
        colorScheme.onSurfaceVariant;
    final progress = selected.progress;
    // Same threshold and the same scaler-not-LayoutBuilder rationale as
    // `SectionHeader`: past 1.4x the label and its controls stop fitting on one
    // line, and a reading size is not a window width.
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4;
    // Six short pills and their gaps are about what a phone shows without
    // scrubbing, and a grown reading size spends that budget on fewer. Keyed off
    // the scaler and not a `LayoutBuilder` for the same reason `SectionHeader`
    // is: a reading size is not a window width, and a shared widget sits inside
    // callers that ask it for intrinsic dimensions.
    final showPicker = groups.length > 6 || stacked;

    final summaryTitle = Semantics(
      container: true,
      label: <String>[
        selected.label,
        if (selected.summary != null) selected.summary!,
      ].join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected.label,
              style: theme.textTheme.titleSmall!.weight(FontWeight.w700),
            ),
            if (selected.summary != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                selected.summary!,
                // Counts that climb as children import.
                style: theme.textTheme.labelSmall!.tabular.copyWith(
                  color: dimText,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final summaryTrailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusBadge(info: selected.status),
        if (action != null) ...[const SizedBox(width: AppSpacing.xs), action!],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groups.length > 1) ...[
          Row(
            children: [
              Expanded(
                child: SelectionPills<int>(
                  values: groups
                      .map((group) => group.id)
                      .toList(growable: false),
                  selected: selected.id,
                  accent: accent,
                  labelBuilder: (id) =>
                      groups.firstWhere((group) => group.id == id).shortLabel,
                  onSelected: onSelected,
                ),
              ),
              // The jump-to exists only where the rail genuinely cannot serve.
              // It used to render on its own right-aligned row above the pills
              // whenever there was more than one container, so a five-season
              // series got a control that duplicated the five pills below it in
              // a band of dead space. Past the threshold — or once a reading size
              // has grown the pills — reaching season 40 without scrubbing is a
              // real problem, and then it earns the space, at the end of the rail
              // it belongs to rather than above it.
              if (showPicker) ...[
                const SizedBox(width: AppSpacing.xs),
                SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    onPressed: onOpenPicker,
                    // The count lives in the accessible name and the tooltip:
                    // spelling it out beside the rail would eat the width the
                    // pills need, which is the space this control is here to
                    // give back.
                    tooltip: pickerLabel,
                    icon: const Icon(Icons.unfold_more_rounded, size: 18),
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
        if (stacked)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              summaryTitle,
              const SizedBox(height: AppSpacing.sm),
              summaryTrailing,
            ],
          )
        else
          Row(
            children: [
              Expanded(child: summaryTitle),
              const SizedBox(width: AppSpacing.sm),
              summaryTrailing,
            ],
          ),
        if (progress != null && progress > 0 && progress < 1) ...[
          const SizedBox(height: AppSpacing.sm),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: AppRadius.borderRadiusXs,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  statusToneColor(colorScheme, selected.status.tone),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

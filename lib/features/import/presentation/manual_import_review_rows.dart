import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/import/domain/manual_import_display.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/domain/manual_import_status.dart';
import 'package:cupola/features/import/presentation/manual_import_widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _rowMargin = EdgeInsets.fromLTRB(
  AppSpacing.lg,
  0,
  AppSpacing.lg,
  AppSpacing.sm,
);

/// A filename that keeps both ends legible.
///
/// A release filename carries its identity at the front and its evidence at the
/// back — `Boruto.S01E12.1080p.WEB-DL.x264-GROUP.mkv`. A trailing ellipsis
/// deletes exactly the half that answers "is this the right file?", so the
/// elision is moved to the middle and both ends survive.
///
/// The split point is measured rather than guessed. A fixed character budget
/// would be wrong at every reading size but one, and pinning the tail in a
/// `Row` overflows the moment the tail alone outgrows the row — which is how
/// the first version painted overflow stripes at accessibility text sizes.
class FilenameText extends StatelessWidget {
  final String filename;
  final TextStyle? style;

  /// Characters of the tail worth protecting: the release group and extension.
  ///
  /// Kept short on purpose. Quality, language and size already have a line of
  /// their own on these rows, so the filename's remaining job is to confirm the
  /// title and episode code — which live at the front — and the tail only needs
  /// to prove which file this is.
  static const _tailLength = 10;

  /// Separators that would otherwise collide with the ellipsis and read as a
  /// run of dots: `Next.…264` looked like `Next.....264`.
  static final _trailingSeparators = RegExp(r'[._\-\s]+$');

  const FilenameText({super.key, required this.filename, this.style});

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final text = _fit(
          available: constraints.maxWidth,
          style: resolvedStyle,
          textScaler: textScaler,
        );
        return Text(
          text,
          maxLines: 1,
          softWrap: false,
          // A last-resort guard: if even the shortest candidate cannot fit, the
          // framework elides instead of overflowing.
          overflow: TextOverflow.ellipsis,
          style: style,
          semanticsLabel: filename,
        );
      },
    );
  }

  /// The longest middle-elided form of [filename] that fits [available].
  String _fit({
    required double available,
    required TextStyle style,
    required TextScaler textScaler,
  }) {
    if (!available.isFinite) return filename;

    double widthOf(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    if (widthOf(filename) <= available) return filename;
    if (filename.length <= _tailLength + 4) return filename;

    final tail = filename.substring(filename.length - _tailLength);
    final head = filename.substring(0, filename.length - _tailLength);

    String candidate(int headLength) {
      final trimmed = head
          .substring(0, headLength)
          .replaceFirst(_trailingSeparators, '');
      return '$trimmed…$tail';
    }

    // Binary search the longest head that still leaves room for the tail.
    var low = 0;
    var high = head.length;
    var best = 0;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (widthOf(candidate(mid)) <= available) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    // No room for a head at all: the tail alone is the most useful thing left.
    if (best == 0) return '…$tail';
    return candidate(best);
  }
}

/// A short positional code — `S02E01`, a year, a track number.
class IdentityCodeChip extends StatelessWidget {
  final String code;
  final Color accent;

  const IdentityCodeChip({super.key, required this.code, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Text(
        code,
        style: theme.textTheme.labelSmall!
            .weight(FontWeight.w700)
            .tabular
            .copyWith(
              color: ServiceTheme.onTint(
                accent,
                surface: theme.colorScheme.surface,
                tintAlpha: 0.14,
              ),
            ),
      ),
    );
  }
}

/// One matched-media group in the list.
///
/// Carries the group's own select-all, which is the gesture that makes a
/// four-hundred file scan workable: take every episode of one series at once.
///
/// The select-all reaches only the group's [total] importable files, never the
/// [importedCount] the service already holds. Sending a file over the copy in
/// the library is a decision worth one deliberate tick; it is not something a
/// bulk gesture should do on the user's behalf.
class ReadyGroupHeader extends StatelessWidget {
  final ServiceKey service;
  final String title;

  /// Files in this group that are not yet in the library.
  final int total;

  /// Files in this group the service already holds.
  final int importedCount;

  final int selectedCount;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<bool> onSelectionChanged;

  const ReadyGroupHeader({
    super.key,
    required this.service,
    required this.title,
    required this.total,
    required this.importedCount,
    required this.selectedCount,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allSelected = selectedCount == total;
    final noneSelected = selectedCount == 0;
    final libraryNote = importedCount == 0 ? null : '$importedCount in library';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          // A group of nothing but already-imported files has no select-all to
          // offer, and a permanently empty checkbox beside it would read as a
          // control that does nothing.
          if (total == 0)
            const SizedBox(width: AppSpacing.lg)
          else
            Semantics(
              label: 'Select all $total files of $title',
              child: Checkbox(
                value: allSelected
                    ? true
                    : noneSelected
                    ? false
                    : null,
                tristate: true,
                activeColor: service.accent,
                checkColor: ServiceTheme.foregroundOn(service.accent),
                onChanged: (_) => onSelectionChanged(!allSelected),
              ),
            ),
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              header: true,
              expanded: expanded,
              label: title,
              value: [
                if (total > 0) '$selectedCount of $total selected',
                if (libraryNote != null) libraryNote,
              ].join(', '),
              hint: expanded ? 'collapses the group' : 'expands the group',
              onTap: onToggleExpanded,
              excludeSemantics: true,
              child: InkWell(
                onTap: onToggleExpanded,
                excludeFromSemantics: true,
                borderRadius: AppRadius.borderRadiusSm,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                    horizontal: AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall!.weight(
                                FontWeight.w700,
                              ),
                            ),
                            Text(
                              [
                                if (total > 0)
                                  selectedCount == 0
                                      ? '$total ${total == 1 ? 'file' : 'files'}'
                                      : '$selectedCount of $total selected',
                                if (libraryNote != null) libraryNote,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              // The selected count changes as rows are ticked.
                              style: theme.textTheme.labelSmall!.tabular
                                  .copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: AppAnimation.durationSm,
                        curve: AppAnimation.emphasizedCurve,
                        child: Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A matched file, arranged so the match can be checked at a glance.
///
/// The row answers one question — did the service guess right? — so it puts the
/// parsed identity directly above the filename it was parsed from, and never
/// lets a trailing ellipsis eat either one.
///
/// It adapts to its surroundings. Under a group header the matched title is
/// already overhead, so the row leads with the positional code and the episode
/// name. Standing alone (a movie, a one-file group) it carries the title itself
/// — repeating a header that is not there would be as bad as omitting one.
///
/// Two variants, because a scan holds two kinds of matched file and the list
/// interleaves them: [MatchedFileRow.ready] for one waiting to be imported and
/// [MatchedFileRow.imported] for one the service already holds. The imported
/// form deliberately does **not** live in a section of its own — S01E05 already
/// in the library belongs beside S01E06 in broadcast order, where the gap it
/// explains actually is. It reads as handled rather than pending through four
/// channels, only one of which is colour: the card steps down the surface
/// ladder, its hairline softens, its title takes the secondary ink, and its
/// badge says "Imported". Its checkbox still works — ticking one is how you ask
/// for a better rip to replace what is on disk.
class MatchedFileRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportItem item;
  final String groupTitle;

  /// Whether a [ReadyGroupHeader] is already naming the matched media above.
  final bool underGroupHeader;

  final bool selected;

  /// Null when this file cannot enter the selection at all — an imported file
  /// whose payload no longer carries a usable identity, which the service would
  /// reject outright.
  final ValueChanged<bool>? onSelectedChanged;

  final VoidCallback onOpenOptions;

  /// Whether the service already holds this file.
  final bool imported;

  const MatchedFileRow.ready({
    super.key,
    required this.service,
    required this.item,
    required this.groupTitle,
    required this.underGroupHeader,
    required this.selected,
    required this.onSelectedChanged,
    required this.onOpenOptions,
  }) : imported = false;

  const MatchedFileRow.imported({
    super.key,
    required this.service,
    required this.item,
    required this.groupTitle,
    required this.underGroupHeader,
    required this.selected,
    required this.onSelectedChanged,
    required this.onOpenOptions,
  }) : imported = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Ticked-and-imported is its own resolved status, not a selected-looking
    // "Imported": this file is going into the next batch, over the copy in the
    // library, and the badge is where that is stated.
    final reimporting = imported && selected;
    final info = manualImportItemStatus(
      service,
      item,
      reimportSelected: reimporting,
    );
    final identity = manualImportIdentityFor(service, item);
    final warning = info.hasWarning ? info.detail : null;

    final dimStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final strongStyle = theme.textTheme.titleSmall!
        .weight(FontWeight.w600)
        .copyWith(
          // Handled files recede a step in ink as well as in surface; a
          // re-import has been promoted back into the batch, so it comes
          // forward again.
          color: imported && !reimporting ? colorScheme.onSurfaceVariant : null,
        );

    // The row has exactly three lines and each one has exactly one job:
    //
    //  1. the matched identity — code chip plus matched names, never anything
    //     parsed out of the filename;
    //  2. the raw filename, and only ever the raw filename;
    //  3. the technical facts.
    //
    // The earlier version moved the filename to line 3 whenever there was no
    // group header above, and promoted it to the title when there was no child
    // name to show — so "the second line" meant the episode title on some rows
    // and the file on others, which is precisely what makes a match hard to
    // check at a glance.
    //
    // Under a group header the series/artist is already stated above, so the
    // line leads with the matched child (episode or album). Standing alone it
    // carries both, joined — both halves are matched values.
    final matchedLine = underGroupHeader
        ? (identity.title ?? groupTitle)
        : [groupTitle, if (identity.title != null) identity.title!].join(' · ');

    final identityName = [
      groupTitle,
      if (identity.code != null) identity.code!,
    ].join(' ');

    return Padding(
      padding: _rowMargin,
      child: AppCard.surfaceOutlined(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        // An imported row sits one step *down* the ladder — the same move
        // DESIGN.md uses for an unlit service cell, and the reason it reads as
        // handled without borrowing a status colour it has no business wearing.
        backgroundColor: reimporting
            ? service.accent.withValues(alpha: 0.06)
            : imported
            ? colorScheme.surfaceContainerLow
            : null,
        borderColor: reimporting
            ? service.accent.withValues(alpha: 0.45)
            : warning != null
            ? statusToneColor(
                colorScheme,
                StatusTone.warning,
              ).withValues(alpha: 0.35)
            : imported
            ? colorScheme.outlineVariant.withValues(alpha: 0.5)
            : null,
        onTap: onOpenOptions,
        semanticLabel: [
          groupTitle,
          if (identity.code != null) identity.code!,
          if (identity.title != null) identity.title!,
        ].join(', '),
        semanticValue: [
          item.fileName,
          if (identity.quality != null) identity.quality!,
          info.semanticLabel,
          if (warning != null) warning,
          if (imported) 'already in your ${service.title} library',
          if (selected)
            imported ? 'ticked to be imported again' : 'included in import',
        ].join(', '),
        semanticHint: 'opens quality, language and match options',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: imported
                  ? 'Import $identityName again'
                  : 'Include $identityName in import',
              hint: imported
                  ? 'replaces the copy already in your library'
                  : null,
              child: Checkbox(
                value: selected,
                activeColor: service.accent,
                checkColor: ServiceTheme.foregroundOn(service.accent),
                onChanged: onSelectedChanged == null
                    ? null
                    : (value) => onSelectedChanged!(value == true),
              ),
            ),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (identity.code != null) ...[
                          IdentityCodeChip(
                            code: identity.code!,
                            accent: service.accent,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Expanded(
                          child: Text(
                            matchedLine,
                            // One line, always. A wrapping title pushed the two
                            // lines below it down and left the status badge
                            // floating against nothing — the card's whole
                            // geometry came apart on any episode name longer
                            // than the row. Every line of this row is now
                            // exactly one line, so a group of them reads as a
                            // column of equal cards; the full title stays
                            // reachable through the row's own sheet, and its
                            // accessible name is never elided.
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: strongStyle,
                          ),
                        ),
                      ],
                    ),
                    // Line 2, unconditionally: the file on disk.
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: FilenameText(
                        filename: item.fileName,
                        style: dimStyle,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (identity.quality != null) identity.quality!,
                        item.languageLabel,
                        formatImportBytes(item.size),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: dimStyle,
                    ),
                    if (warning != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _RowNote.warning(text: warning),
                    ],
                    // Only once ticked: the consequence of a re-import is worth
                    // spelling out, and spelling it out on every imported row
                    // would be a paragraph of advice nobody asked for.
                    if (reimporting) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _RowNote.info(
                        text:
                            'Re-importing replaces the copy '
                            '${service.title} already holds.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(info: info, excludeFromSemantics: true),
          ],
        ),
      ),
    );
  }
}

/// A one-line consequence, tinted by its tone and stated in words.
///
/// [_RowNote.warning] carries the service's own caveat — a tone-only warning on
/// the badge told the user something was off and nothing about what, while the
/// reason sat in the payload the whole time. [_RowNote.info] carries what a
/// choice the user just made is going to do.
class _RowNote extends StatelessWidget {
  final String text;
  final StatusTone tone;
  final IconData icon;

  const _RowNote.warning({required this.text})
    : tone = StatusTone.warning,
      icon = Icons.warning_amber_rounded;

  const _RowNote.info({required this.text})
    : tone = StatusTone.info,
      icon = Icons.swap_horiz_rounded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = statusToneColor(theme.colorScheme, this.tone);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall!
                  .weight(FontWeight.w600)
                  .copyWith(
                    color: ServiceTheme.onTint(
                      tone,
                      surface: theme.colorScheme.surface,
                      tintAlpha: 0.1,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An unmatched file: the service's rejection up front, one tap into the fix
/// flow, plus a tick that adds it to a shared assignment.
class AttentionFileRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportItem item;
  final bool picked;
  final ValueChanged<bool> onPickedChanged;
  final VoidCallback onFix;

  const AttentionFileRow({
    super.key,
    required this.service,
    required this.item,
    required this.picked,
    required this.onPickedChanged,
    required this.onFix,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = manualImportItemStatus(service, item);

    return Padding(
      padding: _rowMargin,
      child: AppCard.surfaceOutlined(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        borderColor: picked ? service.accent.withValues(alpha: 0.45) : null,
        backgroundColor: picked ? service.accent.withValues(alpha: 0.06) : null,
        onTap: onFix,
        semanticLabel: item.fileName,
        semanticValue: [
          info.semanticLabel,
          if (info.detail != null) info.detail!,
          if (picked) 'ticked for shared assignment',
        ].join(', '),
        semanticHint: 'opens match assignment',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: 'Assign ${item.fileName} together with other files',
              child: Checkbox(
                value: picked,
                activeColor: service.accent,
                checkColor: ServiceTheme.foregroundOn(service.accent),
                onChanged: (value) => onPickedChanged(value == true),
              ),
            ),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilenameText(
                      filename: item.fileName,
                      style: theme.textTheme.titleSmall!.weight(
                        FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.firstRejectionReason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.extension} · ${formatImportBytes(item.size)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(info: info, excludeFromSemantics: true),
            // The affordance that says this row opens something. Neutral, not
            // the status tone: a red chevron reads as a second alarm rather
            // than as "tap here".
            ExcludeSemantics(
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A file of a kind this service does not import — still openable, so a
/// misjudged extension costs one tap rather than the capability.
class OtherFileRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportItem item;

  const OtherFileRow({super.key, required this.service, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: _rowMargin,
      child: AppCard.filled(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        backgroundColor: colorScheme.surfaceContainerLow,
        semanticLabel: item.fileName,
        semanticValue: manualImportUnsupportedReason(service, item),
        excludeChildSemantics: true,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilenameText(
                    filename: item.fileName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${item.extension} · ${formatImportBytes(item.size)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Not imported',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A file already handed to a `ManualImport` command.
///
/// Deliberately not selectable. It exists so the list can account for a file
/// that vanished from "Ready to import" without the user wondering where it
/// went — and so the screen never offers to submit the same file twice, which
/// used to queue a duplicate import mid-flight and fail outright once the
/// service had already moved the file into the library.
class InFlightFileRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportItem item;
  final ManualImportCommandStatus command;

  const InFlightFileRow({
    super.key,
    required this.service,
    required this.item,
    required this.command,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = manualImportCommandStatus(command);
    final tone = statusToneColor(colorScheme, info.tone);
    final identity = manualImportIdentityFor(service, item);

    return Padding(
      padding: _rowMargin,
      child: AppCard.filled(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        backgroundColor: colorScheme.surfaceContainerLow,
        semanticLabel: [
          manualImportGroupTitle(service, item),
          if (identity.code != null) identity.code!,
        ].join(', '),
        semanticValue: '${item.fileName}, ${info.semanticLabel}',
        excludeChildSemantics: true,
        child: Row(
          children: [
            SizedBox.square(
              dimension: 16,
              child: command.isActive
                  ? CircularProgressIndicator(strokeWidth: 2, color: tone)
                  : Icon(
                      command.isFailure
                          ? Icons.error_outline_rounded
                          : Icons.check_rounded,
                      size: 16,
                      color: tone,
                    ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      manualImportGroupTitle(service, item),
                      if (identity.code != null) identity.code!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
                  ),
                  FilenameText(
                    filename: item.fileName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(info: info, excludeFromSemantics: true),
          ],
        ),
      ),
    );
  }
}

/// One option in a picker, spoken as a radio button.
///
/// Modeled on the settings picker's choice row: selection carried by a filled
/// accent check plus a weight change, so it survives greyscale displays.
class ImportChoiceRow extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onSelected;

  const ImportChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: label,
      excludeSemantics: true,
      onTap: onSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onSelected,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge!
                        .weight(selected ? FontWeight.w700 : FontWeight.w500)
                        .copyWith(
                          color: selected
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          size: 22,
                          color: accent,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';

class MediaInfoCard extends StatelessWidget {
  final List<MediaInfoGroup> groups;

  const MediaInfoCard({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return _InfoGrid(
      cells: groups
          .map((group) => _InfoGridCell(label: group.title, child: group.child))
          .toList(growable: false),
    );
  }
}

class MediaInfoGroup {
  final String title;
  final Widget child;

  const MediaInfoGroup({required this.title, required this.child});
}

class MediaFactsList extends StatelessWidget {
  final List<MediaFact> facts;

  const MediaFactsList({super.key, required this.facts});

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _InfoGrid(
      cells: facts
          .map(
            (fact) => _InfoGridCell(
              label: fact.label,
              child: Text(
                fact.value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final List<_InfoGridCell> cells;

  const _InfoGrid({required this.cells});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSingleColumn = constraints.maxWidth < 320;

        if (useSingleColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                cells[i],
              ],
            ],
          );
        }

        // Pair cells into two-column rows so the columns stay aligned and share
        // a top baseline regardless of individual cell height. The previous
        // Wrap-of-fixed-width layout could wrap raggedly at sub-pixel widths,
        // producing the broken table that was reported.
        final rows = <Widget>[];
        for (var i = 0; i < cells.length; i += 2) {
          final right = i + 1 < cells.length ? cells[i + 1] : null;
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cells[i]),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: right ?? const SizedBox.shrink()),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

class _InfoGridCell extends StatelessWidget {
  final String label;
  final Widget child;

  const _InfoGridCell({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
          child: child,
        ),
      ],
    );
  }
}

class MediaFact {
  final String label;
  final String value;

  const MediaFact(this.label, this.value);
}

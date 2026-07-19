import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/media_detail_view.dart';
import 'package:seekarr/core/widgets/tag_chip.dart';

class MediaDetailUnavailableSection extends StatelessWidget {
  final String title;
  final String message;

  /// Optional per-service accent for the section header pipe.
  final Color? accent;

  const MediaDetailUnavailableSection({
    super.key,
    required this.title,
    required this.message,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MediaDetailSectionHeader(title: title, accent: accent),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusSm,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class MediaDetailTagsSection extends StatelessWidget {
  final List<String> tags;

  /// Optional per-service accent for the section header pipe.
  final Color? accent;

  const MediaDetailTagsSection({super.key, required this.tags, this.accent});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MediaDetailSectionHeader(title: 'Tags', accent: accent),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: tags
              .map((tag) => TagChip(text: tag))
              .toList(growable: false),
        ),
      ],
    );
  }
}

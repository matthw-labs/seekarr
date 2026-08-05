import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/app_card.dart';

/// A short "this is not available" note, for a region that exists but has
/// nothing to show and no action attached to it.
///
/// Headless on purpose: the heading comes from the `MediaDetailSlot` that hosts
/// it, so every heading on a detail page is built by the spine and cannot lose
/// its accent, its `Semantics(header: true)` or its position in the region
/// order. Passing a title here as well would print it twice.
///
/// For the empty state of a region the user could *act* on, prefer
/// `AppEmptyState.compact` — it carries an icon and a verb.
class MediaDetailUnavailableSection extends StatelessWidget {
  /// One or two sentences, in the app's own voice. Not an exception string.
  final String message;

  const MediaDetailUnavailableSection({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

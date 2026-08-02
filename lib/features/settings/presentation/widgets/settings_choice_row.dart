import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:seekarr/core/app_spacing.dart';

/// One option in a settings picker.
///
/// Replaces `RadioListTile`, which arrived with Material's own selection
/// control and none of this system's language. The selected state is carried by
/// a filled accent check and a weight change, so it survives greyscale and
/// reduced-transparency displays where a tint alone would not.
///
/// Publishes itself as a radio button so VoiceOver and TalkBack announce both
/// the option and whether it is the current one.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.description,
  });

  final String label;
  final String? description;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: description == null ? label : '$label, $description',
      excludeSemantics: true,
      onTap: onSelected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: () {
            HapticFeedback.selectionClick();
            onSelected();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Sized whether or not it is drawn, so selecting an option
                // never shifts the label beside it.
                SizedBox(
                  width: 24,
                  height: 24,
                  child: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          size: 22,
                          color: colorScheme.primary,
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

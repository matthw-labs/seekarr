import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';

/// A compact label/value row for detail screens. [value] falls back to `—`.
class TrueNasInfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Color? valueColor;

  const TrueNasInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value?.isNotEmpty == true ? value! : '—',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

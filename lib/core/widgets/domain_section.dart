import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:seekarr/core/app_spacing.dart';

/// A small, uppercase section label used to head a group of services that
/// belong to the same [ServiceDomain]. Shared by the Home dashboard, Settings
/// and onboarding so the domain grouping reads identically everywhere.
class DomainSectionHeader extends StatelessWidget {
  const DomainSectionHeader({
    super.key,
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
  });

  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A domain group whose body can be collapsed to keep long, growing service
/// lists compact. Used by the Home service picker (Media open, others closed)
/// and the onboarding connect step.
///
/// When collapsed, an optional [collapsedPreview] is shown in place of [child]
/// so the section still communicates its contents at a glance.
class CollapsibleDomainSection extends StatefulWidget {
  const CollapsibleDomainSection({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
    this.collapsedPreview,
    this.initiallyExpanded = false,
    this.headerPadding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
  });

  final String label;
  final Widget child;

  /// Shown on the right of the header regardless of expanded state (e.g. a
  /// count or an online summary).
  final Widget? trailing;

  /// Shown in place of [child] while collapsed. If null, nothing is shown.
  final Widget? collapsedPreview;

  final bool initiallyExpanded;
  final EdgeInsetsGeometry headerPadding;

  @override
  State<CollapsibleDomainSection> createState() =>
      _CollapsibleDomainSectionState();
}

class _CollapsibleDomainSectionState extends State<CollapsibleDomainSection> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          child: Padding(
            padding: widget.headerPadding,
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    widget.label.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          firstChild: SizedBox(
            width: double.infinity,
            child: widget.collapsedPreview ?? const SizedBox.shrink(),
          ),
          secondChild: SizedBox(width: double.infinity, child: widget.child),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
        ),
      ],
    );
  }
}

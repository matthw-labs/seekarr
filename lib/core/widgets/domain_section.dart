import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

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
    return Semantics(
      container: true,
      explicitChildNodes: true,
      header: true,
      // The un-uppercased label: `.toUpperCase()` is typography, and VoiceOver
      // spells out all-caps tokens it does not recognise. The eye gets the caps,
      // the ear gets the word.
      label: label,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  label.toUpperCase(),
                  // One kicker per domain group, introducing the region below
                  // it — the case `AppTheme.eyebrow` exists for, and the only
                  // place tracking is authored rather than derived.
                  style: AppTheme.eyebrow(theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            // Left audible: callers use it for a live count, which is worth its
            // own node.
            if (trailing != null) trailing!,
          ],
        ),
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
        // `expanded:` rather than an announcement on toggle: the platform speaks
        // the change off the node update, it works on TalkBack (where
        // announcements are dropped), and the current state stays discoverable
        // on re-focus instead of only at the moment of the tap.
        Semantics(
          container: true,
          explicitChildNodes: true,
          header: true,
          button: true,
          expanded: _expanded,
          label: widget.label,
          hint: _expanded ? 'collapses this group' : 'expands this group',
          onTap: _toggle,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            excludeFromSemantics: true,
            child: Padding(
              padding: widget.headerPadding,
              child: Row(
                children: [
                  // The rotation is the visual expand cue; `expanded:` above is
                  // the audible one.
                  ExcludeSemantics(
                    child: AnimatedRotation(
                      turns: _expanded ? 0.25 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        widget.label.toUpperCase(),
                        // Same single-kicker role as [DomainSection]'s header.
                        style: AppTheme.eyebrow(
                          theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  if (widget.trailing != null) widget.trailing!,
                ],
              ),
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

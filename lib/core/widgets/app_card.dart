import 'package:flutter/material.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

/// Variants for AppCard appearance following Material Design 3.
enum AppCardVariant {
  /// Filled card with surface container background
  filled,

  /// Outlined card with border and transparent background
  outlined,

  /// Elevated card with shadow
  elevated,

  /// Outlined card using the default surface container and subtle outline
  surfaceOutlined,
}

/// How a tappable card acknowledges a press.
///
/// Deliberately a parameter rather than a set of named constructors, which is
/// the house style for card *variants*. Feedback is orthogonal to appearance —
/// expressing the pair as constructors means a `filled`/`outlined`/
/// `surfaceOutlined`/`elevated` cross product, eight names for two decisions.
enum AppCardPressFeedback {
  /// Material's ink ripple, painted above the card's own background.
  ///
  /// The default, and right for a card with room for a splash to read as a
  /// touch spreading across a surface.
  ink,

  /// The card dips under the thumb — [PressableScale]'s 0.97 and a light
  /// haptic — and paints no ink at all.
  ///
  /// For cards too small for the first reading to survive: a ripple that
  /// *floods* its container is how a chip signals selection, not how a surface
  /// signals a touch. The threshold is about the ripple relative to the box,
  /// so it tracks the same judgment as DESIGN.md's Pill-for-Metadata Rule.
  scale,
}

/// A versatile card component following Material Design 3 guidelines.
///
/// Provides three variants: filled, outlined, and elevated.
/// Uses design system tokens for consistent styling.
class AppCard extends StatelessWidget {
  /// The card's child widget
  final Widget child;

  /// The card variant (filled, outlined, elevated)
  final AppCardVariant variant;

  /// Optional callback when the card is tapped
  final VoidCallback? onTap;

  /// How a press is acknowledged. Ignored when [onTap] is null.
  final AppCardPressFeedback pressFeedback;

  /// Optional padding override (defaults to AppSpacing.lg)
  final EdgeInsetsGeometry? padding;

  /// Optional border radius override
  final BorderRadius? borderRadius;

  /// Optional custom background color
  final Color? backgroundColor;

  /// Optional custom outline color for outlined cards.
  final Color? borderColor;

  /// When set, paints a soft accent glow inside the card (signature surfaces).
  final Color? accentColor;

  /// Strength and origin of that glow.
  ///
  /// The defaults are the signature-card treatment: a strong wash from the top
  /// right, on the one card that owns the screen. A card in a *grid* wants a
  /// fraction of it and usually a different corner — the stack matrix lights
  /// each cell from the top left at 0.08, because thirteen cells at full
  /// strength stop reading as identity and start reading as decoration.
  final double accentGlowAlpha;
  final Alignment accentGlowCenter;

  /// The accessible name of the card.
  ///
  /// A tappable card without one publishes a nameless actionable node: a screen
  /// reader announces the ripple region as an unnamed control, then reads the
  /// contents after it as loose fragments. One composed label collapses that
  /// into a single named button.
  ///
  /// Controls inside [child] keep nodes of their own. There are two shapes:
  ///
  ///  * No nested control — pass [excludeChildSemantics] and let this label say
  ///    everything.
  ///  * A nested control (a popup menu, a delete button) — leave
  ///    [excludeChildSemantics] off and wrap only the parts this label already
  ///    speaks in [ExcludeSemantics] at the call site:
  ///
  /// ```dart
  /// AppCard.outlined(
  ///   onTap: openDetails,
  ///   semanticLabel: title,
  ///   semanticValue: status,
  ///   child: Row(
  ///     children: [
  ///       Expanded(child: ExcludeSemantics(child: body)),
  ///       MediaSearchPopupMenu(...), // not excluded: still reachable
  ///     ],
  ///   ),
  /// )
  /// ```
  ///
  /// Never pass [excludeChildSemantics] on a card that encloses a control: it
  /// drops that control out of the accessibility tree entirely.
  final String? semanticLabel;

  /// Changing state announced after [semanticLabel], e.g. 'Offline'.
  final String? semanticValue;

  /// What tapping the card does, e.g. 'opens the queue item'.
  final String? semanticHint;

  /// Whether to hide [child]'s own semantics behind [semanticLabel].
  final bool excludeChildSemantics;

  const AppCard({
    super.key,
    required this.child,
    this.variant = AppCardVariant.filled,
    this.onTap,
    this.pressFeedback = AppCardPressFeedback.ink,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.accentColor,
    this.accentGlowAlpha = 0.22,
    this.accentGlowCenter = Alignment.topRight,
    this.semanticLabel,
    this.semanticValue,
    this.semanticHint,
    this.excludeChildSemantics = false,
  });

  /// Creates a filled card (default)
  const AppCard.filled({
    super.key,
    required this.child,
    this.onTap,
    this.pressFeedback = AppCardPressFeedback.ink,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.accentColor,
    this.accentGlowAlpha = 0.22,
    this.accentGlowCenter = Alignment.topRight,
    this.semanticLabel,
    this.semanticValue,
    this.semanticHint,
    this.excludeChildSemantics = false,
  }) : variant = AppCardVariant.filled;

  /// Creates an outlined card
  const AppCard.outlined({
    super.key,
    required this.child,
    this.onTap,
    this.pressFeedback = AppCardPressFeedback.ink,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.accentColor,
    this.accentGlowAlpha = 0.22,
    this.accentGlowCenter = Alignment.topRight,
    this.semanticLabel,
    this.semanticValue,
    this.semanticHint,
    this.excludeChildSemantics = false,
  }) : variant = AppCardVariant.outlined;

  /// Creates the common app surface card with an outline.
  const AppCard.surfaceOutlined({
    super.key,
    required this.child,
    this.onTap,
    this.pressFeedback = AppCardPressFeedback.ink,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.accentColor,
    this.accentGlowAlpha = 0.22,
    this.accentGlowCenter = Alignment.topRight,
    this.semanticLabel,
    this.semanticValue,
    this.semanticHint,
    this.excludeChildSemantics = false,
  }) : variant = AppCardVariant.surfaceOutlined;

  /// Creates an elevated card with shadow
  const AppCard.elevated({
    super.key,
    required this.child,
    this.onTap,
    this.pressFeedback = AppCardPressFeedback.ink,
    this.padding,
    this.borderRadius,
    this.backgroundColor,
    this.borderColor,
    this.accentColor,
    this.accentGlowAlpha = 0.22,
    this.accentGlowCenter = Alignment.topRight,
    this.semanticLabel,
    this.semanticValue,
    this.semanticHint,
    this.excludeChildSemantics = false,
  }) : variant = AppCardVariant.elevated;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveBorderRadius = borderRadius ?? AppRadius.borderRadiusMd;
    final effectivePadding = padding ?? const EdgeInsets.all(AppSpacing.lg);

    // Determine styling based on variant
    Color bgColor;
    BoxBorder? border;
    List<BoxShadow>? shadows;

    switch (variant) {
      case AppCardVariant.filled:
        bgColor = backgroundColor ?? colorScheme.surfaceContainer;
        border = null;
        shadows = null;
        break;
      case AppCardVariant.outlined:
        bgColor = backgroundColor ?? Colors.transparent;
        border = Border.all(color: borderColor ?? colorScheme.outline);
        shadows = null;
        break;
      case AppCardVariant.elevated:
        bgColor = backgroundColor ?? colorScheme.surfaceContainer;
        border = null;
        shadows = AppElevation.level2(colorScheme);
        break;
      case AppCardVariant.surfaceOutlined:
        bgColor = backgroundColor ?? colorScheme.surfaceContainer;
        border = Border.all(color: borderColor ?? colorScheme.outlineVariant);
        shadows = null;
        break;
    }

    // Optional accent glow painted behind the content for signature cards.
    final glow = accentColor != null
        ? AppGradients.serviceGlow(
            accentColor!,
            center: accentGlowCenter,
            alpha: accentGlowAlpha,
          )
        : null;

    Widget wrapWithGlow(Widget padded) {
      if (glow == null) return padded;
      return Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: glow)),
          ),
          padded,
        ],
      );
    }

    if (onTap != null) {
      // Place background on Material so InkWell ripple paints on top.
      //
      // The `Material` carries the outline as its `shape` in *both* feedback
      // modes, and that is load-bearing beyond the ripple: a shape's stroke
      // costs no layout, where the untappable branch's `BoxDecoration.border`
      // insets its child 1px per side. Keeping the Material means a card does
      // not change interior height when it gains or loses an `onTap`.
      final shape = RoundedRectangleBorder(
        borderRadius: effectiveBorderRadius,
        side:
            variant == AppCardVariant.outlined ||
                variant == AppCardVariant.surfaceOutlined
            ? BorderSide(
                color:
                    borderColor ??
                    (variant == AppCardVariant.surfaceOutlined
                        ? colorScheme.outlineVariant
                        : colorScheme.outline),
              )
            : BorderSide.none,
      );

      final padded = wrapWithGlow(
        Padding(padding: effectivePadding, child: child),
      );
      final scaled = pressFeedback == AppCardPressFeedback.scale;

      final material = Material(
        color: bgColor,
        shape: shape,
        clipBehavior: glow != null ? Clip.antiAlias : Clip.none,
        // No ink at all under `scale`: an `InkWell` here would splash *and*
        // dip, and the splash is the half being rejected.
        child: scaled
            ? padded
            : InkWell(
                onTap: onTap,
                customBorder: shape,
                // The name and the tap action are published by _spoken;
                // without this the ink response adds a second, unnamed
                // actionable node.
                excludeFromSemantics: semanticLabel != null,
                child: padded,
              ),
      );

      // Explicit token shadows sit under the Material so tappable elevated
      // cards match the non-tappable ones.
      final Widget body = shadows == null
          ? material
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: effectiveBorderRadius,
                boxShadow: shadows,
              ),
              child: material,
            );

      // Under `scale`, `PressableScale` is the whole gesture layer *and* the
      // semantics node — it publishes the button role, the name and the tap
      // action itself, so `_spoken` must not also wrap one or the card becomes
      // two nested actionable nodes. It sits outside the shadow so the card
      // dips as one object, shadow included.
      if (!scaled) return _spoken(body);
      return PressableScale(
        onTap: onTap,
        semanticLabel: semanticLabel,
        semanticValue: semanticValue,
        semanticHint: semanticHint,
        excludeChildSemantics: excludeChildSemantics,
        borderRadius: effectiveBorderRadius,
        child: body,
      );
    }

    // Non-tappable: plain Container.
    return _spoken(
      Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: effectiveBorderRadius,
          border: border,
          boxShadow: shadows,
        ),
        clipBehavior: glow != null ? Clip.antiAlias : Clip.none,
        child: wrapWithGlow(Padding(padding: effectivePadding, child: child)),
      ),
    );
  }

  /// Publishes the card as one named node, or leaves it alone when unlabelled.
  ///
  /// Deliberately the outermost widget `build` returns: a wrapper buried inside
  /// the [Material]/[InkWell] would leave `tester.getSemantics` — and the
  /// platform — resolving some other node, and the failure is silent.
  Widget _spoken(Widget card) {
    if (semanticLabel == null) return card;

    return Semantics(
      container: true,
      // Keeps this node's label exactly what was passed in, and lets any
      // control inside [child] keep a node of its own.
      explicitChildNodes: true,
      button: onTap != null,
      label: semanticLabel,
      value: semanticValue,
      hint: onTap == null ? null : semanticHint,
      excludeSemantics: excludeChildSemantics,
      // Forwarded because `excludeFromSemantics` above drops the InkWell's tap
      // action along with its labels; without this, double-tap stops working.
      onTap: onTap,
      child: card,
    );
  }
}

/// A card specifically designed for settings/list items
class SettingsCard extends StatelessWidget {
  /// Leading widget (usually an icon)
  final Widget? leading;

  /// Title text
  final String title;

  /// Subtitle text
  final String? subtitle;

  /// Optional widget rendered before the subtitle text (e.g. a status icon).
  /// Only shown when [subtitle] is also provided.
  final Widget? subtitleLeading;

  /// Trailing widget
  final Widget? trailing;

  /// Callback when tapped
  final VoidCallback? onTap;

  /// Accent color used by the leading icon container.
  final Color? accentColor;

  /// Optional subtitle color override.
  final Color? subtitleColor;

  /// What [subtitleLeading] means, in words.
  ///
  /// Callers pass a bare `Icon` or spinner whose entire meaning is its glyph — a
  /// cloud for "connected", a slashed cloud for "not reachable" — so a screen
  /// reader gets nothing from it. Set this whenever [subtitleLeading] is set.
  /// Announced between the title and the subtitle, the order the eye reads them.
  final String? subtitleLeadingLabel;

  /// Overrides the composed spoken name of the row.
  ///
  /// Defaults to [title], then [subtitleLeadingLabel], then [subtitle].
  final String? semanticLabel;

  /// What tapping the row does, e.g. 'opens Radarr settings'.
  final String? semanticHint;

  /// Whether this row is rendered inside a [SettingsGroupCard].
  final bool grouped;

  const SettingsCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleLeading,
    this.subtitleLeadingLabel,
    this.trailing,
    this.onTap,
    this.accentColor,
    this.subtitleColor,
    this.semanticLabel,
    this.semanticHint,
  }) : grouped = false;

  const SettingsCard.grouped({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleLeading,
    this.subtitleLeadingLabel,
    this.trailing,
    this.onTap,
    this.accentColor,
    this.subtitleColor,
    this.semanticLabel,
    this.semanticHint,
  }) : grouped = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveAccentColor = accentColor ?? colorScheme.primary;

    final spokenLabel =
        semanticLabel ??
        [
          title,
          if (subtitleLeadingLabel != null) subtitleLeadingLabel!,
          if (subtitle != null) subtitle!,
        ].join(', ');

    final row = Row(
      children: [
        if (leading != null) ...[
          // Decorative: it restates the title the row already speaks.
          ExcludeSemantics(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: ServiceTheme.fromAccent(
                  effectiveAccentColor,
                ).softContainer,
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: IconTheme(
                data: IconThemeData(color: effectiveAccentColor, size: 20),
                child: Center(child: leading!),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
        ],
        Expanded(
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge!.weight(FontWeight.w600),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (subtitleLeading != null) ...[
                        subtitleLeading!,
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Flexible(
                        child: Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                subtitleColor ?? colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        // `trailing` is the one slot that can hold a control — a delete button,
        // say — so it is the one slot this row does not silence.
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ] else if (onTap != null) ...[
          ExcludeSemantics(
            child: Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    final paddedRow = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: row,
    );

    if (grouped) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        button: onTap != null,
        label: spokenLabel,
        hint: onTap == null ? null : semanticHint,
        onTap: onTap,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            excludeFromSemantics: true,
            child: paddedRow,
          ),
        ),
      );
    }

    return AppCard.filled(
      onTap: onTap,
      padding: EdgeInsets.zero,
      semanticLabel: spokenLabel,
      semanticHint: semanticHint,
      child: paddedRow,
    );
  }
}

class SettingsGroupCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsGroupCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard.outlined(
      padding: EdgeInsets.zero,
      backgroundColor: colorScheme.surfaceContainer,
      borderColor: colorScheme.outlineVariant,
      borderRadius: AppRadius.borderRadiusLg,
      child: ClipRRect(
        borderRadius: AppRadius.borderRadiusLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: AppSpacing.lg + 36 + AppSpacing.lg,
                  color: colorScheme.outlineVariant,
                ),
              children[index],
            ],
          ],
        ),
      ),
    );
  }
}

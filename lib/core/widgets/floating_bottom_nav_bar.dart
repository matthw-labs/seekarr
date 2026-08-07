import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';

/// A destination for the [FloatingBottomNavBar].
class FloatingNavDestination {
  /// The icon to display when this destination is not selected.
  final IconData icon;

  /// The icon to display when this destination is selected.
  final IconData selectedIcon;

  /// The label for this destination.
  final String label;

  /// Accent color used for the selected pill.
  final Color accentColor;

  /// Count of things waiting on this destination, or zero for none.
  ///
  /// Painted in the destination's **own accent**, never a status tone: a green or
  /// amber pill living in permanent chrome reads as stack health, which is
  /// exactly what the section accents exist to keep separate from the closed
  /// status vocabulary.
  final int badgeCount;

  /// Spoken alongside the label, because a number drawn on an icon is invisible
  /// to a screen reader.
  final String? badgeSemanticLabel;

  const FloatingNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.accentColor,
    this.badgeCount = 0,
    this.badgeSemanticLabel,
  });
}

/// Constants for FloatingBottomNavBar dimensions.
///
/// Use [FloatingNavBarMetrics.getScrollViewBottomPadding] to calculate content
/// padding: the bar grows with the reading size, so a fixed constant would leave
/// the last row of a list under the bar at large text scales.
class FloatingNavBarMetrics {
  FloatingNavBarMetrics._();

  /// Height of the nav bar at the default reading size.
  static const double barHeight = 60.0;

  /// Top padding above the nav bar.
  static const double topPadding = AppSpacing.sm; // 8dp

  /// Bottom padding below the nav bar (excluding safe area).
  static const double bottomPadding = AppSpacing.xs;

  /// Inset between the glass surface edge and the item row.
  static const double surfacePadding = 6.0;

  /// Total height at the default reading size, excluding safe area.
  ///
  /// Prefer [totalHeightFor], which accounts for the user's text scale.
  static const double totalHeight = barHeight + topPadding + bottomPadding;

  /// Upper bound applied to the user's text scale inside the bar.
  ///
  /// The nav bar is compact chrome sitting over content: letting its label grow
  /// without limit pushes the bar over half the screen, and ignoring the
  /// preference outright is hostile. Growing up to this factor keeps the label
  /// legible while the bar stays a bar — the same compromise the system tab bar
  /// makes.
  static const double maxTextScaleFactor = 1.3;

  /// The text scale actually used to lay the bar out.
  static TextScaler effectiveTextScaler(BuildContext context) =>
      _clamp(MediaQuery.textScalerOf(context));

  static TextScaler _clamp(TextScaler scaler) =>
      scaler.clamp(maxScaleFactor: maxTextScaleFactor);

  /// Height of the bar at the current reading size.
  ///
  /// Derived from the tallest thing inside it — the selection pill — so the row
  /// can never overflow the surface.
  static double barHeightFor(BuildContext context) {
    final pillHeight = _NavBarItem.pillHeightFor(
      effectiveTextScaler(context),
      _NavBarItem.labelStyleOf(context),
    );
    final needed = pillHeight + (surfacePadding * 2);
    return needed > barHeight ? needed : barHeight;
  }

  /// Total height at the current reading size, excluding safe area.
  static double totalHeightFor(BuildContext context) =>
      barHeightFor(context) + topPadding + bottomPadding;

  /// Returns the bottom padding needed for scroll views to allow content
  /// to scroll above the floating nav bar.
  ///
  /// Includes the nav bar height, margins, and device safe area.
  static double getScrollViewBottomPadding(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    return totalHeightFor(context) + bottomSafeArea;
  }
}

/// A custom floating bottom navigation bar with rounded corners and glass styling.
///
/// Features:
/// - Floating design with margins on all sides
/// - Rounded corners using [AppRadius.xl]
/// - Compact selected pill with per-destination accent color
/// - Elastic drag animation (rubber band effect)
/// - Glass surface with backdrop blur
///
/// Example usage:
/// ```dart
/// FloatingBottomNavBar(
///   selectedIndex: 0,
///   onDestinationSelected: (index) => print('Selected: $index'),
///   destinations: [
///     FloatingNavDestination(
///       icon: Icons.home_outlined,
///       selectedIcon: Icons.home,
///       label: 'Home',
///       accentColor: Colors.indigo,
///     ),
///   ],
/// )
/// ```
class FloatingBottomNavBar extends StatefulWidget {
  /// The index of the currently selected destination.
  final int selectedIndex;

  /// Called when one of the destinations is selected.
  final ValueChanged<int> onDestinationSelected;

  /// The list of destinations to display.
  final List<FloatingNavDestination> destinations;

  const FloatingBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  State<FloatingBottomNavBar> createState() => _FloatingBottomNavBarState();
}

class _FloatingBottomNavBarState extends State<FloatingBottomNavBar>
    with SingleTickerProviderStateMixin {
  /// Current drag offset from original position.
  Offset _dragOffset = Offset.zero;

  /// Animation controller for spring-back animation.
  late AnimationController _springController;

  /// Animation for returning to original position.
  Animation<Offset>? _springAnimation;

  // === Elastic drag physics parameters ===

  /// Maximum allowed drag distance in any direction.
  static const double _maxDragDistance = 15.0;

  /// Base resistance factor (lower = more rigid).
  static const double _baseResistance = 0.15;

  /// Controls how quickly resistance increases with distance.
  static const double _resistanceFalloff = 30.0;

  static const double _barHorizontalPadding =
      FloatingNavBarMetrics.surfacePadding;
  static const double _barVerticalPadding =
      FloatingNavBarMetrics.surfacePadding;
  static const double _blurSigma = 24.0;
  static const double _selectedExtraShare = 0.6;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: AppAnimation.durationXl,
    );
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  /// Applies elastic resistance to drag delta.
  ///
  /// Resistance increases as offset grows, creating a "rubber band" feel.
  double _applyElasticResistance(double delta, double currentOffset) {
    // Resistance increases exponentially as we get further from origin
    final resistance =
        _baseResistance / (1 + (currentOffset.abs() / _resistanceFalloff));
    return delta * resistance;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Stop any running spring animation
    if (_springController.isAnimating) {
      _springController.stop();
    }

    setState(() {
      // Apply elastic resistance to both axes
      final dx = _applyElasticResistance(details.delta.dx, _dragOffset.dx);
      final dy = _applyElasticResistance(details.delta.dy, _dragOffset.dy);

      _dragOffset += Offset(dx, dy);

      // Clamp to maximum drag distance
      _dragOffset = Offset(
        _dragOffset.dx.clamp(-_maxDragDistance, _maxDragDistance),
        _dragOffset.dy.clamp(-_maxDragDistance, _maxDragDistance),
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // Animate back to original position with elastic curve
    _springAnimation = Tween<Offset>(begin: _dragOffset, end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _springController, curve: Curves.elasticOut),
        );

    _springAnimation!.addListener(_onSpringAnimation);
    _springController.forward(from: 0).whenComplete(() {
      _springAnimation?.removeListener(_onSpringAnimation);
    });
  }

  void _handleDestinationTap(int index) {
    // No haptic here: the shell fires one selection click for every tap, and it
    // is the only call site that covers both this bar and the wide-window rail.
    // Firing here as well buzzed twice on a tab change.
    widget.onDestinationSelected(index);
  }

  void _onSpringAnimation() {
    if (_springAnimation != null) {
      setState(() {
        _dragOffset = _springAnimation!.value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Clamped so the bar follows the user's reading size without letting an
    // accessibility scale turn it into a full-height panel.
    final textScaler = FloatingNavBarMetrics.effectiveTextScaler(context);
    final barHeight = FloatingNavBarMetrics.barHeightFor(context);
    // Resolved once and threaded down: the pill's width and height are measured
    // from this exact style before the label is painted with it.
    final labelStyle = _NavBarItem.labelStyleOf(context);
    final isDark = colorScheme.brightness == Brightness.dark;
    final glassColor =
        theme.extension<CupolaThemeColors>()?.glassSurface ??
        colorScheme.surfaceContainer.withValues(alpha: isDark ? 0.72 : 0.55);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : colorScheme.outline.withValues(alpha: 0.85);
    final selectedDestination =
        widget.selectedIndex >= 0 &&
            widget.selectedIndex < widget.destinations.length
        ? widget.destinations[widget.selectedIndex]
        : null;

    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // Outer padding to make it float
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: bottomPadding + FloatingNavBarMetrics.bottomPadding,
          top: FloatingNavBarMetrics.topPadding,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final preferredSurfaceWidth =
                (_NavBarLayoutMetrics.preferredInnerWidth(
                          widget.destinations,
                          textScaler,
                          labelStyle,
                        ) +
                        (_barHorizontalPadding * 2))
                    .clamp(0.0, constraints.maxWidth)
                    .toDouble();

            return Align(
              alignment: Alignment.center,
              heightFactor: 1,
              child: Transform.translate(
                key: const ValueKey('floating-nav-drag-transform'),
                offset: _dragOffset,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.borderRadiusXl,
                    boxShadow: AppElevation.glass(colorScheme),
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.borderRadiusXl,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: _blurSigma,
                        sigmaY: _blurSigma,
                      ),
                      child: Container(
                        key: const ValueKey('floating-nav-surface'),
                        width: preferredSurfaceWidth,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: glassColor,
                          borderRadius: AppRadius.borderRadiusXl,
                          border: Border.all(color: borderColor),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: _barHorizontalPadding,
                          vertical: _barVerticalPadding,
                        ),
                        child: SizedBox.expand(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final layout = _NavBarLayoutMetrics.resolve(
                                availableWidth: constraints.maxWidth,
                                destinations: widget.destinations,
                                selectedIndex: widget.selectedIndex,
                                selectedExtraShare: _selectedExtraShare,
                                textScaler: textScaler,
                                labelStyle: labelStyle,
                              );
                              final indicatorWidth = selectedDestination == null
                                  ? 0.0
                                  : _NavBarItem.preferredSelectedWidthFor(
                                          selectedDestination,
                                          textScaler,
                                          labelStyle,
                                        )
                                        .clamp(
                                          0.0,
                                          layout.itemWidths[widget
                                              .selectedIndex],
                                        )
                                        .toDouble();
                              final indicatorLeft = selectedDestination == null
                                  ? 0.0
                                  : layout.itemLefts[widget.selectedIndex] +
                                        ((layout.itemWidths[widget
                                                    .selectedIndex] -
                                                indicatorWidth) /
                                            2);

                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (selectedDestination != null)
                                    IgnorePointer(
                                      child: _NavBarIndicator(
                                        left: indicatorLeft,
                                        width: indicatorWidth,
                                        barHeight: constraints.maxHeight,
                                        selectedDestination:
                                            selectedDestination,
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      for (
                                        var index = 0;
                                        index < widget.destinations.length;
                                        index++
                                      ) ...[
                                        if (index > 0)
                                          SizedBox(width: layout.gap),
                                        AnimatedContainer(
                                          duration: AppAnimation.durationSm,
                                          curve: AppAnimation.emphasizedCurve,
                                          width: layout.itemWidths[index],
                                          child: _NavBarItem(
                                            destination:
                                                widget.destinations[index],
                                            isSelected:
                                                index == widget.selectedIndex,
                                            index: index,
                                            destinationCount:
                                                widget.destinations.length,
                                            onTap: () =>
                                                _handleDestinationTap(index),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavBarIndicator extends StatelessWidget {
  /// Alpha of the accent fill behind the selected destination.
  ///
  /// Shared with [_NavBarItem], which has to measure its label against this exact
  /// value: the fill and the label on top of it are one contrast decision, and
  /// letting the two read different constants is how a legible pill silently
  /// becomes an illegible one.
  static double tintAlphaFor(Brightness brightness) =>
      brightness == Brightness.dark ? 0.16 : 0.13;

  final double left;
  final double width;
  final double barHeight;
  final FloatingNavDestination selectedDestination;

  const _NavBarIndicator({
    required this.left,
    required this.width,
    required this.barHeight,
    required this.selectedDestination,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = selectedDestination.accentColor;
    final activeBackground = accentColor.withValues(
      alpha: tintAlphaFor(colorScheme.brightness),
    );
    final activeBorder = accentColor.withValues(alpha: 0.27);
    final pillHeight = _NavBarItem.pillHeightFor(
      FloatingNavBarMetrics.effectiveTextScaler(context),
      _NavBarItem.labelStyleOf(context),
    ).clamp(0.0, barHeight);

    return Stack(
      children: [
        AnimatedPositioned(
          duration: AppAnimation.durationSm,
          curve: AppAnimation.emphasizedCurve,
          left: left,
          top: (barHeight - pillHeight) / 2,
          width: width,
          height: pillHeight,
          child: DecoratedBox(
            key: const ValueKey('floating-nav-indicator'),
            decoration: BoxDecoration(
              color: activeBackground,
              borderRadius: BorderRadius.circular(_NavBarItem.itemRadius),
              border: Border.all(color: activeBorder),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavBarLayoutMetrics {
  static const double _compactBreakpoint = 360.0;
  static const double _compactTargetWidth = 52.0;
  static const double _compactMinWidth = 48.0;

  final List<double> itemWidths;
  final List<double> itemLefts;
  final double gap;

  const _NavBarLayoutMetrics({
    required this.itemWidths,
    required this.itemLefts,
    required this.gap,
  });

  static double preferredInnerWidth(
    List<FloatingNavDestination> destinations,
    TextScaler scaler,
    TextStyle labelStyle,
  ) {
    final count = destinations.length;
    if (count == 0) return 0.0;

    final preferredSelectedWidth = destinations.fold<double>(
      _NavBarItem.minSelectedWidth,
      (currentMax, destination) {
        final width = _NavBarItem.preferredSelectedWidthFor(
          destination,
          scaler,
          labelStyle,
        ).clamp(_NavBarItem.minSelectedWidth, double.infinity).toDouble();
        return width > currentMax ? width : currentMax;
      },
    );

    if (count == 1) {
      return preferredSelectedWidth;
    }

    double widthForGap(double gap) {
      return preferredSelectedWidth +
          (_compactTargetWidth * (count - 1)) +
          (gap * (count - 1));
    }

    final regularGap = AppSpacing.sm - 2;
    final regularWidth = widthForGap(regularGap);
    if (regularWidth >= _compactBreakpoint) {
      return regularWidth;
    }

    return widthForGap(AppSpacing.xs);
  }

  factory _NavBarLayoutMetrics.resolve({
    required double availableWidth,
    required List<FloatingNavDestination> destinations,
    required int selectedIndex,
    required double selectedExtraShare,
    required TextScaler textScaler,
    required TextStyle labelStyle,
  }) {
    final count = destinations.length;
    final gap = count > 1
        ? (availableWidth < _compactBreakpoint
              ? AppSpacing.xs
              : AppSpacing.sm - 2)
        : 0.0;
    final totalGapWidth = gap * (count - 1);
    final itemAreaWidth = (availableWidth - totalGapWidth)
        .clamp(0.0, double.infinity)
        .toDouble();

    if (count == 0) {
      return const _NavBarLayoutMetrics(itemWidths: [], itemLefts: [], gap: 0);
    }

    if (selectedIndex < 0 || selectedIndex >= count) {
      final equalWidth = itemAreaWidth / count;
      final itemWidths = List<double>.filled(count, equalWidth);
      return _NavBarLayoutMetrics(
        itemWidths: itemWidths,
        itemLefts: _leftsFor(itemWidths, gap),
        gap: gap,
      );
    }

    final itemWidths = List<double>.filled(count, _compactTargetWidth);
    itemWidths[selectedIndex] = _NavBarItem.preferredSelectedWidthFor(
      destinations[selectedIndex],
      textScaler,
      labelStyle,
    ).clamp(_NavBarItem.minSelectedWidth, double.infinity).toDouble();

    var delta = itemAreaWidth - _sum(itemWidths);

    if (delta >= 0) {
      if (count == 1) {
        itemWidths[0] += delta;
      } else {
        final selectedExtra = delta * selectedExtraShare;
        final compactExtra = (delta - selectedExtra) / (count - 1);

        for (var index = 0; index < count; index++) {
          itemWidths[index] += index == selectedIndex
              ? selectedExtra
              : compactExtra;
        }
      }
    } else {
      var deficit = -delta;

      if (count > 1) {
        final compactReductionCapacity =
            (_compactTargetWidth - _compactMinWidth) * (count - 1);
        final compactReduction = deficit.clamp(0.0, compactReductionCapacity);
        final perCompactReduction = compactReduction / (count - 1);

        for (var index = 0; index < count; index++) {
          if (index == selectedIndex) {
            continue;
          }
          itemWidths[index] -= perCompactReduction;
        }

        deficit -= compactReduction;
      }

      if (deficit > 0) {
        final selectedReductionCapacity =
            (itemWidths[selectedIndex] - _NavBarItem.minSelectedWidth)
                .clamp(0.0, double.infinity)
                .toDouble();
        final selectedReduction = deficit.clamp(0.0, selectedReductionCapacity);

        itemWidths[selectedIndex] -= selectedReduction;
        deficit -= selectedReduction;
      }

      if (deficit > 0) {
        final minimumWidths = List<double>.filled(count, _compactMinWidth);
        minimumWidths[selectedIndex] = _NavBarItem.minSelectedWidth;
        final scaleFactor = itemAreaWidth / _sum(minimumWidths);

        for (var index = 0; index < count; index++) {
          itemWidths[index] = minimumWidths[index] * scaleFactor;
        }
      }
    }

    itemWidths[selectedIndex] += itemAreaWidth - _sum(itemWidths);

    return _NavBarLayoutMetrics(
      itemWidths: itemWidths,
      itemLefts: _leftsFor(itemWidths, gap),
      gap: gap,
    );
  }

  static List<double> _leftsFor(List<double> widths, double gap) {
    final lefts = <double>[];
    var currentLeft = 0.0;

    for (final width in widths) {
      lefts.add(currentLeft);
      currentLeft += width + gap;
    }

    return lefts;
  }

  static double _sum(List<double> widths) {
    return widths.fold(0.0, (sum, width) => sum + width);
  }
}

class _NavBarItem extends StatelessWidget {
  static const double _iconSize = 20.0;
  static const double _itemHorizontalPadding = 14.0;

  /// The app's selected-affordance radius, shared with the Activity segment
  /// pills so "this one is active" reads the same in both places.
  static const double itemRadius = AppRadius.pill;
  static const double _labelGap = 6.0;
  static const double _selectedWidthSlack = 6.0;
  static const double minSelectedWidth = 84.0;

  /// Height of the animated selection pill — shorter than the full inner bar
  /// height so the highlight feels proportionate rather than filling the bar.
  static const double _pillHeight = 36.0;

  final FloatingNavDestination destination;
  final bool isSelected;

  /// Zero-based position in the bar, announced as "Tab 2 of 4".
  final int index;
  final int destinationCount;

  final VoidCallback onTap;

  const _NavBarItem({
    required this.destination,
    required this.isSelected,
    required this.index,
    required this.destinationCount,
    required this.onTap,
  });

  /// Icons keep a fixed size, as the system tab bar's do: the compact
  /// (unselected) items are icon-only and sized from this, so scaling it would
  /// overflow them before the label ever grew.
  static const double iconSize = _iconSize;

  /// The selected destination's label style: `labelMedium` at w700.
  ///
  /// Nav is chrome in a fixed-height pill, which is exactly what the label roles
  /// are for, and `labelMedium` is the 12pt rung this bar has always drawn at.
  ///
  /// It lives in one place because the bar *measures its own label*: both
  /// [pillHeightFor] and [preferredSelectedWidthFor] lay this style out to
  /// derive the pill's geometry, and [build] then paints with it. Measuring one
  /// style and painting another is how a bar that fits becomes a bar that
  /// overflows, so the geometry reads its size and leading off the role rather
  /// than off a private literal that could drift from the ramp.
  static TextStyle labelStyleOf(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium!.weight(FontWeight.w700);

  /// Height of the selection pill at the current reading size.
  static double pillHeightFor(TextScaler scaler, TextStyle labelStyle) {
    final scaledLabel =
        scaler.scale(labelStyle.fontSize ?? 12) * (labelStyle.height ?? 1.0);
    final tallest = scaledLabel > iconSize ? scaledLabel : iconSize;
    final needed = tallest + (AppSpacing.sm * 2);
    return needed > _pillHeight ? needed : _pillHeight;
  }

  /// Width the selected pill wants at the current reading size.
  ///
  /// [scaler] must be threaded in: measuring at 1.0x while the label renders
  /// scaled is what made the bar overflow at accessibility text sizes. So must
  /// [labelStyle], for the same reason — see [labelStyleOf].
  static double preferredSelectedWidthFor(
    FloatingNavDestination destination,
    TextScaler scaler,
    TextStyle labelStyle,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: destination.label, style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();

    return _itemHorizontalPadding * 2 +
        iconSize +
        _labelGap +
        painter.width +
        _selectedWidthSlack;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = destination.accentColor;
    final scaler = FloatingNavBarMetrics.effectiveTextScaler(context);

    // The selected label and icon sit *on top of* the indicator pill, which is
    // this same accent at a low alpha (see [_NavBarIndicator]). Painting the raw
    // accent there was the exact failure DESIGN.md's Luminance Rule describes: in
    // light theme an accent over a 13% tint of itself measures under 2:1 against a
    // 4.5:1 requirement, so every service accent was failing AA in daylight while
    // looking fine in dark, where the same combination clears about 7.7:1.
    //
    // `onTint` keeps the hue and darkens only as far as AA needs, so the bar stays
    // accent-coloured rather than dropping to a neutral.
    final itemColor = isSelected
        ? ServiceTheme.onTint(
            accentColor,
            // The pill floats on the glass bar, whose own fill is translucent, so
            // the true composite is not knowable here. `surface` is the opaque
            // base the ambient background paints from, which makes this the
            // conservative choice in light theme — where the risk actually is.
            surface: colorScheme.surface,
            tintAlpha: _NavBarIndicator.tintAlphaFor(colorScheme.brightness),
          )
        : colorScheme.onSurfaceVariant;

    // Rail parity: NavigationRail and NavigationBar both append this, so the
    // wide-window rail already announced "Tab 1 of 4" while this bar did not —
    // the same app saying two different things about the same navigation. '\n'
    // is the separator Flutter itself uses when merging labels, so the string is
    // byte-identical to Material's.
    final indexLabel = MaterialLocalizations.of(
      context,
    ).tabLabel(tabIndex: index + 1, tabCount: destinationCount);

    return Semantics(
      key: ValueKey('floating-nav-item-${destination.label.toLowerCase()}'),
      button: true,
      container: true,
      excludeSemantics: true,
      // The badge draws a number the screen reader cannot see, so the count
      // joins the spoken label rather than living only in the paint.
      label: destination.badgeSemanticLabel == null
          ? '${destination.label}\n$indexLabel'
          : '${destination.label}, ${destination.badgeSemanticLabel}\n$indexLabel',
      selected: isSelected,
      enabled: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            child: AnimatedScale(
              scale: isSelected ? 1.02 : 1.0,
              duration: AppAnimation.durationXs,
              curve: AppAnimation.emphasizedCurve,
              child: AnimatedContainer(
                duration: AppAnimation.durationSm,
                curve: AppAnimation.emphasizedCurve,
                constraints: const BoxConstraints(minWidth: 48),
                // No fixed horizontal padding here: the item's assigned width
                // already accounts for _itemHorizontalPadding (see
                // preferredSelectedWidthFor), so adding it again as padding made
                // the row compete with its own allotment and overflow by a
                // fraction of a pixel at large reading sizes. Centring the
                // content reproduces the same insets and cannot overflow.
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(itemRadius),
                  border: Border.all(color: Colors.transparent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _BadgedIcon(
                      count: destination.badgeCount,
                      accent: destination.accentColor,
                      child: AnimatedSwitcher(
                        duration: AppAnimation.durationSm,
                        child: Icon(
                          isSelected
                              ? destination.selectedIcon
                              : destination.icon,
                          key: ValueKey(isSelected),
                          color: itemColor,
                          size: iconSize,
                        ),
                      ),
                    ),
                    // Flexible so the label ellipsises when the row is tighter
                    // than the measured preference — at large reading sizes the
                    // available width can fall short of what the pill wants.
                    Flexible(
                      child: AnimatedSize(
                        duration: AppAnimation.durationSm,
                        curve: AppAnimation.emphasizedCurve,
                        alignment: Alignment.centerLeft,
                        child: isSelected
                            ? Padding(
                                padding: const EdgeInsets.only(left: _labelGap),
                                child: AnimatedDefaultTextStyle(
                                  duration: AppAnimation.durationSm,
                                  // The same style the pill was measured with.
                                  style: labelStyleOf(
                                    context,
                                  ).copyWith(color: itemColor),
                                  child: Text(
                                    destination.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    // Clamped scaler: the pill was measured with
                                    // it, so the label must render with it too.
                                    textScaler: scaler,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A count on a navigation icon.
///
/// Deliberately the destination's own accent rather than a status tone — see
/// [FloatingNavDestination.badgeCount]. Excluded from semantics because the
/// destination already speaks the count in its label; a second node would read
/// the number twice.
class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({
    required this.count,
    required this.accent,
    required this.child,
  });

  final int count;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 15),
              height: 15,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.surface, width: 1.5),
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: Theme.of(context).textTheme.labelSmall
                    ?.weight(FontWeight.w800)
                    .tabular
                    .copyWith(
                      // Measured against the fill rather than assumed: white on
                      // the section cyan is 2.4:1, the dark ink is 6.6:1.
                      color: ServiceTheme.foregroundOn(accent),
                      height: 1,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_elevation.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';

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

  const FloatingNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.accentColor,
  });
}

/// Constants for FloatingBottomNavBar dimensions.
///
/// Use [FloatingNavBarMetrics.totalHeight] to calculate content padding.
class FloatingNavBarMetrics {
  FloatingNavBarMetrics._();

  /// Height of the nav bar itself.
  static const double barHeight = 60.0;

  /// Top padding above the nav bar.
  static const double topPadding = AppSpacing.sm; // 8dp

  /// Bottom padding below the nav bar (excluding safe area).
  static const double bottomPadding = AppSpacing.xs;

  /// Total height including top/bottom padding (excluding safe area).
  /// Use this value to add bottom padding to screen content.
  static const double totalHeight = barHeight + topPadding + bottomPadding;

  /// Returns the bottom padding needed for scroll views to allow content
  /// to scroll above the floating nav bar.
  ///
  /// Includes the nav bar height, margins, and device safe area.
  static double getScrollViewBottomPadding(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    return totalHeight + bottomSafeArea;
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

  static const double _barHorizontalPadding = 6.0;
  static const double _barVerticalPadding = 6.0;
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
    if (index != widget.selectedIndex) {
      HapticFeedback.selectionClick();
    }
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
    final isDark = colorScheme.brightness == Brightness.dark;
    final glassColor =
        theme.extension<SeekarrThemeColors>()?.glassSurface ??
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
                (_NavBarLayoutMetrics.preferredInnerWidth(widget.destinations) +
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
                        height: FloatingNavBarMetrics.barHeight,
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
                              );
                              final indicatorWidth = selectedDestination == null
                                  ? 0.0
                                  : _NavBarItem.preferredSelectedWidthFor(
                                          selectedDestination,
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
    final isDark = colorScheme.brightness == Brightness.dark;
    final accentColor = selectedDestination.accentColor;
    final activeBackground = accentColor.withValues(
      alpha: isDark ? 0.16 : 0.13,
    );
    final activeBorder = accentColor.withValues(alpha: 0.27);

    return Stack(
      children: [
        AnimatedPositioned(
          duration: AppAnimation.durationSm,
          curve: AppAnimation.emphasizedCurve,
          left: left,
          top: (barHeight - _NavBarItem._pillHeight) / 2,
          width: width,
          height: _NavBarItem._pillHeight,
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

  static double preferredInnerWidth(List<FloatingNavDestination> destinations) {
    final count = destinations.length;
    if (count == 0) return 0.0;

    final preferredSelectedWidth = destinations.fold<double>(
      _NavBarItem.minSelectedWidth,
      (currentMax, destination) {
        final width = _NavBarItem.preferredSelectedWidthFor(
          destination,
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
  static const double itemRadius = 20.0;
  static const double _labelGap = 6.0;
  static const double _selectedLabelFontSize = 12.0;
  static const double _selectedWidthSlack = 6.0;
  static const double minSelectedWidth = 84.0;

  /// Height of the animated selection pill — shorter than the full inner bar
  /// height so the highlight feels proportionate rather than filling the bar.
  static const double _pillHeight = 36.0;

  final FloatingNavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  static double preferredSelectedWidthFor(FloatingNavDestination destination) {
    final painter = TextPainter(
      text: TextSpan(
        text: destination.label,
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: _selectedLabelFontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.12,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    return _itemHorizontalPadding * 2 +
        _iconSize +
        _labelGap +
        painter.width +
        _selectedWidthSlack;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = destination.accentColor;

    final itemColor = isSelected ? accentColor : colorScheme.onSurfaceVariant;

    return Semantics(
      key: ValueKey('floating-nav-item-${destination.label.toLowerCase()}'),
      button: true,
      container: true,
      excludeSemantics: true,
      label: destination.label,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: _itemHorizontalPadding,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(itemRadius),
                  border: Border.all(color: Colors.transparent),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: AppAnimation.durationSm,
                      child: Icon(
                        isSelected
                            ? destination.selectedIcon
                            : destination.icon,
                        key: ValueKey(isSelected),
                        color: itemColor,
                        size: _iconSize,
                      ),
                    ),
                    AnimatedSize(
                      duration: AppAnimation.durationSm,
                      curve: AppAnimation.emphasizedCurve,
                      alignment: Alignment.centerLeft,
                      child: isSelected
                          ? Padding(
                              padding: const EdgeInsets.only(left: _labelGap),
                              child: AnimatedDefaultTextStyle(
                                duration: AppAnimation.durationSm,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontSize: _selectedLabelFontSize,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.12,
                                  color: itemColor,
                                ),
                                child: Text(
                                  destination.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
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

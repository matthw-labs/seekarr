import 'dart:async';

import 'package:flutter/material.dart';

import 'package:seekarr/core/app_animation.dart';

/// A one-shot fade + slide-up entrance for list/grid children.
///
/// Plays once when the widget is first inserted (it never re-animates on
/// subsequent rebuilds because the animation lives in [State]). For lazily
/// built collections, pass [index] and [wrapCount] so the per-item delay
/// cycles instead of growing unbounded as the user scrolls — this keeps the
/// stagger feeling continuous rather than laggy far down the list.
class StaggeredEntrance extends StatefulWidget {
  final Widget child;

  /// Position of this child; drives the staggered start delay.
  final int index;

  /// Delay increment per index step.
  final Duration step;

  /// The delay pattern resets every [wrapCount] items so off-screen items
  /// don't accumulate large delays. Set to 0 to disable wrapping.
  final int wrapCount;

  /// Vertical travel distance of the slide-up, in logical pixels.
  final double offset;

  const StaggeredEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.step = const Duration(milliseconds: 45),
    this.wrapCount = 12,
    this.offset = 16,
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppAnimation.durationMd,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: AppAnimation.emphasizedCurve,
  );

  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    final effectiveIndex = widget.wrapCount > 0
        ? widget.index % widget.wrapCount
        : widget.index;
    final delay = widget.step * effectiveIndex;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: AnimatedBuilder(
        animation: _fade,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - _fade.value) * widget.offset),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:seekarr/core/app_animation.dart';

/// Wraps a tappable child with a subtle press-down scale + optional haptic,
/// giving the app a tactile, "alive" feel on touch.
///
/// Use around posters, cards and list rows that navigate or act on tap. Keep
/// the effect gentle ([pressedScale] ~0.97) so it reads as depth, not a bounce.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale applied while pressed. Defaults to a subtle 0.97.
  final double pressedScale;

  /// Whether to fire [HapticFeedback.lightImpact] on tap.
  final bool haptic;

  /// Border radius used to clip the ripple/hit area, when relevant.
  final BorderRadius? borderRadius;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.haptic = true,
    this.borderRadius,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;

    return GestureDetector(
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled ? _handleTap : null,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: AppAnimation.durationXs,
        curve: AppAnimation.emphasizedCurve,
        child: widget.child,
      ),
    );
  }
}

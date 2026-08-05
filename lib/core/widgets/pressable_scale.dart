import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:seekarr/core/app_animation.dart';

/// Wraps a tappable child with a subtle press-down scale + optional haptic,
/// giving the app a tactile, "alive" feel on touch.
///
/// Use around posters, cards and list rows that navigate or act on tap. Keep
/// the effect gentle ([pressedScale] ~0.97) so it reads as depth, not a bounce.
///
/// Because nearly every tappable card in the app funnels through here, this is
/// also where the button role and label for assistive technology are attached:
/// pass [semanticLabel] and VoiceOver/TalkBack announce the tile as a button
/// with a name instead of an unlabelled image. Set [excludeChildSemantics] when
/// the child's own text would otherwise be read out twice.
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

  /// Accessible name announced for this control.
  ///
  /// Supply it whenever the child is visual-only (a poster, an artwork tile);
  /// omit it when the child already renders the text a screen reader needs.
  final String? semanticLabel;

  /// Additional context announced after the label, e.g. "Missing".
  final String? semanticValue;

  /// What activating this does, e.g. 'opens the queue item'.
  ///
  /// Exists so [AppCard] can hand its own `semanticHint` down when it delegates
  /// press feedback here: without it the hint would be dropped silently, which
  /// is the sort of gap only a screen reader notices.
  final String? semanticHint;

  /// Whether to hide the child's own semantics behind [semanticLabel].
  final bool excludeChildSemantics;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.haptic = true,
    this.borderRadius,
    this.semanticLabel,
    this.semanticValue,
    this.semanticHint,
    this.excludeChildSemantics = false,
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
    // Honour Reduce Motion: the press-down scale is decoration, so drop it
    // rather than animate it.
    final animate = !MediaQuery.disableAnimationsOf(context);

    final Widget scaled = AnimatedScale(
      scale: _pressed && animate ? widget.pressedScale : 1.0,
      duration: animate ? AppAnimation.durationXs : Duration.zero,
      curve: AppAnimation.emphasizedCurve,
      child: widget.child,
    );

    final Widget detector = GestureDetector(
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: enabled ? _handleTap : null,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: scaled,
    );

    if (!enabled && widget.semanticLabel == null) return detector;

    return Semantics(
      button: enabled,
      container: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      hint: enabled ? widget.semanticHint : null,
      excludeSemantics: widget.excludeChildSemantics,
      onTap: enabled ? _handleTap : null,
      onLongPress: widget.onLongPress,
      child: detector,
    );
  }
}

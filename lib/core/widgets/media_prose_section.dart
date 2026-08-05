import 'package:flutter/material.dart';

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/widgets/media_detail_body_metrics.dart';

/// Running prose on a detail page — an overview, a biography — clamped to a
/// readable measure and expandable in place.
///
/// Set in `bodyLarge` on `onSurfaceVariant`, the role the type ramp designates
/// for reading, at the 1.55 leading that role already carries. **No `height:`
/// override:** a hand-set line height on a themed role is a Leading Ladder Rule
/// violation, and the previous overview section's `height: 1.6` was exactly
/// that.
///
/// Bounded by `maxLines`, never by a fixed height, so it needs no
/// `TextScaleMetrics` and no clamp — it grows downward with the reading size
/// like a paragraph should.
class MediaProseSection extends StatefulWidget {
  /// The paragraph. Blank renders nothing at all.
  final String text;

  /// Lines shown before the reader asks for the rest.
  final int maxLines;

  const MediaProseSection({super.key, required this.text, this.maxLines = 6});

  @override
  State<MediaProseSection> createState() => _MediaProseSectionState();
}

class _MediaProseSectionState extends State<MediaProseSection> {
  /// Local, not provider-backed, on purpose: a refresh or a queue poll
  /// invalidating the screen's provider must not collapse a paragraph the user
  /// is halfway through reading.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final style = theme.textTheme.bodyLarge!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // `Align` before the `ConstrainedBox`, not instead of it: a slot arrives
    // with a *tight* width from the spine's `Padding`, and
    // `ConstrainedBox.enforce` clamps its own `maxWidth` back up into that tight
    // range — so on a wide macOS window the measure was silently inert and the
    // paragraph ran the full column. `Align` loosens the incoming width first,
    // which is what lets the measure bite, and keeps the block leading-aligned.
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: MediaDetailMetrics.proseMaxWidth,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Whether the clamp actually bites, measured rather than assumed: a
            // two-line overview must not grow a "Show more" that reveals nothing.
            // Safe here because this is a route body slot — nothing asks it for
            // intrinsics, which is the one thing a `LayoutBuilder` cannot answer.
            final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              maxLines: widget.maxLines,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: constraints.maxWidth);
            final overflows = painter.didExceedMaxLines;
            painter.dispose();

            final clamped = overflows && !_expanded;

            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: style,
                  maxLines: clamped ? widget.maxLines : null,
                  overflow: clamped
                      ? TextOverflow.ellipsis
                      : TextOverflow.visible,
                ),
                if (overflows)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Show less' : 'Show more'),
                    ),
                  ),
              ],
            );

            // Reduce Motion removes the animator rather than zeroing it: a
            // zero-duration `AnimatedSize` re-dirties inside its own
            // `performLayout` and the framework asserts.
            if (MediaQuery.disableAnimationsOf(context)) return content;

            return AnimatedSize(
              duration: AppAnimation.durationSm,
              curve: AppAnimation.emphasizedCurve,
              alignment: Alignment.topLeft,
              child: content,
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';
import 'package:seekarr/features/stream/domain/stream_semantics.dart';

/// One live playback, as three stacked lines.
///
/// **Why this is a card and not a horizontal path row.** The first design drew a
/// session as one line tracing what → how → where → rate, with connectors, on the
/// theory that a connection should be traceable end to end. That layout cannot
/// ship: `TextScaleMetrics.singleLineChromeMaxScaleFactor` is 1.3 precisely
/// because "a strip of pills with connectors between them… cannot reflow", and
/// worse, any `Flexible` distribution ellipsises the longest child first — which
/// here is the transcode *reason*, the one string the surface exists to show. The
/// layout would have eaten its own focal point. `TorrentTile`, the app's other
/// live-transfer row, reached the same conclusion and stacks.
///
/// So the path survives as **vertical reading order** instead:
///
///  1. what is playing,
///  2. how it is being delivered, and why — in the warning tone when it costs a
///     re-encode,
///  3. who is watching it, on what, and how far in.
///
/// The rate keeps its own row-end slot rather than a column, so it can update in
/// place (tabular figures) without a shared column grid to keep aligned.
class StreamSessionCard extends StatelessWidget {
  const StreamSessionCard({
    super.key,
    required this.session,
    required this.accent,
    this.onStop,
  });

  final StreamSession session;
  final Color accent;

  /// Stopping is optional because it is not always permitted: Plex gates
  /// termination behind Plex Pass and admin scope. A null handler renders no
  /// control at all rather than a button that fails on tap.
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reason = session.transcodeReasonLabel;
    final rate = formatStreamBitrate(session.bitrate);
    final progressLabel = _progressLabel(session.progress);

    // The tone is the *session's* own, resolved in the domain layer: a transcode
    // is the thing asking for attention, everything else is the stack working.
    final costColor = session.needsAttention
        ? AppColors.warning
        : colorScheme.onSurfaceVariant;

    return Semantics(
      container: true,
      label: session.title,
      value: streamSessionValue(
        userName: session.userName,
        title: session.title,
        subtitle: session.subtitle,
        playMethodLabel: session.playMethod.label,
        transcodeReason: reason,
        deviceLabel: session.deviceLabel,
        progressLabel: progressLabel,
        bitrateLabel: rate,
        bitrateIsNominal: session.bitrateIsNominal,
        isPaused: session.isPaused,
      ),
      excludeSemantics: true,
      child: AppCard.filled(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TitleRow(session: session, onStop: onStop),
            const SizedBox(height: AppSpacing.sm),
            _CostRow(
              session: session,
              reason: reason,
              color: costColor,
              rate: rate,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${session.userName} · ${session.deviceLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (session.progress != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _ProgressBar(progress: session.progress!, accent: accent),
            ],
          ],
        ),
      ),
    );
  }

  static String? _progressLabel(double? progress) {
    if (progress == null) return null;
    return '${(progress * 100).round()}% in';
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.session, required this.onStop});

  final StreamSession session;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = session.subtitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (session.isPaused)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs, top: 2),
            child: Icon(
              Icons.pause_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (onStop != null)
          IconButton(
            onPressed: onStop,
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            color: theme.colorScheme.onSurfaceVariant,
            tooltip: 'Stop this playback',
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

/// How the bytes are being delivered, and what it costs.
///
/// A `Wrap` rather than a `Row`, so the reason can take a second line instead of
/// eliding — see the class doc on [StreamSessionCard]. The rate sits in the same
/// wrap so it follows the reason down rather than pinning a column.
class _CostRow extends StatelessWidget {
  const _CostRow({
    required this.session,
    required this.reason,
    required this.color,
    required this.rate,
  });

  final StreamSession session;
  final String? reason;
  final Color color;
  final String? rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              session.needsAttention
                  ? Icons.memory_rounded
                  : Icons.bolt_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              session.playMethod.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (reason != null)
          Text(
            reason!,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        if (rate != null)
          Text(
            // "~" carries the same hedge the spoken form says as "about". Neither
            // server reports measured throughput, so an unqualified figure would
            // assert egress the API never gave us.
            session.bitrateIsNominal ? '~$rate' : rate!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 3,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation(accent),
      ),
    );
  }
}

/// Bits per second as a short human figure.
///
/// Decimal megabits, because that is the unit every media server, router and ISP
/// states a stream in — bytes here would be correct and unreadable. Returns null
/// for a null or non-positive input so callers can omit the slot rather than
/// printing "0 Mbps" for a session whose rate the server simply did not report.
String? formatStreamBitrate(int? bitsPerSecond) {
  if (bitsPerSecond == null || bitsPerSecond <= 0) return null;
  final mbps = bitsPerSecond / 1000000;
  if (mbps >= 10) return '${mbps.round()} Mbps';
  if (mbps >= 1) return '${mbps.toStringAsFixed(1)} Mbps';
  return '${(bitsPerSecond / 1000).round()} kbps';
}

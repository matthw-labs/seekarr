import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One background release search, as an instrument.
///
/// **The service accent is confined to the glyph.** DESIGN.md's Room Light Rule
/// forbids two service accents lighting one screen, and this list can hold a
/// Sonarr job beside a Radarr one — so it follows the `/services` precedent, but
/// narrower: no icon tile and not even the matrix's corner wash. Thirteen washes
/// across a grid read as lit cells; six stacked in a list read as a rainbow.
/// Identity gets one glyph of hue, health gets the closed tone vocabulary, and
/// the glyph's meaning is spoken because a colour is not information.
class ReleaseSearchJobCard extends StatelessWidget {
  const ReleaseSearchJobCard({
    super.key,
    required this.job,
    required this.now,
    this.queuePosition,
    this.onTap,
    this.onCancel,
    this.onSearchAgain,
    this.onDismiss,
    this.expandVerdict = false,
  });

  final ReleaseSearchJob job;

  /// Passed in rather than read from the clock so the whole list agrees, and so
  /// a test can place the job anywhere in its window.
  final DateTime now;

  /// 1-based position among queued jobs, when this one is waiting.
  final int? queuePosition;

  final VoidCallback? onTap;
  final VoidCallback? onCancel;
  final VoidCallback? onSearchAgain;
  final VoidCallback? onDismiss;

  /// Whether a failed job shows its full diagnosis rather than a summary.
  final bool expandVerdict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = releaseSearchTone(job);
    final remaining = job.grabWindowRemaining(now);
    final serviceTheme = ServiceTheme.fromAccent(job.target.service.accent);

    // A warning-toned chip beside an amber-accented service would show two
    // ambers meaning two different things (`radarr`, `sabnzbd` and `warning` are
    // the same hex), so the identity drains for as long as they share the card.
    final windowIsUrgent =
        remaining != null && remaining <= const Duration(minutes: 5);
    final glyphColor = windowIsUrgent && _accentClashesWithWarning
        ? colors.onSurfaceVariant
        : serviceTheme.accent;

    return AppCard.filled(
      onTap: onTap,
      semanticLabel: _spokenSummary,
      excludeChildSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(job.target.service.icon, size: 18, color: glyphColor),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.target.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _trailing(context, tone, remaining, windowIsUrgent),
            ],
          ),
          if (job.status == ReleaseSearchJobStatus.failed &&
              job.failure != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Verdict(failure: job.failure!, expanded: expandVerdict),
          ],
          if (_actions(context).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: _actions(context),
            ),
          ],
        ],
      ),
    );
  }

  bool get _accentClashesWithWarning {
    final accent = job.target.service.accent.toARGB32();
    return accent == const Color(0xFFF59E0B).toARGB32();
  }

  String get _subtitle {
    return switch (job.status) {
      ReleaseSearchJobStatus.queued =>
        queuePosition == null
            ? 'Waiting for a slot'
            : '$queuePosition ahead · starts when a slot frees',
      ReleaseSearchJobStatus.running => 'Searching your indexers',
      ReleaseSearchJobStatus.completed =>
        job.releaseCount == 0
            ? 'No releases found'
            : '${job.releaseCount} release${job.releaseCount == 1 ? '' : 's'}',
      ReleaseSearchJobStatus.failed =>
        job.failure?.headline ?? 'The search stopped',
      ReleaseSearchJobStatus.expired =>
        '${job.releaseCount} release${job.releaseCount == 1 ? '' : 's'} · expired',
    };
  }

  Widget _trailing(
    BuildContext context,
    StatusTone tone,
    Duration? remaining,
    bool urgent,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    // The elapsed clock lives in the sheet, not here: once a search is off
    // screen, a ticking figure answers nothing actionable, and sharing this slot
    // with the countdown made one position mean two opposite things.
    if (job.status == ReleaseSearchJobStatus.running) {
      return _Pill(
        label: 'Searching',
        tone: StatusTone.info,
        leading: SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: colors.primary,
          ),
        ),
      );
    }
    if (job.status == ReleaseSearchJobStatus.queued) {
      return const _Pill(label: 'Queued', tone: StatusTone.neutral);
    }
    if (remaining != null) {
      return _Pill(
        label: formatWindowRemaining(remaining),
        tone: urgent ? StatusTone.warning : StatusTone.info,
        icon: Icons.schedule_rounded,
        tabular: true,
      );
    }
    return switch (job.status) {
      ReleaseSearchJobStatus.expired => const _Pill(
        label: 'Expired',
        tone: StatusTone.neutral,
      ),
      ReleaseSearchJobStatus.failed => const _Pill(
        label: 'Stopped',
        tone: StatusTone.error,
      ),
      _ => const _Pill(label: 'Done', tone: StatusTone.neutral),
    };
  }

  List<Widget> _actions(BuildContext context) {
    return [
      if (job.isActive && onCancel != null)
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      if (!job.isActive && onSearchAgain != null)
        TextButton(onPressed: onSearchAgain, child: const Text('Search again')),
      if (!job.isActive && onDismiss != null)
        TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
    ];
  }

  /// One spoken sentence for the card's summary. In-card controls keep their own
  /// nodes — a single merged node would swallow them from the tree.
  String get _spokenSummary {
    final service = job.target.service.title;
    final remaining = job.grabWindowRemaining(now);
    return switch (job.status) {
      ReleaseSearchJobStatus.queued =>
        '${job.target.label}. Queued on $service, not started yet.',
      ReleaseSearchJobStatus.running =>
        '${job.target.label}. Searching on $service.',
      ReleaseSearchJobStatus.completed =>
        job.releaseCount == 0
            ? '${job.target.label}. No releases found on $service.'
            : '${job.target.label}. ${job.releaseCount} releases found on '
                  '$service, grabbable for '
                  '${formatWindowForSpeech(remaining ?? Duration.zero)}. '
                  'Double tap to pick one.',
      ReleaseSearchJobStatus.failed =>
        '${job.target.label}. ${job.failure?.headline ?? 'Search stopped.'}',
      ReleaseSearchJobStatus.expired =>
        '${job.target.label}. ${job.releaseCount} releases, no longer '
            'grabbable. Search again to use them.',
    };
  }
}

/// A resolved-tone pill. Renders a status; never derives one.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.tone,
    this.icon,
    this.leading,
    this.tabular = false,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;
  final Widget? leading;
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final toneColor = statusToneColor(colors, tone);
    // The label sits on a tint of its own tone, so it is measured against the
    // composite rather than against the tone alone.
    final labelColor = tone == StatusTone.neutral
        ? colors.onSurfaceVariant
        : ServiceTheme.onTint(
            toneColor,
            surface: colors.surface,
            tintAlpha: 0.16,
          );
    final background = tone == StatusTone.neutral
        ? Colors.transparent
        : toneColor.withValues(alpha: 0.16);

    var style = theme.textTheme.labelSmall!.weight(FontWeight.w600);
    if (tabular) style = style.tabular;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: tone == StatusTone.neutral
              ? colors.outlineVariant
              : toneColor.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 5)],
          if (icon != null) ...[
            Icon(icon, size: 12, color: labelColor),
            const SizedBox(width: 4),
          ],
          Text(label, style: style.copyWith(color: labelColor)),
        ],
      ),
    );
  }
}

/// A classified failure, in three registers.
///
/// The split of labour mirrors `AppErrorState`: the headline names what happened
/// in plain words, the diagnosis explains it, and the raw exception is demoted to
/// dim mono — present, because a self-hoster can act on "502 · nginx", but never
/// the message.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.failure, required this.expanded});

  final ReleaseSearchFailure failure;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // An OS ceiling or a deliberate cancellation is not a fault, so it does not
    // take the alarm rail — the Quiet Alarm Rule applied to a job.
    final isFault =
        failure.kind != ReleaseSearchFailureKind.cancelled &&
        failure.kind != ReleaseSearchFailureKind.interruptedByBackground;

    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            width: 2,
            color: isFault ? colors.error : colors.onSurfaceVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failure.diagnosis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (expanded && failure.detail != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              failure.detail!,
              style: theme.textTheme.labelSmall?.mono.copyWith(
                color: colors.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

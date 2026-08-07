import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/release_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';

/// Semantic tone of a release row.
///
/// Drives the status rail, the grab button and the header badge so a list of
/// releases can be triaged at a glance: green = the *Arr will accept it,
/// amber = accepted with reservations, red = rejected by the decision engine.
enum ReleaseStatusTone {
  approved(AppColors.success, 'Approved'),
  pending(AppColors.warning, 'Not approved'),
  rejected(AppColors.error, 'Rejected');

  final Color color;
  final String label;
  const ReleaseStatusTone(this.color, this.label);
}

/// Resolves the [ReleaseStatusTone] for a raw release map.
///
/// Shares [releaseIsApproved] with the filter chip and the summary count so all
/// three agree on what "approved" means.
ReleaseStatusTone releaseStatusTone(dynamic release) {
  if (releaseIsRejected(release)) return ReleaseStatusTone.rejected;
  if (releaseIsApproved(release)) return ReleaseStatusTone.approved;
  return ReleaseStatusTone.pending;
}

/// A single release row in the Interactive Search sheet.
///
/// Collapsed, the row reads top-down: quality + protocol + custom-format score,
/// then the release title, then a metadata line (size, age, indexer, peers).
/// Tapping anywhere expands it to reveal the full title (with copy), the custom
/// formats breakdown and any rejection reasons.
class ReleaseListItem extends StatefulWidget {
  final dynamic release;

  /// Null while another row's grab is in flight, which disables this row's grab
  /// affordance so only one download can be started at a time.
  final VoidCallback? onGrab;

  /// Shows a spinner in place of the grab affordance while *this* row's grab is
  /// in flight, and blocks repeated taps.
  final bool isGrabbing;

  const ReleaseListItem({
    super.key,
    required this.release,
    required this.onGrab,
    this.isGrabbing = false,
  });

  @override
  State<ReleaseListItem> createState() => _ReleaseListItemState();
}

class _ReleaseListItemState extends State<ReleaseListItem> {
  bool _expanded = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final release = widget.release;

    final tone = releaseStatusTone(release);
    final releaseTitle = release['title'] as String? ?? 'Unknown';
    final indexer = release['indexer'] as String? ?? 'Unknown';
    final sizeStr = formatReleaseSize((release['size'] as num? ?? 0).toInt());
    final seeders = (release['seeders'] as num?)?.toInt();
    final leechers = (release['leechers'] as num?)?.toInt();
    final quality = release['quality']?['quality']?['name'] as String? ?? '';
    final ageStr = formatReleaseAge(
      (release['ageMinutes'] as num? ?? 0).toInt(),
    );
    final protocol = releaseProtocolOf(release);
    final score = (release['customFormatScore'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(
            color: tone == ReleaseStatusTone.rejected
                ? tone.color.withValues(alpha: 0.28)
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: AppElevation.level1(colorScheme),
        ),
        child: ClipRRect(
          borderRadius: AppRadius.borderRadiusMd,
          child: Stack(
            children: [
              // Status rail — the fastest signal in the list.
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: 3,
                child: ColoredBox(color: tone.color.withValues(alpha: 0.9)),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ReleaseBadgeRow(
                                    quality: quality,
                                    protocol: protocol,
                                    score: score,
                                    tone: tone,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    releaseTitle,
                                    maxLines: _expanded ? 4 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium!
                                        .weight(FontWeight.w600)
                                        .copyWith(height: 1.25),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  _ReleaseMetaRow(
                                    indexer: indexer,
                                    sizeStr: sizeStr,
                                    ageStr: ageStr,
                                    seeders: seeders,
                                    leechers: leechers,
                                    isTorrent:
                                        protocol == ReleaseProtocol.torrent,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Column(
                              children: [
                                _GrabButton(
                                  tone: tone,
                                  busy: widget.isGrabbing,
                                  onPressed: widget.onGrab,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                AnimatedRotation(
                                  turns: _expanded ? 0.5 : 0,
                                  duration: AppAnimation.durationSm,
                                  curve: AppAnimation.standardCurve,
                                  child: Icon(
                                    Icons.expand_more_rounded,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        AnimatedSize(
                          duration: AppAnimation.durationSm,
                          curve: AppAnimation.standardCurve,
                          alignment: Alignment.topCenter,
                          child: _expanded
                              ? _ReleaseDetails(
                                  release: release,
                                  releaseTitle: releaseTitle,
                                  tone: tone,
                                  score: score,
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quality / protocol / custom-format score badges above the release title.
class _ReleaseBadgeRow extends StatelessWidget {
  final String quality;
  final ReleaseProtocol? protocol;
  final int score;
  final ReleaseStatusTone tone;

  const _ReleaseBadgeRow({
    required this.quality,
    required this.protocol,
    required this.score,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Badges wrap onto a second run instead of overflowing: quality names and
    // protocol labels vary a lot in width, and the score badge must stay put.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (quality.isNotEmpty)
                _Pill(
                  label: quality,
                  color: colorScheme.primary,
                  emphasize: true,
                ),
              if (protocol != null)
                _Pill(
                  label: protocol!.label,
                  icon: protocol!.icon,
                  color: colorScheme.onSurfaceVariant,
                ),
              if (tone == ReleaseStatusTone.rejected)
                _Pill(
                  label: tone.label,
                  icon: Icons.block_rounded,
                  color: tone.color,
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        ScoreBadge(score: score),
      ],
    );
  }
}

/// Metadata line under the release title.
class _ReleaseMetaRow extends StatelessWidget {
  final String indexer;
  final String sizeStr;
  final String ageStr;
  final int? seeders;
  final int? leechers;
  final bool isTorrent;

  const _ReleaseMetaRow({
    required this.indexer,
    required this.sizeStr,
    required this.ageStr,
    required this.seeders,
    required this.leechers,
    required this.isTorrent,
  });

  @override
  Widget build(BuildContext context) {
    final peerColor = _peerColor(context);

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        InfoChip(icon: Icons.storage_outlined, text: sizeStr),
        InfoChip(icon: Icons.schedule_outlined, text: ageStr),
        InfoChip(icon: Icons.dns_outlined, text: indexer),
        if (seeders != null)
          InfoChip(
            icon: Icons.arrow_upward_rounded,
            text: leechers != null && isTorrent
                ? '$seeders / $leechers'
                : '$seeders',
            color: peerColor,
          ),
      ],
    );
  }

  /// Torrents with no seeders will never finish — call that out in colour.
  Color? _peerColor(BuildContext context) {
    if (!isTorrent || seeders == null) return null;
    if (seeders == 0) return AppColors.error;
    if (seeders! < 5) return AppColors.warning;
    return AppColors.success;
  }
}

/// Expanded content: full title, custom formats and rejection reasons.
class _ReleaseDetails extends StatelessWidget {
  final dynamic release;
  final String releaseTitle;
  final ReleaseStatusTone tone;
  final int score;

  const _ReleaseDetails({
    required this.release,
    required this.releaseTitle,
    required this.tone,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customFormats =
        release['customFormats'] as List<dynamic>? ?? const [];
    final rejections = releaseRejectionReasons(release);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: AppSpacing.md),

        // Full, untruncated release name with a copy affordance.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                releaseTitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy release name',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: releaseTitle));
                if (context.mounted) {
                  SnackBarHelper.info(context, 'Release name copied');
                }
              },
            ),
          ],
        ),

        if (customFormats.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _SectionHeader(title: 'Custom Formats', score: score),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: customFormats.map<Widget>((cf) {
              return CustomFormatChip(
                name: cf['name'] as String? ?? 'Unknown',
                score: (cf['score'] as num?)?.toInt() ?? 0,
              );
            }).toList(),
          ),
        ],

        if (rejections.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const _SectionHeader(title: 'Rejection Reasons', isError: true),
          const SizedBox(height: AppSpacing.xs),
          ...rejections.map(
            (reason) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 14,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        if (customFormats.isEmpty && rejections.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No custom format data available',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Circular grab affordance with an inline busy state.
class _GrabButton extends StatelessWidget {
  final ReleaseStatusTone tone;
  final bool busy;

  /// Null while any grab is in flight, which renders the button disabled.
  final VoidCallback? onPressed;

  const _GrabButton({
    required this.tone,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: busy
          ? Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tone.color,
                ),
              ),
            )
          : IconButton(
              icon: const Icon(Icons.download_rounded, size: 20),
              color: tone.color,
              onPressed: onPressed,
              tooltip: onPressed == null
                  ? 'Another download is starting'
                  : 'Grab Release',
              style: IconButton.styleFrom(
                backgroundColor: tone.color.withValues(
                  alpha: onPressed == null ? 0.06 : 0.14,
                ),
                shape: const CircleBorder(),
              ),
            ),
    );
  }
}

/// Section label inside the expanded details, with an optional score badge.
class _SectionHeader extends StatelessWidget {
  final String title;
  final int? score;
  final bool isError;

  const _SectionHeader({required this.title, this.score, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Text(
          title.toUpperCase(),
          // Not `AppTheme.eyebrow`: this repeats inside every expanded release
          // card (and twice in one when a release is both scored and
          // rejected), so it is a dense label, not a region kicker.
          style: theme.textTheme.labelSmall!
              .weight(FontWeight.w700)
              .copyWith(
                color: isError
                    ? AppColors.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
        ),
        if (score != null) ...[
          const Spacer(),
          _Pill(
            label: 'Score: ${_signed(score!)}',
            color: score! >= 0 ? AppColors.success : AppColors.error,
          ),
        ],
      ],
    );
  }
}

/// Custom-format score badge shown on the right of the badge row.
class ScoreBadge extends StatelessWidget {
  final int score;

  const ScoreBadge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final neutral = score == 0;
    final color = neutral
        ? theme.colorScheme.onSurfaceVariant
        : (score > 0 ? AppColors.success : AppColors.error);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: neutral ? 0.10 : 0.16),
        borderRadius: AppRadius.borderRadiusFull,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _signed(score),
            // Scores stack down a release list and are read against each other.
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w700)
                .tabular
                .copyWith(color: color),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            // Was fontSize 9; the unit keeps its dimmer tone to stay quieter
            // than the number it annotates.
            'CF',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip showing a custom format name with its score.
class CustomFormatChip extends StatelessWidget {
  final String name;
  final int score;

  const CustomFormatChip({super.key, required this.name, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPositive = score >= 0;
    final color = isPositive ? AppColors.success : AppColors.error;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusFull,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _signed(score),
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w700)
                .tabular
                .copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Small chip displaying an icon with text, used for metadata display.
class InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  /// Optional semantic tint (e.g. peer health). Defaults to the variant tone.
  final Color? color;

  const InfoChip({
    super.key,
    required this.icon,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = color ?? theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: effective),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Every caller feeds this a size, an age or a seed/peer pair, and
            // the chips line up in a column down the release list.
            style: theme.textTheme.labelSmall!.tabular.copyWith(
              color: effective,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact tinted label used for quality, protocol and status.
class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool emphasize;

  const _Pill({
    required this.label,
    required this.color,
    this.icon,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: emphasize ? 0.16 : 0.10),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall!
                  .weight(emphasize ? FontWeight.w700 : FontWeight.w600)
                  .copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

String _signed(int score) => score >= 0 ? '+$score' : '$score';

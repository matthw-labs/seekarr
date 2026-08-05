import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';
import 'package:seekarr/features/discover/presentation/discover_detail_extras_provider.dart';
import 'package:seekarr/features/discover/presentation/discover_details_provider.dart';
import 'package:seekarr/features/discover/presentation/discover_navigation_utils.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_videos_button.dart';
import 'package:seekarr/features/discover/presentation/widgets/manage_media_sheet.dart';
import 'package:seekarr/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Action buttons for the discover detail screen header.
///
/// One expanded request action plus two captioned icon actions for trailers and
/// management — three controls, not six.
///
/// This is the Discover page's region-1 deck, so the same rule
/// [LibraryDetailActions] carries applies: **never pad this widget.** The detail
/// spine already wraps `deck` in the resolved gutter and the gap above it. When
/// this widget carried its own `symmetric(horizontal: lg, vertical: md)` the
/// Discover action row sat 32pt in and 12pt lower than every other page's deck —
/// the two insets compounded rather than replacing one another.
class DiscoverActionButtons extends ConsumerWidget {
  final int mediaId;
  final String mediaType;
  final bool hasManageableMedia;
  final bool isInService;
  final bool isAvailable;
  final int? tvdbId;
  final Map<String, dynamic>? mediaInfo;
  final String title;
  final double? voteAverage;

  /// Related videos for the Trailers button.
  final List<RelatedVideo> videos;

  const DiscoverActionButtons({
    super.key,
    required this.mediaId,
    required this.mediaType,
    required this.hasManageableMedia,
    required this.isInService,
    required this.isAvailable,
    required this.tvdbId,
    required this.mediaInfo,
    required this.title,
    required this.voteAverage,
    required this.videos,
  });

  String get _normalizedMediaType => mediaType == 'movie' ? 'movie' : 'tv';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final serviceName = _normalizedMediaType == 'movie' ? 'Radarr' : 'Sonarr';
    // Seerr's own accent, not `colorScheme.primary`. The two colours coincide
    // today — Seerr's brand indigo *is* the app primary — so there is no visual
    // symptom, which is exactly why this was the one control on the page that
    // had quietly opted out of the accent system.
    final accent = ServiceKey.seerr.accent;
    // Never a local luminance threshold: the app's own helper measures both
    // candidate inks against the fill instead of guessing from a cutoff.
    final onAccent = ServiceTheme.foregroundOn(accent);

    final isRequested = isInService || hasManageableMedia;
    // "Requested" is the wrong word for a title that is already on disk, and a
    // disabled button with no explanation is a dead end. So the label states the
    // actual state and a single line underneath says why nothing is offered.
    final String requestLabel;
    final IconData requestIcon;
    final String? disabledReason;
    if (isAvailable) {
      requestLabel = 'Available';
      requestIcon = Icons.check_circle_outline_rounded;
      disabledReason = 'Already in your library — nothing to request.';
    } else if (isRequested) {
      requestLabel = 'Requested';
      requestIcon = Icons.check_circle_outline_rounded;
      disabledReason = '$serviceName is already tracking this.';
    } else {
      requestLabel = 'Request';
      requestIcon = Icons.add_circle_outline_rounded;
      disabledReason = null;
    }
    final canRequest = disabledReason == null;
    final hasManageAction = hasManageableMedia || isInService;

    return Row(
      // Tops align, so the two captions hang below their own buttons instead
      // of pushing them up out of line with the request action.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: canRequest
                    ? () => _showRequestSheet(context, ref)
                    : null,
                icon: Icon(requestIcon, size: ActionStateGlyph.glyphSize),
                // Clamped at 1.6x for the reason the stacking section header
                // is: an unclamped single word too wide for its line gets
                // broken mid-word, which is how this button came to read
                // "Requeste / d" at an accessibility reading size.
                label: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaleMetrics.clampedScalerOf(context),
                  ),
                  child: Text(
                    requestLabel,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                ),
                style: HeaderActionRow.expandedButtonStyle(
                  backgroundColor: accent,
                  foregroundColor: onAccent,
                  disabledBackgroundColor: accent.withValues(alpha: 0.18),
                  // The label sits on an 18% accent tint over the surface, so
                  // the surface underneath is part of the contrast: the raw
                  // accent over its own tint fails AA in light theme.
                  disabledForegroundColor: ServiceTheme.onTint(
                    accent,
                    surface: colorScheme.surface,
                    tintAlpha: 0.18,
                  ),
                ),
              ),
              if (disabledReason != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  disabledReason,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        HeaderActionButton(
          icon: Icons.play_circle_outline_rounded,
          label: 'Trailers',
          semanticLabel: 'Trailers and teasers',
          onPressed: videos.isEmpty
              ? null
              : () => DiscoverVideosButton.show(context, videos),
        ),
        const SizedBox(width: AppSpacing.sm),
        HeaderActionButton(
          icon: hasManageableMedia
              ? Icons.settings_outlined
              : Icons.open_in_new_rounded,
          label: hasManageableMedia ? 'Manage' : 'Open',
          semanticLabel: hasManageableMedia
              ? 'Manage ${_normalizedMediaType == 'movie' ? 'movie' : 'series'}'
              : 'Open in $serviceName',
          onPressed: hasManageAction
              ? hasManageableMedia
                    ? () => _showManageSheet(context, ref)
                    : () => _openInService(context, ref)
              : null,
        ),
      ],
    );
  }

  void _showRequestSheet(BuildContext context, WidgetRef ref) {
    AppBottomSheet.show(
      context: context,
      title: _normalizedMediaType == 'tv' ? 'Request TV Show' : 'Request Movie',
      icon: Icons.download_rounded,
      accent: ServiceKey.seerr.accent,
      builder: (sheetContext) => RequestBottomSheet(
        mediaId: mediaId,
        mediaType: _normalizedMediaType,
        onRequestComplete: () {
          if (!context.mounted) {
            return;
          }

          // Through the helper, not a bare ScaffoldMessenger: the app's one
          // celebratory moment should not be default Material chrome with no
          // live region.
          SnackBarHelper.success(context, 'Request submitted');
          _invalidateDetailProviders(ref);
        },
      ),
    );
  }

  void _showManageSheet(BuildContext context, WidgetRef ref) {
    final currentMediaInfo = mediaInfo;
    if (currentMediaInfo == null) {
      return;
    }

    AppBottomSheet.showScrollable(
      context: context,
      title: 'Manage',
      subtitle: title,
      icon: Icons.settings_outlined,
      accent: ServiceKey.seerr.accent,
      builder: (sheetContext, scrollController) => ManageMediaSheet(
        mediaInfo: currentMediaInfo,
        mediaTitle: title,
        mediaType: _normalizedMediaType,
        tmdbId: mediaId,
        tvdbId: tvdbId,
        scrollController: scrollController,
        onDataChanged: () => _invalidateDetailProviders(ref),
      ),
    );
  }

  Future<void> _openInService(BuildContext context, WidgetRef ref) async {
    await openMediaInService(
      context: context,
      ref: ref,
      mediaType: _normalizedMediaType,
      tmdbId: mediaId,
      tvdbId: tvdbId,
    );
  }

  void _invalidateDetailProviders(WidgetRef ref) {
    ref.invalidate(
      discoverDetailProvider((id: mediaId, type: _normalizedMediaType)),
    );
    ref.invalidate(
      discoverDetailExtrasProvider((
        mediaId: mediaId,
        mediaType: _normalizedMediaType,
        tvdbId: tvdbId,
        voteAverage: voteAverage,
      )),
    );
  }
}

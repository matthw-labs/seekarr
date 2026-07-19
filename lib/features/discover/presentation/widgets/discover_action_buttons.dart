import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';
import 'package:seekarr/features/discover/presentation/discover_detail_extras_provider.dart';
import 'package:seekarr/features/discover/presentation/discover_details_provider.dart';
import 'package:seekarr/features/discover/presentation/discover_navigation_utils.dart';
import 'package:seekarr/features/discover/presentation/widgets/discover_videos_button.dart';
import 'package:seekarr/features/discover/presentation/widgets/manage_media_sheet.dart';
import 'package:seekarr/features/discover/presentation/widgets/request_bottom_sheet.dart';

/// Action buttons for the discover detail screen header.
///
/// Renders a compact row: an expanded request button followed by icon-only
/// actions for videos and management.
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

  /// Collapse progress passed through from [MediaDetailPosterRow].
  final double collapseFactor;

  /// Related videos for the Videos icon-only button.
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
    required this.collapseFactor,
    required this.videos,
  });

  String get _normalizedMediaType => mediaType == 'movie' ? 'movie' : 'tv';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final serviceName = _normalizedMediaType == 'movie' ? 'Radarr' : 'Sonarr';
    final requestLabel = isAvailable || isInService || hasManageableMedia
        ? 'Requested'
        : 'Request';
    final hasManageAction = hasManageableMedia || isInService;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: isAvailable || isInService || hasManageableMedia
                  ? null
                  : () => _showRequestSheet(context, ref),
              icon: Icon(
                isAvailable || isInService
                    ? Icons.check_circle_outline_rounded
                    : Icons.add_circle_outline_rounded,
                size: 18,
              ),
              label: Text(requestLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  HeaderActionRow.buttonHeight,
                ),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                disabledBackgroundColor: colorScheme.primary.withValues(
                  alpha: 0.18,
                ),
                disabledForegroundColor: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _DiscoverDetailIconButton(
            icon: Icons.play_circle_outline_rounded,
            tooltip: 'Trailers and teasers',
            onPressed: videos.isEmpty
                ? null
                : () => DiscoverVideosButton.show(context, videos),
          ),
          const SizedBox(width: AppSpacing.sm),
          _DiscoverDetailIconButton(
            icon: hasManageableMedia
                ? Icons.settings_outlined
                : Icons.open_in_new_rounded,
            tooltip: hasManageableMedia
                ? 'Manage ${_normalizedMediaType == 'movie' ? 'movie' : 'series'}'
                : 'Open in $serviceName',
            onPressed: hasManageAction
                ? hasManageableMedia
                      ? () => _showManageSheet(context, ref)
                      : () => _openInService(context, ref)
                : null,
          ),
        ],
      ),
    );
  }

  void _showRequestSheet(BuildContext context, WidgetRef ref) {
    AppBottomSheet.show(
      context: context,
      title: _normalizedMediaType == 'tv' ? 'Request TV Show' : 'Request Movie',
      icon: Icons.download_rounded,
      accent: AppColors.seerr,
      builder: (sheetContext) => RequestBottomSheet(
        mediaId: mediaId,
        mediaType: _normalizedMediaType,
        onRequestComplete: () {
          if (!context.mounted) {
            return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request submitted successfully!')),
          );
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
      accent: AppColors.seerr,
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

class _DiscoverDetailIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _DiscoverDetailIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: HeaderActionRow.buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: HeaderActionRow.tonalIconButtonStyle(
          foregroundColor: colorScheme.onSurfaceVariant,
          backgroundColor: colorScheme.onSurface.withValues(alpha: 0.06),
          borderColor: colorScheme.outlineVariant,
        ),
        child: Icon(icon, size: 18, semanticLabel: tooltip),
      ),
    );
  }
}

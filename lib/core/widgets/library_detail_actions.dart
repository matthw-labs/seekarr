import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/header_action_row.dart';
import 'package:seekarr/core/widgets/media_profile_selector.dart';

/// Shared action buttons for library detail screens (Movies, Series, Music).
///
/// Renders the tri-state primary action plus library management actions.
class LibraryDetailActions extends StatelessWidget {
  /// Collapse progress from [MediaDetailPosterRow].
  final double collapseFactor;

  /// Whether the current item already exists in the library.
  final bool isInLibrary;

  /// Whether the current item is monitored.
  final bool isMonitored;

  /// Service-specific label used when the item is not in the library yet.
  final String addLabel;

  /// Whether a search operation is in progress.
  final bool isSearching;

  /// Whether a delete operation is in progress.
  final bool isDeleting;

  /// Whether the primary monitor/unmonitor action is in progress.
  final bool isUpdatingMonitoredState;

  /// Current quality profile name. If null, Row 2 is hidden.
  final String? currentProfileName;

  /// Current quality profile ID for highlighting in the selector.
  final int? currentProfileId;

  /// Available quality profiles for the selector.
  final List<Map<String, dynamic>> qualityProfiles;

  /// Called when the user taps the primary button.
  final VoidCallback onPrimaryAction;

  /// Called when the user taps Interactive Search.
  final VoidCallback onInteractiveSearch;

  /// Called when the user taps the Auto Search icon button.
  final VoidCallback onAutoSearch;

  /// Called when a new quality profile is selected.
  final Future<void> Function(int profileId) onProfileSelected;

  /// Called when the user taps the Delete icon button.
  final VoidCallback onDelete;

  /// Called when the user taps the manual Import icon button.
  final VoidCallback? onImport;

  /// Per-service accent used for the primary action button. Falls back to the
  /// theme primary when null.
  final Color? accent;

  const LibraryDetailActions({
    super.key,
    required this.collapseFactor,
    required this.isInLibrary,
    required this.isMonitored,
    required this.addLabel,
    required this.isSearching,
    required this.isDeleting,
    required this.isUpdatingMonitoredState,
    required this.onPrimaryAction,
    required this.onInteractiveSearch,
    required this.onAutoSearch,
    required this.onProfileSelected,
    required this.onDelete,
    this.onImport,
    this.accent,
    this.currentProfileName,
    this.currentProfileId,
    this.qualityProfiles = const [],
  });

  /// Legible foreground for a filled [accent] button — dark text on light
  /// accents (e.g. Radarr amber), white on darker ones.
  static Color _onAccent(Color accent) =>
      accent.computeLuminance() > 0.55 ? Colors.black : Colors.white;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = accent ?? colorScheme.primary;
    final onAccent = accent == null
        ? colorScheme.onPrimary
        : _onAccent(accentColor);
    final primaryLabel = !isInLibrary
        ? addLabel
        : isMonitored
        ? 'Unmonitor'
        : 'Monitor';
    final primaryIcon = !isInLibrary
        ? Icons.add_circle_outline_rounded
        : isMonitored
        ? Icons.bookmark_remove_outlined
        : Icons.bookmark_add_outlined;
    final actions = <Widget>[
      _DetailActionButton(
        icon: isSearching ? null : Icons.search_rounded,
        label: 'Interactive',
        onPressed: isSearching ? null : onInteractiveSearch,
        loading: isSearching,
      ),
      _DetailActionButton(
        icon: Icons.saved_search_rounded,
        label: 'Auto Search',
        onPressed: isSearching ? null : onAutoSearch,
      ),
      if (currentProfileName != null)
        _ProfileActionButton(
          currentProfileName: currentProfileName!,
          currentProfileId: currentProfileId,
          qualityProfiles: qualityProfiles,
          onProfileSelected: onProfileSelected,
        ),
      _DetailActionButton(
        icon: Icons.download_for_offline_outlined,
        label: 'Import',
        onPressed: onImport,
      ),
      _DetailActionButton(
        icon: isDeleting ? null : Icons.delete_outline_rounded,
        label: 'Delete',
        onPressed: isDeleting ? null : onDelete,
        loading: isDeleting,
        color: colorScheme.error,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: isUpdatingMonitoredState ? null : onPrimaryAction,
            icon: isUpdatingMonitoredState
                ? SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onAccent,
                    ),
                  )
                : Icon(primaryIcon, size: 18),
            label: Text(primaryLabel),
            style: HeaderActionRow.expandedButtonStyle(
              foregroundColor: onAccent,
              backgroundColor: accentColor,
            ),
          ),
          if (isInLibrary) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? color;

  const _DetailActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.onSurfaceVariant;
    final backgroundColor = color == colorScheme.error
        ? colorScheme.error.withValues(alpha: 0.1)
        : colorScheme.onSurface.withValues(alpha: 0.06);
    final borderColor = color == colorScheme.error
        ? colorScheme.error.withValues(alpha: 0.25)
        : colorScheme.outlineVariant;

    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: HeaderActionRow.buttonHeight,
            child: OutlinedButton(
              onPressed: onPressed,
              style: HeaderActionRow.tonalIconButtonStyle(
                foregroundColor: effectiveColor,
                backgroundColor: backgroundColor,
                borderColor: borderColor,
              ),
              child: loading
                  ? SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: effectiveColor,
                      ),
                    )
                  : Icon(icon, size: 18),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: effectiveColor,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  final String currentProfileName;
  final int? currentProfileId;
  final List<Map<String, dynamic>> qualityProfiles;
  final Future<void> Function(int profileId) onProfileSelected;

  const _ProfileActionButton({
    required this.currentProfileName,
    required this.currentProfileId,
    required this.qualityProfiles,
    required this.onProfileSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: HeaderActionRow.buttonHeight,
            child: MediaProfileSelector.iconOnly(
              currentProfileName: currentProfileName,
              currentProfileId: currentProfileId,
              qualityProfiles: qualityProfiles,
              onProfileSelected: onProfileSelected,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Profile',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

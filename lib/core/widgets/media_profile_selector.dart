import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

/// Opens the quality profile picker.
///
/// A top-level function rather than a static, per the house convention for sheet
/// helpers — and it exists as a function at all so the detail actions overflow
/// can open the picker directly. There the sheet row *is* the tap target, so
/// there is no button to host it.
///
/// Returns after [onProfileSelected] has been awaited, and only calls it when
/// the chosen profile actually differs from [currentProfileId] — a no-op write
/// to a quality profile can queue a library-wide upgrade sweep.
///
/// [accent] lights the sheet and the selected row. Pass the page's service
/// accent; without it the picker would put `colorScheme.primary` indigo on a
/// Sonarr violet page, which is a second accent on one screen.
Future<void> showMediaProfileSelector(
  BuildContext context, {
  required String currentProfileName,
  required int? currentProfileId,
  required List<Map<String, dynamic>> qualityProfiles,
  required Future<void> Function(int profileId) onProfileSelected,
  Color? accent,
  bool enableHaptics = true,
}) async {
  if (qualityProfiles.isEmpty) return;

  if (enableHaptics) {
    HapticFeedback.selectionClick();
  }

  final selectedId = await AppBottomSheet.show<int>(
    context: context,
    title: 'Quality profile',
    // Not the bare name: the selected row already says it, and two nodes reading
    // "HD-1080p" is one stop too many for a screen reader.
    subtitle: 'Currently $currentProfileName',
    icon: Icons.tune_rounded,
    accent: accent,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final profile in qualityProfiles)
          _ProfileRow(
            name: profile['name'] as String,
            isSelected: (profile['id'] as int) == currentProfileId,
            accent: accent,
            onTap: () =>
                Navigator.of(sheetContext).pop<int>(profile['id'] as int),
          ),
      ],
    ),
  );

  if (selectedId != null && selectedId != currentProfileId) {
    await onProfileSelected(selectedId);
  }
}

/// One profile row in the picker.
///
/// Through [PressableScale] rather than a `ListTile`: that widget is the sole
/// home of the press-scale, the haptic, the Reduce Motion check *and* the button
/// role plus accessible name, and a ~48pt row floods its own ink splash — a
/// flooded ripple reads as selection rather than as a touch, which is precisely
/// the wrong signal on a row where one sibling genuinely *is* selected.
class _ProfileRow extends StatelessWidget {
  final String name;
  final bool isSelected;
  final Color? accent;
  final VoidCallback onTap;

  const _ProfileRow({
    required this.name,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = accent ?? colorScheme.primary;
    final selectedInk = ServiceTheme.onTint(
      accentColor,
      surface: colorScheme.surfaceContainer,
      tintAlpha: 0,
    );

    return PressableScale(
      onTap: onTap,
      semanticLabel: name,
      semanticValue: isSelected ? 'Selected' : null,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: HeaderActionRow.buttonHeight,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: ActionStateGlyph.glyphSize,
              color: isSelected ? selectedInk : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                name,
                style: isSelected
                    ? theme.textTheme.bodyLarge!
                          .weight(FontWeight.w700)
                          .copyWith(color: selectedInk)
                    : theme.textTheme.bodyLarge!.weight(FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A reusable quality profile selector control.
///
/// Displays the current profile and opens [showMediaProfileSelector] on tap.
class MediaProfileSelector extends StatelessWidget {
  /// The currently selected profile name to display.
  final String currentProfileName;

  /// The currently selected profile ID for highlighting in the picker.
  final int? currentProfileId;

  /// List of available quality profiles.
  /// Each map should have 'id' (int) and 'name' (String) keys.
  final List<Map<String, dynamic>> qualityProfiles;

  /// Callback when a new profile is selected.
  /// Called with newly selected profile ID.
  final Future<void> Function(int profileId) onProfileSelected;

  /// Whether to use haptic feedback when opening the picker.
  final bool enableHaptics;

  /// Page accent, so the control and the picker stay on the screen's one accent
  /// instead of falling back to `colorScheme.primary`.
  final Color? accent;

  /// One form, deliberately. `.split` and `.iconOnly` existed for two hosts the
  /// status-led action band replaced: `.split` was built only by
  /// `MediaManagementRow` (deleted with it) and `.iconOnly` was the icon-only
  /// profile button the overflow sheet's "Quality profile: <name>" row took
  /// over. Both had zero call sites in `lib/`, so they are gone rather than
  /// carried as two untaken branches inside `build`.
  const MediaProfileSelector({
    super.key,
    required this.currentProfileName,
    required this.currentProfileId,
    required this.qualityProfiles,
    required this.onProfileSelected,
    this.enableHaptics = true,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = accent ?? colorScheme.primary;

    final label = ServiceTheme.onTint(
      accentColor,
      surface: colorScheme.surfaceContainer,
      tintAlpha: 0,
    );

    // Through PressableScale, not a bare InkWell: that is where the press-scale,
    // the haptic, the Reduce Motion check and the button role plus accessible
    // name live, and a hand-rolled gesture silently drops all four.
    return PressableScale(
      onTap: () => _open(context),
      semanticLabel: 'Quality profile: $currentProfileName',
      excludeChildSemantics: true,
      borderRadius: AppRadius.borderRadiusSm,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: HeaderActionRow.buttonHeight,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusSm,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.high_quality_rounded,
                size: ActionStateGlyph.glyphSize,
                color: label,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  currentProfileName,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.edit_rounded, size: 14, color: label),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) => showMediaProfileSelector(
    context,
    currentProfileName: currentProfileName,
    currentProfileId: currentProfileId,
    qualityProfiles: qualityProfiles,
    onProfileSelected: onProfileSelected,
    accent: accent,
    enableHaptics: enableHaptics,
  );
}

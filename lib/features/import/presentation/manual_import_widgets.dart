import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

extension ManualImportServiceCopy on ServiceKey {
  String get manualImportSubLabel {
    return switch (this) {
      ServiceKey.radarr => 'Movies',
      ServiceKey.sonarr => 'Series',
      ServiceKey.lidarr => 'Music',
      _ => 'Requests',
    };
  }

  String get manualImportSubtitle {
    return switch (this) {
      ServiceKey.radarr => 'Manual import movies',
      ServiceKey.sonarr => 'Manual import series',
      ServiceKey.lidarr => 'Manual import music',
      _ => 'Manual import requests',
    };
  }

  String get manualImportSearchHint {
    return switch (this) {
      ServiceKey.radarr => 'Search movie...',
      ServiceKey.sonarr => 'Search series...',
      ServiceKey.lidarr => 'Search artist...',
      _ => 'Search...',
    };
  }
}

/// The shared scaffold for the three import stations: ambient room tinted by
/// the owning service, glass app bar with a two-line title, and an optional
/// pinned bottom bar for the station's primary action.
class ManualImportFrame extends StatelessWidget {
  final ServiceKey service;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? bottomBar;
  final List<Widget>? actions;

  const ManualImportFrame({
    super.key,
    required this.service,
    required this.title,
    required this.subtitle,
    required this.child,
    this.bottomBar,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AmbientScaffold(
      accent: service.accent,
      appBar: GlassAppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium!.weight(FontWeight.w800),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Track passes a submitted-file count through this slot; the
              // other two stations pass digitless copy, which tabular figures
              // leave untouched.
              style: theme.textTheme.labelSmall!.tabular.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: child),
            if (bottomBar != null) bottomBar!,
          ],
        ),
      ),
    );
  }
}

/// The names of the three import stations, in order.
const manualImportStations = ['Locate', 'Review', 'Track'];

/// A compact "where am I" strip for a multi-step flow.
///
/// One pill per station: the active one takes the service accent as a soft
/// tint (the same selected-affordance vocabulary as the nav pill), finished
/// ones get a small check, upcoming ones recede. Spoken as a single node —
/// "Step 2 of 3: Review" — because three pills and two connectors are one fact.
class ImportStationBar extends StatelessWidget {
  final ServiceKey service;
  final List<String> stations;
  final int activeIndex;

  const ImportStationBar({
    super.key,
    required this.service,
    required this.activeIndex,
    this.stations = manualImportStations,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = service.accent;
    final activeLabelColor = ServiceTheme.onTint(
      accent,
      surface: colorScheme.surface,
      tintAlpha: 0.14,
    );

    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'Step ${activeIndex + 1} of ${stations.length}: '
          '${stations[activeIndex]}',
      // Compact chrome that must stay one line, so it follows the reading size
      // only to 1.3× — the same clamp DESIGN.md pins on the floating nav bar,
      // and for the same reason: three pills and two connectors cannot reflow.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: TextScaleMetrics.singleLineChromeMaxScaleFactor,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Row(
            children: [
              for (var index = 0; index < stations.length; index++) ...[
                if (index > 0)
                  // Fixed, not Expanded: a flexible connector competes with the
                  // pills for the same flex space, which squeezed "Locate" down
                  // to "Lo…" at the default reading size.
                  Container(
                    width: AppSpacing.lg,
                    height: 2,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: index <= activeIndex
                          ? accent.withValues(alpha: 0.45)
                          : colorScheme.outlineVariant,
                      borderRadius: AppRadius.borderRadiusFull,
                    ),
                  ),
                Flexible(
                  // Loose: the pill takes its natural width and only gives way
                  // when the row genuinely runs out of room.
                  fit: FlexFit.loose,
                  child: AnimatedContainer(
                    duration: AppAnimation.durationSm,
                    curve: AppAnimation.emphasizedCurve,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: index == activeIndex
                          ? accent.withValues(alpha: 0.14)
                          : Colors.transparent,
                      borderRadius: AppRadius.borderRadiusPill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (index < activeIndex) ...[
                          Icon(Icons.check_rounded, size: 14, color: accent),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        // Ellipsises past the clamp rather than clipping.
                        Flexible(
                          child: Text(
                            stations[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium!
                                .weight(
                                  index == activeIndex
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                )
                                .copyWith(
                                  color: index == activeIndex
                                      ? activeLabelColor
                                      : colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The current folder path as tappable segments.
class ImportBreadcrumb extends StatelessWidget {
  final ServiceKey service;
  final String? path;
  final ValueChanged<String>? onSegmentTap;
  final List<String>? segments;

  const ImportBreadcrumb({
    super.key,
    required this.service,
    this.path,
    this.onSegmentTap,
    this.segments,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pathSegments = segments ?? _segmentsFor(path ?? '');
    final isRoot = path == '/' || pathSegments.isEmpty;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Root folder',
            visualDensity: VisualDensity.compact,
            onPressed: onSegmentTap == null ? null : () => onSegmentTap!('/'),
            icon: Icon(
              Icons.home_rounded,
              size: 18,
              color: isRoot ? service.accent : colorScheme.onSurfaceVariant,
            ),
          ),
          for (var index = 0; index < pathSegments.length; index++) ...[
            ExcludeSemantics(
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton(
              onPressed: onSegmentTap == null || path == null
                  ? null
                  : () => onSegmentTap!(_pathForSegment(path!, index)),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                foregroundColor: index == pathSegments.length - 1
                    ? service.accent
                    : colorScheme.onSurfaceVariant,
                textStyle: theme.textTheme.labelMedium!.weight(
                  index == pathSegments.length - 1
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
              child: Text(pathSegments[index]),
            ),
          ],
        ],
      ),
    );
  }
}

/// The station's single primary action, pinned above the home indicator.
class ImportPrimaryButton extends StatelessWidget {
  final ServiceKey service;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const ImportPrimaryButton({
    super.key,
    required this.service,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onAccent = ServiceTheme.foregroundOn(service.accent);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: FilledButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          backgroundColor: service.accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: colorScheme.surfaceContainerHighest,
          disabledForegroundColor: colorScheme.onSurfaceVariant,
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}

String formatImportBytes(int size) {
  if (size <= 0) return 'Unknown size';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = size.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final precision = unit <= 1 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unit]}';
}

List<String> _segmentsFor(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.trim().isNotEmpty)
      .toList(growable: false);
}

String _pathForSegment(String path, int segmentIndex) {
  final prefix = path.startsWith('/') ? '/' : '';
  final segments = _segmentsFor(path).take(segmentIndex + 1).join('/');
  return '$prefix$segments';
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.36,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class ImportStepPills extends StatelessWidget {
  final ServiceKey service;
  final int activeStep;

  const ImportStepPills({
    super.key,
    required this.service,
    required this.activeStep,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          _StepPill(
            service: service,
            step: 1,
            activeStep: activeStep,
            label: 'Select',
          ),
          _StepConnector(done: activeStep > 1, accent: service.accent),
          _StepPill(
            service: service,
            step: 2,
            activeStep: activeStep,
            label: 'Match',
          ),
          _StepConnector(done: activeStep > 2, accent: service.accent),
          _StepPill(
            service: service,
            step: 3,
            activeStep: activeStep,
            label: 'Import',
          ),
        ],
      ),
    );
  }
}

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
    final colorScheme = Theme.of(context).colorScheme;
    final pathSegments = segments ?? _segmentsFor(path ?? '');
    final isRoot = path == '/' || pathSegments.isEmpty;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onSegmentTap == null ? null : () => onSegmentTap!('/'),
            borderRadius: AppRadius.borderRadiusFull,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                Icons.home_rounded,
                size: 16,
                color: isRoot ? service.accent : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (var index = 0; index < pathSegments.length; index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: index == pathSegments.length - 1
                    ? service.accent
                    : colorScheme.onSurfaceVariant,
              ),
              child: Text(
                pathSegments[index],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: index == pathSegments.length - 1
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: service.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            disabledForegroundColor: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant,
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
  }
}

class ImportMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? detail;

  const ImportMessage({
    super.key,
    required this.icon,
    required this.message,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
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

Color importStatusColor(String status) {
  return switch (status) {
    'queued' => AppColors.warning,
    'started' => AppColors.info,
    'completed' => AppColors.success,
    'failed' || 'aborted' || 'cancelled' || 'orphaned' => AppColors.error,
    _ => AppColors.info,
  };
}

class _StepPill extends StatelessWidget {
  final ServiceKey service;
  final int step;
  final int activeStep;
  final String label;

  const _StepPill({
    required this.service,
    required this.step,
    required this.activeStep,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final done = activeStep > step;
    final active = activeStep == step;
    final circleColor = done || active
        ? service.accent
        : colorScheme.surfaceContainerHigh;
    final borderColor = done || active ? service.accent : colorScheme.outline;
    final labelColor = done
        ? service.accent
        : active
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: circleColor,
            borderRadius: AppRadius.borderRadiusFull,
            border: Border.all(color: borderColor),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
              : Text(
                  '$step',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: active ? Colors.white : colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool done;
  final Color accent;

  const _StepConnector({required this.done, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        color: done ? accent : Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
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

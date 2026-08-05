import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/import/domain/manual_import_display.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/import/domain/manual_import_status.dart';
import 'package:seekarr/features/import/presentation/manual_import_provider.dart';
import 'package:seekarr/features/import/presentation/manual_import_review_rows.dart';
import 'package:seekarr/features/import/presentation/manual_import_widgets.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Station 3 — Track: the running `ManualImport` command as an instrument
/// panel.
///
/// The \*arr command is aggregate — the services never report per-file
/// results — so this screen deliberately renders one command status as truth
/// and points at Activity → History for the per-file verdicts, instead of
/// painting a green check on every row the moment the command completes.
class ManualImportProgressScreen extends ConsumerStatefulWidget {
  final ServiceKey service;

  const ManualImportProgressScreen({super.key, required this.service});

  @override
  ConsumerState<ManualImportProgressScreen> createState() =>
      _ManualImportProgressScreenState();
}

class _ManualImportProgressScreenState
    extends ConsumerState<ManualImportProgressScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      ref.read(manualImportFlowProvider.notifier).pollCommand();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualImportFlowProvider);
    final command = state.command;
    if (command == null || !command.isActive) {
      _pollTimer?.cancel();
    }

    return ManualImportFrame(
      service: widget.service,
      title: 'Import Progress',
      subtitle:
          '${widget.service.title} · ${state.submittedItems.length} '
          '${state.submittedItems.length == 1 ? 'file' : 'files'} submitted',
      bottomBar: _TrackButtons(
        service: widget.service,
        command: command,
        onDone: () => context.go('/activity'),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ImportStationBar(service: widget.service, activeIndex: 2),
          if (command == null)
            AppEmptyState(
              icon: Icons.downloading_rounded,
              title: 'Import has not started',
              message: 'Go back and confirm selected files to begin.',
              accentColor: widget.service.accent,
            )
          else ...[
            _CommandCard(
              service: widget.service,
              command: command,
              fileCount: state.submittedItems.length,
            ),
            if (command.isCompleted) const _HistoryNote(),
            for (final item in state.submittedItems)
              _SubmittedFileRow(
                service: widget.service,
                item: item,
                command: command,
              ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ],
      ),
    );
  }
}

/// The command as one signature instrument: status, timing, file count.
class _CommandCard extends StatelessWidget {
  final ServiceKey service;
  final ManualImportCommandStatus command;
  final int fileCount;

  const _CommandCard({
    required this.service,
    required this.command,
    required this.fileCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = manualImportCommandStatus(command);
    final tone = statusToneColor(colorScheme, info.tone);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: AppCard.elevated(
        accentColor: service.accent,
        child: Semantics(
          container: true,
          liveRegion: true,
          label:
              'Manual import ${info.label}, $fileCount '
              '${fileCount == 1 ? 'file' : 'files'}',
          explicitChildNodes: true,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Manual import',
                        style: theme.textTheme.titleMedium!.weight(
                          FontWeight.w700,
                        ),
                      ),
                    ),
                    StatusBadge(info: info),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Started',
                        value: _timeValue(command.started),
                      ),
                    ),
                    Expanded(
                      child: _Metric(
                        label: 'Duration',
                        value: command.duration ?? 'Running',
                      ),
                    ),
                    Expanded(
                      child: _Metric(label: 'Files', value: '$fileCount'),
                    ),
                  ],
                ),
                if (command.message?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    command.message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (command.exception?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.1),
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 16,
                          color: tone,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            command.exception!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One eyebrow-labelled instrument value.
class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTheme.eyebrow(theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall!.weight(FontWeight.w700).tabular,
        ),
      ],
    );
  }
}

/// Where the real per-file verdicts live once the command finishes.
class _HistoryNote extends StatelessWidget {
  const _HistoryNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Per-file results appear in Activity → History.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmittedFileRow extends StatelessWidget {
  final ServiceKey service;
  final ManualImportItem item;
  final ManualImportCommandStatus command;

  const _SubmittedFileRow({
    required this.service,
    required this.item,
    required this.command,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = manualImportCommandStatus(command);
    final tone = statusToneColor(colorScheme, info.tone);
    final identity = manualImportIdentityFor(service, item);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.filled(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: command.isActive
                    ? SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tone,
                        ),
                      )
                    : Icon(
                        command.isFailure
                            ? Icons.close_rounded
                            : Icons.check_rounded,
                        size: 18,
                        color: tone,
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Same three-line contract as the Review rows: matched
                  // identity, then the raw file on its own, then the facts.
                  Text(
                    [
                      item.mediaTitle,
                      if (identity.code != null) identity.code!,
                      if (identity.title != null) identity.title!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
                  ),
                  FilenameText(
                    filename: item.fileName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${item.qualityLabel} · ${formatImportBytes(item.size)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackButtons extends StatelessWidget {
  final ServiceKey service;
  final ManualImportCommandStatus? command;
  final VoidCallback onDone;

  const _TrackButtons({
    required this.service,
    required this.command,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showRetry = command?.isFailure == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (showRetry) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Back to review'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.error,
                  side: BorderSide(
                    color: colorScheme.error.withValues(alpha: 0.5),
                  ),
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.done_rounded, size: 18),
              label: const Text('Done'),
              style: FilledButton.styleFrom(
                backgroundColor: service.accent,
                foregroundColor: ServiceTheme.foregroundOn(service.accent),
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _timeValue(String? isoValue) {
  if (isoValue == null || isoValue.isEmpty) return 'Pending';
  final parsed = DateTime.tryParse(isoValue)?.toLocal();
  if (parsed == null) return isoValue;
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

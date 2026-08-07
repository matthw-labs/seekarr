import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';

/// Tag picker used by the indexer edit form and the bulk "Set tags" sheet.
///
/// Mirrors the web UI's tag input: every existing tag is a toggle, and typing a
/// label that does not exist yet creates it on Prowlarr before selecting it.
class ProwlarrTagSelector extends ConsumerStatefulWidget {
  const ProwlarrTagSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  @override
  ConsumerState<ProwlarrTagSelector> createState() =>
      _ProwlarrTagSelectorState();
}

class _ProwlarrTagSelectorState extends ConsumerState<ProwlarrTagSelector> {
  final _controller = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle(int id) {
    final next = [...widget.selected];
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    widget.onChanged(next);
  }

  Future<void> _createTag() async {
    final label = _controller.text.trim();
    if (label.isEmpty || _creating) return;

    // An existing label is selected rather than duplicated — Prowlarr would
    // accept the duplicate and leave two identical tags behind.
    final existing = ref.read(prowlarrTagsProvider).asData?.value ?? const [];
    for (final tag in existing) {
      if (tag.label.toLowerCase() == label.toLowerCase()) {
        _controller.clear();
        if (!widget.selected.contains(tag.id)) _toggle(tag.id);
        return;
      }
    }

    setState(() => _creating = true);
    try {
      final tag = await ref.read(prowlarrServiceProvider).createTag(label);
      ref.invalidate(prowlarrTagsProvider);
      _controller.clear();
      widget.onChanged([...widget.selected, tag.id]);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.error(context, 'Could not create the tag', detail: e);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tagsAsync = ref.watch(prowlarrTagsProvider);
    final tags = tagsAsync.asData?.value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isEmpty)
          Text(
            tagsAsync.isLoading
                ? 'Loading tags…'
                : 'No tags yet — type one below to create it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final tag in tags)
                _TagToggle(
                  label: tag.label,
                  selected: widget.selected.contains(tag.id),
                  onTap: () => _toggle(tag.id),
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _createTag(),
          decoration: InputDecoration(
            isDense: true,
            labelText: 'New tag',
            hintText: 'e.g. italian',
            suffixIcon: _creating
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'Create tag',
                    onPressed: _createTag,
                  ),
          ),
        ),
      ],
    );
  }
}

class _TagToggle extends StatelessWidget {
  const _TagToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? AppColors.prowlarr.withValues(alpha: 0.16)
          : colorScheme.surfaceContainerHighest,
      borderRadius: AppRadius.borderRadiusFull,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusFull,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 14,
                color: selected
                    ? AppColors.prowlarr
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!
                    .weight(FontWeight.w700)
                    .copyWith(
                      color: selected
                          ? AppColors.prowlarr
                          : colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

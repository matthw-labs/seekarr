import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_bottom_sheet.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';

/// Picks newznab categories to filter indexers by.
///
/// Only the top level is offered, as in the web UI: a selection of "Movies"
/// should match an indexer that advertises `2040` without asking the user to
/// enumerate every child id — [prowlarrExpandCategories] does that expansion.
Future<Set<int>?> showProwlarrCategoryPicker({
  required BuildContext context,
  required Set<int> selected,
}) {
  return AppBottomSheet.showScrollable<Set<int>>(
    context: context,
    title: 'Categories',
    subtitle: 'Show indexers that cover any of these',
    icon: Icons.category_outlined,
    accent: AppColors.prowlarr,
    showClose: true,
    initialSize: 0.7,
    minSize: 0.4,
    builder: (context, controller) =>
        _CategoryPicker(controller: controller, initial: selected),
  );
}

/// Expands a selection of parent categories into every id that should match:
/// the parents themselves plus their children.
Set<int> prowlarrExpandCategories(
  Set<int> parents,
  List<ProwlarrCategory> tree,
) {
  if (parents.isEmpty) return const {};
  final ids = <int>{...parents};
  for (final category in tree) {
    if (!parents.contains(category.id)) continue;
    for (final sub in category.subCategories) {
      ids.add(sub.id);
    }
  }
  return ids;
}

class _CategoryPicker extends ConsumerStatefulWidget {
  const _CategoryPicker({required this.controller, required this.initial});

  final ScrollController controller;
  final Set<int> initial;

  @override
  ConsumerState<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends ConsumerState<_CategoryPicker> {
  late Set<int> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(prowlarrCategoriesProvider);

    return categoriesAsync.when(
      data: (categories) {
        final sorted = [...categories]..sort((a, b) => a.id.compareTo(b.id));
        return ListView(
          controller: widget.controller,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final category in sorted)
                  _CategoryChip(
                    label: category.name ?? '${category.id}',
                    selected: _selected.contains(category.id),
                    onTap: () => setState(() {
                      if (!_selected.remove(category.id)) {
                        _selected.add(category.id);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _selected = <int>{}),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load the categories'),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => ref.invalidate(prowlarrCategoriesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium!
                .weight(FontWeight.w700)
                .copyWith(
                  color: selected
                      ? AppColors.prowlarr
                      : colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}

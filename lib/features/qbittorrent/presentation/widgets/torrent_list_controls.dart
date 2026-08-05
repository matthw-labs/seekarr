import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/qbittorrent/presentation/qbittorrent_provider.dart';

const List<TorrentFilter> kTorrentStatusFilters = [
  TorrentFilter.all,
  TorrentFilter.downloading,
  TorrentFilter.seeding,
  TorrentFilter.completed,
  TorrentFilter.paused,
  TorrentFilter.queued,
];

String torrentFilterLabel(TorrentFilter filter) {
  switch (filter) {
    case TorrentFilter.all:
      return 'All';
    case TorrentFilter.downloading:
      return 'Downloading';
    case TorrentFilter.seeding:
      return 'Seeding';
    case TorrentFilter.completed:
      return 'Completed';
    case TorrentFilter.paused:
      return 'Paused';
    case TorrentFilter.queued:
      return 'Queued';
  }
}

class TorrentFilterChipsRow extends ConsumerWidget {
  const TorrentFilterChipsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedFilter = ref.watch(torrentFilterProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = AppColors.qbittorrent;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          for (var i = 0; i < kTorrentStatusFilters.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm - 2),
            _FilterChip(
              label: torrentFilterLabel(kTorrentStatusFilters[i]),
              active: kTorrentStatusFilters[i] == selectedFilter,
              accent: accent,
              colorScheme: colorScheme,
              textTheme: textTheme,
              onTap: () {
                ref.read(torrentFilterProvider.notifier).state =
                    kTorrentStatusFilters[i];
              },
            ),
          ],
        ],
      ),
    );
  }
}

class TorrentFilterPillsRow extends ConsumerWidget {
  const TorrentFilterPillsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(availableCategoriesProvider);
    final tags = ref.watch(availableTagsProvider);
    final trackers = ref.watch(availableTrackersProvider);
    final selectedCategory = ref.watch(torrentCategoryFilterProvider);
    final selectedTag = ref.watch(torrentTagFilterProvider);
    final selectedTracker = ref.watch(torrentTrackerFilterProvider);

    final hasAnyOptions =
        categories.isNotEmpty || tags.isNotEmpty || trackers.isNotEmpty;

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = AppColors.qbittorrent;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            'Filter',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: hasAnyOptions
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterPill(
                          label: 'Categories',
                          selectedLabel: selectedCategory,
                          options: categories,
                          accent: accent,
                          colorScheme: colorScheme,
                          textTheme: textTheme,
                          onSelected: (value) {
                            ref
                                    .read(
                                      torrentCategoryFilterProvider.notifier,
                                    )
                                    .state =
                                value;
                          },
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _FilterPill(
                          label: 'Tags',
                          selectedLabel: selectedTag,
                          options: tags,
                          accent: accent,
                          colorScheme: colorScheme,
                          textTheme: textTheme,
                          onSelected: (value) {
                            ref.read(torrentTagFilterProvider.notifier).state =
                                value;
                          },
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _FilterPill(
                          label: 'Trackers',
                          selectedLabel: selectedTracker,
                          options: trackers,
                          accent: accent,
                          colorScheme: colorScheme,
                          textTheme: textTheme,
                          onSelected: (value) {
                            ref
                                    .read(torrentTrackerFilterProvider.notifier)
                                    .state =
                                value;
                          },
                        ),
                      ],
                    ),
                  )
                : Text(
                    '—',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class TorrentSortRow extends ConsumerWidget {
  const TorrentSortRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSort = ref.watch(torrentSortProvider);
    final reverse = ref.watch(torrentSortReverseProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = AppColors.qbittorrent;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            'Sort',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final sort in TorrentSort.values) ...[
                    if (sort != TorrentSort.values.first)
                      const SizedBox(width: AppSpacing.xs),
                    InkWell(
                      onTap: () {
                        if (sort == currentSort) {
                          ref.read(torrentSortReverseProvider.notifier).state =
                              !reverse;
                        } else {
                          ref.read(torrentSortProvider.notifier).state = sort;
                        }
                      },
                      borderRadius: AppRadius.borderRadiusMd,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md - 2,
                          vertical: AppSpacing.xs + 1,
                        ),
                        decoration: BoxDecoration(
                          color: sort == currentSort
                              ? accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: AppRadius.borderRadiusMd,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sort.label,
                              style: textTheme.labelSmall!
                                  .weight(
                                    sort == currentSort
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  )
                                  .copyWith(
                                    color: sort == currentSort
                                        ? accent
                                        : colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            if (sort == currentSort) ...[
                              const SizedBox(width: 2),
                              Icon(
                                reverse
                                    ? Icons.arrow_downward_rounded
                                    : Icons.arrow_upward_rounded,
                                size: 12,
                                color: accent,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.accent,
    required this.colorScheme,
    required this.textTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusFull,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md + 1,
          vertical: AppSpacing.xs + 1,
        ),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.15)
              : colorScheme.surfaceContainer,
          border: Border.all(
            color: active ? accent : colorScheme.outlineVariant,
          ),
          borderRadius: AppRadius.borderRadiusFull,
        ),
        child: Text(
          label,
          style: textTheme.labelSmall!
              .weight(FontWeight.w700)
              .copyWith(color: active ? accent : colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final String? selectedLabel;
  final List<String> options;
  final Color accent;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final ValueChanged<String?> onSelected;

  const _FilterPill({
    required this.label,
    required this.selectedLabel,
    required this.options,
    required this.accent,
    required this.colorScheme,
    required this.textTheme,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final active = selectedLabel != null;
    final displayLabel = selectedLabel ?? label;

    if (options.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md - 2,
          vertical: AppSpacing.xs + 1,
        ),
        child: Text(
          label,
          style: textTheme.labelSmall!
              .weight(FontWeight.w400)
              .copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
        ),
      );
    }

    return PopupMenuButton<String>(
      offset: const Offset(0, 36),
      padding: EdgeInsets.zero,
      onSelected: (value) => onSelected(value.isEmpty ? null : value),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: '',
          child: Text(
            'All',
            style: textTheme.bodySmall!.weight(
              selectedLabel == null ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        ...options.map(
          (o) => PopupMenuItem<String>(
            value: o,
            child: Text(
              o,
              style: textTheme.bodySmall!.weight(
                o == selectedLabel ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.hardEdge,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          onTap: null,
          borderRadius: AppRadius.borderRadiusMd,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md - 2,
              vertical: AppSpacing.xs + 1,
            ),
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(alpha: 0.12)
                  : colorScheme.surfaceContainer,
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayLabel,
                  style: textTheme.labelSmall!
                      .weight(active ? FontWeight.w700 : FontWeight.w500)
                      .copyWith(
                        color: active ? accent : colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 12,
                  color: active ? accent : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

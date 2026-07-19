import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/async_value_widget.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/search_bar_header.dart';
import 'package:seekarr/features/search/domain/global_search_result.dart';
import 'package:seekarr/features/search/presentation/global_search_provider.dart';
import 'package:seekarr/features/search/presentation/recent_searches_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(globalSearchQueryProvider);
    final selectedService = ref.watch(_selectedSearchServiceProvider);
    final results = ref.watch(globalSearchResultsProvider);
    final resetVersion = ref.watch(_globalSearchResetVersionProvider);
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    ref.listen<int>(navigationRefreshProvider(NavigationSection.search), (
      previous,
      next,
    ) {
      ref.read(globalSearchQueryProvider.notifier).state = '';
      ref.read(_globalSearchResetVersionProvider.notifier).state++;
    });

    // Record queries that returned results as recent searches.
    ref.listen<AsyncValue<List<GlobalSearchServiceResults>>>(
      globalSearchResultsProvider,
      (previous, next) {
        next.whenData((groups) {
          final q = ref.read(globalSearchQueryProvider).trim();
          if (q.isNotEmpty && groups.any((g) => g.results.isNotEmpty)) {
            ref.read(recentSearchesProvider.notifier).add(q);
          }
        });
      },
    );

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Search')),
      body: Column(
        children: [
          SearchBarHeader(
            key: ValueKey(resetVersion),
            initialQuery: query,
            hintText: 'Movies, shows, artists...',
            onQueryChanged: (value) {
              ref.read(globalSearchQueryProvider.notifier).state = value;
            },
          ),
          _ServiceFilterChips(
            selectedService: selectedService,
            onSelected: (service) {
              ref.read(_selectedSearchServiceProvider.notifier).state = service;
            },
          ),
          Divider(
            height: 1,
            indent: AppSpacing.lg,
            endIndent: AppSpacing.lg,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(
            child: query.trim().isEmpty
                ? const _SearchEmptyState()
                : AsyncValueWidget<List<GlobalSearchServiceResults>>(
                    value: results,
                    serviceName: 'search',
                    skeleton: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: AppSkeleton.listRows(),
                    ),
                    data: (groups) => _SearchResultsList(
                      groups: groups,
                      selectedService: selectedService,
                      bottomPadding: bottomPadding,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

final _globalSearchResetVersionProvider = StateProvider<int>((ref) => 0);

final _selectedSearchServiceProvider = StateProvider<ServiceKey?>(
  (ref) => null,
);

class _ServiceFilterChips extends StatelessWidget {
  final ServiceKey? selectedService;
  final ValueChanged<ServiceKey?> onSelected;

  const _ServiceFilterChips({
    required this.selectedService,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          _FilterChip(
            label: 'All services',
            selected: selectedService == null,
            onTap: () => onSelected(null),
          ),
          for (final service in ServiceKey.values.where((s) => s.isSearchable))
            _FilterChip(
              label: service.title,
              color: service.accent,
              selected: selectedService == service,
              onTap: () => onSelected(service),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.onTap,
    this.color,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? effectiveColor
                : effectiveColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? Colors.white : effectiveColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  final List<GlobalSearchServiceResults> groups;
  final ServiceKey? selectedService;
  final double bottomPadding;

  const _SearchResultsList({
    required this.groups,
    required this.selectedService,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final visibleGroups = groups
        .where(
          (group) =>
              selectedService == null || group.service == selectedService,
        )
        .toList(growable: false);
    final hasAnyResult = visibleGroups.any((group) => group.results.isNotEmpty);

    if (selectedService == null &&
        !hasAnyResult &&
        !visibleGroups.any((group) => group.hasError)) {
      return const _NoResultsState();
    }

    return ListView(
      padding: EdgeInsets.only(top: AppSpacing.sm, bottom: bottomPadding),
      children: [
        for (final group in visibleGroups) _SearchSection(group: group),
      ],
    );
  }
}

class _SearchSection extends StatelessWidget {
  final GlobalSearchServiceResults group;

  const _SearchSection({required this.group});

  @override
  Widget build(BuildContext context) {
    final service = group.service;
    final colorScheme = Theme.of(context).colorScheme;
    final count = group.results.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: service.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(service.icon, size: 14, color: service.accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                service.title,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                group.hasError
                    ? 'offline'
                    : '$count result${count == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: group.hasError
              ? _SearchSectionMessage(
                  icon: Icons.cloud_off_rounded,
                  text: '${service.title} is offline',
                  color: colorScheme.error,
                )
              : count == 0
              ? _SearchSectionMessage(
                  icon: Icons.search_off_rounded,
                  text: 'No ${service.title} results',
                  color: colorScheme.onSurfaceVariant,
                )
              : Column(
                  children: [
                    for (final result in group.results)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _SearchResultCard(result: result),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final GlobalSearchResult result;

  const _SearchResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = result.service;

    return AppCard.outlined(
      onTap: () => context.push(result.route, extra: result.routeExtra),
      backgroundColor: colorScheme.surfaceContainer,
      borderColor: colorScheme.outlineVariant,
      borderRadius: AppRadius.borderRadiusMd,
      padding: const EdgeInsets.all(11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            height: 75,
            child: ContentCard(
              imageUrl: result.imageUrl,
              httpHeaders: result.imageHeaders,
              badge: Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: service.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  result.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in result.tags.take(3))
                      _ResultTag(label: tag, color: service.accent),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox.square(
            dimension: 32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _resultActionColor(),
                shape: BoxShape.circle,
              ),
              child: Icon(_resultActionIcon(), size: 15, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Color _resultActionColor() {
    if (result.tags.any((tag) => tag.toLowerCase().contains('available'))) {
      return AppColors.success;
    }
    return result.service.accent;
  }

  IconData _resultActionIcon() {
    if (result.tags.any((tag) => tag.toLowerCase().contains('available'))) {
      return Icons.check_rounded;
    }
    return Icons.add_rounded;
  }
}

class _ResultTag extends StatelessWidget {
  final String label;
  final Color color;

  const _ResultTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _SearchSectionMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _SearchSectionMessage({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppRadius.borderRadiusLg,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.search_off_rounded,
      title: 'No results found',
      message: 'Try a different title or spelling.',
    );
  }
}

class _SearchEmptyState extends ConsumerWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final recents = ref.watch(recentSearchesProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: AppSpacing.xl),
        Icon(
          Icons.search_rounded,
          size: 48,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Search across every service',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Enter a title, show, or artist to query Seerr, Radarr, Sonarr, Lidarr, and Bazarr.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (recents.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          Row(
            children: [
              Text(
                'RECENT',
                style: AppTheme.eyebrow(colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: Text(
                  'Clear',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final query in recents)
                _RecentChip(
                  label: query,
                  onTap: () {
                    ref.read(globalSearchQueryProvider.notifier).state = query;
                    ref
                        .read(_globalSearchResetVersionProvider.notifier)
                        .state++;
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _RecentChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

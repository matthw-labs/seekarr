import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/utils/image_utils.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/async_value_widget.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/media_grid.dart';
import 'package:seekarr/core/widgets/media_poster_card.dart';
import 'package:seekarr/core/widgets/search_bar_header.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

typedef SettingsSelector = (String, String) Function(SettingsModel settings);
typedef MediaBrowseItemTap<T> =
    void Function(BuildContext context, T item, String heroTag);
typedef MediaBrowseTextExtractor<T> = String Function(T item);
typedef MediaBrowseRefreshCallback = void Function(WidgetRef ref);

enum MediaBrowseFilter { all, available, missing, inQueue }

/// Shared scaffold for media library browse screens.
///
/// Provides the shared AppBar, search bar, navigation refresh listener,
/// library refresh flow, and search results layout used by the Movies, Series,
/// and Music screens.
///
class MediaBrowseScaffold<T> extends ConsumerStatefulWidget {
  final String title;
  final String searchHint;
  final String activityRoute;
  final NavigationSection navigationSection;
  final String serviceName;
  final Color? accentColor;
  final String heroTagPrefix;
  final String searchHeroTagPrefix;
  final FutureProvider<List<T>> libraryProvider;
  final StateProvider<String> searchQueryProvider;
  final FutureProvider<List<T>?> searchResultsProvider;
  final MediaBrowseTextExtractor<T> titleExtractor;
  final MediaBrowseTextExtractor<T> subtitleExtractor;
  final MediaBrowseTextExtractor<T>? sortTitleExtractor;
  final List<dynamic>? Function(T item) imagesExtractor;
  final int Function(T item) idExtractor;
  final StatusExtractor<T>? statusExtractor;
  final MediaBrowseRefreshCallback? onRefresh;
  final SettingsSelector settingsSelector;
  final MediaBrowseItemTap<T> onItemTap;
  final List<String>? coverTypes;
  final bool showAppBar;
  final double topPadding;

  /// Optional KPI peek rail shown under the search bar (hidden while searching).
  final Widget? kpiPeek;

  const MediaBrowseScaffold({
    super.key,
    required this.title,
    required this.searchHint,
    required this.activityRoute,
    required this.navigationSection,
    required this.serviceName,
    this.accentColor,
    required this.heroTagPrefix,
    required this.searchHeroTagPrefix,
    required this.libraryProvider,
    required this.searchQueryProvider,
    required this.searchResultsProvider,
    required this.titleExtractor,
    required this.subtitleExtractor,
    this.sortTitleExtractor,
    required this.imagesExtractor,
    required this.idExtractor,
    this.statusExtractor,
    this.onRefresh,
    required this.settingsSelector,
    required this.onItemTap,
    this.coverTypes,
    this.showAppBar = true,
    this.topPadding = 0,
    this.kpiPeek,
  });

  @override
  ConsumerState<MediaBrowseScaffold<T>> createState() =>
      _MediaBrowseScaffoldState<T>();
}

class _MediaBrowseScaffoldState<T>
    extends ConsumerState<MediaBrowseScaffold<T>> {
  MediaBrowseFilter _selectedFilter = MediaBrowseFilter.all;

  @override
  Widget build(BuildContext context) {
    final isSearching = ref.watch(
      widget.searchQueryProvider.select((value) => value.isNotEmpty),
    );

    ref.listen<int>(navigationRefreshProvider(widget.navigationSection), (
      previous,
      next,
    ) {
      ref.read(widget.searchQueryProvider.notifier).state = '';
      ref.invalidate(widget.libraryProvider);
      widget.onRefresh?.call(ref);
      if (_selectedFilter != MediaBrowseFilter.all) {
        setState(() {
          _selectedFilter = MediaBrowseFilter.all;
        });
      }
    });

    return AmbientScaffold(
      accent: widget.accentColor,
      appBar: widget.showAppBar
          ? GlassAppBar(
              leading: isSearching
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        ref.read(widget.searchQueryProvider.notifier).state =
                            '';
                      },
                      tooltip: 'Exit search',
                    )
                  : null,
              title: Text(widget.title),
              actions: [
                IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: () => context.push(widget.activityRoute),
                  tooltip: 'Activity',
                ),
              ],
            )
          : null,
      // The header (search + KPI + filters) lives in the NestedScrollView
      // header slivers as non-pinned adapters, so it scrolls away with the
      // content instead of staying fixed above the list.
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          if (widget.topPadding > 0)
            SliverToBoxAdapter(
              child: SizedBox(
                height: widget.topPadding + MediaQuery.paddingOf(context).top,
              ),
            ),
          SliverToBoxAdapter(
            child: SearchBarHeader(
              hintText: widget.searchHint,
              accent: widget.accentColor,
              onQueryChanged: (query) {
                ref.read(widget.searchQueryProvider.notifier).state = query;
              },
            ),
          ),
          if (!isSearching && widget.kpiPeek != null)
            SliverToBoxAdapter(child: widget.kpiPeek!),
          if (!isSearching)
            SliverToBoxAdapter(
              child: _MediaBrowseFilterChips(
                selectedFilter: _selectedFilter,
                color:
                    widget.accentColor ?? Theme.of(context).colorScheme.primary,
                onSelected: (filter) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
              ),
            ),
        ],
        body: isSearching
            ? _buildSearchResults(context)
            : _buildLibraryContent(context),
      ),
    );
  }

  Widget _buildLibraryContent(BuildContext context) {
    final libraryAsync = ref.watch(widget.libraryProvider);
    final (url, apiKey) = ref.watch(
      currentSettingsProvider.select(widget.settingsSelector),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(widget.libraryProvider);
        widget.onRefresh?.call(ref);
      },
      child: AsyncValueWidget<List<T>>(
        value: libraryAsync,
        serviceName: widget.serviceName,
        data: (items) => _buildBrowseContent(
          context: context,
          items: items,
          baseUrl: url,
          apiKey: apiKey,
        ),
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final searchResultsAsync = ref.watch(widget.searchResultsProvider);
    final (url, apiKey) = ref.watch(
      currentSettingsProvider.select(widget.settingsSelector),
    );

    return searchResultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (results) {
        if (results == null || results.isEmpty) {
          return const Center(child: Text('No results found'));
        }

        return _buildGrid(
          context: context,
          items: results,
          baseUrl: url,
          apiKey: apiKey,
          heroTagPrefix: widget.searchHeroTagPrefix,
        );
      },
    );
  }

  Widget _buildBrowseContent({
    required BuildContext context,
    required List<T> items,
    required String baseUrl,
    required String apiKey,
  }) {
    final visibleItems = _filteredItems(items);

    if (visibleItems.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom:
              AppSpacing.lg +
              FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: const [
          SizedBox(height: 160),
          Center(child: Text('No items found')),
        ],
      );
    }

    final sections = _buildSections(visibleItems);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom:
            AppSpacing.lg +
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      itemCount: sections.length,
      itemBuilder: (context, sectionIndex) {
        final section = sections[sectionIndex];
        return Padding(
          key: ValueKey('media-browse-section-${section.label}'),
          padding: EdgeInsets.only(
            bottom: sectionIndex == sections.length - 1
                ? AppSpacing.lg
                : AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.label,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge!.weight(FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  const tileWidth = 96.0;
                  final columns = math.max(
                    1,
                    ((constraints.maxWidth + AppSpacing.gridGap) /
                            (tileWidth + AppSpacing.gridGap))
                        .floor(),
                  );
                  final tileSpacing = columns > 1
                      ? (constraints.maxWidth - (columns * tileWidth)) /
                            (columns - 1)
                      : 0.0;

                  return Wrap(
                    spacing: tileSpacing.clamp(0, AppSpacing.gridGap),
                    runSpacing: AppSpacing.lg,
                    children: [
                      for (
                        var itemIndex = 0;
                        itemIndex < section.items.length;
                        itemIndex++
                      )
                        _BrowsePosterTile(
                          title: widget.titleExtractor(
                            section.items[itemIndex],
                          ),
                          subtitle: widget.subtitleExtractor(
                            section.items[itemIndex],
                          ),
                          imageSource: ImageUtils.extractPosterUrl(
                            widget.imagesExtractor(section.items[itemIndex]),
                            baseUrl: baseUrl,
                            apiKey: apiKey,
                            coverTypes:
                                widget.coverTypes ?? const ['poster', 'cover'],
                          ),
                          status: widget.statusExtractor?.call(
                            section.items[itemIndex],
                          ),
                          heroTag:
                              '${widget.heroTagPrefix}_${widget.idExtractor(section.items[itemIndex])}_${section.startIndex + itemIndex}',
                          onTap: () => widget.onItemTap(
                            context,
                            section.items[itemIndex],
                            '${widget.heroTagPrefix}_${widget.idExtractor(section.items[itemIndex])}_${section.startIndex + itemIndex}',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGrid({
    required BuildContext context,
    required List<T> items,
    required String baseUrl,
    required String apiKey,
    required String heroTagPrefix,
  }) {
    return MediaGrid<T>(
      items: items,
      imagesExtractor: widget.imagesExtractor,
      idExtractor: widget.idExtractor,
      statusExtractor: widget.statusExtractor,
      titleExtractor: widget.titleExtractor,
      baseUrl: baseUrl,
      apiKey: apiKey,
      heroTagPrefix: heroTagPrefix,
      onItemTap: (item, heroTag) {
        widget.onItemTap(context, item, heroTag);
      },
      coverTypes: widget.coverTypes ?? const ['poster', 'cover'],
    );
  }

  List<T> _filteredItems(List<T> items) {
    final sortedItems = [...items]
      ..sort((left, right) {
        final bySortTitle = _sortKeyFor(left).compareTo(_sortKeyFor(right));
        if (bySortTitle != 0) {
          return bySortTitle;
        }
        return widget
            .titleExtractor(left)
            .toLowerCase()
            .compareTo(widget.titleExtractor(right).toLowerCase());
      });

    return sortedItems
        .where((item) {
          final status = widget.statusExtractor?.call(item);
          return switch (_selectedFilter) {
            MediaBrowseFilter.all => true,
            MediaBrowseFilter.available =>
              status != null &&
                  (status.isAvailable ||
                      status.availability == MediaAvailability.partial),
            // Deliberately excludes `unavailable`: an unreleased title is not a
            // gap the user can act on.
            MediaBrowseFilter.missing =>
              status == null ||
                  status.availability == MediaAvailability.missing,
            MediaBrowseFilter.inQueue => status?.isInPipeline ?? false,
          };
        })
        .toList(growable: false);
  }

  List<_MediaBrowseSection<T>> _buildSections(List<T> items) {
    final sections = <_MediaBrowseSection<T>>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final label = _sectionLabelFor(item);
      if (sections.isEmpty || sections.last.label != label) {
        sections.add(_MediaBrowseSection(label: label, startIndex: index));
      }
      sections.last.items.add(item);
    }
    return sections;
  }

  String _sortKeyFor(T item) {
    final sortTitle =
        (widget.sortTitleExtractor?.call(item) ?? widget.titleExtractor(item))
            .trim()
            .toLowerCase();
    return sortTitle;
  }

  String _sectionLabelFor(T item) {
    final sortKey = _sortKeyFor(item);
    if (sortKey.isEmpty) {
      return '#';
    }
    final firstCharacter = sortKey.characters.first.toUpperCase();
    return RegExp(r'^[A-Z]$').hasMatch(firstCharacter) ? firstCharacter : '#';
  }
}

class _MediaBrowseSection<T> {
  final String label;
  final int startIndex;
  final List<T> items;

  _MediaBrowseSection({required this.label, required this.startIndex})
    : items = <T>[];
}

class _MediaBrowseFilterChips extends StatelessWidget {
  final MediaBrowseFilter selectedFilter;
  final Color color;
  final ValueChanged<MediaBrowseFilter> onSelected;

  const _MediaBrowseFilterChips({
    required this.selectedFilter,
    required this.color,
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
          for (final filter in MediaBrowseFilter.values)
            _MediaBrowseFilterChip(
              label: switch (filter) {
                MediaBrowseFilter.all => 'All',
                MediaBrowseFilter.available => 'Available',
                MediaBrowseFilter.missing => 'Missing',
                MediaBrowseFilter.inQueue => 'In Queue',
              },
              color: color,
              selected: selectedFilter == filter,
              onTap: () => onSelected(filter),
            ),
        ],
      ),
    );
  }
}

class _MediaBrowseFilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _MediaBrowseFilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      // `AppRadius.pill`, not a twice-repeated literal 20. The season selector in
      // `media_child_list.dart` was deliberately unified onto this chip's
      // vocabulary, so the two were pixel-identical by coincidence rather than by
      // construction — a change to the token would have silently split them.
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusPill,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.12),
            borderRadius: AppRadius.borderRadiusPill,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium!
                .weight(FontWeight.w700)
                .copyWith(
                  color: selected ? ServiceTheme.foregroundOn(color) : color,
                ),
          ),
        ),
      ),
    );
  }
}

class _BrowsePosterTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final ImageSource imageSource;
  final MediaStatusInfo? status;
  final String heroTag;
  final VoidCallback onTap;

  const _BrowsePosterTile({
    required this.title,
    required this.subtitle,
    required this.imageSource,
    required this.status,
    required this.heroTag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The status dot is painted inside the excluded subtree, so it has to be
    // spoken here or it is lost entirely.
    final spokenValue = joinDisplayParts([
      subtitle,
      status?.semanticLabel,
    ], separator: ', ');

    return SizedBox(
      width: 96,
      // Labelled as one button: the visible title is truncated to a single line,
      // so a screen reader would otherwise announce a clipped name.
      child: Semantics(
        button: true,
        container: true,
        excludeSemantics: true,
        label: title,
        value: spokenValue.isEmpty ? null : spokenValue,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                height: 138,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Hero(
                        tag: heroTag,
                        transitionOnUserGestures:
                            MediaPosterCard.flightOnUserGestures,
                        child: ContentCard(
                          imageUrl: imageSource.url,
                          httpHeaders: imageSource.headers,
                        ),
                      ),
                    ),
                    if (status != null)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        // Redundant against the parent's `excludeSemantics`,
                        // but it keeps the invariant local: the tile speaks the
                        // status, the dot does not.
                        child: StatusBadge(
                          info: status!,
                          iconOnly: true,
                          excludeFromSemantics: true,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall!
                    .weight(FontWeight.w600)
                    .copyWith(color: colorScheme.onSurface),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Was fontSize 10, below the 11pt floor; the subtitle keeps
                  // its dimmer tone to stay a step under the title.
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

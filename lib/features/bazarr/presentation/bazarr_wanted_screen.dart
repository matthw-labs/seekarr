import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

enum _BazarrWantedTabKind { episodes, movies }

class BazarrWantedScreen extends ConsumerStatefulWidget {
  const BazarrWantedScreen({super.key});

  @override
  ConsumerState<BazarrWantedScreen> createState() => _BazarrWantedScreenState();
}

class _BazarrWantedScreenState extends ConsumerState<BazarrWantedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.bazarr);

    return Scaffold(
      appBar: _BazarrDetailAppBar(
        title: 'Wanted Subtitles',
        backRoute: ServiceRoutes.bazarr,
        accent: AppColors.bazarr,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.bazarr,
          labelColor: AppColors.bazarr,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          labelStyle: Theme.of(
            context,
          ).textTheme.titleSmall!.weight(FontWeight.w800),
          tabs: const [
            Tab(text: 'Episodes'),
            Tab(text: 'Movies'),
          ],
        ),
      ),
      body: isConfigured
          ? TabBarView(
              controller: _tabController,
              children: const [
                _BazarrWantedTab(kind: _BazarrWantedTabKind.episodes),
                _BazarrWantedTab(kind: _BazarrWantedTabKind.movies),
              ],
            )
          // The shared placeholder, not a private copy. A deep link into Wanted
          // with Bazarr unconfigured used to render a bare sentence with no
          // icon, no button and no route — the dead end the dashboard's own
          // copy of this state was replaced to stop being.
          : NotConfiguredPlaceholder.forService(ServiceKey.bazarr),
    );
  }
}

class _BazarrWantedTab extends ConsumerStatefulWidget {
  const _BazarrWantedTab({required this.kind});

  final _BazarrWantedTabKind kind;

  @override
  ConsumerState<_BazarrWantedTab> createState() => _BazarrWantedTabState();
}

class _BazarrWantedTabState extends ConsumerState<_BazarrWantedTab> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final List<BazarrWantedItem> _items = [];
  int _start = 0;
  int? _total;
  bool _initialLoading = true;
  bool _loadingMore = false;
  Object? _error;
  String? _errorKey;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  String get _providerKey =>
      widget.kind == _BazarrWantedTabKind.episodes ? 'episodes' : 'movies';

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      final service = ref.read(bazarrServiceProvider);
      final page = widget.kind == _BazarrWantedTabKind.episodes
          ? await service.getWantedEpisodes(start: 0, length: _pageSize)
          : await service.getWantedMovies(start: 0, length: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.data);
        _start = page.data.length;
        _total = page.total;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorKey = '${_providerKey}_init_${identityHashCode(e)}';
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    if (_total != null && _items.length >= _total!) return;
    setState(() => _loadingMore = true);
    try {
      final service = ref.read(bazarrServiceProvider);
      final page = widget.kind == _BazarrWantedTabKind.episodes
          ? await service.getWantedEpisodes(start: _start, length: _pageSize)
          : await service.getWantedMovies(start: _start, length: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.data);
        _start += page.data.length;
        _total = page.total;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorKey = '${_providerKey}_more_${identityHashCode(e)}';
        _loadingMore = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (_initialLoading || _loadingMore) return;
    if (_error != null) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const _BazarrWantedShimmerList();
    }

    if (_error != null && _items.isEmpty) {
      return _BazarrWantedError(
        key: ValueKey(_errorKey),
        message: 'Failed to load wanted ${widget.kind.name}',
        onRetry: _loadInitial,
      );
    }

    if (_items.isEmpty) {
      return const _BazarrWantedEmpty(
        label: 'No wanted subtitles. Everything is covered!',
      );
    }

    final hasMore = _total == null ? false : _items.length < _total!;
    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        itemCount: _items.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator(
                        color: AppColors.bazarr,
                        strokeWidth: 2.4,
                      )
                    : Text(
                        _error != null
                            ? 'Failed to load more'
                            : 'Pull up to load more',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            );
          }
          return _BazarrWantedRow(item: _items[index]);
        },
      ),
    );
  }
}

class _BazarrWantedRow extends StatelessWidget {
  const _BazarrWantedRow({required this.item});

  final BazarrWantedItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMovie = item.radarrId != null;
    final title = isMovie ? item.title : item.seriesTitle;
    final subtitle = _rowSubtitle(item, isMovie);
    final langCodes = item.missingLanguages
        .map((l) => l.code2 ?? l.name)
        .join(', ')
        .toUpperCase();

    return Material(
      color: colorScheme.surface,
      borderRadius: AppRadius.borderRadiusMd,
      child: InkWell(
        borderRadius: AppRadius.borderRadiusMd,
        onTap: () => _openDetail(context, item),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Text(
                  isMovie ? '🎬' : '📺',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? 'Unknown',
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall!.weight(FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bazarr.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: Text(
                  langCodes.isNotEmpty ? langCodes : 'WANTED',
                  style: Theme.of(context).textTheme.labelSmall!
                      .weight(FontWeight.w800)
                      .copyWith(color: AppColors.bazarr),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _rowSubtitle(BazarrWantedItem item, bool isMovie) {
    if (isMovie) return item.sceneName;
    final parts = <String>[];
    if (item.episodeNumber != null) parts.add(item.episodeNumber!);
    if (item.episodeTitle != null) parts.add(item.episodeTitle!);
    return parts.isNotEmpty ? parts.join(' · ') : null;
  }

  void _openDetail(BuildContext context, BazarrWantedItem item) {
    if (item.radarrId != null) {
      context.push(ServiceRoutes.bazarrMovie(item.radarrId!), extra: item);
    } else if (item.sonarrSeriesId != null) {
      context.push(
        ServiceRoutes.bazarrSeries(item.sonarrSeriesId!),
        extra: item,
      );
    }
  }
}

class _BazarrWantedShimmerList extends StatelessWidget {
  const _BazarrWantedShimmerList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, __) => ShimmerPlaceholder(
        height: 64,
        borderRadius: AppRadius.borderRadiusMd,
      ),
    );
  }
}

class _BazarrWantedEmpty extends StatelessWidget {
  const _BazarrWantedEmpty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 36,
              color: AppColors.success,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BazarrWantedError extends StatelessWidget {
  const _BazarrWantedError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BazarrDetailAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _BazarrDetailAppBar({
    required this.title,
    required this.backRoute,
    required this.accent,
    this.bottom,
  });

  final String title;
  final String backRoute;
  final Color accent;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize {
    final extra = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + extra);
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: accent.withValues(alpha: 0.12),
      leading: IconButton(
        icon: const Icon(Icons.chevron_left_rounded),
        onPressed: () => RouteUtils.popOrGo(context, backRoute),
        tooltip: 'Back',
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium!.weight(FontWeight.w700),
      ),
      bottom: bottom,
    );
  }
}

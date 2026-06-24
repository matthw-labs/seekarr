import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/route_utils.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';
import 'package:seekarr/features/bazarr/domain/models/bazarr_models.dart';
import 'package:seekarr/features/bazarr/presentation/bazarr_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

enum _BazarrLibraryTabKind { series, movies }

class BazarrLibraryScreen extends ConsumerStatefulWidget {
  const BazarrLibraryScreen({super.key});

  @override
  ConsumerState<BazarrLibraryScreen> createState() =>
      _BazarrLibraryScreenState();
}

class _BazarrLibraryScreenState extends ConsumerState<BazarrLibraryScreen>
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
      appBar: AppBar(
        backgroundColor: AppColors.bazarr.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => RouteUtils.popOrGo(context, ServiceRoutes.bazarr),
          tooltip: 'Back',
        ),
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.bazarr,
          labelColor: AppColors.bazarr,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          labelStyle: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(text: 'Series'),
            Tab(text: 'Movies'),
          ],
        ),
      ),
      body: isConfigured
          ? TabBarView(
              controller: _tabController,
              children: const [
                _BazarrLibraryTab(kind: _BazarrLibraryTabKind.series),
                _BazarrLibraryTab(kind: _BazarrLibraryTabKind.movies),
              ],
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Bazarr is not configured yet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
    );
  }
}

class _BazarrLibraryTab extends ConsumerStatefulWidget {
  const _BazarrLibraryTab({required this.kind});

  final _BazarrLibraryTabKind kind;

  @override
  ConsumerState<_BazarrLibraryTab> createState() => _BazarrLibraryTabState();
}

class _BazarrLibraryTabState extends ConsumerState<_BazarrLibraryTab> {
  static const int _pageSize = 50;

  final ScrollController _scrollController = ScrollController();
  final List<BazarrLibraryEntry> _items = [];
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
      widget.kind == _BazarrLibraryTabKind.series ? 'series' : 'movies';

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      final service = ref.read(bazarrServiceProvider);
      final page = widget.kind == _BazarrLibraryTabKind.series
          ? await service.getSeries(start: 0, length: _pageSize)
          : await service.getMovies(start: 0, length: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.data.map(BazarrLibraryEntry.from));
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
      final page = widget.kind == _BazarrLibraryTabKind.series
          ? await service.getSeries(start: _start, length: _pageSize)
          : await service.getMovies(start: _start, length: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.data.map(BazarrLibraryEntry.from));
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
      return ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        itemCount: 8,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, __) => ShimmerPlaceholder(
          height: 64,
          borderRadius: AppRadius.borderRadiusMd,
        ),
      );
    }

    if (_error != null && _items.isEmpty) {
      return _BazarrLibraryError(
        key: ValueKey(_errorKey),
        message: 'Failed to load library',
        onRetry: _loadInitial,
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No items found in your Bazarr library.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
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
                        'Pull up to load more',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            );
          }
          return _BazarrLibraryRow(entry: _items[index]);
        },
      ),
    );
  }
}

class BazarrLibraryEntry {
  BazarrLibraryEntry({required this.title, required this.subtitle});

  factory BazarrLibraryEntry.from(dynamic item) {
    if (item is BazarrSeries) {
      return BazarrLibraryEntry(
        title: item.title ?? 'Untitled series',
        subtitle: item.path ?? item.sortTitle ?? '',
      );
    }
    if (item is BazarrMovie) {
      final year = item.year != null ? ' (${item.year})' : '';
      return BazarrLibraryEntry(
        title: '${item.title ?? 'Untitled movie'}$year',
        subtitle: item.path ?? item.sortTitle ?? '',
      );
    }
    return BazarrLibraryEntry(title: 'Unknown', subtitle: '');
  }

  final String title;
  final String subtitle;
}

class _BazarrLibraryRow extends StatelessWidget {
  const _BazarrLibraryRow({required this.entry});

  final BazarrLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      borderRadius: AppRadius.borderRadiusMd,
      child: InkWell(
        borderRadius: AppRadius.borderRadiusMd,
        onTap: () => _openEntry(context),
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
                  entry.subtitle.isNotEmpty
                      ? entry.title.contains('Untitled movie')
                            ? '🎬'
                            : '📺'
                      : '❔',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.subtitle.isNotEmpty)
                      Text(
                        entry.subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEntry(BuildContext context) {
    if (entry.title.contains('Untitled movie')) {
      // Should not occur unless the data layer is misbehaving.
      return;
    }
  }
}

class _BazarrLibraryError extends StatelessWidget {
  const _BazarrLibraryError({
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

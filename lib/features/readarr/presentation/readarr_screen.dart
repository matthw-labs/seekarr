import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/readarr/domain/models/readarr_models.dart';
import 'package:seekarr/features/readarr/presentation/readarr_provider.dart';
import 'package:seekarr/features/readarr/presentation/widgets/readarr_tiles.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Readarr service dashboard: author overview, library KPIs and recent activity.
/// Read-only for the first release. Readarr is archived upstream but its v1 API
/// still works, so the standard *arr header-auth pattern applies.
class ReadarrScreen extends ConsumerWidget {
  const ReadarrScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.readarr);

    return AmbientScaffold(
      accent: AppColors.readarr,
      appBar: showAppBar ? const GlassAppBar(title: Text('Readarr')) : null,
      body: SafeArea(
        child: isConfigured
            ? _ReadarrDashboard(topPadding: topPadding)
            : _ReadarrNotConfigured(
                onOpenSettings: () => context.go(
                  '/settings/service/${ServiceKey.readarr.routeParam}',
                ),
              ),
      ),
    );
  }
}

class _ReadarrNotConfigured extends StatelessWidget {
  const _ReadarrNotConfigured({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_rounded,
              size: 48,
              color: AppColors.readarr,
            ),
            const SizedBox(height: 12),
            const Text(
              'Readarr is not configured yet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadarrDashboard extends ConsumerWidget {
  const _ReadarrDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorsAsync = ref.watch(readarrAuthorsProvider);
    final historyAsync = ref.watch(readarrRecentHistoryProvider);
    final summaryAsync = ref.watch(serviceSummaryProvider(ServiceKey.readarr));
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.readarr.title,
        accent: AppColors.readarr,
        onRetry: () => _invalidateAll(ref),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateAll(ref);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.readarr)),
            accent: AppColors.readarr,
          ),
          const SizedBox(height: 8),
          SectionHeader(
            title: 'Authors',
            showChevron: true,
            onTap: () => context.push(ServiceRoutes.readarrLibrary),
          ),
          const SizedBox(height: 2),
          _AuthorPreview(authorsAsync: authorsAsync),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Recent Activity', showChevron: false),
          const SizedBox(height: 2),
          _HistoryList(historyAsync: historyAsync),
        ],
      ),
    );
  }
}

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(readarrAuthorsProvider);
  ref.invalidate(readarrRecentHistoryProvider);
  ref.invalidate(readarrQueueProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.readarr));
  ref.invalidate(serviceSummaryProvider(ServiceKey.readarr));
}

class _AuthorPreview extends ConsumerWidget {
  const _AuthorPreview({required this.authorsAsync});

  final AsyncValue<List<ReadarrAuthor>> authorsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return authorsAsync.when(
      data: (authors) {
        if (authors.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No authors in the library yet.'),
          );
        }
        final sorted = [...authors]
          ..sort(
            (a, b) => a.authorName.toLowerCase().compareTo(
              b.authorName.toLowerCase(),
            ),
          );
        return Column(
          children: sorted
              .take(5)
              .map((author) => ReadarrAuthorTile(author: author))
              .toList(),
        );
      },
      loading: () => const ReadarrListShimmer(),
      error: (error, _) => ReadarrErrorRetry(
        message: 'Failed to load authors',
        onRetry: () => ref.invalidate(readarrAuthorsProvider),
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.historyAsync});

  final AsyncValue<List<ReadarrHistoryItem>> historyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return historyAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No recent activity yet.'),
          );
        }
        return Column(
          children: items
              .take(10)
              .map((item) => ReadarrHistoryTile(item: item))
              .toList(),
        );
      },
      loading: () => const ReadarrListShimmer(),
      error: (error, _) => ReadarrErrorRetry(
        message: 'Failed to load recent activity',
        onRetry: () => ref.invalidate(readarrRecentHistoryProvider),
      ),
    );
  }
}

/// Lightweight skeleton rows shown while a Readarr list loads.
class ReadarrListShimmer extends StatelessWidget {
  const ReadarrListShimmer({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(
        rows,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: AppRadius.borderRadiusMd,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline error placeholder with retry, distinct from the loading shimmer.
class ReadarrErrorRetry extends StatelessWidget {
  const ReadarrErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

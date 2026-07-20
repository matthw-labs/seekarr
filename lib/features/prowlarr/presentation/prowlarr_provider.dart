import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/features/prowlarr/data/prowlarr_service.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';

const int _defaultHistoryPageSize = 20;

/// Dashboard-ready alias for the underlying Prowlarr service.
///
/// Throws if Prowlarr is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.prowlarr)` before reading.
final prowlarrServiceProvider = Provider<ProwlarrService>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.prowlarrUrl.isEmpty || settings.prowlarrApiKey.isEmpty) {
    throw Exception('Prowlarr not configured');
  }
  final service = ProwlarrService(
    ApiClient(baseUrl: settings.prowlarrUrl, apiKey: settings.prowlarrApiKey),
  );
  // The provider is rebuilt whenever the config changes; close the previous
  // Dio instance so its connections are not leaked.
  ref.onDispose(() => service.client.close());
  return service;
});

/// Configured indexers.
final prowlarrIndexersProvider = FutureProvider<List<ProwlarrIndexer>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getIndexers();
});

/// Aggregated per-indexer usage statistics.
final prowlarrIndexerStatsProvider = FutureProvider<ProwlarrIndexerStats>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getIndexerStats();
});

/// Indexers currently disabled due to failures.
final prowlarrIndexerStatusProvider =
    FutureProvider<List<ProwlarrIndexerStatus>>((ref) async {
      return ref.watch(prowlarrServiceProvider).getIndexerStatus();
    });

/// Current health issues.
final prowlarrHealthProvider = FutureProvider<List<ProwlarrHealthIssue>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getHealth();
});

/// Most recent indexer activity for the dashboard.
final prowlarrRecentHistoryProvider = FutureProvider<ProwlarrHistoryPage>((
  ref,
) async {
  return ref
      .watch(prowlarrServiceProvider)
      .getHistory(page: 1, pageSize: _defaultHistoryPageSize);
});

/// A single indexer resolved from [prowlarrIndexersProvider], or null if the id
/// is unknown. Reuses the list fetch so the detail screen adds no extra call.
final prowlarrIndexerByIdProvider =
    FutureProvider.family<ProwlarrIndexer?, int>((ref, id) async {
      final indexers = await ref.watch(prowlarrIndexersProvider.future);
      for (final indexer in indexers) {
        if (indexer.id == id) return indexer;
      }
      return null;
    });

/// Per-indexer usage statistics resolved from [prowlarrIndexerStatsProvider].
final prowlarrIndexerStatByIdProvider =
    FutureProvider.family<ProwlarrIndexerStat?, int>((ref, id) async {
      final stats = await ref.watch(prowlarrIndexerStatsProvider.future);
      for (final stat in stats.indexers) {
        if (stat.indexerId == id) return stat;
      }
      return null;
    });

/// Failure state for a single indexer, or null when it is healthy.
final prowlarrIndexerStatusByIdProvider =
    FutureProvider.family<ProwlarrIndexerStatus?, int>((ref, id) async {
      final statuses = await ref.watch(prowlarrIndexerStatusProvider.future);
      for (final status in statuses) {
        if (status.indexerId == id) return status;
      }
      return null;
    });

/// Recent history for a single indexer.
///
/// Prowlarr's history endpoint has no reliable per-indexer filter, so a larger
/// page is fetched and filtered client-side by `indexerId`.
final prowlarrIndexerHistoryProvider =
    FutureProvider.family<List<ProwlarrHistoryItem>, int>((ref, id) async {
      final page = await ref
          .watch(prowlarrServiceProvider)
          .getHistory(page: 1, pageSize: 100);
      return page.records
          .where((item) => item.indexerId == id)
          .toList(growable: false);
    });

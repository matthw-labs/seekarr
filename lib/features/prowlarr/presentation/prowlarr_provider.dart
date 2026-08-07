import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

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
    ApiClient(
      baseUrl: settings.prowlarrUrl,
      apiKey: settings.prowlarrApiKey,
      pinnedCertFingerprint: settings.pinForUrl(settings.prowlarrUrl),
    ),
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

/// Recent history for a single indexer, filtered server-side.
final prowlarrIndexerHistoryProvider =
    FutureProvider.family<List<ProwlarrHistoryItem>, int>((ref, id) async {
      return ref.watch(prowlarrServiceProvider).getIndexerHistory(id);
    });

/// Configured providers of one kind (apps, download clients, notifications,
/// indexer proxies).
final prowlarrProvidersProvider =
    FutureProvider.family<List<ProwlarrProviderResource>, ProwlarrProviderKind>(
      (ref, kind) async {
        return ref.watch(prowlarrServiceProvider).getProviders(kind);
      },
    );

/// Implementations that can be added for one kind.
///
/// `autoDispose` because it is only read while a picker is open.
final prowlarrProviderSchemaProvider = FutureProvider.autoDispose
    .family<List<ProwlarrProviderResource>, ProwlarrProviderKind>((
      ref,
      kind,
    ) async {
      return ref.watch(prowlarrServiceProvider).getProviderSchema(kind);
    });

/// Applications Prowlarr syncs its indexers to.
final prowlarrApplicationsProvider =
    FutureProvider<List<ProwlarrProviderResource>>((ref) async {
      return ref.watch(
        prowlarrProvidersProvider(ProwlarrProviderKind.application).future,
      );
    });

/// Download clients, offered per indexer in the edit form.
final prowlarrDownloadClientsProvider =
    FutureProvider<List<ProwlarrProviderResource>>((ref) async {
      return ref.watch(
        prowlarrProvidersProvider(ProwlarrProviderKind.downloadClient).future,
      );
    });

/// Newznab categories, for the indexer category filter.
final prowlarrCategoriesProvider = FutureProvider<List<ProwlarrCategory>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getIndexerCategories();
});

/// Tags with their usage, for the tag manager.
final prowlarrTagDetailsProvider = FutureProvider<List<ProwlarrTagDetail>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getTagDetails();
});

/// Tags, used by the indexer filters and the edit form.
final prowlarrTagsProvider = FutureProvider<List<ProwlarrTag>>((ref) async {
  return ref.watch(prowlarrServiceProvider).getTags();
});

/// Tag labels by id, so a tile can render names instead of numbers.
final prowlarrTagLabelsProvider = Provider<Map<int, String>>((ref) {
  final tags = ref.watch(prowlarrTagsProvider);
  return tags.maybeWhen(
    data: (tags) => {for (final tag in tags) tag.id: tag.label},
    orElse: () => const <int, String>{},
  );
});

/// Sync profiles offered by the indexer edit form.
final prowlarrAppProfilesProvider = FutureProvider<List<ProwlarrAppProfile>>((
  ref,
) async {
  return ref.watch(prowlarrServiceProvider).getAppProfiles();
});

/// Every definition Prowlarr can add.
///
/// `autoDispose` on purpose: the payload is thousands of definitions and it is
/// only needed while the add-indexer picker is open.
final prowlarrIndexerSchemaProvider =
    FutureProvider.autoDispose<List<ProwlarrIndexer>>((ref) async {
      return ref.watch(prowlarrServiceProvider).getIndexerSchema();
    });

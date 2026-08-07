import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/features/readarr/data/readarr_service.dart';
import 'package:seekarr/features/readarr/domain/models/readarr_models.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';

/// Dashboard-ready alias for the underlying Readarr service.
///
/// Throws if Readarr is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.readarr)` before reading.
final readarrServiceProvider = Provider<ReadarrService>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.readarrUrl.isEmpty || settings.readarrApiKey.isEmpty) {
    throw Exception('Readarr not configured');
  }
  final service = ReadarrService(
    ApiClient(
      baseUrl: settings.readarrUrl,
      apiKey: settings.readarrApiKey,
      pinnedCertFingerprint: settings.pinForUrl(settings.readarrUrl),
    ),
  );
  // The provider is rebuilt whenever the config changes; close the previous
  // Dio instance so its connections are not leaked.
  ref.onDispose(() => service.client.close());
  return service;
});

/// All authors in the library.
final readarrAuthorsProvider = FutureProvider<List<ReadarrAuthor>>((ref) async {
  return ref.watch(readarrServiceProvider).getAuthors();
});

/// Most recent activity for the dashboard.
final readarrRecentHistoryProvider = FutureProvider<List<ReadarrHistoryItem>>((
  ref,
) async {
  return ref.watch(readarrServiceProvider).getRecentHistory();
});

/// Current download queue. Degrades to an empty list on failure so a queue
/// error never hides the rest of the KPI rail.
final readarrQueueProvider = FutureProvider<List<dynamic>>((ref) async {
  try {
    return await ref.watch(readarrServiceProvider).getQueue();
  } catch (_) {
    return const <dynamic>[];
  }
});

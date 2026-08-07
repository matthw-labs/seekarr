import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:seekarr/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';

/// SABnzbd client bound to the current settings.
///
/// Throws if SABnzbd is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.sabnzbd)` before reading.
final sabnzbdClientProvider = Provider<SabnzbdClient>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.sabnzbdUrl.isEmpty || settings.sabnzbdApiKey.isEmpty) {
    throw Exception('SABnzbd not configured');
  }
  final client = SabnzbdClient(
    url: settings.sabnzbdUrl,
    apiKey: settings.sabnzbdApiKey,
    certFingerprint: settings.pinForUrl(settings.sabnzbdUrl),
  );
  ref.onDispose(() => client.close());
  return client;
});

/// The current download queue.
final sabnzbdQueueProvider = FutureProvider<SabnzbdQueue>((ref) async {
  return ref.watch(sabnzbdClientProvider).getQueue();
});

/// Recent completed/failed downloads.
final sabnzbdHistoryProvider = FutureProvider<List<SabnzbdHistorySlot>>((
  ref,
) async {
  return ref.watch(sabnzbdClientProvider).getHistory();
});

/// Aggregate transfer statistics (total downloaded, etc.).
final sabnzbdServerStatsProvider = FutureProvider<SabnzbdServerStats>((
  ref,
) async {
  return ref.watch(sabnzbdClientProvider).getServerStats();
});

/// The configured categories, for the add-NZB dialog.
final sabnzbdCategoriesProvider = FutureProvider<List<String>>((ref) async {
  return ref.watch(sabnzbdClientProvider).getCategories();
});

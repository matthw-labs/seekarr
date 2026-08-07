import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// NZBGet client bound to the current settings.
///
/// Throws if NZBGet is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.nzbget)` before reading.
final nzbgetClientProvider = Provider<NzbgetClient>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.nzbgetUrl.isEmpty) {
    throw Exception('NZBGet not configured');
  }
  final client = NzbgetClient(
    url: settings.nzbgetUrl,
    username: settings.nzbgetUsername.isEmpty ? null : settings.nzbgetUsername,
    password: settings.nzbgetPassword.isEmpty ? null : settings.nzbgetPassword,
    certFingerprint: settings.pinForUrl(settings.nzbgetUrl),
  );
  ref.onDispose(() => client.close());
  return client;
});

/// Global download status.
final nzbgetStatusProvider = FutureProvider<NzbgetStatus>((ref) async {
  return ref.watch(nzbgetClientProvider).status();
});

/// The active download queue.
final nzbgetQueueProvider = FutureProvider<List<NzbgetGroup>>((ref) async {
  return ref.watch(nzbgetClientProvider).listGroups();
});

/// Recent completed/failed downloads.
final nzbgetHistoryProvider = FutureProvider<List<NzbgetHistoryItem>>((
  ref,
) async {
  return ref.watch(nzbgetClientProvider).history();
});

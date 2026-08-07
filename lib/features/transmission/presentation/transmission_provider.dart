import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

/// Transmission client bound to the current settings.
///
/// Throws if Transmission is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.transmission)` before reading.
///
/// Deliberately **one long-lived client per configuration** rather than one per
/// call. Two pieces of state make that load-bearing: the CSRF session id, which
/// costs an extra round trip to relearn, and the sticky credentials-rejected
/// flag, which is what stops a polling screen from spending the daemon's
/// hundred allowed login failures and locking the user out until they restart
/// it. A fresh client per request would throw both away every tick.
final transmissionClientProvider = Provider<TransmissionClient>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.transmissionUrl.isEmpty) {
    throw Exception('Transmission not configured');
  }
  final client = TransmissionClient(
    url: settings.transmissionUrl,
    username: settings.transmissionUsername.isEmpty
        ? null
        : settings.transmissionUsername,
    password: settings.transmissionPassword.isEmpty
        ? null
        : settings.transmissionPassword,
    certFingerprint: settings.pinForUrl(settings.transmissionUrl),
  );
  ref.onDispose(() => client.close());
  return client;
});

/// Every torrent the daemon knows about.
final transmissionTorrentsProvider = FutureProvider<List<TransmissionTorrent>>((
  ref,
) async {
  return ref.watch(transmissionClientProvider).torrents();
});

/// Aggregate counters — speeds and torrent counts.
final transmissionStatsProvider = FutureProvider<TransmissionStats>((
  ref,
) async {
  return ref.watch(transmissionClientProvider).stats();
});

/// Daemon settings: version, global limits, turtle mode.
final transmissionSessionProvider = FutureProvider<TransmissionSession>((
  ref,
) async {
  return ref.watch(transmissionClientProvider).session();
});

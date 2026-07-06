import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/truenas/data/truenas_service.dart';
import 'package:seekarr/features/truenas/data/truenas_ws_client.dart';

/// Long-lived WebSocket client for TrueNAS, rebuilt when its URL/API key
/// change. Closed automatically when disposed.
final truenasClientProvider = Provider<TrueNasWsClient>((ref) {
  final url = ref.watch(currentSettingsProvider.select((s) => s.truenasUrl));
  final apiKey = ref.watch(
    currentSettingsProvider.select((s) => s.truenasApiKey),
  );
  if (url.isEmpty || apiKey.isEmpty) {
    throw const TrueNasException('TrueNAS not configured');
  }
  final client = TrueNasWsClient(baseUrl: url, apiKey: apiKey);
  ref.onDispose(client.close);
  return client;
});

final truenasServiceProvider = Provider<TrueNasService>((ref) {
  return TrueNasService(ref.watch(truenasClientProvider));
});

/// The dashboard snapshot (system, pools, alerts, services).
final truenasDashboardProvider = FutureProvider.autoDispose((ref) async {
  // Keep the client alive for the life of this fetch.
  ref.watch(truenasClientProvider);
  return ref.watch(truenasServiceProvider).loadDashboard();
});

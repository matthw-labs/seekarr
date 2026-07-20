import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/truenas/data/apps_api.dart';
import 'package:seekarr/features/truenas/data/credentials_api.dart';
import 'package:seekarr/features/truenas/data/data_protection_api.dart';
import 'package:seekarr/features/truenas/data/dataset_api.dart';
import 'package:seekarr/features/truenas/data/network_api.dart';
import 'package:seekarr/features/truenas/data/reporting_api.dart';
import 'package:seekarr/features/truenas/data/sharing_api.dart';
import 'package:seekarr/features/truenas/data/storage_api.dart';
import 'package:seekarr/features/truenas/data/system_api.dart';
import 'package:seekarr/features/truenas/data/truenas_service.dart';
import 'package:seekarr/features/truenas/data/truenas_ws_client.dart';
import 'package:seekarr/features/truenas/data/virt_api.dart';
import 'package:seekarr/features/truenas/domain/truenas_version.dart';

/// Long-lived WebSocket client for TrueNAS, rebuilt when its URL/API key
/// change. Closed automatically when disposed.
final truenasClientProvider = Provider<TrueNasWsClient>((ref) {
  final url = ref.watch(currentSettingsProvider.select((s) => s.truenasUrl));
  final apiKey = ref.watch(
    currentSettingsProvider.select((s) => s.truenasApiKey),
  );
  final certFingerprint = ref.watch(
    currentSettingsProvider.select((s) => s.truenasCertFingerprint),
  );
  if (url.isEmpty || apiKey.isEmpty) {
    throw const TrueNasException('TrueNAS not configured');
  }
  final client = TrueNasWsClient(
    baseUrl: url,
    apiKey: apiKey,
    certFingerprint: certFingerprint.isEmpty ? null : certFingerprint,
  );
  ref.onDispose(client.close);
  return client;
});

final truenasServiceProvider = Provider<TrueNasService>((ref) {
  return TrueNasService(ref.watch(truenasClientProvider));
});

// ── Domain-grouped API providers ───────────────────────────────────────────
final truenasSystemApiProvider = Provider<TrueNasSystemApi>(
  (ref) => TrueNasSystemApi(ref.watch(truenasClientProvider)),
);
final truenasStorageApiProvider = Provider<TrueNasStorageApi>(
  (ref) => TrueNasStorageApi(ref.watch(truenasClientProvider)),
);
final truenasDatasetApiProvider = Provider<TrueNasDatasetApi>(
  (ref) => TrueNasDatasetApi(ref.watch(truenasClientProvider)),
);
final truenasSharingApiProvider = Provider<TrueNasSharingApi>(
  (ref) => TrueNasSharingApi(ref.watch(truenasClientProvider)),
);
final truenasDataProtectionApiProvider = Provider<TrueNasDataProtectionApi>(
  (ref) => TrueNasDataProtectionApi(ref.watch(truenasClientProvider)),
);
final truenasVirtApiProvider = Provider<TrueNasVirtApi>(
  (ref) => TrueNasVirtApi(ref.watch(truenasClientProvider)),
);
final truenasAppsApiProvider = Provider<TrueNasAppsApi>(
  (ref) => TrueNasAppsApi(ref.watch(truenasClientProvider)),
);
final truenasReportingApiProvider = Provider<TrueNasReportingApi>(
  (ref) => TrueNasReportingApi(ref.watch(truenasClientProvider)),
);
final truenasNetworkApiProvider = Provider<TrueNasNetworkApi>(
  (ref) => TrueNasNetworkApi(ref.watch(truenasClientProvider)),
);
final truenasCredentialsApiProvider = Provider<TrueNasCredentialsApi>(
  (ref) => TrueNasCredentialsApi(ref.watch(truenasClientProvider)),
);

/// The set of RPC methods the server exposes (capability discovery). Empty on
/// failure — treat unknown as "assume available".
final truenasCapabilitiesProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  return ref.watch(truenasClientProvider).getMethods();
});

/// The connected server's parsed version, or null if unavailable/unparseable.
final truenasVersionProvider = FutureProvider.autoDispose<TrueNasVersion?>((
  ref,
) async {
  final raw = await ref.watch(truenasSystemApiProvider).getVersion();
  return TrueNasVersion.parse(raw);
});

/// The dashboard snapshot (system, pools, alerts, services).
final truenasDashboardProvider = FutureProvider.autoDispose((ref) async {
  // Keep the client alive for the life of this fetch.
  ref.watch(truenasClientProvider);
  return ref.watch(truenasServiceProvider).loadDashboard();
});

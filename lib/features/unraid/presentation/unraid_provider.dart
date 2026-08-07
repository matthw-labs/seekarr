import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/unraid/data/unraid_client.dart';
import 'package:seekarr/features/unraid/domain/models/unraid_models.dart';

/// Unraid client bound to the current settings.
///
/// Throws if Unraid is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.unraid)` before reading.
final unraidClientProvider = Provider<UnraidClient>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.unraidUrl.isEmpty || settings.unraidApiKey.isEmpty) {
    throw Exception('Unraid not configured');
  }
  final client = UnraidClient(
    url: settings.unraidUrl,
    apiKey: settings.unraidApiKey,
    certFingerprint: settings.pinForUrl(settings.unraidUrl),
  );
  ref.onDispose(() => client.close());
  return client;
});

/// Storage array status.
final unraidArrayProvider = FutureProvider<UnraidArray>((ref) async {
  return ref.watch(unraidClientProvider).getArray();
});

/// Docker containers.
final unraidDockerProvider = FutureProvider<List<UnraidDockerContainer>>((
  ref,
) async {
  return ref.watch(unraidClientProvider).getDockerContainers();
});

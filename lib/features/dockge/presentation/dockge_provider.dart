import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/dockge/data/dockge_client.dart';
import 'package:seekarr/features/dockge/data/dockge_service.dart';
import 'package:seekarr/features/dockge/domain/models/dockge_stack.dart';
import 'package:seekarr/features/dockge/domain/models/dockge_stack_detail.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';

/// Long-lived Socket.IO client for Dockge, rebuilt when its URL/credentials
/// change. Closed automatically when disposed.
final dockgeClientProvider = Provider<DockgeClient>((ref) {
  final url = ref.watch(currentSettingsProvider.select((s) => s.dockgeUrl));
  final username = ref.watch(
    currentSettingsProvider.select((s) => s.dockgeUsername),
  );
  final password = ref.watch(
    currentSettingsProvider.select((s) => s.dockgePassword),
  );
  final certFingerprint = ref.watch(
    currentSettingsProvider.select((s) => s.dockgeCertFingerprint),
  );
  if (url.isEmpty) {
    throw const DockgeException('Dockge not configured');
  }
  final client = DockgeClient(
    baseUrl: url,
    username: username.isEmpty ? null : username,
    password: password.isEmpty ? null : password,
    certFingerprint: certFingerprint.isEmpty ? null : certFingerprint,
  );
  ref.onDispose(client.close);
  return client;
});

final dockgeServiceProvider = Provider<DockgeService>((ref) {
  return DockgeService(ref.watch(dockgeClientProvider));
});

/// Live stack list — connects, requests a refresh, then streams every push
/// Dockge sends (`stackList` / `stackStatusList`).
final dockgeStackListProvider = StreamProvider.autoDispose<List<DockgeStack>>((
  ref,
) async* {
  final client = ref.watch(dockgeClientProvider);
  await client.ensureConnected();
  if (client.latestStacks.isNotEmpty) {
    yield client.latestStacks;
  }
  unawaited(client.requestStackList());
  yield* client.stackListStream;
});

/// Full detail (compose YAML/ENV) for a single stack.
final dockgeStackDetailProvider = FutureProvider.autoDispose
    .family<DockgeStackDetail, String>((ref, name) async {
      return ref.watch(dockgeServiceProvider).getStack(name);
    });

/// Per-service container status for a single stack.
final dockgeServiceStatusProvider = FutureProvider.autoDispose
    .family<List<DockgeServiceStatus>, String>((ref, name) async {
      return ref.watch(dockgeServiceProvider).getServiceStatusList(name);
    });

/// Available Docker networks (used by the compose editor).
final dockgeNetworkListProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  return ref.watch(dockgeClientProvider).getDockerNetworkList();
});

/// Connected server version, or null if unavailable.
final dockgeVersionProvider = FutureProvider.autoDispose<String?>((ref) async {
  return ref.watch(dockgeServiceProvider).fetchVersion();
});

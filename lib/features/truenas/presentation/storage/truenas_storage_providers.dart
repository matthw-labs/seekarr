import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/truenas/domain/models/pool.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

/// All pools (lightweight, no topology).
final truenasPoolsProvider = FutureProvider.autoDispose<List<TrueNasPool>>((
  ref,
) async {
  ref.watch(truenasClientProvider);
  return ref.watch(truenasStorageApiProvider).getPools();
});

/// A single pool including topology, by name.
final truenasPoolProvider = FutureProvider.autoDispose
    .family<TrueNasPool?, String>((ref, name) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasStorageApiProvider).getPool(name);
    });

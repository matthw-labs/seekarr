import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/truenas/domain/models/virt_instance.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';

final truenasVirtGlobalProvider =
    FutureProvider.autoDispose<TrueNasVirtGlobalConfig>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasVirtApiProvider).getGlobalConfig();
    });

/// Instances filtered by type (`CONTAINER` or `VM`).
final truenasVirtInstancesProvider = FutureProvider.autoDispose
    .family<List<TrueNasVirtInstance>, String>((ref, type) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasVirtApiProvider).getInstances(type);
    });

final truenasVirtInstanceProvider = FutureProvider.autoDispose
    .family<TrueNasVirtInstance?, String>((ref, id) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasVirtApiProvider).getInstance(id);
    });

final truenasVirtDevicesProvider = FutureProvider.autoDispose
    .family<List<TrueNasVirtDevice>, String>((ref, id) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasVirtApiProvider).getDevices(id);
    });

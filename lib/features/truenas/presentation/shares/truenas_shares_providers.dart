import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/truenas/domain/models/service_item.dart';
import 'package:seekarr/features/truenas/domain/models/share.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';

final truenasSmbSharesProvider =
    FutureProvider.autoDispose<List<TrueNasSmbShare>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSharingApiProvider).getSmbShares();
    });

final truenasNfsSharesProvider =
    FutureProvider.autoDispose<List<TrueNasNfsShare>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSharingApiProvider).getNfsShares();
    });

final truenasIscsiTargetsProvider =
    FutureProvider.autoDispose<List<TrueNasIscsiTarget>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSharingApiProvider).getIscsiTargets();
    });

/// All system services (used for share service-state banners and the System
/// › Services screen).
final truenasServicesProvider =
    FutureProvider.autoDispose<List<TrueNasServiceItem>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getServices();
    });

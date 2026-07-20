import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/truenas/domain/models/dataset.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';

final truenasDatasetTreeProvider =
    FutureProvider.autoDispose<List<TrueNasDataset>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasDatasetApiProvider).getDatasetTree();
    });

final truenasDatasetProvider = FutureProvider.autoDispose
    .family<TrueNasDataset?, String>((ref, id) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasDatasetApiProvider).getDataset(id);
    });

final truenasSnapshotsProvider = FutureProvider.autoDispose
    .family<List<TrueNasSnapshot>, String>((ref, dataset) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasDatasetApiProvider).getSnapshots(dataset);
    });

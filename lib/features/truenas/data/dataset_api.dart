import 'package:cupola/features/truenas/data/truenas_api_base.dart';
import 'package:cupola/features/truenas/domain/models/dataset.dart';

/// Dataset / zvol / snapshot operations (`pool.dataset.*`, `zfs.snapshot.*`).
class TrueNasDatasetApi extends TrueNasApiBase {
  const TrueNasDatasetApi(super.client);

  /// Top-level datasets with nested `children` (a tree per pool).
  Future<List<TrueNasDataset>> getDatasetTree() async {
    final result = await client.call('pool.dataset.query', [
      const <dynamic>[],
      {
        'extra': {'flat': false},
      },
    ]);
    return TrueNasDatasetApiParser.parse(result);
  }

  Future<TrueNasDataset?> getDataset(String id) async {
    final result = await client.call('pool.dataset.query', [
      [
        ['id', '=', id],
      ],
    ]);
    if (result is! List || result.isEmpty) return null;
    final map = result.first;
    if (map is! Map) return null;
    return TrueNasDataset.fromJson(Map<String, dynamic>.from(map));
  }

  Future<void> createDataset(Map<String, dynamic> payload) =>
      client.call('pool.dataset.create', [payload]);

  Future<void> updateDataset(String id, Map<String, dynamic> patch) =>
      client.call('pool.dataset.update', [id, patch]);

  /// Deletes a dataset. [recursive] also removes child datasets/snapshots.
  Future<dynamic> deleteDataset(String id, {bool recursive = false}) =>
      client.call('pool.dataset.delete', [
        id,
        {'recursive': recursive},
      ]);

  Future<List<TrueNasSnapshot>> getSnapshots(String dataset) =>
      queryList('zfs.snapshot.query', TrueNasSnapshot.fromJson, [
        [
          ['dataset', '=', dataset],
        ],
      ]);

  Future<void> createSnapshot(
    String dataset,
    String name, {
    bool recursive = false,
  }) => client.call('zfs.snapshot.create', [
    {'dataset': dataset, 'name': name, 'recursive': recursive},
  ]);

  Future<void> deleteSnapshot(String id) =>
      client.call('zfs.snapshot.delete', [id]);
}

/// Parses a `pool.dataset.query` result into a list of trees.
class TrueNasDatasetApiParser {
  static List<TrueNasDataset> parse(dynamic result) {
    if (result is! List) return const [];
    return result
        .whereType<Map>()
        .map((m) => TrueNasDataset.fromJson(Map<String, dynamic>.from(m)))
        .toList(growable: false);
  }
}

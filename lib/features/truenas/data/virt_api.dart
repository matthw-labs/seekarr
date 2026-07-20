import 'package:seekarr/features/truenas/data/truenas_api_base.dart';
import 'package:seekarr/features/truenas/domain/models/virt_instance.dart';

/// Incus virtualization: LXC containers and VMs (`virt.instance.*`,
/// `virt.device.*`, `virt.global.*`). Available on TrueNAS SCALE 25.04+.
class TrueNasVirtApi extends TrueNasApiBase {
  const TrueNasVirtApi(super.client);

  Future<TrueNasVirtGlobalConfig> getGlobalConfig() =>
      fetchObject('virt.global.config', TrueNasVirtGlobalConfig.fromJson);

  /// Instances of a given [type] (`CONTAINER` or `VM`).
  Future<List<TrueNasVirtInstance>> getInstances(String type) async {
    // TODO: push the type filter server-side via a query-filter
    // (`[["type","=",type]]`) once we can confirm the exact stored casing of
    // the `type` field across API versions. Kept client-side for now — a
    // case-mismatched server filter would silently return zero instances,
    // whereas the local `toUpperCase()` compare is tolerant.
    final all = await queryList(
      'virt.instance.query',
      TrueNasVirtInstance.fromJson,
    );
    return all
        .where((i) => i.type.toUpperCase() == type.toUpperCase())
        .toList(growable: false);
  }

  Future<TrueNasVirtInstance?> getInstance(String id) async {
    final result = await client.call('virt.instance.query', [
      [
        ['id', '=', id],
      ],
    ]);
    if (result is! List || result.isEmpty) return null;
    final map = result.first;
    if (map is! Map) return null;
    return TrueNasVirtInstance.fromJson(Map<String, dynamic>.from(map));
  }

  Future<List<TrueNasVirtDevice>> getDevices(String id) =>
      queryList('virt.instance.device_list', TrueNasVirtDevice.fromJson, [id]);

  Future<dynamic> start(String id) =>
      client.callJob('virt.instance.start', [id]);

  Future<dynamic> stop(String id, {bool force = false}) =>
      client.callJob('virt.instance.stop', [
        id,
        {'force': force, 'timeout': -1},
      ]);

  Future<dynamic> restart(String id, {bool force = false}) =>
      client.callJob('virt.instance.restart', [
        id,
        {'force': force, 'timeout': -1},
      ]);

  Future<dynamic> create(Map<String, dynamic> payload) =>
      client.callJob('virt.instance.create', [payload]);

  Future<dynamic> delete(String id) =>
      client.callJob('virt.instance.delete', [id]);
}

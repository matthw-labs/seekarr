import 'package:seekarr/features/truenas/data/truenas_api_base.dart';
import 'package:seekarr/features/truenas/domain/models/virt_instance.dart';

/// Incus virtualization: LXC containers and VMs (`virt.instance.*`,
/// `virt.device.*`, `virt.global.*`). Available on TrueNAS SCALE 25.04+.
class TrueNasVirtApi extends TrueNasApiBase {
  const TrueNasVirtApi(super.client);

  Future<TrueNasVirtGlobalConfig> getGlobalConfig() =>
      fetchObject('virt.global.config', TrueNasVirtGlobalConfig.fromJson);

  /// Instances of a given [type] (`CONTAINER` or `VM`).
  ///
  /// Containers come from Incus (`virt.instance.query`). VMs are gathered from
  /// BOTH the legacy KVM subsystem (`vm.query`) and Incus VMs, since a server
  /// can have either kind — legacy VMs never appear in `virt.instance.query`.
  Future<List<TrueNasVirtInstance>> getInstances(String type) async {
    if (type.toUpperCase() == 'VM') {
      final results = <TrueNasVirtInstance>[];
      try {
        results.addAll(
          await queryList('vm.query', TrueNasVirtInstance.fromLegacyVm),
        );
      } catch (_) {
        // Legacy VM subsystem may be absent on some builds; ignore.
      }
      try {
        final incus = await queryList(
          'virt.instance.query',
          TrueNasVirtInstance.fromJson,
        );
        results.addAll(incus.where((i) => i.isVm));
      } catch (_) {
        // Incus virtualization may not be configured; ignore.
      }
      return results;
    }

    final all = await queryList(
      'virt.instance.query',
      TrueNasVirtInstance.fromJson,
    );
    return all
        .where((i) => i.type.toUpperCase() == type.toUpperCase())
        .toList(growable: false);
  }

  Future<TrueNasVirtInstance?> getInstance(String id) async {
    // Incus instance first.
    final result = await client.call('virt.instance.query', [
      [
        ['id', '=', id],
      ],
    ]);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return TrueNasVirtInstance.fromJson(
        Map<String, dynamic>.from(result.first as Map),
      );
    }
    // Fall back to a legacy KVM VM matched by name (== id) or numeric id.
    try {
      final vms = await queryList('vm.query', TrueNasVirtInstance.fromLegacyVm);
      for (final vm in vms) {
        if (vm.id == id || vm.legacyVmId?.toString() == id) return vm;
      }
    } catch (_) {
      // Ignore when the legacy subsystem is unavailable.
    }
    return null;
  }

  // ── Legacy KVM VM lifecycle (`vm.*`) ──────────────────────────────────────

  Future<dynamic> vmStart(int id) => client.call('vm.start', [id]);

  Future<dynamic> vmStop(int id, {bool force = false}) =>
      client.callJob('vm.stop', [
        id,
        {'force': force},
      ]);

  Future<dynamic> vmRestart(int id) => client.callJob('vm.restart', [id]);

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

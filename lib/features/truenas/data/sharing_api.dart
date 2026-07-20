import 'package:seekarr/features/truenas/data/truenas_api_base.dart';
import 'package:seekarr/features/truenas/domain/models/share.dart';

/// SMB / NFS / iSCSI share operations (`sharing.*`, `iscsi.target.*`).
class TrueNasSharingApi extends TrueNasApiBase {
  const TrueNasSharingApi(super.client);

  // ── SMB ────────────────────────────────────────────────────────────────
  Future<List<TrueNasSmbShare>> getSmbShares() =>
      queryList('sharing.smb.query', TrueNasSmbShare.fromJson);

  Future<void> createSmbShare(Map<String, dynamic> payload) =>
      client.call('sharing.smb.create', [payload]);

  Future<void> updateSmbShare(int id, Map<String, dynamic> patch) =>
      client.call('sharing.smb.update', [id, patch]);

  Future<void> setSmbEnabled(int id, bool enabled) =>
      updateSmbShare(id, {'enabled': enabled});

  Future<void> deleteSmbShare(int id) =>
      client.call('sharing.smb.delete', [id]);

  // ── NFS ────────────────────────────────────────────────────────────────
  Future<List<TrueNasNfsShare>> getNfsShares() =>
      queryList('sharing.nfs.query', TrueNasNfsShare.fromJson);

  Future<void> createNfsShare(Map<String, dynamic> payload) =>
      client.call('sharing.nfs.create', [payload]);

  Future<void> updateNfsShare(int id, Map<String, dynamic> patch) =>
      client.call('sharing.nfs.update', [id, patch]);

  Future<void> setNfsEnabled(int id, bool enabled) =>
      updateNfsShare(id, {'enabled': enabled});

  Future<void> deleteNfsShare(int id) =>
      client.call('sharing.nfs.delete', [id]);

  // ── iSCSI ──────────────────────────────────────────────────────────────
  Future<List<TrueNasIscsiTarget>> getIscsiTargets() =>
      queryList('iscsi.target.query', TrueNasIscsiTarget.fromJson);

  Future<void> deleteIscsiTarget(int id) =>
      client.call('iscsi.target.delete', [id]);
}

import 'package:cupola/features/truenas/data/truenas_api_base.dart';
import 'package:cupola/features/truenas/domain/models/credentials.dart';

/// User and group management (`user.*`, `group.*`).
class TrueNasCredentialsApi extends TrueNasApiBase {
  const TrueNasCredentialsApi(super.client);

  Future<List<TrueNasUser>> getUsers() =>
      queryList('user.query', TrueNasUser.fromJson);

  Future<void> createUser(Map<String, dynamic> payload) =>
      client.call('user.create', [payload]);

  Future<void> updateUser(int id, Map<String, dynamic> patch) =>
      client.call('user.update', [id, patch]);

  Future<void> deleteUser(int id, {bool deletePrimaryGroup = false}) =>
      client.call('user.delete', [
        id,
        {'delete_group': deletePrimaryGroup},
      ]);

  Future<List<TrueNasGroup>> getGroups() =>
      queryList('group.query', TrueNasGroup.fromJson);

  Future<void> createGroup(Map<String, dynamic> payload) =>
      client.call('group.create', [payload]);

  Future<void> updateGroup(int id, Map<String, dynamic> patch) =>
      client.call('group.update', [id, patch]);

  Future<void> deleteGroup(int id) => client.call('group.delete', [id]);
}

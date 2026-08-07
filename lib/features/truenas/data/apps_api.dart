import 'package:cupola/features/truenas/data/truenas_api_base.dart';
import 'package:cupola/features/truenas/domain/models/app.dart';

/// Installed application operations (`app.*`).
class TrueNasAppsApi extends TrueNasApiBase {
  const TrueNasAppsApi(super.client);

  Future<List<TrueNasApp>> getApps() =>
      queryList('app.query', TrueNasApp.fromJson);

  Future<TrueNasApp?> getApp(String name) async {
    final result = await client.call('app.query', [
      [
        ['name', '=', name],
      ],
    ]);
    if (result is! List || result.isEmpty) return null;
    final map = result.first;
    if (map is! Map) return null;
    return TrueNasApp.fromJson(Map<String, dynamic>.from(map));
  }

  Future<dynamic> start(String name) => client.callJob('app.start', [name]);

  Future<dynamic> stop(String name) => client.callJob('app.stop', [name]);

  Future<dynamic> upgrade(String name) => client.callJob('app.upgrade', [name]);

  Future<dynamic> delete(String name) => client.callJob('app.delete', [name]);
}

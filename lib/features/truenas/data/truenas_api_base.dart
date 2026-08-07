import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/domain/models/dashboard.dart';

/// Shared helpers for the domain-grouped TrueNAS API classes. Each API wraps
/// the single shared [TrueNasWsClient]; the connection is opened lazily and
/// reused across all of them.
abstract class TrueNasApiBase {
  final TrueNasWsClient client;
  const TrueNasApiBase(this.client);

  /// Queries a collection method and maps each row through [fromJson].
  Future<List<T>> queryList<T>(
    String method,
    T Function(Map<String, dynamic>) fromJson, [
    List<dynamic> params = const [],
  ]) async {
    final result = await client.call(method, params);
    return TrueNasDashboard.parseList(result, fromJson);
  }

  /// Fetches a single config object and maps it, or throws if the shape is
  /// unexpected.
  Future<T> fetchObject<T>(
    String method,
    T Function(Map<String, dynamic>) fromJson, [
    List<dynamic> params = const [],
  ]) async {
    final result = await client.call(method, params);
    final map = mapOrNull(result);
    if (map == null) {
      throw TrueNasException('Unexpected $method response');
    }
    return fromJson(map);
  }
}

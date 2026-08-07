import 'package:cupola/features/truenas/data/truenas_api_base.dart';
import 'package:cupola/features/truenas/domain/models/network.dart';

/// Network interface + global network configuration (`interface.*`,
/// `network.configuration.*`).
class TrueNasNetworkApi extends TrueNasApiBase {
  const TrueNasNetworkApi(super.client);

  Future<List<TrueNasInterface>> getInterfaces() =>
      queryList('interface.query', TrueNasInterface.fromJson);

  Future<TrueNasNetworkConfig> getConfig() => fetchObject(
    'network.configuration.config',
    TrueNasNetworkConfig.fromJson,
  );
}

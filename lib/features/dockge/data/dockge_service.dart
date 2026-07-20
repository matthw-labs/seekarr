import 'package:seekarr/features/dockge/data/dockge_client.dart';
import 'package:seekarr/features/dockge/domain/models/dockge_stack.dart';
import 'package:seekarr/features/dockge/domain/models/dockge_stack_detail.dart';

/// Thin facade over [DockgeClient] for one-shot, request/response style reads
/// (used by KPI and status aggregation). Live views should watch the client's
/// [DockgeClient.stackListStream] directly instead.
class DockgeService {
  final DockgeClient client;

  DockgeService(this.client);

  /// Connects (if needed) and returns the current stack list, requesting a
  /// fresh push when none has been received yet.
  Future<List<DockgeStack>> fetchStacks() async {
    await client.ensureConnected();
    if (client.latestStacks.isNotEmpty) {
      return client.latestStacks;
    }
    final next = client.stackListStream.first.timeout(
      const Duration(seconds: 10),
      onTimeout: () => const <DockgeStack>[],
    );
    await client.requestStackList();
    return next;
  }

  Future<DockgeStackDetail> getStack(String name) => client.getStack(name);

  Future<List<DockgeServiceStatus>> getServiceStatusList(String name) =>
      client.getServiceStatusList(name);

  /// Connects and returns the reported Dockge version (null if unavailable).
  Future<String?> fetchVersion() async {
    await client.ensureConnected();
    return client.version;
  }
}

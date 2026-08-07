import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/truenas/domain/models/truenas_models.dart';

void main() {
  test('TrueNasPool parses capacity and topology', () {
    final pool = TrueNasPool.fromJson({
      'id': 1,
      'name': 'tank',
      'status': 'ONLINE',
      'healthy': true,
      'size': 1000,
      'allocated': 250,
      'free': 750,
      'topology': {
        'data': [
          {
            'type': 'RAIDZ1',
            'status': 'ONLINE',
            'children': [
              {'disk': 'sda', 'status': 'ONLINE'},
              {'disk': 'sdb', 'status': 'ONLINE'},
            ],
          },
        ],
        'cache': [],
      },
    });

    expect(pool.name, 'tank');
    expect(pool.healthy, isTrue);
    expect(pool.usedFraction, closeTo(0.25, 1e-9));
    expect(pool.hasTopology, isTrue);
    expect(pool.topology['data']!.first.members, hasLength(2));
    expect(pool.topology['data']!.first.members.first.name, 'sda');
  });

  test('TrueNasPool derives capacity from the root dataset as used + free', () {
    // `root_dataset.available` is ZFS FREE space, not the pool size. Reading it
    // as the total made usedFraction compute used/free, which the clamp pinned
    // to a flat 100% for any pool at or past half full.
    final pool = TrueNasPool.fromJson({
      'name': 'tank',
      'status': 'ONLINE',
      'healthy': true,
      'root_dataset': {
        'used': {'parsed': 600},
        'available': {'parsed': 400},
      },
    });

    expect(pool.sizeBytes, 1000);
    expect(pool.allocatedBytes, 600);
    expect(pool.freeBytes, 400);
    expect(pool.usedFraction, closeTo(0.6, 1e-9));
  });

  test('TrueNasPool prefers top-level capacity over the root dataset', () {
    final pool = TrueNasPool.fromJson({
      'name': 'tank',
      'status': 'ONLINE',
      'healthy': true,
      'size': 2000,
      'allocated': 500,
      'free': 1500,
      'root_dataset': {
        'used': {'parsed': 1},
        'available': {'parsed': 2},
      },
    });

    expect(pool.sizeBytes, 2000);
    expect(pool.allocatedBytes, 500);
    expect(pool.freeBytes, 1500);
    expect(pool.usedFraction, closeTo(0.25, 1e-9));
  });

  test('TrueNasDataset reads parsed property values and short name', () {
    final dataset = TrueNasDataset.fromJson({
      'id': 'tank/media',
      'name': 'tank/media',
      'pool': 'tank',
      'type': 'FILESYSTEM',
      'used': {'parsed': 2048},
      'available': {'parsed': 4096},
      'compression': {'value': 'LZ4'},
      'children': [
        {
          'id': 'tank/media/movies',
          'name': 'tank/media/movies',
          'pool': 'tank',
        },
      ],
    });

    expect(dataset.shortName, 'media');
    expect(dataset.usedBytes, 2048);
    expect(dataset.compression, 'LZ4');
    expect(dataset.children, hasLength(1));
    expect(dataset.children.first.shortName, 'movies');
  });

  test('TrueNasVirtInstance distinguishes VM from container', () {
    final vm = TrueNasVirtInstance.fromJson({
      'id': 'web',
      'name': 'web',
      'type': 'VM',
      'status': 'RUNNING',
      'cpu': 2,
      'memory': 2147483648,
      'image': {'os': 'Ubuntu', 'release': '24.04'},
    });
    expect(vm.isVm, isTrue);
    expect(vm.isRunning, isTrue);
    expect(vm.image, 'Ubuntu 24.04');
  });

  test('TrueNasApp reads metadata and upgrade flag', () {
    final app = TrueNasApp.fromJson({
      'name': 'plex',
      'state': 'RUNNING',
      'human_version': '1.40.0',
      'upgrade_available': true,
      'metadata': {
        'title': 'Plex',
        'icon': 'https://x/icon.png',
        'train': 'stable',
      },
      'portals': {'Web UI': 'https://host:32400'},
    });
    expect(app.title, 'Plex');
    expect(app.isRunning, isTrue);
    expect(app.upgradeAvailable, isTrue);
    expect(app.portals['Web UI'], 'https://host:32400');
  });

  test('TrueNasSnapshot decodes the {\$date: ms} creation shape', () {
    final snapshot = TrueNasSnapshot.fromJson({
      'id': 'tank/media@auto-2026-08-06',
      'snapshot_name': 'auto-2026-08-06',
      'dataset': 'tank/media',
      'properties': {
        'used': {'parsed': 4096},
        'creation': {
          'parsed': {'\$date': 1770000000000},
          'rawvalue': '1770000000',
        },
      },
    });

    expect(snapshot.usedBytes, 4096);
    expect(snapshot.createdMs, 1770000000000);
  });

  test('TrueNasSnapshot reads a bare creation value as epoch seconds', () {
    final snapshot = TrueNasSnapshot.fromJson({
      'id': 'tank/media@manual',
      'dataset': 'tank/media',
      'properties': {
        'creation': {'parsed': 1770000000},
      },
    });

    expect(snapshot.createdMs, 1770000000 * 1000);
  });

  test('TrueNasProtectionTask normalizes per kind', () {
    final snap = TrueNasProtectionTask.fromJson(TrueNasTaskKind.snapshot, {
      'id': 3,
      'dataset': 'tank/media',
      'naming_schema': 'auto-%Y%m%d',
      'recursive': true,
      'enabled': true,
    });
    expect(snap.title, 'tank/media');
    expect(snap.enabled, isTrue);
    expect(snap.subtitle, contains('recursive'));
    expect(snap.poolName, isNull);
  });

  test('TrueNasProtectionTask keeps the pool name of a scrub task', () {
    // `pool.scrub.run` is keyed by pool name, so dropping it (the previous
    // behaviour) left "Run now" with nothing to send.
    final scrub = TrueNasProtectionTask.fromJson(TrueNasTaskKind.scrub, {
      'id': 1,
      'pool_name': 'tank',
      'threshold': 35,
      'enabled': true,
    });
    expect(scrub.title, 'tank');
    expect(scrub.poolName, 'tank');
  });

  test('TrueNasTaskKind maps cloud sync onto cloudsync.sync', () {
    // `cloudsync.run` does not exist on the middleware; every "Run now"
    // against it failed server-side.
    expect(TrueNasTaskKind.cloudSync.runMethod, 'cloudsync.sync');
    expect(TrueNasTaskKind.scrub.runMethod, 'pool.scrub.run');
    expect(TrueNasTaskKind.snapshot.runMethod, 'pool.snapshottask.run');
    expect(TrueNasTaskKind.replication.runMethod, 'replication.run');
    expect(TrueNasTaskKind.rsync.runMethod, 'rsynctask.run');
  });

  test('TrueNasServiceItem derives running from state', () {
    final svc = TrueNasServiceItem.fromJson({
      'id': 5,
      'service': 'cifs',
      'state': 'RUNNING',
      'enable': true,
    });
    expect(svc.running, isTrue);
    expect(svc.enabled, isTrue);
    expect(svc.name, 'cifs');
  });
}

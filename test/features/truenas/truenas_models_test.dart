import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/features/truenas/domain/models/truenas_models.dart';

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
        {'id': 'tank/media/movies', 'name': 'tank/media/movies', 'pool': 'tank'},
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
      'metadata': {'title': 'Plex', 'icon': 'https://x/icon.png', 'train': 'stable'},
      'portals': {'Web UI': 'https://host:32400'},
    });
    expect(app.title, 'Plex');
    expect(app.isRunning, isTrue);
    expect(app.upgradeAvailable, isTrue);
    expect(app.portals['Web UI'], 'https://host:32400');
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

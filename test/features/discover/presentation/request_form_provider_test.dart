import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/request_form_provider.dart';

import '../../../test_helpers/fake_services.dart' as shared;

void main() {
  group('form model fromJson', () {
    test('SeerrServer parses all fields and falls back to defaults', () {
      final full = SeerrServer.fromJson({
        'id': 1,
        'name': 'Main',
        'activeProfileId': 5,
        'activeDirectory': '/movies',
      });
      expect(full.id, 1);
      expect(full.name, 'Main');
      expect(full.activeProfileId, 5);
      expect(full.activeDirectory, '/movies');

      final empty = SeerrServer.fromJson({});
      expect(empty.id, 0);
      expect(empty.name, 'Server');
      expect(empty.activeProfileId, isNull);
      expect(empty.activeDirectory, isNull);
    });

    test('QualityProfileOption parses fields and falls back to defaults', () {
      final full = QualityProfileOption.fromJson({'id': 7, 'name': 'HD'});
      expect(full.id, 7);
      expect(full.name, 'HD');

      final empty = QualityProfileOption.fromJson({});
      expect(empty.id, 0);
      expect(empty.name, 'Profile');
    });

    test('RootFolderOption parses fields and falls back to defaults', () {
      expect(RootFolderOption.fromJson({'path': '/movies'}).path, '/movies');
      expect(RootFolderOption.fromJson({}).path, '');
    });
  });

  group('RequestFormState.canSubmit', () {
    const ready = RequestFormState(isLoading: false, selectedProfileId: 1);
    final cases = <(String, RequestFormState, bool)>[
      ('ready', ready, true),
      ('loading', ready.copyWith(isLoading: true), false),
      ('no profile', const RequestFormState(isLoading: false), false),
      ('submitting', ready.copyWith(isSubmitting: true), false),
      ('error set', ready.copyWith(error: 'boom'), false),
    ];
    for (final (label, state, expected) in cases) {
      test('is $expected when $label', () {
        expect(state.canSubmit, expected);
      });
    }
  });

  group('RequestFormState.copyWith', () {
    test('preserves unchanged fields', () {
      const state = RequestFormState(
        servers: [SeerrServer(id: 1, name: 'Main')],
        selectedProfileId: 2,
        isLoading: false,
        error: 'boom',
      );

      final updated = state.copyWith(isSubmitting: true);

      expect(updated.servers, same(state.servers));
      expect(updated.selectedProfileId, 2);
      expect(updated.isLoading, isFalse);
      expect(updated.isSubmitting, isTrue);
      expect(updated.error, 'boom');
    });

    test('can clear nullable selections and error', () {
      const state = RequestFormState(
        selectedServerId: 1,
        selectedProfileId: 2,
        selectedRootFolder: '/movies',
        error: 'boom',
      );

      final updated = state.copyWith(
        selectedServerId: null,
        selectedProfileId: null,
        selectedRootFolder: null,
        clearError: true,
      );

      expect(updated.selectedServerId, isNull);
      expect(updated.selectedProfileId, isNull);
      expect(updated.selectedRootFolder, isNull);
      expect(updated.error, isNull);
    });
  });

  group('requestFormProvider', () {
    ProviderContainer createContainer(_FakeSeerr service) {
      final container = ProviderContainer(
        overrides: [seerrServiceProvider.overrideWith((ref) => service)],
      );
      addTearDown(container.dispose);
      return container;
    }

    void keepAlive(ProviderContainer container, RequestFormArgs args) {
      final subscription = container.listen<RequestFormState>(
        requestFormProvider(args),
        (previous, next) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
    }

    test('loads movie servers and active defaults', () async {
      final service = _FakeSeerr(
        radarrServers: [
          {
            'id': 3,
            'name': 'Radarr',
            'activeProfileId': 9,
            'activeDirectory': '/movies',
          },
        ],
        radarrProfilesByServer: {
          3: {
            'profiles': [
              {'id': 9, 'name': 'HD-1080p'},
              {'id': 10, 'name': '4K'},
            ],
            'rootFolders': [
              {'path': '/movies'},
              {'path': '/archive'},
            ],
          },
        },
      );
      final container = createContainer(service);
      const args = (mediaId: 123, mediaType: 'movie');
      keepAlive(container, args);

      await _flushProviderTasks();
      final state = container.read(requestFormProvider(args));

      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.servers, hasLength(1));
      expect(state.selectedServerId, 3);
      expect(state.selectedProfileId, 9);
      expect(state.selectedRootFolder, '/movies');
      expect(service.radarrServersCallCount, 1);
      expect(service.radarrProfilesCallCount, [3]);
    });

    test('reports empty server configuration', () async {
      final container = createContainer(_FakeSeerr(radarrServers: const []));
      const args = (mediaId: 123, mediaType: 'movie');
      keepAlive(container, args);

      await _flushProviderTasks();
      final state = container.read(requestFormProvider(args));

      expect(state.isLoading, isFalse);
      expect(state.error, 'No Radarr servers configured in Seerr');
    });

    test('selectServer loads sonarr profiles for chosen server', () async {
      final service = _FakeSeerr(
        sonarrServers: [
          {'id': 1, 'name': 'A'},
          {'id': 2, 'name': 'B', 'activeDirectory': '/tv-b'},
        ],
        sonarrProfilesByServer: {
          1: {
            'profiles': [
              {'id': 10, 'name': 'HD'},
            ],
            'rootFolders': [
              {'path': '/tv-a'},
            ],
          },
          2: {
            'profiles': [
              {'id': 22, 'name': 'Ultra'},
            ],
            'rootFolders': [
              {'path': '/tv-b'},
            ],
          },
        },
      );
      final container = createContainer(service);
      const args = (mediaId: 456, mediaType: 'tv');
      keepAlive(container, args);

      await _flushProviderTasks();
      final notifier = container.read(requestFormProvider(args).notifier);

      notifier.selectServer(2);
      await _flushProviderTasks();
      final state = container.read(requestFormProvider(args));

      expect(state.selectedServerId, 2);
      expect(state.selectedProfileId, 22);
      expect(state.selectedRootFolder, '/tv-b');
      expect(service.sonarrProfilesCallCount, [1, 2]);
    });

    test('submitRequest calls service with selected values', () async {
      final service = _FakeSeerr(
        radarrServers: [
          {'id': 9, 'name': 'Main'},
        ],
        radarrProfilesByServer: {
          9: {
            'profiles': [
              {'id': 2, 'name': 'HD'},
              {'id': 3, 'name': '4K'},
            ],
            'rootFolders': [
              {'path': '/movies'},
              {'path': '/archive'},
            ],
          },
        },
      );
      final container = createContainer(service);
      const args = (mediaId: 321, mediaType: 'movie');
      keepAlive(container, args);

      await _flushProviderTasks();
      final notifier = container.read(requestFormProvider(args).notifier);
      notifier.selectProfile(3);
      notifier.selectRootFolder('/archive');

      final error = await notifier.submitRequest();
      final state = container.read(requestFormProvider(args));

      expect(error, isNull);
      expect(state.isSubmitting, isFalse);
      expect(service.lastCreateRequestCall, {
        'mediaType': 'movie',
        'mediaId': 321,
        'profileId': 3,
        'rootFolder': '/archive',
        'serverId': 9,
      });
    });

    test('submitRequest fails when no profile is selected', () async {
      final container = createContainer(_FakeSeerr());
      const args = (mediaId: 111, mediaType: 'movie');

      final error = await container
          .read(requestFormProvider(args).notifier)
          .submitRequest();

      expect(error, 'No profile selected');
    });
  });
}

Future<void> _flushProviderTasks() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeSeerr extends shared.FakeSeerrService {
  _FakeSeerr({
    this.radarrServers = const <Map<String, dynamic>>[],
    this.sonarrServers = const <Map<String, dynamic>>[],
    this.radarrProfilesByServer = const <int, Map<String, dynamic>>{},
    this.sonarrProfilesByServer = const <int, Map<String, dynamic>>{},
  });

  final List<Map<String, dynamic>> radarrServers;
  final List<Map<String, dynamic>> sonarrServers;
  final Map<int, Map<String, dynamic>> radarrProfilesByServer;
  final Map<int, Map<String, dynamic>> sonarrProfilesByServer;

  int radarrServersCallCount = 0;
  int sonarrServersCallCount = 0;
  final List<int> radarrProfilesCallCount = <int>[];
  final List<int> sonarrProfilesCallCount = <int>[];
  Map<String, Object?>? lastCreateRequestCall;

  @override
  Future<List<Map<String, dynamic>>> getRadarrServers() async {
    radarrServersCallCount += 1;
    return radarrServers;
  }

  @override
  Future<List<Map<String, dynamic>>> getSonarrServers() async {
    sonarrServersCallCount += 1;
    return sonarrServers;
  }

  @override
  Future<Map<String, dynamic>> getRadarrProfiles(int serverId) async {
    radarrProfilesCallCount.add(serverId);
    return radarrProfilesByServer[serverId] ??
        {'profiles': const [], 'rootFolders': const []};
  }

  @override
  Future<Map<String, dynamic>> getSonarrProfiles(int serverId) async {
    sonarrProfilesCallCount.add(serverId);
    return sonarrProfilesByServer[serverId] ??
        {'profiles': const [], 'rootFolders': const []};
  }

  @override
  Future<void> createRequest({
    required String mediaType,
    required int mediaId,
    int? profileId,
    String? rootFolder,
    int? serverId,
    bool is4k = false,
    List<int>? seasons,
  }) async {
    lastCreateRequestCall = {
      'mediaType': mediaType,
      'mediaId': mediaId,
      'profileId': profileId,
      'rootFolder': rootFolder,
      'serverId': serverId,
    };
  }
}

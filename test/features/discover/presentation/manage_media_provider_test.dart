import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/manage_media_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart' as shared;

void main() {
  group('ManageMediaState', () {
    test('default state has correct defaults', () {
      const state = ManageMediaState();

      expect(state.requests, isEmpty);
      expect(state.isLoading, isTrue);
      expect(state.isDeleting, isFalse);
      expect(state.error, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const state = ManageMediaState(
        requests: [],
        isLoading: false,
        isDeleting: true,
        error: 'boom',
      );

      final updated = state.copyWith(isLoading: true);

      expect(updated.requests, same(state.requests));
      expect(updated.isLoading, isTrue);
      expect(updated.isDeleting, isTrue);
      expect(updated.error, 'boom');
    });

    test('copyWith clearError removes error', () {
      const state = ManageMediaState(error: 'boom');

      final updated = state.copyWith(clearError: true);

      expect(updated.error, isNull);
    });
  });

  group('manageMediaProvider', () {
    ProviderContainer createContainer({
      required ManageMediaArgs args,
      _FakeSeerr? service,
      SettingsModel? settings,
    }) {
      final container = ProviderContainer(
        overrides: [
          if (settings != null)
            currentSettingsProvider.overrideWith((ref) => settings),
          if (service != null)
            seerrServiceProvider.overrideWith((ref) => service),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => container.invalidate(manageMediaProvider(args)));
      return container;
    }

    test('parses valid requests from mediaInfo', () {
      final args = _buildArgs(
        mediaInfo: {
          'id': 101,
          'externalServiceId': 202,
          'requests': [_validRequestJson(id: 7)],
        },
      );
      final state = createContainer(args: args).read(manageMediaProvider(args));

      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.requests, hasLength(1));
      expect(state.requests.single.id, 7);
      expect(state.requests.single.requestedBy?.displayName, 'Matt');
    });

    test('handles empty requests list', () {
      final args = _buildArgs(mediaInfo: {'requests': const []});
      final state = createContainer(args: args).read(manageMediaProvider(args));

      expect(state.requests, isEmpty);
      expect(state.error, isNull);
    });

    test('filters malformed request entries', () {
      final args = _buildArgs(
        mediaInfo: {
          'requests': [_validRequestJson(id: 3), 'bad entry', 42],
        },
      );
      final state = createContainer(args: args).read(manageMediaProvider(args));

      expect(state.requests, hasLength(1));
      expect(state.requests.single.id, 3);
    });

    test('handles missing requests key', () {
      final args = _buildArgs(mediaInfo: {'id': 10});
      final state = createContainer(args: args).read(manageMediaProvider(args));

      expect(state.requests, isEmpty);
      expect(state.error, isNull);
    });

    test('exposes media ids through notifier getters', () {
      final args = _buildArgs(
        mediaInfo: {'id': 10, 'externalServiceId': 20, 'requests': const []},
      );
      final notifier = createContainer(
        args: args,
      ).read(manageMediaProvider(args).notifier);

      expect(notifier.seerrMediaId, 10);
      expect(notifier.externalServiceId, 20);
      expect(notifier.hasExternalService, isTrue);
    });

    test('returns null ids when missing', () {
      final args = _buildArgs(mediaInfo: {'requests': const []});
      final notifier = createContainer(
        args: args,
      ).read(manageMediaProvider(args).notifier);

      expect(notifier.seerrMediaId, isNull);
      expect(notifier.externalServiceId, isNull);
      expect(notifier.hasExternalService, isFalse);
    });

    const radarrConfigured = SettingsModel(
      radarrUrl: 'https://radarr.example.com',
      radarrApiKey: 'key',
    );
    const sonarrConfigured = SettingsModel(
      sonarrUrl: 'https://sonarr.example.com',
      sonarrApiKey: 'key',
    );

    final serviceConfiguredCases = <(String, String, SettingsModel, bool)>[
      ('movie', 'radarr configured', radarrConfigured, true),
      ('movie', 'radarr missing', const SettingsModel(), false),
      ('tv', 'sonarr configured', sonarrConfigured, true),
      ('tv', 'sonarr missing', const SettingsModel(), false),
    ];

    for (final (mediaType, label, settings, expected)
        in serviceConfiguredCases) {
      test('isServiceConfigured=$expected for $mediaType with $label', () {
        final args = _buildArgs(
          mediaInfo: {'externalServiceId': 42, 'requests': const []},
          mediaType: mediaType,
          tvdbId: mediaType == 'tv' ? 555 : null,
        );
        final notifier = createContainer(
          args: args,
          settings: settings,
        ).read(manageMediaProvider(args).notifier);

        expect(notifier.isServiceConfigured, expected);
      });
    }

    test('showMediaSection is true only when both signals are true', () {
      final args = _buildArgs(
        mediaInfo: {'externalServiceId': 42, 'requests': const []},
      );
      final notifier = createContainer(
        args: args,
        settings: radarrConfigured,
      ).read(manageMediaProvider(args).notifier);

      expect(notifier.showMediaSection, isTrue);
    });

    test('showMediaSection false when externalServiceId is null', () {
      final args = _buildArgs(mediaInfo: {'requests': const []});
      final notifier = createContainer(
        args: args,
        settings: radarrConfigured,
      ).read(manageMediaProvider(args).notifier);

      expect(notifier.showMediaSection, isFalse);
    });

    test('showMediaSection false when service not configured', () {
      final args = _buildArgs(
        mediaInfo: {'externalServiceId': 42, 'requests': const []},
      );
      final notifier = createContainer(
        args: args,
        settings: const SettingsModel(),
      ).read(manageMediaProvider(args).notifier);

      expect(notifier.showMediaSection, isFalse);
    });

    test('deleteRequest removes request from state', () async {
      final service = _FakeSeerr();
      final args = _buildArgs(
        mediaInfo: {
          'id': 11,
          'requests': [_validRequestJson(id: 1), _validRequestJson(id: 2)],
        },
      );
      final container = createContainer(args: args, service: service);
      final notifier = container.read(manageMediaProvider(args).notifier);

      final error = await notifier.deleteRequest(1);
      final state = container.read(manageMediaProvider(args));

      expect(error, isNull);
      expect(service.deletedRequestIds, [1]);
      expect(state.requests.map((request) => request.id), [2]);
    });

    test('deleteRequest returns error when service throws', () async {
      final service = _FakeSeerr(throwOnDeleteRequest: true);
      final args = _buildArgs(
        mediaInfo: {
          'id': 11,
          'requests': [_validRequestJson(id: 1)],
        },
      );
      final container = createContainer(args: args, service: service);
      final notifier = container.read(manageMediaProvider(args).notifier);

      final error = await notifier.deleteRequest(1);

      expect(error, contains('Failed to delete request'));
      expect(container.read(manageMediaProvider(args)).requests, hasLength(1));
    });

    test('removeFromService returns no media id when missing', () async {
      final args = _buildArgs(mediaInfo: {'requests': const []});
      final notifier = createContainer(
        args: args,
      ).read(manageMediaProvider(args).notifier);

      expect(await notifier.removeFromService(), 'No media ID');
    });

    test('removeFromService calls deleteMediaFile and resets state', () async {
      final service = _FakeSeerr();
      final args = _buildArgs(mediaInfo: {'id': 44, 'requests': const []});
      final container = createContainer(args: args, service: service);
      final notifier = container.read(manageMediaProvider(args).notifier);

      final error = await notifier.removeFromService();

      expect(error, isNull);
      expect(service.deletedMediaFileIds, [44]);
      expect(container.read(manageMediaProvider(args)).isDeleting, isFalse);
    });

    test('removeFromService returns error when service throws', () async {
      final service = _FakeSeerr(throwOnDeleteMediaFile: true);
      final args = _buildArgs(mediaInfo: {'id': 44, 'requests': const []});
      final container = createContainer(args: args, service: service);
      final notifier = container.read(manageMediaProvider(args).notifier);

      final error = await notifier.removeFromService();

      expect(error, contains('Failed to remove'));
      expect(container.read(manageMediaProvider(args)).isDeleting, isFalse);
      expect(service.deletedMediaFileIds, isEmpty);
    });

    test('clearAllData calls deleteMedia and resets state', () async {
      final service = _FakeSeerr();
      final args = _buildArgs(mediaInfo: {'id': 55, 'requests': const []});
      final container = createContainer(args: args, service: service);
      final notifier = container.read(manageMediaProvider(args).notifier);

      final error = await notifier.clearAllData();

      expect(error, isNull);
      expect(service.deletedMediaIds, [55]);
      expect(container.read(manageMediaProvider(args)).isDeleting, isFalse);
    });

    test('clearAllData returns error when service throws', () async {
      final service = _FakeSeerr(throwOnDeleteMedia: true);
      final args = _buildArgs(mediaInfo: {'id': 55, 'requests': const []});
      final container = createContainer(args: args, service: service);
      final notifier = container.read(manageMediaProvider(args).notifier);

      final error = await notifier.clearAllData();

      expect(error, contains('Failed to clear data'));
      expect(container.read(manageMediaProvider(args)).isDeleting, isFalse);
      expect(service.deletedMediaIds, isEmpty);
    });
  });
}

ManageMediaArgs _buildArgs({
  required Map<String, dynamic> mediaInfo,
  String mediaType = 'movie',
  int? tvdbId,
}) {
  return (
    mediaInfo: mediaInfo,
    mediaType: mediaType,
    tmdbId: 123,
    tvdbId: tvdbId,
  );
}

Map<String, dynamic> _validRequestJson({required int id}) {
  return {
    'id': id,
    'status': 2,
    'createdAt': '2024-01-02T00:00:00.000Z',
    'type': 'movie',
    'is4k': false,
    'canRemove': true,
    'requestedBy': {'id': 1, 'displayName': 'Matt'},
    'media': {
      'id': 101,
      'tmdbId': 123,
      'status': 5,
      'mediaType': 'movie',
      'title': 'Movie',
    },
  };
}

class _FakeSeerr extends shared.FakeSeerrService {
  _FakeSeerr({
    this.throwOnDeleteRequest = false,
    this.throwOnDeleteMediaFile = false,
    this.throwOnDeleteMedia = false,
  });

  final bool throwOnDeleteRequest;
  final bool throwOnDeleteMediaFile;
  final bool throwOnDeleteMedia;

  final List<int> deletedRequestIds = <int>[];
  final List<int> deletedMediaFileIds = <int>[];
  final List<int> deletedMediaIds = <int>[];

  @override
  Future<void> deleteRequest(int requestId) async {
    if (throwOnDeleteRequest) throw Exception('delete request failed');
    deletedRequestIds.add(requestId);
  }

  @override
  Future<void> deleteMediaFile(int mediaId) async {
    if (throwOnDeleteMediaFile) throw Exception('delete media file failed');
    deletedMediaFileIds.add(mediaId);
  }

  @override
  Future<void> deleteMedia(int mediaId) async {
    if (throwOnDeleteMedia) throw Exception('delete media failed');
    deletedMediaIds.add(mediaId);
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

typedef ManageMediaArgs = ({
  Map<String, dynamic> mediaInfo,
  String mediaType,
  int tmdbId,
  int? tvdbId,
});

class ManageMediaState {
  final List<SeerrRequest> requests;
  final bool isLoading;
  final bool isDeleting;
  final String? error;

  const ManageMediaState({
    this.requests = const [],
    this.isLoading = true,
    this.isDeleting = false,
    this.error,
  });

  ManageMediaState copyWith({
    List<SeerrRequest>? requests,
    bool? isLoading,
    bool? isDeleting,
    String? error,
    bool clearError = false,
  }) {
    return ManageMediaState(
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
      isDeleting: isDeleting ?? this.isDeleting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final manageMediaProvider = NotifierProvider.autoDispose
    .family<ManageMediaNotifier, ManageMediaState, ManageMediaArgs>(
      ManageMediaNotifier.new,
    );

class ManageMediaNotifier extends Notifier<ManageMediaState> {
  ManageMediaNotifier(this.arg);

  final ManageMediaArgs arg;

  @override
  ManageMediaState build() {
    try {
      final requestsData = arg.mediaInfo['requests'] as List<dynamic>? ?? [];
      final requests = requestsData
          .map((request) {
            try {
              return SeerrRequest.fromJson(request as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<SeerrRequest>()
          .toList();

      return ManageMediaState(requests: requests, isLoading: false);
    } catch (error) {
      return ManageMediaState(
        isLoading: false,
        error: 'Failed to load requests: $error',
      );
    }
  }

  int? get seerrMediaId => arg.mediaInfo['id'] as int?;

  int? get externalServiceId => arg.mediaInfo['externalServiceId'] as int?;

  bool get hasExternalService => externalServiceId != null;

  bool get isServiceConfigured {
    final settings = ref.read(currentSettingsProvider);

    if (arg.mediaType == 'movie') {
      return settings.radarrUrl.isNotEmpty && settings.radarrApiKey.isNotEmpty;
    }

    return settings.sonarrUrl.isNotEmpty && settings.sonarrApiKey.isNotEmpty;
  }

  bool get showMediaSection => hasExternalService && isServiceConfigured;

  Future<String?> deleteRequest(int requestId) async {
    try {
      final service = ref.read(seerrServiceProvider);
      await service.deleteRequest(requestId);
      state = state.copyWith(
        requests: state.requests
            .where((request) => request.id != requestId)
            .toList(),
      );
      return null;
    } catch (error) {
      return 'Failed to delete request: $error';
    }
  }

  Future<String?> removeFromService() async {
    final mediaId = seerrMediaId;
    if (mediaId == null) {
      return 'No media ID';
    }

    state = state.copyWith(isDeleting: true);
    try {
      final service = ref.read(seerrServiceProvider);
      await service.deleteMediaFile(mediaId);
      return null;
    } catch (error) {
      return 'Failed to remove: $error';
    } finally {
      state = state.copyWith(isDeleting: false);
    }
  }

  Future<String?> clearAllData() async {
    final mediaId = seerrMediaId;
    if (mediaId == null) {
      return 'No media ID';
    }

    state = state.copyWith(isDeleting: true);
    try {
      final service = ref.read(seerrServiceProvider);
      await service.deleteMedia(mediaId);
      return null;
    } catch (error) {
      return 'Failed to clear data: $error';
    } finally {
      state = state.copyWith(isDeleting: false);
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';

const Object _noSelectionUpdate = Object();

typedef RequestFormArgs = ({int mediaId, String mediaType});

class SeerrServer {
  final int id;
  final String name;
  final int? activeProfileId;
  final String? activeDirectory;

  const SeerrServer({
    required this.id,
    required this.name,
    this.activeProfileId,
    this.activeDirectory,
  });

  factory SeerrServer.fromJson(Map<String, dynamic> json) {
    return SeerrServer(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'Server',
      activeProfileId: json['activeProfileId'] as int?,
      activeDirectory: json['activeDirectory'] as String?,
    );
  }
}

class QualityProfileOption {
  final int id;
  final String name;

  const QualityProfileOption({required this.id, required this.name});

  factory QualityProfileOption.fromJson(Map<String, dynamic> json) {
    return QualityProfileOption(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'Profile',
    );
  }
}

class RootFolderOption {
  final String path;

  const RootFolderOption({required this.path});

  factory RootFolderOption.fromJson(Map<String, dynamic> json) {
    return RootFolderOption(path: json['path'] as String? ?? '');
  }
}

class RequestFormState {
  final List<SeerrServer> servers;
  final List<QualityProfileOption> profiles;
  final List<RootFolderOption> rootFolders;
  final int? selectedServerId;
  final int? selectedProfileId;
  final String? selectedRootFolder;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  const RequestFormState({
    this.servers = const [],
    this.profiles = const [],
    this.rootFolders = const [],
    this.selectedServerId,
    this.selectedProfileId,
    this.selectedRootFolder,
    this.isLoading = true,
    this.isSubmitting = false,
    this.error,
  });

  bool get canSubmit =>
      selectedProfileId != null && !isSubmitting && !isLoading && error == null;

  RequestFormState copyWith({
    List<SeerrServer>? servers,
    List<QualityProfileOption>? profiles,
    List<RootFolderOption>? rootFolders,
    Object? selectedServerId = _noSelectionUpdate,
    Object? selectedProfileId = _noSelectionUpdate,
    Object? selectedRootFolder = _noSelectionUpdate,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) {
    return RequestFormState(
      servers: servers ?? this.servers,
      profiles: profiles ?? this.profiles,
      rootFolders: rootFolders ?? this.rootFolders,
      selectedServerId: identical(selectedServerId, _noSelectionUpdate)
          ? this.selectedServerId
          : selectedServerId as int?,
      selectedProfileId: identical(selectedProfileId, _noSelectionUpdate)
          ? this.selectedProfileId
          : selectedProfileId as int?,
      selectedRootFolder: identical(selectedRootFolder, _noSelectionUpdate)
          ? this.selectedRootFolder
          : selectedRootFolder as String?,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final requestFormProvider = NotifierProvider.autoDispose
    .family<RequestFormNotifier, RequestFormState, RequestFormArgs>(
      RequestFormNotifier.new,
    );

class RequestFormNotifier extends Notifier<RequestFormState> {
  RequestFormNotifier(this.arg);

  final RequestFormArgs arg;

  @override
  RequestFormState build() {
    Future.microtask(_loadServers);
    return const RequestFormState();
  }

  Future<void> _loadServers() async {
    try {
      final service = ref.read(seerrServiceProvider);
      final serverMaps = arg.mediaType == 'movie'
          ? await service.getRadarrServers()
          : await service.getSonarrServers();
      final servers = serverMaps.map(SeerrServer.fromJson).toList();

      if (servers.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error:
              'No ${arg.mediaType == 'movie' ? 'Radarr' : 'Sonarr'} servers configured in Seerr',
          clearError: false,
        );
        return;
      }

      state = state.copyWith(
        servers: servers,
        selectedServerId: servers.first.id,
        clearError: true,
      );
      await _loadProfiles(servers.first.id);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load servers: $error',
      );
    }
  }

  Future<void> _loadProfiles(int serverId) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(seerrServiceProvider);
      final data = arg.mediaType == 'movie'
          ? await service.getRadarrProfiles(serverId)
          : await service.getSonarrProfiles(serverId);

      final profileMaps = data['profiles'] as List<dynamic>? ?? const [];
      final rootFolderMaps = data['rootFolders'] as List<dynamic>? ?? const [];
      final profiles = profileMaps
          .whereType<Map<String, dynamic>>()
          .map(QualityProfileOption.fromJson)
          .toList();
      final rootFolders = rootFolderMaps
          .whereType<Map<String, dynamic>>()
          .map(RootFolderOption.fromJson)
          .toList();

      final selectedServer = state.servers.firstWhere(
        (server) => server.id == serverId,
        orElse: () => const SeerrServer(id: 0, name: 'Server'),
      );

      final activeProfileId = selectedServer.activeProfileId;
      final activeDirectory = selectedServer.activeDirectory;

      final selectedProfileId =
          activeProfileId != null &&
              profiles.any((profile) => profile.id == activeProfileId)
          ? activeProfileId
          : profiles.isNotEmpty
          ? profiles.first.id
          : null;

      final selectedRootFolder =
          activeDirectory != null &&
              rootFolders.any((folder) => folder.path == activeDirectory)
          ? activeDirectory
          : rootFolders.isNotEmpty
          ? rootFolders.first.path
          : null;

      state = state.copyWith(
        profiles: profiles,
        rootFolders: rootFolders,
        selectedProfileId: selectedProfileId,
        selectedRootFolder: selectedRootFolder,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load profiles: $error',
      );
    }
  }

  void selectServer(int serverId) {
    state = state.copyWith(selectedServerId: serverId, clearError: true);
    _loadProfiles(serverId);
  }

  void selectProfile(int profileId) {
    state = state.copyWith(selectedProfileId: profileId, clearError: true);
  }

  void selectRootFolder(String path) {
    state = state.copyWith(selectedRootFolder: path, clearError: true);
  }

  Future<String?> submitRequest() async {
    if (state.selectedProfileId == null) {
      return 'No profile selected';
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final service = ref.read(seerrServiceProvider);
      await service.createRequest(
        mediaType: arg.mediaType,
        mediaId: arg.mediaId,
        profileId: state.selectedProfileId,
        rootFolder: state.selectedRootFolder,
        serverId: state.selectedServerId,
      );
      return null;
    } catch (error) {
      return 'Request failed: $error';
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }
}

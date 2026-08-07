import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class ManualImportRootFolder {
  final int id;
  final String path;
  final String? name;
  final bool accessible;
  final int? freeSpace;

  const ManualImportRootFolder({
    required this.id,
    required this.path,
    this.name,
    this.accessible = true,
    this.freeSpace,
  });

  factory ManualImportRootFolder.fromJson(Map<String, dynamic> json) {
    return ManualImportRootFolder(
      id: intOrNull(json['id']) ?? 0,
      path: stringOrNull(json['path']) ?? '',
      name: stringOrNull(json['name']),
      accessible: json['accessible'] != false,
      freeSpace: intOrNull(json['freeSpace']),
    );
  }

  String get displayName => name ?? manualImportPathName(path);
}

class ManualImportFileSystemEntry {
  final String type;
  final String name;
  final String path;
  final String? lastModified;
  final String? extension;
  final int? size;

  const ManualImportFileSystemEntry({
    required this.type,
    required this.name,
    required this.path,
    this.lastModified,
    this.extension,
    this.size,
  });

  factory ManualImportFileSystemEntry.fromJson(Map<String, dynamic> json) {
    final path = stringOrNull(json['path']) ?? '';
    return ManualImportFileSystemEntry(
      type: stringOrNull(json['type']) ?? 'folder',
      name: stringOrNull(json['name']) ?? manualImportPathName(path),
      path: path,
      lastModified: stringOrNull(json['lastModified']),
      extension: stringOrNull(json['extension']),
      size: intOrNull(json['size']),
    );
  }
}

class ManualImportFileSystemResult {
  final String? parent;
  final List<ManualImportFileSystemEntry> directories;
  final List<ManualImportFileSystemEntry> files;

  const ManualImportFileSystemResult({
    this.parent,
    this.directories = const [],
    this.files = const [],
  });

  factory ManualImportFileSystemResult.fromJson(Map<String, dynamic> json) {
    return ManualImportFileSystemResult(
      parent: stringOrNull(json['parent']),
      directories: _mapList(
        json['directories'],
        ManualImportFileSystemEntry.fromJson,
      ),
      files: _mapList(json['files'], ManualImportFileSystemEntry.fromJson),
    );
  }
}

class ManualImportRejection {
  final String reason;
  final String type;

  const ManualImportRejection({required this.reason, required this.type});

  factory ManualImportRejection.fromJson(Map<String, dynamic> json) {
    return ManualImportRejection(
      reason:
          stringOrNull(json['reason']) ??
          stringOrNull(json['message']) ??
          'Cannot import this file.',
      type: stringOrNull(json['type'])?.toLowerCase() ?? 'permanent',
    );
  }

  bool get isPermanent => type == 'permanent';
}

class ManualImportItem {
  final int id;
  final String path;
  final String? relativePath;
  final String? folderName;
  final String name;
  final int size;
  final Map<String, dynamic>? movie;
  final int? movieFileId;
  final Map<String, dynamic>? series;
  final int? seasonNumber;
  final List<Map<String, dynamic>> episodes;
  final int? episodeFileId;
  final Map<String, dynamic>? artist;
  final Map<String, dynamic>? album;
  final int? albumReleaseId;
  final List<Map<String, dynamic>> tracks;
  final Map<String, dynamic>? quality;
  final List<dynamic> languages;
  final int qualityWeight;
  final String? releaseGroup;
  final String? downloadId;
  final List<dynamic> customFormats;
  final int customFormatScore;
  final int indexerFlags;
  final String? releaseType;
  final Map<String, dynamic>? audioTags;
  final bool additionalFile;
  final bool replaceExistingFiles;
  final bool disableReleaseSwitching;
  final List<ManualImportRejection> rejections;

  const ManualImportItem({
    required this.id,
    required this.path,
    this.relativePath,
    this.folderName,
    required this.name,
    required this.size,
    this.movie,
    this.movieFileId,
    this.series,
    this.seasonNumber,
    this.episodes = const [],
    this.episodeFileId,
    this.artist,
    this.album,
    this.albumReleaseId,
    this.tracks = const [],
    this.quality,
    this.languages = const [],
    this.qualityWeight = 0,
    this.releaseGroup,
    this.downloadId,
    this.customFormats = const [],
    this.customFormatScore = 0,
    this.indexerFlags = 0,
    this.releaseType,
    this.audioTags,
    this.additionalFile = false,
    this.replaceExistingFiles = false,
    this.disableReleaseSwitching = false,
    this.rejections = const [],
  });

  factory ManualImportItem.fromJson(Map<String, dynamic> json) {
    final path = stringOrNull(json['path']) ?? '';
    return ManualImportItem(
      id: intOrNull(json['id']) ?? path.hashCode,
      path: path,
      relativePath: stringOrNull(json['relativePath']),
      folderName: stringOrNull(json['folderName']),
      name: stringOrNull(json['name']) ?? manualImportPathName(path),
      size: intOrNull(json['size']) ?? 0,
      movie: mapOrNull(json['movie']),
      movieFileId: intOrNull(json['movieFileId']),
      series: mapOrNull(json['series']),
      seasonNumber: intOrNull(json['seasonNumber']),
      episodes: _mapList(json['episodes'], (item) => item),
      episodeFileId: intOrNull(json['episodeFileId']),
      artist: mapOrNull(json['artist']),
      album: mapOrNull(json['album']),
      albumReleaseId: intOrNull(json['albumReleaseId']),
      tracks: _mapList(json['tracks'], (item) => item),
      quality: mapOrNull(json['quality']),
      languages: _dynamicList(json['languages']),
      qualityWeight: intOrNull(json['qualityWeight']) ?? 0,
      releaseGroup: stringOrNull(json['releaseGroup']),
      downloadId: stringOrNull(json['downloadId']),
      customFormats: _dynamicList(json['customFormats']),
      customFormatScore: intOrNull(json['customFormatScore']) ?? 0,
      indexerFlags: intOrNull(json['indexerFlags']) ?? 0,
      releaseType: stringOrNull(json['releaseType']),
      audioTags: mapOrNull(json['audioTags']),
      additionalFile: json['additionalFile'] == true,
      replaceExistingFiles: json['replaceExistingFiles'] == true,
      disableReleaseSwitching: json['disableReleaseSwitching'] == true,
      rejections: _mapList(json['rejections'], ManualImportRejection.fromJson),
    );
  }

  String get extension {
    final value = path.contains('.') ? path.split('.').last : '';
    return value.isEmpty ? 'FILE' : value.toUpperCase();
  }

  /// The file's real name on disk, extension included.
  ///
  /// Always prefer this over [name] for anything the user reads as "the file".
  /// [name] is whatever the service chose to put in its `name` field, and the
  /// \*arrs put the basename **without** the extension there — so a UI line
  /// built on [name] silently means "basename minus extension" for a real
  /// service and "basename with extension" whenever the field is absent and the
  /// [path] fallback kicks in. One label cannot mean two things.
  String get fileName => path.isEmpty ? name : manualImportPathName(path);

  bool get isAlreadyImported {
    // Radarr/Sonarr use 0 for "no existing file" in manual import payloads.
    return (movieFileId ?? 0) > 0 || (episodeFileId ?? 0) > 0;
  }

  bool get hasPermanentRejection => rejections.any((item) => item.isPermanent);

  bool get hasBlockingIdentityRejection =>
      rejections.any((item) => item.isPermanent && _isIdentityRejection(item));

  bool get hasBlockingMetadataRejection =>
      rejections.any((item) => item.isPermanent && !_isIdentityRejection(item));

  bool get hasMatch => movie != null || series != null || artist != null;

  bool hasMatchFor(ServiceKey service) {
    return switch (service) {
      ServiceKey.radarr => movie != null,
      ServiceKey.sonarr => series != null && episodes.isNotEmpty,
      ServiceKey.lidarr => artist != null && album != null && tracks.isNotEmpty,
      _ => false,
    };
  }

  bool get isSelectable => !isAlreadyImported;

  bool get isReadyForImport =>
      isSelectable && hasBlockingRequirementsFor(ServiceKey.radarr) == false;

  bool isReadyForImportFor(ServiceKey service) {
    return isSelectable && !hasBlockingRequirementsFor(service);
  }

  /// Whether this file, already in the library, can be handed over again.
  ///
  /// The deliberate exception to [isSelectable]. Review lists imported files
  /// inline — the answer to "did I already take this one?" — and a file the
  /// service already holds is still a file the user may want it to take again:
  /// a better rip of an episode that is already on disk is exactly the scene
  /// manual import exists for. It still needs a complete identity, which is
  /// what [hasBlockingRequirementsFor] checks; an imported file whose payload
  /// carries no match cannot be sent anywhere.
  bool isReimportableFor(ServiceKey service) {
    return isAlreadyImported && !hasBlockingRequirementsFor(service);
  }

  /// Whether this file may enter the import selection at all — freshly matched
  /// or deliberately sent again.
  bool isSubmittableFor(ServiceKey service) {
    return isReadyForImportFor(service) || isReimportableFor(service);
  }

  bool isMatchedFor(ServiceKey service) {
    return hasMatchFor(service) && !hasBlockingIdentityRejection;
  }

  bool hasWarningFor(ServiceKey service) {
    return !isMatchedFor(service) || hasBlockingMetadataRejection;
  }

  bool hasBlockingRequirementsFor(ServiceKey service) {
    if (!hasMatchFor(service)) return true;

    return switch (service) {
      ServiceKey.radarr => (intOrNull(movie?['id']) ?? 0) <= 0,
      ServiceKey.sonarr =>
        (intOrNull(series?['id']) ?? 0) <= 0 ||
            episodes
                .map((item) => intOrNull(item['id']))
                .whereType<int>()
                .where((id) => id > 0)
                .isEmpty,
      ServiceKey.lidarr =>
        (intOrNull(artist?['id']) ?? 0) <= 0 ||
            (intOrNull(album?['id']) ?? 0) <= 0 ||
            tracks
                .map((item) => intOrNull(item['id']))
                .whereType<int>()
                .where((id) => id > 0)
                .isEmpty,
      _ => true,
    };
  }

  ManualImportItem resolvedWithAssignment(
    ServiceKey service,
    ManualImportFixAssignment assignment,
  ) {
    var movie = this.movie;
    var series = this.series;
    var resolvedSeasonNumber = seasonNumber;
    var episodes = this.episodes;
    var artist = this.artist;
    var album = this.album;
    var resolvedAlbumReleaseId = albumReleaseId;
    var tracks = this.tracks;

    switch (service) {
      case ServiceKey.radarr:
        movie = assignment.match.raw;
        break;
      case ServiceKey.sonarr:
        series = assignment.match.raw;
        resolvedSeasonNumber = assignment.episode?.seasonNumber ?? seasonNumber;
        episodes = assignment.episodes.isNotEmpty
            ? assignment.episodes
                  .map((item) => item.raw)
                  .toList(growable: false)
            : assignment.episode == null
            ? episodes
            : [assignment.episode!.raw];
        break;
      case ServiceKey.lidarr:
        artist = assignment.match.raw;
        album = assignment.album?.raw ?? album;
        resolvedAlbumReleaseId =
            intOrNull(assignment.album?.raw['albumReleaseId']) ??
            intOrNull(assignment.track?.raw['albumReleaseId']) ??
            albumReleaseId;
        tracks = assignment.tracks.isNotEmpty
            ? assignment.tracks.map((item) => item.raw).toList(growable: false)
            : assignment.track == null
            ? tracks
            : [assignment.track!.raw];
        break;
      case _:
        break;
    }

    final resolved = ManualImportItem(
      id: id,
      path: path,
      relativePath: relativePath,
      folderName: folderName,
      name: name,
      size: size,
      movie: movie,
      movieFileId: movieFileId,
      series: series,
      seasonNumber: resolvedSeasonNumber,
      episodes: episodes,
      episodeFileId: episodeFileId,
      artist: artist,
      album: album,
      albumReleaseId: resolvedAlbumReleaseId,
      tracks: tracks,
      quality: quality,
      languages: languages,
      qualityWeight: qualityWeight,
      releaseGroup: releaseGroup,
      downloadId: downloadId,
      customFormats: customFormats,
      customFormatScore: customFormatScore,
      indexerFlags: indexerFlags,
      releaseType: releaseType,
      audioTags: audioTags,
      additionalFile: additionalFile,
      replaceExistingFiles: replaceExistingFiles,
      disableReleaseSwitching: disableReleaseSwitching,
      rejections: rejections,
    );

    if (!resolved.hasMatchFor(service)) {
      return resolved;
    }

    return ManualImportItem(
      id: resolved.id,
      path: resolved.path,
      relativePath: resolved.relativePath,
      folderName: resolved.folderName,
      name: resolved.name,
      size: resolved.size,
      movie: resolved.movie,
      movieFileId: resolved.movieFileId,
      series: resolved.series,
      seasonNumber: resolved.seasonNumber,
      episodes: resolved.episodes,
      episodeFileId: resolved.episodeFileId,
      artist: resolved.artist,
      album: resolved.album,
      albumReleaseId: resolved.albumReleaseId,
      tracks: resolved.tracks,
      quality: resolved.quality,
      languages: resolved.languages,
      qualityWeight: resolved.qualityWeight,
      releaseGroup: resolved.releaseGroup,
      downloadId: resolved.downloadId,
      customFormats: resolved.customFormats,
      customFormatScore: resolved.customFormatScore,
      indexerFlags: resolved.indexerFlags,
      releaseType: resolved.releaseType,
      audioTags: resolved.audioTags,
      additionalFile: resolved.additionalFile,
      replaceExistingFiles: resolved.replaceExistingFiles,
      disableReleaseSwitching: resolved.disableReleaseSwitching,
      rejections: _removeIdentityRejections(resolved.rejections),
    );
  }

  String get firstRejectionReason => rejections.isEmpty
      ? 'No matching media was found for this file.'
      : rejections.first.reason;

  String get mediaTitle {
    return stringOrNull(movie?['title']) ??
        stringOrNull(series?['title']) ??
        stringOrNull(album?['title']) ??
        stringOrNull(artist?['artistName']) ??
        stringOrNull(artist?['title']) ??
        'Unmatched';
  }

  String get mediaSubtitle {
    final episodeSummary = _episodeSummary(episodes);
    final parts = [
      stringOrNull(movie?['year']),
      stringOrNull(series?['year']),
      seasonNumber == null ? null : 'Season $seasonNumber',
      episodeSummary,
      tracks.isEmpty ? null : '${tracks.length} tracks',
    ].whereType<String>();
    return parts.isEmpty ? 'Needs assignment' : parts.join(' · ');
  }

  String get qualityLabel {
    return _extractQualityName(quality) ?? 'Unknown';
  }

  int? get qualityId {
    final qualityMap = mapOrNull(quality?['quality']);
    final nestedQualityMap = mapOrNull(qualityMap?['quality']);
    return intOrNull(nestedQualityMap?['id']) ??
        intOrNull(qualityMap?['id']) ??
        intOrNull(quality?['id']);
  }

  String get languageLabel {
    if (languages.isEmpty) return 'Original';
    return languages
        .map((item) => (mapOrNull(item)?['name'] ?? item).toString())
        .where((item) => item.trim().isNotEmpty)
        .join(', ');
  }

  List<int> get languageIds {
    return languages
        .map((item) => intOrNull(mapOrNull(item)?['id'] ?? item))
        .whereType<int>()
        .toList(growable: false);
  }

  ManualImportItem withMetadataOverrides({
    Map<String, dynamic>? quality,
    List<dynamic>? languages,
  }) {
    return ManualImportItem(
      id: id,
      path: path,
      relativePath: relativePath,
      folderName: folderName,
      name: name,
      size: size,
      movie: movie,
      movieFileId: movieFileId,
      series: series,
      seasonNumber: seasonNumber,
      episodes: episodes,
      episodeFileId: episodeFileId,
      artist: artist,
      album: album,
      albumReleaseId: albumReleaseId,
      tracks: tracks,
      quality: quality ?? this.quality,
      languages: languages ?? this.languages,
      qualityWeight: qualityWeight,
      releaseGroup: releaseGroup,
      downloadId: downloadId,
      customFormats: customFormats,
      customFormatScore: customFormatScore,
      indexerFlags: indexerFlags,
      releaseType: releaseType,
      audioTags: audioTags,
      additionalFile: additionalFile,
      replaceExistingFiles: replaceExistingFiles,
      disableReleaseSwitching: disableReleaseSwitching,
      rejections: rejections,
    );
  }

  Map<String, dynamic> toCommandFileJson(ServiceKey service) {
    final base = <String, dynamic>{
      'path': path,
      'quality': quality,
      'releaseGroup': releaseGroup,
      'indexerFlags': indexerFlags,
      'downloadId': downloadId,
    };

    switch (service) {
      case ServiceKey.radarr:
        return _withoutNulls({
          ...base,
          'folderName': folderName,
          'movieId': intOrNull(movie?['id']),
          'languages': languages,
        });
      case ServiceKey.sonarr:
        return _withoutNulls({
          ...base,
          'folderName': folderName,
          'seriesId': intOrNull(series?['id']),
          'episodeIds': episodes
              .map((item) => intOrNull(item['id']))
              .whereType<int>()
              .toList(),
          'episodeFileId': episodeFileId,
          'languages': languages,
          'releaseType': releaseType,
        });
      case ServiceKey.lidarr:
        return _withoutNulls({
          ...base,
          'languages':
              null, // Lidarr ignores languages in the command file body.
          'artistId': intOrNull(artist?['id']),
          'albumId': intOrNull(album?['id']),
          'albumReleaseId': albumReleaseId,
          'trackIds': tracks
              .map((item) => intOrNull(item['id']))
              .whereType<int>()
              .toList(),
          'disableReleaseSwitching': disableReleaseSwitching,
        });
      case _:
        throw ArgumentError('${service.title} does not support manual import');
    }
  }
}

class ManualImportLookupResult {
  final int id;
  final String title;
  final String? subtitle;
  final Map<String, dynamic> raw;

  const ManualImportLookupResult({
    required this.id,
    required this.title,
    this.subtitle,
    required this.raw,
  });

  factory ManualImportLookupResult.fromJson(
    ServiceKey service,
    Map<String, dynamic> json,
  ) {
    final title = switch (service) {
      ServiceKey.radarr || ServiceKey.sonarr => stringOrNull(json['title']),
      ServiceKey.lidarr =>
        stringOrNull(json['artistName']) ?? stringOrNull(json['title']),
      _ => stringOrNull(json['title']),
    };
    final subtitle = switch (service) {
      ServiceKey.radarr || ServiceKey.sonarr => stringOrNull(json['year']),
      ServiceKey.lidarr =>
        stringOrNull(json['disambiguation']) ??
            stringOrNull(json['artistType']),
      _ => null,
    };

    return ManualImportLookupResult(
      id: intOrNull(json['id']) ?? 0,
      title: title ?? 'Unknown',
      subtitle: subtitle,
      raw: json,
    );
  }
}

class ManualImportEpisode {
  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String title;
  final Map<String, dynamic> raw;

  const ManualImportEpisode({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.title,
    required this.raw,
  });

  factory ManualImportEpisode.fromJson(Map<String, dynamic> json) {
    return ManualImportEpisode(
      id: intOrNull(json['id']) ?? 0,
      episodeNumber: intOrNull(json['episodeNumber']) ?? 0,
      seasonNumber: intOrNull(json['seasonNumber']) ?? 0,
      title: stringOrNull(json['title']) ?? 'Episode',
      raw: json,
    );
  }

  String get label =>
      'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
}

class ManualImportAlbum {
  final int id;
  final String title;
  final int? year;
  final Map<String, dynamic> raw;

  const ManualImportAlbum({
    required this.id,
    required this.title,
    this.year,
    required this.raw,
  });

  factory ManualImportAlbum.fromJson(Map<String, dynamic> json) {
    return ManualImportAlbum(
      id: intOrNull(json['id']) ?? 0,
      title: stringOrNull(json['title']) ?? 'Album',
      year:
          intOrNull(json['year']) ??
          intOrNull(mapOrNull(json['releaseDate'])?['year']),
      raw: json,
    );
  }
}

class ManualImportTrack {
  final int id;
  final String title;
  final int? trackNumber;
  final Map<String, dynamic> raw;

  const ManualImportTrack({
    required this.id,
    required this.title,
    this.trackNumber,
    required this.raw,
  });

  factory ManualImportTrack.fromJson(Map<String, dynamic> json) {
    return ManualImportTrack(
      id: intOrNull(json['id']) ?? 0,
      title: stringOrNull(json['title']) ?? 'Track',
      trackNumber:
          intOrNull(json['trackNumber']) ??
          intOrNull(json['absoluteTrackNumber']),
      raw: json,
    );
  }

  String get label => trackNumber == null ? title : '$trackNumber. $title';
}

class ManualImportFixAssignment {
  final ManualImportLookupResult match;
  final ManualImportEpisode? episode;
  final ManualImportAlbum? album;
  final ManualImportTrack? track;
  final List<ManualImportEpisode> episodes;
  final List<ManualImportTrack> tracks;

  const ManualImportFixAssignment({
    required this.match,
    this.episode,
    this.album,
    this.track,
    this.episodes = const [],
    this.tracks = const [],
  });
}

class ManualImportQualityOption {
  final int id;
  final String name;
  final Map<String, dynamic> raw;

  const ManualImportQualityOption({
    required this.id,
    required this.name,
    required this.raw,
  });

  factory ManualImportQualityOption.fromJson(Map<String, dynamic> json) {
    final quality = mapOrNull(json['quality']);
    return ManualImportQualityOption(
      id: intOrNull(quality?['id']) ?? intOrNull(json['id']) ?? 0,
      name:
          stringOrNull(quality?['name']) ??
          stringOrNull(json['title']) ??
          stringOrNull(json['name']) ??
          'Unknown',
      raw: json,
    );
  }

  Map<String, dynamic> toQualityModel({Map<String, dynamic>? currentQuality}) {
    final quality = mapOrNull(raw['quality']);
    final source = quality == null ? raw : {...raw, 'quality': quality};
    return _withoutNulls({
      'quality': {
        'id': intOrNull(mapOrNull(source['quality'])?['id']) ?? id,
        'name': stringOrNull(mapOrNull(source['quality'])?['name']) ?? name,
      },
      'revision':
          mapOrNull(currentQuality?['revision']) ??
          mapOrNull(source['revision']) ??
          const {'version': 1, 'real': 0, 'isRepack': false},
    });
  }
}

class ManualImportLanguageOption {
  final int id;
  final String name;
  final Map<String, dynamic> raw;

  const ManualImportLanguageOption({
    required this.id,
    required this.name,
    required this.raw,
  });

  factory ManualImportLanguageOption.fromJson(Map<String, dynamic> json) {
    return ManualImportLanguageOption(
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name']) ?? 'Unknown',
      raw: json,
    );
  }

  Map<String, dynamic> toLanguageResource() {
    return _withoutNulls({'id': id, 'name': name, ...raw});
  }
}

enum ManualImportMode {
  auto,
  move,
  copy;

  String get apiValue => name;

  String get label => switch (this) {
    ManualImportMode.auto => 'Auto',
    ManualImportMode.move => 'Move',
    ManualImportMode.copy => 'Copy',
  };

  String get subtitle => switch (this) {
    ManualImportMode.auto => 'Let the service choose the best mode',
    ManualImportMode.move => 'Move files into the library path',
    ManualImportMode.copy => 'Keep source files and copy them',
  };
}

class ManualImportCommandStatus {
  final int id;
  final String name;
  final String status;
  final String? message;
  final String? queued;
  final String? started;
  final String? ended;
  final String? duration;
  final String? exception;

  const ManualImportCommandStatus({
    required this.id,
    required this.name,
    required this.status,
    this.message,
    this.queued,
    this.started,
    this.ended,
    this.duration,
    this.exception,
  });

  factory ManualImportCommandStatus.fromJson(Map<String, dynamic> json) {
    return ManualImportCommandStatus(
      id: intOrNull(json['id']) ?? 0,
      name:
          stringOrNull(json['name']) ??
          stringOrNull(json['commandName']) ??
          'ManualImport',
      status: stringOrNull(json['status'])?.toLowerCase() ?? 'queued',
      message: stringOrNull(json['message']),
      queued: stringOrNull(json['queued']),
      started: stringOrNull(json['started']),
      ended: stringOrNull(json['ended']),
      duration: stringOrNull(json['duration']),
      exception: stringOrNull(json['exception']),
    );
  }

  bool get isActive => status == 'queued' || status == 'started';

  bool get isCompleted => status == 'completed';

  bool get isFailure =>
      status == 'failed' ||
      status == 'aborted' ||
      status == 'cancelled' ||
      status == 'orphaned';
}

String manualImportPathName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return normalized.isEmpty ? 'Root' : normalized;
  return parts.last;
}

List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  final list = value is List ? value : const [];
  return list
      .map(mapOrNull)
      .whereType<Map<String, dynamic>>()
      .map(fromJson)
      .toList(growable: false);
}

List<dynamic> _dynamicList(dynamic value) {
  return value is List ? value : const [];
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> value) {
  return Map.fromEntries(
    value.entries.where((entry) {
      final entryValue = entry.value;
      return entryValue != null &&
          (entryValue is! List || entryValue.isNotEmpty);
    }),
  );
}

List<ManualImportRejection> _removeIdentityRejections(
  List<ManualImportRejection> rejections,
) {
  return rejections
      .where((rejection) {
        return !_isIdentityRejection(rejection);
      })
      .toList(growable: false);
}

bool _isIdentityRejection(ManualImportRejection rejection) {
  if (!rejection.isPermanent) return false;
  final reason = rejection.reason.toLowerCase();
  return reason.contains('no matching') ||
      reason.contains('could not find a match') ||
      reason.contains('series is unknown') ||
      reason.contains('movie is unknown') ||
      reason.contains('artist is unknown') ||
      reason.contains('album is unknown') ||
      reason.contains('episode is unknown') ||
      reason.contains('track is unknown') ||
      reason.contains('unable to determine series') ||
      reason.contains('unable to determine movie') ||
      reason.contains('unable to determine artist') ||
      reason.contains('unable to determine album') ||
      reason.contains('unable to determine episode') ||
      reason.contains('unable to determine track');
}

String? _extractQualityName(Map<String, dynamic>? quality) {
  final directQuality = mapOrNull(quality?['quality']);
  final nestedQuality = mapOrNull(directQuality?['quality']);
  return stringOrNull(nestedQuality?['name']) ??
      stringOrNull(directQuality?['name']) ??
      stringOrNull(quality?['title']) ??
      stringOrNull(quality?['name']);
}

String? _episodeSummary(List<Map<String, dynamic>> episodes) {
  if (episodes.isEmpty) return null;

  final labels = episodes
      .map((episode) {
        final season = intOrNull(episode['seasonNumber']);
        final number = intOrNull(episode['episodeNumber']);
        if (season == null || number == null) return null;
        return 'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}';
      })
      .whereType<String>()
      .toList(growable: false);

  if (labels.isEmpty) return null;
  if (labels.length == 1) return labels.first;
  if (labels.length == 2) return '${labels[0]}, ${labels[1]}';
  return '${labels.take(2).join(', ')} +${labels.length - 2}';
}

/// The two-axis media status vocabulary shared by every service.
///
/// The old single-axis `MediaStatus` enum could not express "nothing on disk
/// *and* a download in flight", so an item being grabbed rendered as `Missing`.
/// Availability (what is on disk) and pipeline (what is happening right now)
/// are therefore modelled separately, and [MediaStatusInfo] combines them.
library;

/// What the service currently holds on disk.
enum MediaAvailability {
  /// The service is not tracking this item at all — nothing requested, nothing
  /// added to the library. The badge doubles as an invitation to add it, which
  /// is why it carries the accent tone rather than a state tone.
  notTracked,

  /// Not released / not aired yet — nothing is wrong, nothing is expected.
  unavailable,

  /// Expected to exist, but nothing is on disk.
  missing,

  /// Some of the expected children are on disk, but not all.
  partial,

  /// Everything expected is on disk.
  available,

  /// On disk, but below the configured quality cutoff.
  upgradable,

  /// Removed from the service.
  deleted,

  /// Could not be determined from the payload.
  unknown,
}

/// What the download/import pipeline is doing right now, if anything.
///
/// Ordered loosely by lifecycle; [salience] — not the declaration order — is
/// what decides which entry wins when several map to the same media item.
enum MediaPipeline {
  queued,
  downloading,
  importPending,
  importing,
  paused,
  failed;

  /// How strongly this state should win when several queue entries collapse
  /// onto one media item (a series with three episodes in flight, say).
  ///
  /// `failed` outranks everything because it needs the user's attention;
  /// `downloading` outranks the waiting states because "something is
  /// happening" is the more useful headline.
  int get salience => switch (this) {
    MediaPipeline.failed => 5,
    MediaPipeline.downloading => 4,
    MediaPipeline.importing => 3,
    MediaPipeline.importPending => 2,
    MediaPipeline.queued => 1,
    MediaPipeline.paused => 0,
  };

  String get label => switch (this) {
    MediaPipeline.queued => 'Queued',
    MediaPipeline.downloading => 'Downloading',
    MediaPipeline.importPending => 'Import Pending',
    MediaPipeline.importing => 'Importing',
    MediaPipeline.paused => 'Paused',
    MediaPipeline.failed => 'Failed',
  };
}

/// Semantic tone of a status, resolved to a real colour by the presentation
/// layer so no widget hardcodes hex values.
enum StatusTone { primary, success, warning, info, error, neutral }

/// A fully resolved media status, ready to render.
///
/// Built by the per-service resolvers in each feature's `domain/` layer — never
/// assembled inside a widget, so grids, detail pages and Activity cannot drift
/// apart the way they did when each had its own derivation.
class MediaStatusInfo {
  final MediaAvailability availability;

  /// Non-null when the item is somewhere in the download/import pipeline.
  final MediaPipeline? pipeline;

  /// Download progress in `0..1`, when known.
  final double? progress;

  /// The item is deliberately not monitored.
  final bool unmonitored;

  /// The service reported a warning (`trackedDownloadStatus`, status messages).
  final bool hasWarning;

  /// Free-form supporting text: an error message, an ETA, a status message.
  final String? detail;

  /// Overrides the derived [label] when a service has better wording of its
  /// own (Seerr's "Available to Request", a download client's native state).
  final String? labelOverride;

  const MediaStatusInfo({
    this.availability = MediaAvailability.unknown,
    this.pipeline,
    this.progress,
    this.unmonitored = false,
    this.hasWarning = false,
    this.detail,
    this.labelOverride,
  });

  const MediaStatusInfo.unknown() : this();

  /// True when the pipeline is actively moving bytes or files.
  bool get isActive =>
      pipeline == MediaPipeline.downloading ||
      pipeline == MediaPipeline.importing;

  /// True when the item is in the pipeline at all — the guard that keeps a
  /// queued item from ever rendering as `Missing`.
  bool get isInPipeline => pipeline != null;

  bool get isAvailable =>
      availability == MediaAvailability.available ||
      availability == MediaAvailability.upgradable;

  /// The pipeline wins over availability: an item with nothing on disk that is
  /// being downloaded reads "Downloading", not "Missing".
  String get label {
    if (labelOverride != null) return labelOverride!;
    if (pipeline != null) return pipeline!.label;
    if (unmonitored && !isAvailable) return 'Unmonitored';

    return switch (availability) {
      MediaAvailability.notTracked => 'Not Requested',
      MediaAvailability.unavailable => 'Not Released',
      MediaAvailability.missing => 'Missing',
      MediaAvailability.partial => 'Partial',
      MediaAvailability.available => 'Available',
      MediaAvailability.upgradable => 'Upgrade Available',
      MediaAvailability.deleted => 'Deleted',
      MediaAvailability.unknown => 'Unknown',
    };
  }

  StatusTone get tone {
    final base = _baseTone;
    // A warning must never downgrade an error, but it should always surface on
    // an otherwise calm tone — this is what replaced the old "… (Warning)"
    // text suffix.
    if (hasWarning && base != StatusTone.error) return StatusTone.warning;
    return base;
  }

  StatusTone get _baseTone {
    if (pipeline != null) {
      return switch (pipeline!) {
        MediaPipeline.downloading || MediaPipeline.importing => StatusTone.info,
        MediaPipeline.queued ||
        MediaPipeline.importPending ||
        MediaPipeline.paused => StatusTone.warning,
        MediaPipeline.failed => StatusTone.error,
      };
    }

    if (unmonitored && !isAvailable) return StatusTone.neutral;

    return switch (availability) {
      MediaAvailability.notTracked => StatusTone.primary,
      MediaAvailability.available => StatusTone.success,
      MediaAvailability.upgradable => StatusTone.info,
      MediaAvailability.partial => StatusTone.info,
      MediaAvailability.missing => StatusTone.error,
      MediaAvailability.deleted => StatusTone.error,
      MediaAvailability.unavailable => StatusTone.neutral,
      MediaAvailability.unknown => StatusTone.neutral,
    };
  }

  MediaStatusInfo copyWith({
    MediaAvailability? availability,
    MediaPipeline? pipeline,
    double? progress,
    bool? unmonitored,
    bool? hasWarning,
    String? detail,
    String? labelOverride,
  }) {
    return MediaStatusInfo(
      availability: availability ?? this.availability,
      pipeline: pipeline ?? this.pipeline,
      progress: progress ?? this.progress,
      unmonitored: unmonitored ?? this.unmonitored,
      hasWarning: hasWarning ?? this.hasWarning,
      detail: detail ?? this.detail,
      labelOverride: labelOverride ?? this.labelOverride,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MediaStatusInfo &&
        other.availability == availability &&
        other.pipeline == pipeline &&
        other.progress == progress &&
        other.unmonitored == unmonitored &&
        other.hasWarning == hasWarning &&
        other.detail == detail &&
        other.labelOverride == labelOverride;
  }

  @override
  int get hashCode => Object.hash(
    availability,
    pipeline,
    progress,
    unmonitored,
    hasWarning,
    detail,
    labelOverride,
  );

  @override
  String toString() =>
      'MediaStatusInfo(${availability.name}'
      '${pipeline == null ? '' : ' + ${pipeline!.name}'}'
      '${progress == null ? '' : ' ${(progress! * 100).round()}%'}'
      '${unmonitored ? ' unmonitored' : ''}'
      '${hasWarning ? ' warning' : ''})';
}

/// Derives the availability axis from a parent/children file count.
///
/// Shared by Sonarr (episodes), Lidarr (tracks) and Readarr (books) so
/// "partial" means the same thing everywhere.
MediaAvailability availabilityFromCounts({
  required int? fileCount,
  required int? totalCount,
  MediaAvailability whenEmpty = MediaAvailability.missing,
}) {
  if (totalCount == null || totalCount <= 0) {
    if (fileCount == null) return MediaAvailability.unknown;
    return fileCount > 0 ? MediaAvailability.available : whenEmpty;
  }

  final files = fileCount ?? 0;
  if (files >= totalCount) return MediaAvailability.available;
  if (files > 0) return MediaAvailability.partial;
  return whenEmpty;
}

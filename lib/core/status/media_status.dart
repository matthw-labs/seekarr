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
///
/// Three of these states exist because the pipeline's *problems* used not to be
/// expressible. A stalled download arrived as `downloading` plus a warning flag,
/// so the row read "Downloading" — the opposite of the truth — for the single
/// most common reason a user opens Activity at all. An unreachable download
/// client was flattened onto [paused] with a label riding alongside it, so the
/// merge below could and did discard it. And `importBlocked`, which needs a
/// manual import to clear, was indistinguishable from `importPending`, which
/// clears itself in seconds.
enum MediaPipeline {
  queued,
  downloading,
  stalled,
  importPending,
  importBlocked,
  importing,
  paused,
  clientUnavailable,
  failed;

  /// How strongly this state should win when several queue entries collapse
  /// onto one media item (a series with three episodes in flight, say).
  ///
  /// The ranking is **gravity** — how badly this state wants the user — not
  /// lifecycle position. That distinction is the fix for a real bug: when
  /// `clientUnavailable` was expressed as [paused], it inherited the *lowest*
  /// salience in the enum, so a series with one episode blocked by a dead
  /// download client and one merely queued reported "Queued" and dropped the
  /// outage entirely. The most actionable fact on the screen lost to the least.
  ///
  /// Within the healthy states the original rule still holds: `downloading`
  /// outranks the benign waiting states because "something is happening" is the
  /// more useful headline. That is why `importPending` sits *below* it while
  /// `importBlocked` sits above — one is a wait, the other is a request for
  /// help.
  int get salience => switch (this) {
    MediaPipeline.failed => 8,
    MediaPipeline.clientUnavailable => 7,
    MediaPipeline.importBlocked => 6,
    MediaPipeline.stalled => 5,
    MediaPipeline.downloading => 4,
    MediaPipeline.importing => 3,
    MediaPipeline.importPending => 2,
    MediaPipeline.queued => 1,
    MediaPipeline.paused => 0,
  };

  String get label => switch (this) {
    MediaPipeline.queued => 'Queued',
    MediaPipeline.downloading => 'Downloading',
    MediaPipeline.stalled => 'Stalled',
    MediaPipeline.importPending => 'Import Pending',
    MediaPipeline.importBlocked => 'Import Blocked',
    MediaPipeline.importing => 'Importing',
    MediaPipeline.paused => 'Paused',
    MediaPipeline.clientUnavailable => 'Client Unavailable',
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

  /// Overrides the derived [tone] for states the two axes cannot express.
  ///
  /// The availability/pipeline pair describes a *thing* — what is on disk and
  /// what is moving. Some rows instead describe an *event* that already
  /// happened: a history record's `downloadFailed` or `movieFileDeleted` has no
  /// current availability and no live pipeline, yet it very much has a severity.
  /// Without this, mapping those onto whichever availability produced the right
  /// colour meant lying about the item's state to get the tone right — and
  /// picking the tone locally instead is exactly how a failed import came to
  /// render in the success green.
  ///
  /// A warning still escalates over an override; an explicit
  /// [StatusTone.error] is never downgraded.
  final StatusTone? toneOverride;

  const MediaStatusInfo({
    this.availability = MediaAvailability.unknown,
    this.pipeline,
    this.progress,
    this.unmonitored = false,
    this.hasWarning = false,
    this.detail,
    this.labelOverride,
    this.toneOverride,
  });

  const MediaStatusInfo.unknown() : this();

  /// True when the pipeline is actively moving bytes or files.
  bool get isActive =>
      pipeline == MediaPipeline.downloading ||
      pipeline == MediaPipeline.importing;

  /// True when this item's [progress] is worth drawing and reading out.
  ///
  /// Wider than [isActive] by exactly one state: a stalled transfer is not
  /// moving, but "Stalled at 43%" is materially more useful than "Stalled" —
  /// the frozen figure is how the user judges whether to wait or to blocklist
  /// and search again. Everything [isActive] excludes stays excluded: a queued
  /// item carries a progress value that is deliberately not drawn.
  bool get showsProgress => isActive || pipeline == MediaPipeline.stalled;

  /// True when the item is in the pipeline at all — the guard that keeps a
  /// queued item from ever rendering as `Missing`.
  bool get isInPipeline => pipeline != null;

  bool get isAvailable =>
      availability == MediaAvailability.available ||
      availability == MediaAvailability.upgradable;

  /// Download progress as whole percent, but only while it is actually being
  /// shown.
  ///
  /// Lives here rather than in the badge so the printed percentage and the
  /// spoken one cannot drift: a queued item carries a [progress] value that is
  /// deliberately not drawn, and it must not be read out either.
  int? get progressPercent {
    final value = progress;
    if (value == null || !showsProgress) return null;
    return (value * 100).round();
  }

  /// The status as one spoken phrase, for assistive technology.
  ///
  /// [label] alone drops the two things a badge shows without ever writing them
  /// down: the percentage drawn as a progress ring, and the warning carried by
  /// the tone colour — [hasWarning] is what replaced the old "… (Warning)" text
  /// suffix, so since then nothing spells it out. A sighted user reads both off
  /// the badge; a screen reader has to be told.
  String get semanticLabel {
    final percent = progressPercent;
    return [
      label,
      if (percent != null) '$percent percent',
      if (hasWarning) 'warning',
    ].join(', ');
  }

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
    final base = toneOverride ?? _baseTone;
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
        // Stuck, and waiting on the user rather than on the network. Not
        // `error`: nothing is lost yet, and reserving red for definite loss is
        // what keeps red meaning something (the same reasoning that keeps the
        // Wanted bucket off red — if everything is an emergency, nothing is).
        MediaPipeline.stalled ||
        MediaPipeline.importBlocked => StatusTone.warning,
        // The download client is unreachable, so nothing in the queue can
        // progress at all. That is infrastructure being down, not an item
        // waiting its turn.
        MediaPipeline.clientUnavailable ||
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
    StatusTone? toneOverride,
  }) {
    return MediaStatusInfo(
      availability: availability ?? this.availability,
      pipeline: pipeline ?? this.pipeline,
      progress: progress ?? this.progress,
      unmonitored: unmonitored ?? this.unmonitored,
      hasWarning: hasWarning ?? this.hasWarning,
      detail: detail ?? this.detail,
      labelOverride: labelOverride ?? this.labelOverride,
      toneOverride: toneOverride ?? this.toneOverride,
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
        other.labelOverride == labelOverride &&
        other.toneOverride == toneOverride;
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
    toneOverride,
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

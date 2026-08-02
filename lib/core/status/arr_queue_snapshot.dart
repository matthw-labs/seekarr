import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/core/utils/string_utils.dart';

export 'package:seekarr/core/status/media_status.dart';
// Part of this layer's surface: `ArrQueueEntry.severity` is typed on it, so a
// caller holding an entry can read it without also importing the raw-JSON utils.
export 'package:seekarr/core/utils/arr_activity_display.dart'
    show ArrQueueSeverity, arrQueueSeverity;

/// One media item's slice of an \*arr download queue.
///
/// The queue is fetched once per service and indexed by media id, so a detail
/// page, a poster grid and the Activity tab all read the same snapshot instead
/// of each deriving its own idea of what is happening.
class ArrQueueEntry {
  final MediaPipeline pipeline;
  final double? progress;

  /// How badly the \*arr says this record is doing.
  ///
  /// Replaces a `bool hasWarning`, which could not tell a service-reported
  /// `error` from a `warning` — see [ArrQueueSeverity].
  final ArrQueueSeverity severity;

  final String? detail;

  /// Set when the raw status carries more information than [pipeline] can — an
  /// unrecognised status keeps its own humanised wording instead of being
  /// flattened to "Queued".
  ///
  /// It no longer carries "Client Unavailable": that was a real state wearing a
  /// label, and a label is exactly what the merge in [_EntryAccumulator] is
  /// entitled to discard. It is [MediaPipeline.clientUnavailable] now.
  final String? label;

  const ArrQueueEntry({
    required this.pipeline,
    this.progress,
    this.severity = ArrQueueSeverity.ok,
    this.detail,
    this.label,
  });

  bool get hasWarning => severity != ArrQueueSeverity.ok;

  /// The tone this record's severity earns over the one its [pipeline] implies.
  ///
  /// Only an `error` overrides: a warning already escalates a calm tone inside
  /// [MediaStatusInfo.tone], but nothing there could promote a record the
  /// service explicitly flagged as failing.
  StatusTone? get toneOverride =>
      severity == ArrQueueSeverity.error ? StatusTone.error : null;

  /// Reads a single `/queue` record.
  ///
  /// `trackedDownloadState` decides the post-download phases (import, failure);
  /// for anything still with the download client the `status` field decides,
  /// because a queued item also carries `trackedDownloadState: downloading`.
  ///
  /// Returns null when the record represents work that is already finished
  /// (`imported`) or deliberately skipped (`ignored`) — those must not mask the
  /// real availability of the item.
  ///
  /// Any unrecognised state still yields a non-null entry (defaulting to
  /// [MediaPipeline.queued]): the record's mere presence in the queue means
  /// something is in flight, and reporting "Queued" is always closer to the
  /// truth than falling through to "Missing".
  static ArrQueueEntry? fromQueueItem(Map<String, dynamic> item) {
    final trackedState = stringOrNull(
      item['trackedDownloadState'],
    )?.toLowerCase();
    final rawStatus = stringOrNull(item['status']);
    final status = rawStatus?.toLowerCase();

    final resolved = _resolve(
      trackedState: trackedState,
      status: status,
      rawStatus: rawStatus,
      isStalled: _looksStalled(item),
    );
    if (resolved == null) return null;

    // A `status` of `warning` is itself a severity signal, even on a record that
    // carries neither `trackedDownloadStatus` nor any status message.
    final reported = arrQueueSeverity(item);
    final severity = status == 'warning' && reported == ArrQueueSeverity.ok
        ? ArrQueueSeverity.warning
        : reported;

    return ArrQueueEntry(
      pipeline: resolved.pipeline,
      label: resolved.label,
      progress: queueProgress(item),
      severity: severity,
      detail:
          stringOrNull(item['errorMessage']) ?? arrQueueWarningMessage(item),
    );
  }

  /// Whether the service is telling us this transfer has stopped moving.
  ///
  /// There is no `stalled` value in an \*arr's `status` field: the services
  /// report a stall in prose, via `errorMessage` or `statusMessages`, and their
  /// own web UIs read it back out the same way. Text matching is therefore the
  /// only signal available, so it is deliberately narrow — if the upstream
  /// wording changes this returns false and the record degrades to the previous
  /// behaviour (`downloading`, carrying a warning) rather than mislabelling a
  /// healthy transfer.
  static bool _looksStalled(Map<String, dynamic> item) {
    final haystack = [
      stringOrNull(item['errorMessage']),
      ...extractArrStatusMessages(item['statusMessages']),
    ].whereType<String>().join(' · ').toLowerCase();

    return haystack.contains('stalled') || haystack.contains('no connections');
  }

  static ({MediaPipeline pipeline, String? label})? _resolve({
    required String? trackedState,
    required String? status,
    required String? rawStatus,
    required bool isStalled,
  }) {
    // `trackedDownloadState` tracks which *phase* the \*arr has reached, so it
    // wins for the post-download phases: those are invisible to `status`, which
    // just reports `completed` for all of them.
    switch (trackedState) {
      case 'importpending':
        return (pipeline: MediaPipeline.importPending, label: null);
      // Split from `importpending` above, which it used to share. The two mean
      // opposite things to the user: `importPending` clears itself within
      // seconds, while `importBlocked` is the \*arr asking for a manual import
      // and will sit there until someone acts. Collapsing them hid every request
      // for help inside the most common transient state in the queue.
      case 'importblocked':
        return (pipeline: MediaPipeline.importBlocked, label: null);
      case 'importing':
        return (pipeline: MediaPipeline.importing, label: null);
      case 'failedpending':
      case 'failed':
        return (pipeline: MediaPipeline.failed, label: null);
      case 'imported':
      case 'ignored':
        return null;
    }

    // `trackedDownloadState: downloading` only means "still with the download
    // client" — a queued or paused item carries it too, so it must NOT be read
    // as "bytes are moving". The client `status` is what decides that, matching
    // what the *arr's own UI shows.
    final isWithClient = trackedState == 'downloading';

    return switch (status) {
      // The client is done but the *arr has not imported yet.
      'completed' => (pipeline: MediaPipeline.importPending, label: null),
      'queued' || 'delay' => (pipeline: MediaPipeline.queued, label: null),
      'downloading' => (
        pipeline: isStalled ? MediaPipeline.stalled : MediaPipeline.downloading,
        label: null,
      ),
      'paused' => (pipeline: MediaPipeline.paused, label: null),
      'failed' => (pipeline: MediaPipeline.failed, label: null),
      'downloadclientunavailable' => (
        pipeline: MediaPipeline.clientUnavailable,
        label: null,
      ),
      // `warning` is one of the \*arr status values, not an unknown string, and
      // it used to fall through to the branch below — which turned a record the
      // service had flagged into the word "Warning" sitting in a "Queued" row.
      'warning' => (
        pipeline: isStalled
            ? MediaPipeline.stalled
            : (isWithClient ? MediaPipeline.downloading : MediaPipeline.queued),
        label: null,
      ),
      // An unrecognised status still means something is in flight; keep the
      // service's own wording (humanised from the original casing) rather than
      // flattening it away.
      final String value when value.isNotEmpty => (
        pipeline: MediaPipeline.queued,
        label: humanizeCamelCase(rawStatus ?? value),
      ),
      // No status at all: fall back to whatever the tracked phase implied.
      _ => (
        pipeline: isWithClient
            ? (isStalled ? MediaPipeline.stalled : MediaPipeline.downloading)
            : MediaPipeline.queued,
        label: null,
      ),
    };
  }
}

/// Collapses several queue entries for the same media item into one.
///
/// Returns null for an empty input. Used by Seerr, whose `downloadStatus` array
/// carries one record per connected \*arr download.
ArrQueueEntry? mergeArrQueueEntries(Iterable<ArrQueueEntry> entries) {
  _EntryAccumulator? accumulator;
  for (final entry in entries) {
    (accumulator ??= _EntryAccumulator(entry.pipeline)).add(entry);
  }
  return accumulator?.freeze();
}

/// Combines the availability axis with a queue entry into a renderable status.
///
/// The single place where "what is on disk" meets "what is in flight", so every
/// \*arr resolver produces the same shape and an item in the queue can never
/// come out as `Missing`.
MediaStatusInfo mediaStatusFromQueue({
  required MediaAvailability availability,
  required bool monitored,
  ArrQueueEntry? queueEntry,
}) {
  return MediaStatusInfo(
    availability: availability,
    pipeline: queueEntry?.pipeline,
    progress: queueEntry?.progress,
    unmonitored: !monitored,
    hasWarning: queueEntry?.hasWarning ?? false,
    detail: queueEntry?.detail,
    labelOverride: queueEntry?.label,
    toneOverride: queueEntry?.toneOverride,
  );
}

/// An \*arr download queue indexed by media id.
class ArrQueueSnapshot {
  static const ArrQueueSnapshot empty = ArrQueueSnapshot._(
    <int, ArrQueueEntry>{},
  );

  final Map<int, ArrQueueEntry> entriesById;

  const ArrQueueSnapshot._(this.entriesById);

  bool get isEmpty => entriesById.isEmpty;
  bool get isNotEmpty => entriesById.isNotEmpty;

  ArrQueueEntry? entryFor(int? mediaId) {
    if (mediaId == null) return null;
    return entriesById[mediaId];
  }

  /// Builds a snapshot from raw `/queue` records.
  ///
  /// [idsFor] returns every media id a record belongs to; a Sonarr record maps
  /// to one series, but callers that pre-resolve album → artist may return
  /// several. Records whose ids cannot be resolved are dropped.
  factory ArrQueueSnapshot.fromQueueItems(
    Iterable<dynamic> items, {
    required Iterable<int> Function(Map<String, dynamic> item) idsFor,
  }) {
    final accumulators = <int, _EntryAccumulator>{};

    for (final raw in items) {
      final item = mapOrNull(raw);
      if (item == null) continue;

      final entry = ArrQueueEntry.fromQueueItem(item);
      if (entry == null) continue;

      for (final id in idsFor(item)) {
        if (id <= 0) continue;
        (accumulators[id] ??= _EntryAccumulator(entry.pipeline)).add(entry);
      }
    }

    return ArrQueueSnapshot._({
      for (final acc in accumulators.entries) acc.key: acc.value.freeze(),
    });
  }
}

/// Collapses several queue records onto one media item.
///
/// The highest-[MediaPipeline.salience] state becomes the headline, and the
/// reported progress is the mean across the records sharing it — a series with
/// two episodes at 20% and 80% reads 50%, not 80%.
class _EntryAccumulator {
  MediaPipeline pipeline;
  String? _label;
  double _progressSum = 0;
  int _progressSamples = 0;
  ArrQueueSeverity _severity = ArrQueueSeverity.ok;
  String? _detail;

  _EntryAccumulator(this.pipeline);

  void add(ArrQueueEntry entry) {
    if (entry.pipeline.salience > pipeline.salience) {
      pipeline = entry.pipeline;
      _label = null;
      _detail = null;
      _progressSum = 0;
      _progressSamples = 0;
    }

    if (entry.pipeline == pipeline) {
      _label ??= entry.label;
      // `_detail` follows the headline for the same reason `_label` does: both
      // describe *the state being reported*. Taking it from whichever record
      // happened to arrive first let a row headline "Downloading" and then print
      // the error message belonging to a different episode — the label was reset
      // when the headline changed and the detail was not.
      _detail ??= entry.detail;
      if (entry.progress != null) {
        _progressSum += entry.progress!;
        _progressSamples++;
      }
    }

    // Severity is deliberately the exception: it belongs to the *group*, not to
    // the headline. One episode erroring still matters when a healthy download
    // wins the headline, so this keeps the worst seen.
    if (entry.severity.index > _severity.index) _severity = entry.severity;
  }

  ArrQueueEntry freeze() {
    return ArrQueueEntry(
      pipeline: pipeline,
      label: _label,
      progress: _progressSamples == 0 ? null : _progressSum / _progressSamples,
      severity: _severity,
      detail: _detail,
    );
  }
}

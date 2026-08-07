import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';

/// Transmission's `status` field.
///
/// The integers are the wire values and are not arbitrary — they are the order
/// a torrent moves through, which is why `checkWait`/`downloadWait`/`seedWait`
/// sit immediately before the states they queue for.
enum TransmissionStatus {
  stopped(0, 'Stopped'),
  checkWait(1, 'Queued to check'),
  check(2, 'Checking'),
  downloadWait(3, 'Queued'),
  download(4, 'Downloading'),
  seedWait(5, 'Queued to seed'),
  seed(6, 'Seeding'),
  unknown(-1, 'Unknown');

  const TransmissionStatus(this.code, this.label);

  final int code;
  final String label;

  static TransmissionStatus fromCode(int code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return TransmissionStatus.unknown;
  }

  /// Whether this torrent is doing work right now, as opposed to sitting in a
  /// queue or stopped. Drives the "active" KPI and the in-flight filter.
  bool get isActive =>
      this == TransmissionStatus.download ||
      this == TransmissionStatus.seed ||
      this == TransmissionStatus.check;

  /// Whether bytes are (meant to be) coming in — the set the hub's in-flight
  /// rail shows. Seeding is deliberately excluded: a library of four hundred
  /// seeding torrents is not "in flight" and would crowd out every other
  /// source.
  bool get isIncoming =>
      this == TransmissionStatus.download ||
      this == TransmissionStatus.downloadWait ||
      this == TransmissionStatus.check ||
      this == TransmissionStatus.checkWait;
}

/// Transmission's `error` field: what kind of problem a torrent is reporting.
enum TransmissionErrorKind {
  none(0),
  trackerWarning(1),
  trackerError(2),
  localError(3);

  const TransmissionErrorKind(this.code);

  final int code;

  static TransmissionErrorKind fromCode(int code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return TransmissionErrorKind.none;
  }

  /// A tracker *warning* is noise on a healthy torrent — announce hiccups are
  /// routine — while a tracker error or a local error means it has actually
  /// stopped working. Only the latter two deserve a warning badge.
  bool get isBlocking =>
      this == TransmissionErrorKind.trackerError ||
      this == TransmissionErrorKind.localError;
}

/// Where a torrent should move in the queue.
enum TransmissionQueueMove {
  top('queue-move-top'),
  up('queue-move-up'),
  down('queue-move-down'),
  bottom('queue-move-bottom');

  const TransmissionQueueMove(this.method);

  /// The RPC method name this move maps to.
  final String method;
}

/// One torrent, as returned by `torrent-get`.
class TransmissionTorrent {
  const TransmissionTorrent({
    required this.id,
    required this.hashString,
    required this.name,
    required this.status,
    required this.percentDone,
    required this.totalSize,
    required this.sizeWhenDone,
    required this.leftUntilDone,
    required this.rateDownload,
    required this.rateUpload,
    required this.eta,
    required this.uploadRatio,
    required this.uploadedEver,
    required this.downloadedEver,
    required this.downloadDir,
    required this.errorKind,
    required this.errorString,
    required this.addedDate,
    required this.doneDate,
    required this.activityDate,
    required this.peersConnected,
    required this.peersSendingToUs,
    required this.peersGettingFromUs,
    required this.queuePosition,
    required this.isFinished,
    required this.isStalled,
    required this.labels,
    required this.recheckProgress,
  });

  /// Per-session integer id.
  ///
  /// **Not durable.** Transmission reuses ids after a daemon restart, so
  /// anything persisted or matched across a restart must key on [hashString].
  /// The RPC `ids` argument accepts hash strings as well as integers, which is
  /// why every write in [TransmissionClient] takes `List<String>` — see
  /// [rpcId].
  final int id;

  final String hashString;
  final String name;
  final TransmissionStatus status;

  /// 0..1, not a percentage.
  final double percentDone;

  final int totalSize;
  final int sizeWhenDone;
  final int leftUntilDone;

  /// Bytes per second. (Every *limit* in this API is kilobytes per second
  /// instead; see `TransmissionClient.setSpeedLimits`.)
  final int rateDownload;
  final int rateUpload;

  /// Seconds remaining, or negative when Transmission does not know — `-1`
  /// meaning "not available" and `-2` "unknown". Read [etaLabel] rather than
  /// formatting this directly.
  final int eta;

  /// Ratio, or `-1` when not available. Read [ratioLabel].
  final double uploadRatio;

  final int uploadedEver;
  final int downloadedEver;

  /// The download directory **on the daemon's filesystem**, which in a
  /// container is not the user's.
  final String downloadDir;

  final TransmissionErrorKind errorKind;
  final String errorString;

  /// Epoch **seconds**, not milliseconds. [doneDate] and [activityDate] are `0`
  /// rather than null when the thing never happened, so formatting them
  /// unguarded prints 1 January 1970.
  final int addedDate;
  final int doneDate;
  final int activityDate;

  final int peersConnected;
  final int peersSendingToUs;
  final int peersGettingFromUs;
  final int queuePosition;
  final bool isFinished;
  final bool isStalled;
  final List<String> labels;

  /// 0..1 while [TransmissionStatus.check] is running.
  final double recheckProgress;

  /// The durable identifier to send in an RPC `ids` array.
  ///
  /// The hash when there is one, falling back to the session id. Writes address
  /// torrents this way so a daemon restart between reading a list and acting on
  /// it cannot make an action land on a different torrent.
  String get rpcId => hashString.isNotEmpty ? hashString : id.toString();

  double get progress => percentDone.clamp(0, 1).toDouble();

  String get sizeLabel => formatSize(totalSize);

  String get remainingLabel => formatSize(leftUntilDone);

  String get downloadSpeedLabel => formatSpeed(rateDownload);

  String get uploadSpeedLabel => formatSpeed(rateUpload);

  String get etaLabel => eta < 0 ? 'Unknown' : formatDuration(eta);

  String get ratioLabel =>
      uploadRatio < 0 ? '—' : uploadRatio.toStringAsFixed(2);

  /// The short phrase shown under the name — the torrent's own status, or the
  /// reason it is not progressing when there is one.
  ///
  /// A stalled torrent is the state most worth surfacing: it looks exactly like
  /// a slow download until you notice it has not moved.
  String? get warning {
    if (errorKind.isBlocking) {
      return errorString.isEmpty ? 'Error' : errorString;
    }
    if (isStalled && status == TransmissionStatus.download) return 'Stalled';
    return null;
  }

  factory TransmissionTorrent.fromJson(Map<String, dynamic> json) {
    final rawLabels = json['labels'];
    return TransmissionTorrent(
      id: parseInt(json['id']),
      hashString: json['hashString']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: TransmissionStatus.fromCode(parseInt(json['status'])),
      percentDone: parseDouble(json['percentDone']),
      totalSize: parseInt(json['totalSize']),
      sizeWhenDone: parseInt(json['sizeWhenDone']),
      leftUntilDone: parseInt(json['leftUntilDone']),
      rateDownload: parseInt(json['rateDownload']),
      rateUpload: parseInt(json['rateUpload']),
      // Defaults to -1 ("unknown") rather than 0, so a field absent on an older
      // daemon reads as "no estimate" instead of "arriving now".
      eta: json.containsKey('eta') ? parseInt(json['eta']) : -1,
      uploadRatio: json.containsKey('uploadRatio')
          ? parseDouble(json['uploadRatio'])
          : -1,
      uploadedEver: parseInt(json['uploadedEver']),
      downloadedEver: parseInt(json['downloadedEver']),
      downloadDir: json['downloadDir']?.toString() ?? '',
      errorKind: TransmissionErrorKind.fromCode(parseInt(json['error'])),
      errorString: json['errorString']?.toString() ?? '',
      addedDate: parseInt(json['addedDate']),
      doneDate: parseInt(json['doneDate']),
      activityDate: parseInt(json['activityDate']),
      peersConnected: parseInt(json['peersConnected']),
      peersSendingToUs: parseInt(json['peersSendingToUs']),
      peersGettingFromUs: parseInt(json['peersGettingFromUs']),
      queuePosition: parseInt(json['queuePosition']),
      isFinished: parseBool(json['isFinished']),
      isStalled: parseBool(json['isStalled']),
      labels: rawLabels is List
          ? rawLabels.map((e) => e.toString()).toList(growable: false)
          : const [],
      recheckProgress: parseDouble(json['recheckProgress']),
    );
  }
}

/// The subset of `session-get` this app reads.
class TransmissionSession {
  const TransmissionSession({
    required this.version,
    required this.rpcVersion,
    required this.downloadDir,
    required this.altSpeedEnabled,
    required this.speedLimitDownKbPerSec,
    required this.speedLimitDownEnabled,
    required this.speedLimitUpKbPerSec,
    required this.speedLimitUpEnabled,
  });

  final String version;

  /// The RPC feature level, which is what a client must branch on rather than
  /// the display version: `labels`, `availability`, `file-count` and friends
  /// are simply absent on older daemons, and Transmission tolerates being asked
  /// for an unknown field by omitting it from the response rather than
  /// erroring. Without checking this, a client written against 4.x degrades
  /// silently on 3.x.
  final int rpcVersion;

  final String downloadDir;
  final bool altSpeedEnabled;

  /// Kilobytes per second, per this API's limit convention.
  final int speedLimitDownKbPerSec;
  final bool speedLimitDownEnabled;
  final int speedLimitUpKbPerSec;
  final bool speedLimitUpEnabled;

  /// Whether this daemon reports per-torrent `labels` (RPC 16 / Transmission
  /// 3.00 and newer).
  bool get supportsLabels => rpcVersion >= 16;

  factory TransmissionSession.fromJson(Map<String, dynamic> json) {
    return TransmissionSession(
      version: json['version']?.toString() ?? '',
      rpcVersion: parseInt(json['rpc-version']),
      downloadDir: json['download-dir']?.toString() ?? '',
      altSpeedEnabled: parseBool(json['alt-speed-enabled']),
      speedLimitDownKbPerSec: parseInt(json['speed-limit-down']),
      speedLimitDownEnabled: parseBool(json['speed-limit-down-enabled']),
      speedLimitUpKbPerSec: parseInt(json['speed-limit-up']),
      speedLimitUpEnabled: parseBool(json['speed-limit-up-enabled']),
    );
  }
}

/// `session-stats` — the aggregate counters, without listing any torrent.
class TransmissionStats {
  const TransmissionStats({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.torrentCount,
    required this.activeTorrentCount,
    required this.pausedTorrentCount,
    required this.downloadedBytes,
    required this.uploadedBytes,
  });

  /// Bytes per second.
  final int downloadSpeed;
  final int uploadSpeed;

  final int torrentCount;
  final int activeTorrentCount;
  final int pausedTorrentCount;

  /// Cumulative totals for the current session.
  final int downloadedBytes;
  final int uploadedBytes;

  String get downloadSpeedLabel => formatSpeed(downloadSpeed);

  String get uploadSpeedLabel => formatSpeed(uploadSpeed);

  String get uploadedLabel => formatSize(uploadedBytes);

  factory TransmissionStats.fromJson(Map<String, dynamic> json) {
    final current = json['current-stats'];
    final currentMap = current is Map
        ? current.cast<String, dynamic>()
        : const <String, dynamic>{};
    return TransmissionStats(
      downloadSpeed: parseInt(json['downloadSpeed']),
      uploadSpeed: parseInt(json['uploadSpeed']),
      torrentCount: parseInt(json['torrentCount']),
      activeTorrentCount: parseInt(json['activeTorrentCount']),
      pausedTorrentCount: parseInt(json['pausedTorrentCount']),
      downloadedBytes: parseInt(currentMap['downloadedBytes']),
      uploadedBytes: parseInt(currentMap['uploadedBytes']),
    );
  }
}

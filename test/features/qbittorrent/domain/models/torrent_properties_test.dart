import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/domain/models/torrent_properties.dart';

Map<String, dynamic> _canonicalProps({
  String savePath = '/downloads/Ubuntu',
  int creationDate = 1700000000,
  int pieceSize = 32768,
  String comment = 'ubuntu-24.04-desktop-amd64.iso',
  int totalWasted = 0,
  int totalUploaded = 1048576,
  int totalUploadedSession = 0,
  int totalDownloaded = 2097152,
  int totalDownloadedSession = 0,
  int upLimit = -1,
  int dlLimit = 1024,
  int timeElapsed = 7200,
  int seedingTime = 600,
  int nbConnections = 5,
  int nbConnectionsLimit = 100,
  double shareRatio = 1.5,
  int additionDate = 1700000000,
  int completionDate = 1700001000,
  String createdBy = 'qBittorrent v4.6.0',
  int dlSpeedAvg = 1024,
  int dlSpeed = 2048,
  int eta = 3600,
  int lastSeen = 1700005000,
  int peers = 5,
  int peersTotal = 10,
  int piecesHave = 32,
  int piecesNum = 64,
  int reannounce = 30,
  int seeds = 7,
  int seedsTotal = 15,
  int totalSize = 2147483648,
  int upSpeedAvg = 512,
  int upSpeed = 256,
  bool isPrivate = false,
}) {
  return {
    'save_path': savePath,
    'creation_date': creationDate,
    'piece_size': pieceSize,
    'comment': comment,
    'total_wasted': totalWasted,
    'total_uploaded': totalUploaded,
    'total_uploaded_session': totalUploadedSession,
    'total_downloaded': totalDownloaded,
    'total_downloaded_session': totalDownloadedSession,
    'up_limit': upLimit,
    'dl_limit': dlLimit,
    'time_elapsed': timeElapsed,
    'seeding_time': seedingTime,
    'nb_connections': nbConnections,
    'nb_connections_limit': nbConnectionsLimit,
    'share_ratio': shareRatio,
    'addition_date': additionDate,
    'completion_date': completionDate,
    'created_by': createdBy,
    'dl_speed_avg': dlSpeedAvg,
    'dl_speed': dlSpeed,
    'eta': eta,
    'last_seen': lastSeen,
    'peers': peers,
    'peers_total': peersTotal,
    'pieces_have': piecesHave,
    'pieces_num': piecesNum,
    'reannounce': reannounce,
    'seeds': seeds,
    'seeds_total': seedsTotal,
    'total_size': totalSize,
    'up_speed_avg': upSpeedAvg,
    'up_speed': upSpeed,
    'is_private': isPrivate,
  };
}

void main() {
  group('TorrentProperties.fromJson', () {
    test('parses canonical qB /properties payload', () {
      final p = TorrentProperties.fromJson(_canonicalProps());

      expect(p.savePath, '/downloads/Ubuntu');
      expect(p.creationDate, 1700000000);
      expect(p.pieceSize, 32768);
      expect(p.comment, 'ubuntu-24.04-desktop-amd64.iso');
      expect(p.totalWasted, 0);
      expect(p.totalUploaded, 1048576);
      expect(p.totalUploadedSession, 0);
      expect(p.totalDownloaded, 2097152);
      expect(p.totalDownloadedSession, 0);
      expect(p.upLimit, -1);
      expect(p.dlLimit, 1024);
      expect(p.timeElapsed, 7200);
      expect(p.seedingTime, 600);
      expect(p.nbConnections, 5);
      expect(p.nbConnectionsLimit, 100);
      expect(p.shareRatio, 1.5);
      expect(p.additionDate, 1700000000);
      expect(p.completionDate, 1700001000);
      expect(p.createdBy, 'qBittorrent v4.6.0');
      expect(p.dlSpeedAvg, 1024);
      expect(p.dlSpeed, 2048);
      expect(p.eta, 3600);
      expect(p.lastSeen, 1700005000);
      expect(p.peers, 5);
      expect(p.peersTotal, 10);
      expect(p.piecesHave, 32);
      expect(p.piecesNum, 64);
      expect(p.reannounceSeconds, 30);
      expect(p.seeds, 7);
      expect(p.seedsTotal, 15);
      expect(p.totalSize, 2147483648);
      expect(p.upSpeedAvg, 512);
      expect(p.upSpeed, 256);
      expect(p.isPrivate, isFalse);
    });

    test('parses is_private as 0/1 int into bool', () {
      final p = TorrentProperties.fromJson(_canonicalProps(isPrivate: false));
      expect(p.isPrivate, isFalse);

      final q = TorrentProperties.fromJson({
        ..._canonicalProps(),
        'is_private': 1,
      });
      expect(q.isPrivate, isTrue);
    });

    test('parses is_private as string "true"/"false" defensively', () {
      final p = TorrentProperties.fromJson({
        ..._canonicalProps(),
        'is_private': 'true',
      });
      expect(p.isPrivate, isTrue);

      final q = TorrentProperties.fromJson({
        ..._canonicalProps(),
        'is_private': 'false',
      });
      expect(q.isPrivate, isFalse);
    });

    test('falls back to empty string for missing string fields', () {
      final json = _canonicalProps()
        ..remove('save_path')
        ..remove('comment')
        ..remove('created_by');
      final p = TorrentProperties.fromJson(json);
      expect(p.savePath, '');
      expect(p.comment, '');
      expect(p.createdBy, '');
    });

    test('falls back to 0 / 0.0 / false for missing numeric / bool fields', () {
      // parseInt(null) -> 0 and parseDouble(null) -> 0.0 by design (see
      // torrent_test for the same caveat on Torrent). The -1 sentinel for
      // limits/dates only appears when the qB server explicitly returns -1.
      final p = TorrentProperties.fromJson(<String, dynamic>{});
      expect(p.creationDate, 0);
      expect(p.pieceSize, 0);
      expect(p.totalWasted, 0);
      expect(p.upLimit, 0);
      expect(p.dlLimit, 0);
      expect(p.timeElapsed, 0);
      expect(p.shareRatio, 0.0);
      expect(p.additionDate, 0);
      expect(p.completionDate, 0);
      expect(p.dlSpeedAvg, 0);
      expect(p.lastSeen, 0);
      expect(p.reannounceSeconds, 0);
      expect(p.totalSize, 0);
      expect(p.isPrivate, isFalse);
    });

    test('coerces numeric strings to numbers', () {
      final p = TorrentProperties.fromJson({
        ..._canonicalProps(),
        'total_size': '2147483648',
        'share_ratio': '1.5',
        'time_elapsed': '7200',
      });
      expect(p.totalSize, 2147483648);
      expect(p.shareRatio, 1.5);
      expect(p.timeElapsed, 7200);
    });

    test('preserves the -1 unlimited sentinel for limits', () {
      // qB returns -1 for "no limit set" on dl_limit/up_limit, and for
      // completion_date when the torrent is not yet complete. fromJson must
      // round-trip these values unchanged so the formatted getters can do
      // their sentinel-aware rendering.
      final p = TorrentProperties.fromJson({
        ..._canonicalProps(),
        'dl_limit': -1,
        'up_limit': -1,
        'completion_date': -1,
      });
      expect(p.dlLimit, -1);
      expect(p.upLimit, -1);
      expect(p.completionDate, -1);
    });
  });

  group('TorrentProperties formatted helpers', () {
    TorrentProperties build({
      String savePath = '/downloads/Ubuntu',
      int creationDate = 0,
      int pieceSize = 0,
      String comment = '',
      int totalWasted = 0,
      int totalUploaded = 0,
      int totalUploadedSession = 0,
      int totalDownloaded = 0,
      int totalDownloadedSession = 0,
      int upLimit = -1,
      int dlLimit = -1,
      int timeElapsed = 0,
      int seedingTime = 0,
      int nbConnections = 0,
      int nbConnectionsLimit = 0,
      double shareRatio = 0.0,
      int additionDate = 0,
      int completionDate = -1,
      String createdBy = '',
      int dlSpeedAvg = 0,
      int dlSpeed = 0,
      int eta = 0,
      int lastSeen = 0,
      int peers = 0,
      int peersTotal = 0,
      int piecesHave = 0,
      int piecesNum = 0,
      int reannounceSeconds = 0,
      int seeds = 0,
      int seedsTotal = 0,
      int totalSize = 0,
      int upSpeedAvg = 0,
      int upSpeed = 0,
      bool isPrivate = false,
    }) {
      return TorrentProperties(
        savePath: savePath,
        creationDate: creationDate,
        pieceSize: pieceSize,
        comment: comment,
        totalWasted: totalWasted,
        totalUploaded: totalUploaded,
        totalUploadedSession: totalUploadedSession,
        totalDownloaded: totalDownloaded,
        totalDownloadedSession: totalDownloadedSession,
        upLimit: upLimit,
        dlLimit: dlLimit,
        timeElapsed: timeElapsed,
        seedingTime: seedingTime,
        nbConnections: nbConnections,
        nbConnectionsLimit: nbConnectionsLimit,
        shareRatio: shareRatio,
        additionDate: additionDate,
        completionDate: completionDate,
        createdBy: createdBy,
        dlSpeedAvg: dlSpeedAvg,
        dlSpeed: dlSpeed,
        eta: eta,
        lastSeen: lastSeen,
        peers: peers,
        peersTotal: peersTotal,
        piecesHave: piecesHave,
        piecesNum: piecesNum,
        reannounceSeconds: reannounceSeconds,
        seeds: seeds,
        seedsTotal: seedsTotal,
        totalSize: totalSize,
        upSpeedAvg: upSpeedAvg,
        upSpeed: upSpeed,
        isPrivate: isPrivate,
      );
    }

    test(
      'savePathFormatted / createdByFormatted / commentFormatted show em-dash for empty',
      () {
        expect(build(savePath: '').savePathFormatted, '—');
        expect(build(savePath: '/data').savePathFormatted, '/data');
        expect(build(createdBy: '').createdByFormatted, '—');
        expect(
          build(createdBy: 'qBittorrent v4.6.0').createdByFormatted,
          'qBittorrent v4.6.0',
        );
        expect(build(comment: '').commentFormatted, '—');
        expect(build(comment: 'ubuntu-24.04').commentFormatted, 'ubuntu-24.04');
      },
    );

    test(
      'timeActiveFormatted and seededForFormatted defer to formatDuration',
      () {
        // The getter naming intentionally mirrors the qB WebUI: "Time active"
        // reads `time_elapsed`; "Seeded for" reads `seeding_time`. Both are
        // formatted via the shared `formatDuration` so the screen renders
        // "1d 02:00:00" consistently with how `lastActivityFormatted` is
        // rendered elsewhere.
        expect(build(timeElapsed: 0).timeActiveFormatted, '');
        expect(build(timeElapsed: -5).timeActiveFormatted, '');
        expect(build(timeElapsed: 65).timeActiveFormatted, '00:01:05');
        expect(build(timeElapsed: 93600).timeActiveFormatted, '1d 02:00:00');

        expect(build(seedingTime: 0).seededForFormatted, '');
        expect(build(seedingTime: 3600).seededForFormatted, '01:00:00');
      },
    );

    test(
      'date getters defer to formatEpochDate (em-dash for non-positive)',
      () {
        // -1 is qB's explicit "not set" / "not yet complete" sentinel for
        // completion_date; 0 is the parseInt(null) default for the rest.
        expect(build(creationDate: 0).creationDateFormatted, '—');
        expect(build(creationDate: -1).creationDateFormatted, '—');
        expect(build(additionDate: 0).additionDateFormatted, '—');
        expect(build(completionDate: -1).completionDateFormatted, '—');
        expect(build(lastSeen: 0).lastSeenFormatted, '—');
        expect(build(lastSeen: -1).lastSeenFormatted, '—');

        // A real epoch second must render as YYYY-MM-DD HH:MM (local TZ).
        final epoch =
            DateTime.utc(2026, 6, 15, 14, 30).millisecondsSinceEpoch ~/ 1000;
        final formatted = build(additionDate: epoch).additionDateFormatted;
        expect(formatted, matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')));
        expect(formatted.startsWith('2026-06-15'), isTrue);
      },
    );

    test('shareRatioFormatted is two-decimal fixed string', () {
      expect(build(shareRatio: 0).shareRatioFormatted, '0.00');
      expect(build(shareRatio: 1.5).shareRatioFormatted, '1.50');
      expect(build(shareRatio: 2.3456789).shareRatioFormatted, '2.35');
    });

    test(
      'dlLimitFormatted and upLimitFormatted map -1 to ∞, 0 to "0", positive to formatSpeed',
      () {
        expect(build(dlLimit: -1).dlLimitFormatted, '∞');
        expect(build(dlLimit: 0).dlLimitFormatted, '0');
        expect(build(dlLimit: 2048).dlLimitFormatted, '2.0 KB/s');
        expect(build(dlLimit: 5 * 1024 * 1024).dlLimitFormatted, '5.0 MB/s');

        expect(build(upLimit: -1).upLimitFormatted, '∞');
        expect(build(upLimit: 0).upLimitFormatted, '0');
        expect(build(upLimit: 1024).upLimitFormatted, '1.0 KB/s');
      },
    );

    test(
      'dlSpeedAvgFormatted and upSpeedAvgFormatted defer to formatSpeed',
      () {
        expect(build(dlSpeedAvg: 0).dlSpeedAvgFormatted, '0 B/s');
        expect(build(dlSpeedAvg: 2048).dlSpeedAvgFormatted, '2.0 KB/s');
        expect(build(upSpeedAvg: 1024 * 1024).upSpeedAvgFormatted, '1.0 MB/s');
      },
    );

    test('pieceSizeFormatted defers to formatSize', () {
      expect(build(pieceSize: 0).pieceSizeFormatted, '—');
      expect(build(pieceSize: 32768).pieceSizeFormatted, '32.0 KB');
    });

    test('pieces / peers / seeds formatted as have / total', () {
      expect(build(piecesHave: 32, piecesNum: 64).piecesFormatted, '32 / 64');
      expect(build(piecesHave: 0, piecesNum: 0).piecesFormatted, '0 / 0');
      expect(build(peers: 5, peersTotal: 10).peersFormatted, '5 / 10');
      expect(build(seeds: 7, seedsTotal: 15).seedsFormatted, '7 / 15');
    });

    test('connectionsFormatted shows denominator only when limit > 0', () {
      // qB uses 0 to mean "no connection limit" — suppress the denominator
      // to avoid a misleading `5 / 0` row.
      expect(
        build(nbConnections: 5, nbConnectionsLimit: 0).connectionsFormatted,
        '5',
      );
      expect(
        build(nbConnections: 5, nbConnectionsLimit: 100).connectionsFormatted,
        '5 / 100',
      );
      expect(
        build(nbConnections: 0, nbConnectionsLimit: 0).connectionsFormatted,
        '0',
      );
    });

    test('reannounceFormatted shows —s for non-positive, <N>s otherwise', () {
      // Reannounce is the countdown until the next tracker announce; qB
      // uses 0 (or -1) for "never" / "not applicable".
      expect(build(reannounceSeconds: 0).reannounceFormatted, '—s');
      expect(build(reannounceSeconds: -1).reannounceFormatted, '—s');
      expect(build(reannounceSeconds: 30).reannounceFormatted, '30s');
    });
  });
}

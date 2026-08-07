import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/domain/models/torrent_tracker.dart';

void main() {
  group('TorrentTracker.fromJson', () {
    test('parses canonical payload', () {
      final t = TorrentTracker.fromJson({
        'url': 'https://tracker.example/announce',
        'status': 2,
        'tier': 0,
        'num_peers': 10,
        'num_seeds': 5,
        'num_leeches': 3,
        'num_downloaded': 100,
        'msg': 'ok',
      });
      expect(t.url, 'https://tracker.example/announce');
      expect(t.status, 2);
      expect(t.tier, 0);
      expect(t.numPeers, 10);
      expect(t.numSeeds, 5);
      expect(t.numLeeches, 3);
      expect(t.numDownloaded, 100);
      expect(t.msg, 'ok');
    });

    test('handles null msg safely', () {
      final t = TorrentTracker.fromJson({
        'url': 'https://tracker.example/announce',
        'status': 0,
        'tier': 0,
        'num_peers': 0,
        'num_seeds': 0,
        'num_leeches': 0,
        'num_downloaded': 0,
        'msg': null,
      });
      expect(t.msg, '');
    });
  });

  group('TorrentTracker.statusLabel', () {
    TorrentTracker build(int status) => TorrentTracker(
      url: '',
      status: status,
      tier: 0,
      numPeers: 0,
      numSeeds: 0,
      numLeeches: 0,
      numDownloaded: 0,
      msg: '',
    );

    test('returns expected labels per status code', () {
      expect(build(0).statusLabel, 'Disabled');
      expect(build(1).statusLabel, 'Not contacted');
      expect(build(2).statusLabel, 'Working');
      expect(build(3).statusLabel, 'Updating');
      expect(build(4).statusLabel, 'Not working');
      expect(build(99).statusLabel, 'Unknown');
    });
  });
}

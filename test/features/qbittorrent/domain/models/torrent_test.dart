import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';

void main() {
  group('TorrentState.fromString', () {
    test('parses standard v4 states', () {
      expect(TorrentState.fromString('downloading'), TorrentState.downloading);
      expect(TorrentState.fromString('forcedDL'), TorrentState.downloading);
      expect(TorrentState.fromString('uploading'), TorrentState.seeding);
      expect(TorrentState.fromString('forcedUP'), TorrentState.seeding);
      expect(TorrentState.fromString('stalledDL'), TorrentState.stalled);
      expect(TorrentState.fromString('stalledUP'), TorrentState.seeding);
      expect(TorrentState.fromString('checkingDL'), TorrentState.checking);
      expect(TorrentState.fromString('checkingUP'), TorrentState.checking);
      expect(TorrentState.fromString('pausedDL'), TorrentState.paused);
      expect(TorrentState.fromString('pausedUP'), TorrentState.paused);
    });

    test('parses v5 stopped states as paused', () {
      expect(TorrentState.fromString('stopped'), TorrentState.paused);
      expect(TorrentState.fromString('stoppedDL'), TorrentState.paused);
      expect(TorrentState.fromString('stoppedUP'), TorrentState.paused);
    });

    test('parses queue states', () {
      expect(TorrentState.fromString('queuedUP'), TorrentState.queuedUp);
      expect(TorrentState.fromString('queuedDL'), TorrentState.queuedDl);
    });

    test('parses meta, error and unknown states', () {
      expect(TorrentState.fromString('metaDL'), TorrentState.metaDownloading);
      expect(TorrentState.fromString('error'), TorrentState.error);
      expect(TorrentState.fromString('missingFiles'), TorrentState.error);
      expect(TorrentState.fromString(null), TorrentState.unknown);
      expect(TorrentState.fromString('garbage'), TorrentState.unknown);
    });

    test('parses transient states as downloading', () {
      expect(TorrentState.fromString('moving'), TorrentState.downloading);
      expect(TorrentState.fromString('allocating'), TorrentState.downloading);
    });
  });

  group('TorrentState.label', () {
    test('returns expected labels', () {
      expect(TorrentState.downloading.label, 'DL');
      expect(TorrentState.metaDownloading.label, 'META');
      expect(TorrentState.seeding.label, 'SEED');
      expect(TorrentState.stalled.label, 'STALLED');
      expect(TorrentState.checking.label, 'CHECK');
      expect(TorrentState.paused.label, 'PAUSE');
      expect(TorrentState.queuedUp.label, 'QUEUE');
      expect(TorrentState.queuedDl.label, 'QUEUE');
      expect(TorrentState.error.label, 'ERR');
      expect(TorrentState.unknown.label, '—');
    });
  });

  group('TorrentState helpers', () {
    test('isActive matches downloading/seeding/metaDownloading', () {
      expect(TorrentState.downloading.isActive, isTrue);
      expect(TorrentState.metaDownloading.isActive, isTrue);
      expect(TorrentState.seeding.isActive, isTrue);
      expect(TorrentState.paused.isActive, isFalse);
      expect(TorrentState.queuedDl.isActive, isFalse);
    });

    test('isPaused only true for paused', () {
      expect(TorrentState.paused.isPaused, isTrue);
      expect(TorrentState.downloading.isPaused, isFalse);
    });

    test('isQueued matches queue states', () {
      expect(TorrentState.queuedUp.isQueued, isTrue);
      expect(TorrentState.queuedDl.isQueued, isTrue);
      expect(TorrentState.downloading.isQueued, isFalse);
    });
  });

  group('Torrent.fromJson', () {
    test('parses canonical payload', () {
      final t = Torrent.fromJson({
        'hash': 'abc123',
        'name': 'Ubuntu',
        'size': 1024,
        'progress': 0.5,
        'state': 'downloading',
        'dlspeed': 1024,
        'upspeed': 256,
        'eta': 3600,
        'category': 'linux',
        'tracker': 'https://tracker.example.com/announce',
        'tags': ['a', 'b'],
        'ratio': 1.5,
        'added_on': 1700000000,
        'completed': 512,
        'num_leechs': 3,
        'num_seeds': 7,
      });

      expect(t.hash, 'abc123');
      expect(t.name, 'Ubuntu');
      expect(t.size, 1024);
      expect(t.progress, 0.5);
      expect(t.parsedState, TorrentState.downloading);
      expect(t.dlSpeed, 1024);
      expect(t.upSpeed, 256);
      expect(t.eta, 3600);
      expect(t.category, 'linux');
      expect(t.tags, ['a', 'b']);
      expect(t.ratio, 1.5);
      expect(t.seeders, 7);
    });

    test('parses v5 stopped state into paused', () {
      final t = Torrent.fromJson({
        'hash': 'h',
        'name': 'X',
        'size': 0,
        'progress': 0,
        'state': 'stoppedDL',
        'dlspeed': 0,
        'upspeed': 0,
        'eta': -1,
        'category': '',
        'tracker': '',
        'tags': <String>[],
        'ratio': 0,
        'added_on': 0,
        'completed': 0,
        'num_leechs': 0,
        'num_seeds': 0,
      });
      expect(t.parsedState, TorrentState.paused);
    });

    test('parses tags as comma-separated string', () {
      final t = Torrent.fromJson({
        'hash': 'h',
        'name': 'X',
        'size': 0,
        'progress': 0,
        'state': 'downloading',
        'dlspeed': 0,
        'upspeed': 0,
        'eta': 0,
        'category': '',
        'tracker': '',
        'tags': 'linux, iso,',
        'ratio': 0,
        'added_on': 0,
        'completed': 0,
        'num_leechs': 0,
        'num_seeds': 0,
      });
      expect(t.tags, ['linux', 'iso']);
    });

    test('parses tags with null as empty', () {
      final t = Torrent.fromJson({
        'hash': 'h',
        'name': 'X',
        'size': 0,
        'progress': 0,
        'state': 'downloading',
        'dlspeed': 0,
        'upspeed': 0,
        'eta': 0,
        'category': '',
        'tracker': '',
        'tags': null,
        'ratio': 0,
        'added_on': 0,
        'completed': 0,
        'num_leechs': 0,
        'num_seeds': 0,
      });
      expect(t.tags, isEmpty);
    });

    test('coerces numeric strings to numbers', () {
      final t = Torrent.fromJson({
        'hash': 'h',
        'name': 'X',
        'size': '2048',
        'progress': '0.75',
        'state': 'downloading',
        'dlspeed': '512',
        'upspeed': 0,
        'eta': 0,
        'category': '',
        'tracker': '',
        'tags': <String>[],
        'ratio': 0,
        'added_on': 0,
        'completed': 0,
        'num_leechs': 0,
        'num_seeds': 0,
      });
      expect(t.size, 2048);
      expect(t.progress, 0.75);
      expect(t.dlSpeed, 512);
    });
  });

  group('Torrent formatted helpers', () {
    Torrent build({
      String state = 'downloading',
      int eta = 3600,
      int dl = 0,
      int up = 0,
      double progress = 0.0,
      int size = 0,
      String tracker = '',
    }) {
      return Torrent(
        hash: 'h',
        name: 'N',
        size: size,
        progress: progress,
        state: state,
        parsedState: TorrentState.fromString(state),
        dlSpeed: dl,
        upSpeed: up,
        eta: eta,
        category: '',
        tracker: tracker,
        tags: const [],
        ratio: 0,
        addedOn: 0,
        completed: 0,
        leechers: 0,
        seeders: 0,
      );
    }

    test('progressFormatted is single-decimal percent', () {
      expect(build(progress: 0.5).progressFormatted, '50.0%');
      expect(build(progress: 1).progressFormatted, '100.0%');
    });

    test('sizeFormatted shows em-dash when zero', () {
      expect(build(size: 0).sizeFormatted, '—');
      expect(build(size: 1024).sizeFormatted, '1.00 KB');
    });

    test('dlSpeedFormatted and upSpeedFormatted', () {
      expect(build(dl: 0).dlSpeedFormatted, '0');
      expect(build(dl: 2048).dlSpeedFormatted, '2.0 KB/s');
      expect(build(up: 0).upSpeedFormatted, '0');
      expect(build(up: 1024).upSpeedFormatted, '1.0 KB/s');
    });

    test('etaFormatted', () {
      expect(build(eta: -1).etaFormatted, '');
      expect(build(state: 'pausedDL').etaFormatted, '');
      expect(build(state: 'stoppedDL').etaFormatted, '');
      expect(build(state: 'stoppedUP').etaFormatted, '');
      expect(build(state: 'stopped').etaFormatted, '');
      expect(build(eta: 8640000).etaFormatted, '∞');
      expect(build(eta: 0).etaFormatted, '0m');
      expect(build(eta: 90).etaFormatted, '1m');
      expect(build(eta: 3600).etaFormatted, '1h 0m');
      expect(build(eta: 3660).etaFormatted, '1h 1m');
      expect(build(eta: 86400).etaFormatted, '1d 0h');
      expect(build(eta: 90000).etaFormatted, '1d 1h');
    });

    test('trackerDomain strips www. prefix', () {
      expect(
        build(tracker: 'https://www.tracker.example/announce').trackerDomain,
        'tracker.example',
      );
      expect(
        build(tracker: 'https://tracker.example/announce').trackerDomain,
        'tracker.example',
      );
      expect(build(tracker: '').trackerDomain, '');
      expect(build(tracker: 'not a url').trackerDomain, '');
    });
  });

  group('Torrent new optional fields', () {
    // Minimal builder that mirrors the original 16-param signature, so the
    // "new field default" assertions below also prove the original call
    // shape still works.
    Torrent buildMin() => Torrent(
      hash: 'h',
      name: 'N',
      size: 0,
      progress: 0,
      state: 'downloading',
      parsedState: TorrentState.downloading,
      dlSpeed: 0,
      upSpeed: 0,
      eta: 0,
      category: '',
      tracker: '',
      tags: const [],
      ratio: 0,
      addedOn: 0,
      completed: 0,
      leechers: 0,
      seeders: 0,
    );

    test('default values match documented sentinels', () {
      final t = buildMin();
      expect(t.contentPath, '');
      expect(t.dlLimit, -1);
      expect(t.upLimit, -1);
      expect(t.lastActivity, 0);
      expect(t.seedingTime, 0);
      expect(t.timeActive, 0);
      expect(t.downloaded, 0);
      expect(t.uploaded, 0);
      expect(t.availability, 1.0);
      expect(t.isPrivate, isFalse);
      expect(t.forceStart, isFalse);
      expect(t.superSeeding, isFalse);
      expect(t.magnetUri, '');
      expect(t.maxRatio, -1);
      expect(t.ratioLimit, -1);
      expect(t.maxSeedingTime, -1);
    });

    test('fromJson maps new /torrents/info fields defensively', () {
      final t = Torrent.fromJson({
        'hash': 'h',
        'name': 'N',
        'size': 0,
        'progress': 0,
        'state': 'downloading',
        'dlspeed': 0,
        'upspeed': 0,
        'eta': 0,
        'category': '',
        'tracker': '',
        'tags': <String>[],
        'ratio': 0,
        'added_on': 0,
        'completed': 0,
        'num_leechs': 0,
        'num_seeds': 0,
        // New /info fields
        'content_path': '/downloads/Ubuntu',
        'dl_limit': 1024,
        'up_limit': -1,
        'last_activity': 1700000500,
        'seeding_time': 600,
        'time_active': 7200,
        'downloaded': 2 * 1024 * 1024,
        'uploaded': 1024 * 1024,
        'availability': 0.95,
        'is_private': 1,
        'force_start': 'true',
        'super_seeding': false,
        'magnet_uri': 'magnet:?xt=urn:btih:abc',
        'max_ratio': 2.0,
        'ratio_limit': -1.0,
        'max_seeding_time': 3600,
      });

      expect(t.contentPath, '/downloads/Ubuntu');
      expect(t.dlLimit, 1024);
      expect(t.upLimit, -1);
      expect(t.lastActivity, 1700000500);
      expect(t.seedingTime, 600);
      expect(t.timeActive, 7200);
      expect(t.downloaded, 2 * 1024 * 1024);
      expect(t.uploaded, 1024 * 1024);
      expect(t.availability, 0.95);
      expect(t.isPrivate, isTrue);
      expect(t.forceStart, isTrue);
      expect(t.superSeeding, isFalse);
      expect(t.magnetUri, 'magnet:?xt=urn:btih:abc');
      expect(t.maxRatio, 2.0);
      expect(t.ratioLimit, -1.0);
      expect(t.maxSeedingTime, 3600);
    });

    test('fromJson defaults new fields when payload omits them', () {
      // Note: parseInt(null) -> 0 and parseDouble(null) -> 0.0, so
      // omitted-from-JSON yields 0 (not the constructor's -1 sentinel).
      // The -1 sentinel only appears when qB itself returns -1 in the payload
      // (i.e. "unlimited"); the UI helper `formatLimit` maps both 0 and
      // positive values to their speed strings and -1 to '∞'. Same goes for
      // `availability`: the constructor defaults to 1.0 (assume fully
      // available), but fromJson with the field omitted produces 0.0.
      final t = Torrent.fromJson({
        'hash': 'h',
        'name': 'N',
        'size': 0,
        'progress': 0,
        'state': 'downloading',
        'dlspeed': 0,
        'upspeed': 0,
        'eta': 0,
        'category': '',
        'tracker': '',
        'tags': <String>[],
        'ratio': 0,
        'added_on': 0,
        'completed': 0,
        'num_leechs': 0,
        'num_seeds': 0,
      });
      expect(t.contentPath, '');
      expect(t.dlLimit, 0);
      expect(t.upLimit, 0);
      expect(t.lastActivity, 0);
      expect(t.downloaded, 0);
      expect(t.uploaded, 0);
      expect(t.availability, 0.0);
      expect(t.isPrivate, isFalse);
      expect(t.forceStart, isFalse);
      expect(t.superSeeding, isFalse);
      expect(t.magnetUri, '');
      expect(t.maxRatio, 0);
      expect(t.ratioLimit, 0);
      expect(t.maxSeedingTime, 0);
    });
  });
}

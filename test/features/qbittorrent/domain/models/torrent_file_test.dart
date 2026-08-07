import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/domain/models/torrent_file.dart';

void main() {
  group('TorrentFile.fromJson', () {
    test('parses canonical payload', () {
      final f = TorrentFile.fromJson({
        'index': 0,
        'name': 'ubuntu.iso',
        'size': 1024,
        'progress': 0.5,
        'priority': 1,
      });
      expect(f.index, 0);
      expect(f.name, 'ubuntu.iso');
      expect(f.size, 1024);
      expect(f.progress, 0.5);
      expect(f.priority, 1);
    });

    test('falls back to id when index missing', () {
      final f = TorrentFile.fromJson({
        'id': 5,
        'name': 'f',
        'size': 0,
        'progress': 0,
        'priority': 0,
      });
      expect(f.index, 5);
    });

    test('coerces stringified numerics', () {
      final f = TorrentFile.fromJson({
        'index': '3',
        'name': 'f',
        'size': '1024',
        'progress': '0.25',
        'priority': '2',
      });
      expect(f.index, 3);
      expect(f.size, 1024);
      expect(f.progress, 0.25);
      expect(f.priority, 2);
    });

    test('uses empty defaults for missing name', () {
      final f = TorrentFile.fromJson({
        'index': 0,
        'size': 0,
        'progress': 0,
        'priority': 0,
      });
      expect(f.name, '');
    });
  });

  group('TorrentFile formatted helpers', () {
    final file = TorrentFile(
      index: 0,
      name: 'x',
      size: 2 * 1024 * 1024,
      progress: 0.5,
      priority: 0,
    );

    test('sizeFormatted', () {
      expect(file.sizeFormatted, '2.00 MB');
    });

    test('progressFormatted is single-decimal percent', () {
      expect(file.progressFormatted, '50.0%');
    });
  });

  group('TorrentFile.priorityLabel', () {
    TorrentFile withPriority(int p) =>
        TorrentFile(index: 0, name: 'x', size: 0, progress: 0, priority: p);

    test('0 → Do not download', () {
      expect(withPriority(0).priorityLabel, 'Do not download');
    });

    test('1 → Normal', () {
      expect(withPriority(1).priorityLabel, 'Normal');
    });

    test('2 → High', () {
      expect(withPriority(2).priorityLabel, 'High');
    });

    test('6 → Maximum', () {
      expect(withPriority(6).priorityLabel, 'Maximum');
    });

    test('7 → Mixed', () {
      expect(withPriority(7).priorityLabel, 'Mixed');
    });

    test('unknown value falls back to "Priority N"', () {
      expect(withPriority(99).priorityLabel, 'Priority 99');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/qbittorrent/domain/models/transfer_info.dart';

void main() {
  group('TransferInfo.fromJson', () {
    test('parses canonical payload', () {
      final info = TransferInfo.fromJson({
        'dl_info_speed': 1024,
        'up_info_speed': 512,
        'dl_info_data': 100000,
        'up_info_data': 50000,
        'dl_rate_limit': 0,
        'up_rate_limit': 0,
        'use_alt_speed_limits': true,
      });
      expect(info.dlSpeed, 1024);
      expect(info.upSpeed, 512);
      expect(info.dlInfoData, 100000);
      expect(info.upInfoData, 50000);
      expect(info.altSpeedEnabled, isTrue);
    });

    test('altSpeedEnabled is false when not true', () {
      final info = TransferInfo.fromJson({
        'dl_info_speed': 0,
        'up_info_speed': 0,
        'dl_info_data': 0,
        'up_info_data': 0,
        'dl_rate_limit': 0,
        'up_rate_limit': 0,
        'use_alt_speed_limits': false,
      });
      expect(info.altSpeedEnabled, isFalse);
    });
  });

  group('TransferInfo formatted helpers', () {
    test('zero speeds render as 0 B/s', () {
      final info = TransferInfo(
        dlSpeed: 0,
        upSpeed: 0,
        dlInfoData: 0,
        upInfoData: 0,
        dlRateLimit: 0,
        upRateLimit: 0,
        altSpeedEnabled: false,
      );
      expect(info.dlSpeedFormatted, '0 B/s');
      expect(info.upSpeedFormatted, '0 B/s');
    });

    test('non-zero speeds render with units', () {
      final info = TransferInfo(
        dlSpeed: 52 * 1024 * 1024,
        upSpeed: 1024,
        dlInfoData: 0,
        upInfoData: 0,
        dlRateLimit: 0,
        upRateLimit: 0,
        altSpeedEnabled: false,
      );
      expect(info.dlSpeedFormatted, '52 MB/s');
      expect(info.upSpeedFormatted, '1.0 KB/s');
    });
  });
}

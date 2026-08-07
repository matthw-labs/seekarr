import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('ServiceSummary', () {
    test('formats online status and version', () {
      const summary = ServiceSummary(
        service: ServiceKey.radarr,
        status: ServiceSummaryStatus.online,
        host: 'radarr.local:7878',
        version: '5.4.6',
      );

      expect(summary.isOnline, isTrue);
      expect(summary.statusLabel, 'Online');
      expect(summary.versionLabel, 'v5.4.6');
    });

    test('leaves an already-prefixed version alone', () {
      const summary = ServiceSummary(
        service: ServiceKey.seerr,
        status: ServiceSummaryStatus.online,
        host: 'seerr.local:5055',
        version: 'v2.5.1',
      );

      expect(summary.versionLabel, 'v2.5.1');
    });

    test('falls back to the registry API label when there is no version', () {
      const offline = ServiceSummary(
        service: ServiceKey.lidarr,
        status: ServiceSummaryStatus.offline,
        host: 'lidarr.local:8686',
        version: null,
      );

      expect(offline.isOnline, isFalse);
      expect(offline.statusLabel, 'Offline');
      expect(offline.versionLabel, 'v1 API');
    });

    test('treats a blank version as absent rather than printing "v"', () {
      const blank = ServiceSummary(
        service: ServiceKey.radarr,
        status: ServiceSummaryStatus.online,
        host: 'radarr.local:7878',
        version: '   ',
      );

      expect(blank.versionLabel, 'v3 API');
    });
  });
}

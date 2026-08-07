import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/domain/connection_presentation.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

void main() {
  group('describeConnection', () {
    test('a refused redirect is not drawn as unreachable', () {
      final presentation = describeConnection(
        ServiceKey.radarr,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.redirected,
      );

      // Red means nothing answered. Something answered — it just answered with
      // a redirect — so this is the amber "fix something" tone, and the label
      // has to say which something.
      expect(presentation.tone, StatusTone.warning);
      expect(presentation.needsAttention, isTrue);
      expect(presentation.label, isNot('Unreachable'));
      expect(presentation.label.toLowerCase(), contains('redirect'));
    });

    test('a redirect and a wrong base path do not read the same', () {
      final redirected = describeConnection(
        ServiceKey.radarr,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.redirected,
      );
      final notFound = describeConnection(
        ServiceKey.radarr,
        status: ServiceConnectionStatus.disconnected,
        reason: ServiceFailureReason.notFound,
      );

      expect(redirected.label, isNot(notFound.label));
      expect(redirected.icon, isNot(notFound.icon));
    });

    // The switch over `reason` is exhaustive, so this is a guard against a new
    // reason being added and quietly landing on the "Unreachable" fallback
    // rather than being given words of its own.
    test('every failure reason resolves to a state worth showing', () {
      for (final reason in ServiceFailureReason.values) {
        final presentation = describeConnection(
          ServiceKey.sonarr,
          status: ServiceConnectionStatus.disconnected,
          reason: reason,
        );
        expect(presentation.needsAttention, isTrue, reason: '$reason');
        expect(presentation.label, isNotEmpty, reason: '$reason');
      }
    });

    test('the healthy and unconfigured states stay quiet', () {
      for (final status in const [
        ServiceConnectionStatus.connected,
        ServiceConnectionStatus.notConfigured,
        ServiceConnectionStatus.checking,
      ]) {
        expect(
          describeConnection(ServiceKey.radarr, status: status).needsAttention,
          isFalse,
          reason: '$status',
        );
      }
    });
  });
}

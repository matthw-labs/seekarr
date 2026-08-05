import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/features/services/domain/services_semantics.dart';

void main() {
  group('downloadRowValue', () {
    test('replaces visual dot separators with commas', () {
      expect(
        downloadRowValue(
          subtitle: 'Movie · Furiosa.2024.2160p.WEB-DL-GROUP',
          percent: 75,
          warning: null,
        ),
        '75% downloaded, Movie, Furiosa.2024.2160p.WEB-DL-GROUP',
      );
    });

    test("leads with the client's own reason, not the word 'Warning'", () {
      // A bare "Warning" named that something was wrong without saying what,
      // while the reason sat unused in the model.
      expect(
        downloadRowValue(
          subtitle: 'Movie',
          percent: 40,
          warning: 'Download stalled',
        ),
        'Download stalled, 40% downloaded, Movie',
      );
    });

    test('omits progress entirely when the client reports none', () {
      // The row paints nothing in that slot either.
      expect(
        downloadRowValue(subtitle: 'Movie', percent: null, warning: null),
        'Movie',
      );
    });
  });

  group('serviceMatrixCellValue', () {
    test('leads with reachability, then the signal, then the host', () {
      expect(
        serviceMatrixCellValue(
          statusLabel: 'Online',
          signalSpoken: 'Missing 12',
          host: 'radarr.local:7878',
        ),
        'Online, Missing 12, radarr.local:7878',
      );
    });

    test('drops the signal while the metric is still resolving', () {
      expect(
        serviceMatrixCellValue(
          statusLabel: 'Checking',
          signalSpoken: null,
          host: 'radarr.local:7878',
        ),
        'Checking, radarr.local:7878',
      );
    });

    test('says only the state when a service has no host configured', () {
      expect(
        serviceMatrixCellValue(
          statusLabel: 'Offline',
          signalSpoken: null,
          host: '',
        ),
        'Offline',
      );
    });
  });

  group('servicesUnconfiguredCellLabel', () {
    test('leads with the verb the bare count was missing', () {
      // One string for the eye and the ear. A bare "4 more services" beside a
      // `+` icon reads as the tail of a truncated list, which is why the spoken
      // form used to have to append "available to set up".
      expect(servicesUnconfiguredCellLabel(count: 4), 'Set up 4 more services');
    });

    test('singularizes the last one', () {
      expect(servicesUnconfiguredCellLabel(count: 1), 'Set up 1 more service');
    });
  });

  group('serviceDomainBandValue', () {
    test('a band announces its size and nothing else', () {
      // It used to carry the offline services too, because a folded band was a
      // strip of bare glyphs and an unlit tile says nothing to a screen reader.
      // The compact cards that replaced the strip are labelled nodes of their
      // own, so repeating it here would say "Lidarr isn't answering" twice on
      // the way into the band.
      expect(serviceDomainBandValue(serviceCount: 6), '6 services');
    });

    test('agrees in number', () {
      expect(serviceDomainBandValue(serviceCount: 1), '1 service');
    });
  });

  group('servicesDismissMoreServicesLabel', () {
    test('names what it dismisses, not the gesture', () {
      // A bare "Dismiss" on a row whose sibling is "Set up 8 more services"
      // leaves the user to guess which of the two the button acts on.
      expect(
        servicesDismissMoreServicesLabel(count: 8),
        'Dismiss the 8 remaining services hint',
      );
    });
  });

  group('servicesSectionOfflineMessage', () {
    test('shares the band sentence but names fewer sources', () {
      // It sits in a 176pt rail as a footnote to a band the user has already
      // scrolled past, not across the full width as the primary warning.
      expect(
        servicesSectionOfflineMessage(const ['Radarr', 'Sonarr', 'Lidarr']),
        "Radarr, Sonarr and 1 other aren't answering",
      );
    });
  });

  group('servicesAlertBandMessage', () {
    test('a single offender gets a singular verb', () {
      expect(servicesAlertBandMessage(['Dockge']), "Dockge isn't answering");
    });

    test('two are joined with "and", not a trailing comma', () {
      expect(
        servicesAlertBandMessage(['Dockge', 'TrueNAS']),
        "Dockge and TrueNAS aren't answering",
      );
    });

    test('three are listed in full', () {
      expect(
        servicesAlertBandMessage(['Dockge', 'TrueNAS', 'Unraid']),
        "Dockge, TrueNAS and Unraid aren't answering",
      );
    });

    test('more than three fold into "and n others"', () {
      expect(
        servicesAlertBandMessage([
          'Dockge',
          'TrueNAS',
          'Unraid',
          'Bazarr',
          'Prowlarr',
        ]),
        "Dockge, TrueNAS, Unraid and 2 others aren't answering",
      );
    });

    test('exactly one hidden offender is singular', () {
      expect(
        servicesAlertBandMessage(['Dockge', 'TrueNAS', 'Unraid', 'Bazarr']),
        "Dockge, TrueNAS, Unraid and 1 other aren't answering",
      );
    });

    test('an empty list produces no sentence at all', () {
      // The band renders nothing in this state; a stray "aren't answering"
      // would be worse than silence.
      expect(servicesAlertBandMessage([]), isEmpty);
      expect(servicesAlertBandMessage(['', '   ']), isEmpty);
    });
  });

  group('seerrRequestRowValue', () {
    test('names the requester instead of leaving a bare handle', () {
      expect(
        seerrRequestRowValue(
          mediaTypeLabel: 'Movie',
          requester: 'sarah',
          statusLabel: 'Available',
        ),
        'Movie, requested by sarah, Available',
      );
    });
  });
}

import 'package:flutter/material.dart' show Icons, ThemeMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/settings/domain/nav_tab.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

void main() {
  group('SettingsModel.urlFor', () {
    const settings = SettingsModel(
      seerrUrl: 'https://jelly.example.com',
      radarrUrl: 'https://radarr.example.com',
      sonarrUrl: 'https://sonarr.example.com',
      lidarrUrl: 'https://lidarr.example.com',
      bazarrUrl: 'https://bazarr.example.com',
    );

    test('returns correct URL for each ServiceKey', () {
      expect(settings.urlFor(ServiceKey.seerr), 'https://jelly.example.com');
      expect(settings.urlFor(ServiceKey.radarr), 'https://radarr.example.com');
      expect(settings.urlFor(ServiceKey.sonarr), 'https://sonarr.example.com');
      expect(settings.urlFor(ServiceKey.lidarr), 'https://lidarr.example.com');
      expect(settings.urlFor(ServiceKey.bazarr), 'https://bazarr.example.com');
    });
  });

  group('SettingsModel.apiKeyFor', () {
    const settings = SettingsModel(
      seerrApiKey: 'jkey',
      radarrApiKey: 'rkey',
      sonarrApiKey: 'skey',
      lidarrApiKey: 'lkey',
      bazarrApiKey: 'bkey',
    );

    test('returns correct API key for each ServiceKey', () {
      expect(settings.apiKeyFor(ServiceKey.seerr), 'jkey');
      expect(settings.apiKeyFor(ServiceKey.radarr), 'rkey');
      expect(settings.apiKeyFor(ServiceKey.sonarr), 'skey');
      expect(settings.apiKeyFor(ServiceKey.lidarr), 'lkey');
      expect(settings.apiKeyFor(ServiceKey.bazarr), 'bkey');
    });
  });

  // The three-way "is it qBittorrent, Dockge or NZBGet" check used to be spelled
  // out in five files. Adding a credential-authenticated service therefore meant
  // finding all five by hand, and missing one left persistence and the settings
  // form disagreeing about which fields the service even has. These lock the
  // answer to the registry capability instead.
  group('the credential model comes from the registry', () {
    const credentials = SettingsModel(
      qbittorrentUsername: 'qb-user',
      qbittorrentPassword: 'qb-pass',
      dockgeUsername: 'dockge-user',
      dockgePassword: 'dockge-pass',
      nzbgetUsername: 'nzbget-user',
      nzbgetPassword: 'nzbget-pass',
      radarrApiKey: 'radarr-key',
    );

    test('usernameFor and passwordFor answer exactly for !usesApiKey', () {
      for (final service in ServiceKey.values) {
        if (service.usesApiKey) {
          expect(
            credentials.usernameFor(service),
            isEmpty,
            reason: '${service.name} authenticates with a key, not a login',
          );
          expect(credentials.passwordFor(service), isEmpty);
        }
      }

      expect(credentials.usernameFor(ServiceKey.qbittorrent), 'qb-user');
      expect(credentials.passwordFor(ServiceKey.qbittorrent), 'qb-pass');
      expect(credentials.usernameFor(ServiceKey.dockge), 'dockge-user');
      expect(credentials.passwordFor(ServiceKey.dockge), 'dockge-pass');
      expect(credentials.usernameFor(ServiceKey.nzbget), 'nzbget-user');
      expect(credentials.passwordFor(ServiceKey.nzbget), 'nzbget-pass');
    });

    test('a credential service counts as configured on its URL alone', () {
      // Some can legitimately run with no auth behind a reverse proxy, so a
      // missing password is not a missing configuration.
      const urlOnly = SettingsModel(
        qbittorrentUrl: 'https://qb.lan:8080',
        radarrUrl: 'https://radarr.lan:7878',
      );

      expect(urlOnly.isServiceConfigured(ServiceKey.qbittorrent), isTrue);
      // An API-key service still needs both halves.
      expect(urlOnly.isServiceConfigured(ServiceKey.radarr), isFalse);
    });
  });

  group('SettingsModel.copyWithoutServiceExtras', () {
    test('removing Jellyfin drops the chosen viewer with it', () {
      // `jellyfinUserId` sits outside the per-service {url, apiKey} map, so
      // `copyWithService` cannot reach it. Left behind, re-adding a *different*
      // Jellyfin binds every per-viewer query to a user id that server has
      // never heard of, and the picker shows nothing selected.
      const settings = SettingsModel(
        jellyfinUrl: 'https://jelly.lan:8096',
        jellyfinApiKey: 'jf-key',
        jellyfinUserId: 'a1b2c3',
      );

      final cleared = settings
          .copyWithService(ServiceKey.jellyfin, url: '', apiKey: '')
          .copyWithoutServiceExtras(ServiceKey.jellyfin);

      expect(cleared.jellyfinUserId, isEmpty);
    });

    test('the Plex client id survives, because it is not per-server', () {
      // It identifies this install, is minted exactly once, and a new value
      // registers another device row on the user's server.
      const settings = SettingsModel(
        plexUrl: 'https://plex.lan:32400',
        plexToken: 'token',
        plexClientId: 'minted-once',
      );

      final cleared = settings
          .copyWithService(ServiceKey.plex, url: '', apiKey: '')
          .copyWithoutServiceExtras(ServiceKey.plex);

      expect(cleared.plexClientId, 'minted-once');
    });

    test('a service with no extras is returned untouched', () {
      const settings = SettingsModel(jellyfinUserId: 'a1b2c3');

      expect(
        settings.copyWithoutServiceExtras(ServiceKey.radarr).jellyfinUserId,
        'a1b2c3',
      );
    });
  });

  group('SettingsModel.copyWithoutUnusedCertificate', () {
    const fingerprint = 'aa:bb';

    test('forgets a pin nothing configured reaches any more', () {
      // Without this the entry outlives the address, and because pins are keyed
      // purely by origin, any service later pointed back there would silently
      // reuse the stale trust with no prompt.
      final settings = const SettingsModel()
          .copyWithService(
            ServiceKey.sonarr,
            url: 'https://nas.lan:8989',
            apiKey: 'k',
          )
          .copyWithTrustedCertificate(
            url: 'https://nas.lan:8989',
            fingerprint: fingerprint,
          );

      final moved = settings
          .copyWithService(
            ServiceKey.sonarr,
            url: 'https://elsewhere.lan:8989',
            apiKey: 'k',
          )
          .copyWithoutUnusedCertificate('https://nas.lan:8989');

      expect(moved.pinForUrl('https://nas.lan:8989'), isNull);
    });

    test('keeps a pin another configured service still shares', () {
      // Removing Sonarr must never break Radarr's trust in the same proxy.
      final settings = const SettingsModel()
          .copyWithService(
            ServiceKey.sonarr,
            url: 'https://nas.lan:443',
            apiKey: 'k',
          )
          .copyWithService(
            ServiceKey.radarr,
            url: 'https://nas.lan:443',
            apiKey: 'k',
          )
          .copyWithTrustedCertificate(
            url: 'https://nas.lan:443',
            fingerprint: fingerprint,
          );

      final removed = settings
          .copyWithService(ServiceKey.sonarr, url: '', apiKey: '')
          .copyWithoutUnusedCertificate('https://nas.lan:443');

      expect(removed.pinForUrl('https://nas.lan:443'), fingerprint);
    });

    test('an empty prior URL is a no-op', () {
      final settings = const SettingsModel().copyWithTrustedCertificate(
        url: 'https://nas.lan:443',
        fingerprint: fingerprint,
      );

      expect(
        settings.copyWithoutUnusedCertificate('').trustedCertificates,
        settings.trustedCertificates,
      );
    });
  });

  group('SettingsModel.copyWithService', () {
    const base = SettingsModel();

    test('updates only the targeted service URL and API key', () {
      final updated = base.copyWithService(
        ServiceKey.radarr,
        url: 'https://new.radarr',
        apiKey: 'new-key',
      );

      expect(updated.radarrUrl, 'https://new.radarr');
      expect(updated.radarrApiKey, 'new-key');
      expect(updated.seerrUrl, '');
      expect(updated.sonarrUrl, '');
      expect(updated.lidarrUrl, '');
    });

    test('partial update only changes provided fields', () {
      final updated = base.copyWithService(
        ServiceKey.sonarr,
        url: 'https://sonarr.local',
      );

      expect(updated.sonarrUrl, 'https://sonarr.local');
      expect(updated.sonarrApiKey, '');
    });

    test('updates Bazarr URL and API key through copyWithService', () {
      final updated = base.copyWithService(
        ServiceKey.bazarr,
        url: 'https://bazarr.local',
        apiKey: 'bzkey',
      );

      expect(updated.bazarrUrl, 'https://bazarr.local');
      expect(updated.bazarrApiKey, 'bzkey');
    });

    test('works for all ServiceKey values', () {
      for (final key in ServiceKey.values) {
        final updated = base.copyWithService(key, url: 'https://test');
        expect(updated.urlFor(key), 'https://test');
      }
    });
  });

  group('SettingsModel.themeMode', () {
    test('defaults to system appearance and resolves to ThemeMode.system', () {
      const settings = SettingsModel();

      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.resolvedThemeMode, ThemeMode.system);
    });

    test('resolves light and dark appearance modes', () {
      const lightSettings = SettingsModel(themeMode: AppThemeMode.light);
      const darkSettings = SettingsModel(themeMode: AppThemeMode.dark);

      expect(lightSettings.resolvedThemeMode, ThemeMode.light);
      expect(darkSettings.resolvedThemeMode, ThemeMode.dark);
    });
  });

  group('NavTab', () {
    test('matches the approved four-tab navigation model', () {
      expect(NavTab.values, [
        NavTab.services,
        NavTab.activity,
        NavTab.search,
        NavTab.settings,
      ]);
      expect(NavTab.values.map((tab) => tab.label), [
        'Services',
        'Activity',
        'Search',
        'Settings',
      ]);
      // Each tab carries its own section accent — sections, not services, per
      // DESIGN.md's nav-* tokens. Services keeps `primary`: it is the app's
      // own colour and the home tab. Asserted against the tokens rather than
      // hex literals so a palette change does not need a test edit.
      expect(NavTab.values.map((tab) => tab.accentColor), [
        AppColors.navServices,
        AppColors.navActivity,
        AppColors.navSearch,
        AppColors.navSettings,
      ]);
      expect(NavTab.services.accentColor, AppColors.primary);
    });
  });

  group('ServiceKey.routeParam', () {
    test('uses stable route params including the Seerr rename', () {
      expect(ServiceKey.seerr.routeParam, 'seerr');
      expect(ServiceKey.radarr.routeParam, 'radarr');
      expect(ServiceKey.sonarr.routeParam, 'sonarr');
      expect(ServiceKey.lidarr.routeParam, 'lidarr');
      expect(ServiceKey.bazarr.routeParam, 'bazarr');
    });
  });

  group('ServiceKey metadata', () {
    test('exposes prototype accent colors and icons', () {
      expect(ServiceKey.seerr.accent.toARGB32(), 0xFF6366F1);
      expect(ServiceKey.radarr.accent.toARGB32(), 0xFFF59E0B);
      expect(ServiceKey.sonarr.accent.toARGB32(), 0xFF8B5CF6);
      expect(ServiceKey.lidarr.accent.toARGB32(), 0xFFEC4899);
      expect(ServiceKey.bazarr.accent.toARGB32(), 0xFF25A7DF);
      expect(ServiceKey.seerr.icon, Icons.search_rounded);
      expect(ServiceKey.radarr.icon, Icons.movie_rounded);
      expect(ServiceKey.sonarr.icon, Icons.tv_rounded);
      expect(ServiceKey.lidarr.icon, Icons.music_note_rounded);
      expect(ServiceKey.bazarr.icon, Icons.subtitles_rounded);
    });

    test('maps API versions per service', () {
      expect(ServiceKey.seerr.apiVersion, 'v1');
      expect(ServiceKey.radarr.apiVersion, 'v3');
      expect(ServiceKey.sonarr.apiVersion, 'v3');
      expect(ServiceKey.lidarr.apiVersion, 'v1');
      expect(ServiceKey.bazarr.apiVersion, 'v1');
    });

    test('maps summary item labels per service', () {
      expect(ServiceKey.seerr.itemLabel, 'requests');
      expect(ServiceKey.radarr.itemLabel, 'movies');
      expect(ServiceKey.sonarr.itemLabel, 'series');
      expect(ServiceKey.lidarr.itemLabel, 'artists');
      expect(ServiceKey.bazarr.itemLabel, 'subtitles');
    });

    test('includes Bazarr in global search but not manual import flows', () {
      expect(ServiceKey.bazarr.isSearchable, isTrue);
      expect(ServiceKey.bazarr.supportsManualImport, isFalse);
      expect(ServiceKey.bazarr.usesApiKey, isTrue);
      expect(
        ServiceKey.values.where((s) => s.isSearchable),
        containsAll([
          ServiceKey.seerr,
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.lidarr,
          ServiceKey.bazarr,
        ]),
        reason: 'Bazarr joins Seerr/*arr as a searchable service',
      );
      expect(
        ServiceKey.values.where((s) => s.isSearchable),
        isNot(contains(ServiceKey.qbittorrent)),
      );
      expect(
        ServiceKey.values.where((s) => s.isSearchable),
        isNot(contains(ServiceKey.truenas)),
      );
    });

    test('extracts host labels with ports for service cards', () {
      expect(
        ServiceKey.radarr.extractHost('http://radarr.local:7878'),
        'radarr.local:7878',
      );
      expect(
        ServiceKey.seerr.extractHost('seerr.local:5055'),
        'seerr.local:5055',
      );
      expect(
        ServiceKey.sonarr.extractHost('sonarr.local:8989/api?token=secret'),
        'sonarr.local:8989',
      );
      expect(ServiceKey.lidarr.extractHost(''), isNull);
      expect(
        ServiceKey.bazarr.extractHost('http://bazarr.local:6767'),
        'bazarr.local:6767',
      );
    });
  });
}

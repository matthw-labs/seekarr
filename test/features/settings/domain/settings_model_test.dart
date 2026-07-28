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
      // The app shell is a single colour: per-service accents belong to service
      // surfaces, not to the nav bar. Asserted against the token rather than a
      // hex literal so a palette change does not need a test edit.
      expect(
        NavTab.values.map((tab) => tab.accentColor),
        everyElement(AppColors.primary),
      );
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

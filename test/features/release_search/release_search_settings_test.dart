import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:seekarr/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> container() async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('defaults match the constants the feature ships with', () async {
    final c = await container();
    final settings = c.read(releaseSearchSettingsProvider);

    expect(settings.concurrency, kDefaultSearchConcurrency);
    expect(settings.timeout, kReleaseSearchReceiveTimeout);
  });

  test('the timeout can never reach the transport ceiling', () {
    // The background library's iOS request timeout is fixed at startup, and a
    // user-facing value that met it would give two different failures the same
    // elapsed — which is the ambiguity the verdicts exist to remove.
    expect(
      ReleaseSearchSettings.maxTimeout,
      lessThan(const Duration(minutes: 15)),
    );
    // Still above every common gateway ceiling, which is what keeps a timeout
    // attributable.
    expect(
      ReleaseSearchSettings.maxTimeout,
      greaterThan(const Duration(seconds: 100)),
    );
  });

  test('concurrency clamps to the courteous range', () async {
    final c = await container();
    final notifier = c.read(releaseSearchSettingsProvider.notifier);

    notifier.setConcurrency(99);
    expect(
      c.read(releaseSearchSettingsProvider).concurrency,
      ReleaseSearchSettings.maxConcurrency,
    );

    notifier.setConcurrency(0);
    expect(
      c.read(releaseSearchSettingsProvider).concurrency,
      ReleaseSearchSettings.minConcurrency,
    );
  });

  test('the timeout clamps at both ends', () async {
    final c = await container();
    final notifier = c.read(releaseSearchSettingsProvider.notifier);

    notifier.setTimeoutMinutes(600);
    expect(
      c.read(releaseSearchSettingsProvider).timeout,
      ReleaseSearchSettings.maxTimeout,
    );

    notifier.setTimeoutMinutes(0);
    expect(
      c.read(releaseSearchSettingsProvider).timeout,
      ReleaseSearchSettings.minTimeout,
    );
  });

  test('both values survive a restart', () async {
    final first = await container();
    first.read(releaseSearchSettingsProvider.notifier).setConcurrency(4);
    first.read(releaseSearchSettingsProvider.notifier).setTimeoutMinutes(8);

    // A fresh container over the same prefs is what a cold start looks like.
    final prefs = await SharedPreferences.getInstance();
    final second = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);

    final settings = second.read(releaseSearchSettingsProvider);
    expect(settings.concurrency, 4);
    expect(settings.timeout, const Duration(minutes: 8));
  });

  test('it still resolves where SharedPreferences was never provided', () {
    // Widget tests routinely omit it; the screen must render rather than throw.
    final bare = ProviderContainer();
    addTearDown(bare.dispose);

    expect(
      bare.read(releaseSearchSettingsProvider).concurrency,
      kDefaultSearchConcurrency,
    );
  });
}

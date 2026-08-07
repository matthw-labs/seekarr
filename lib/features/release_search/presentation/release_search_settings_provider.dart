import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// How long Cupola waits for a release search, and how many it runs at once.
///
/// Persisted, because both are statements about the user's own stack rather than
/// about this visit: an instance behind a slow proxy wants a different ceiling
/// every time, not once.
class ReleaseSearchSettings {
  const ReleaseSearchSettings({
    required this.concurrency,
    required this.timeout,
    this.notifyOnFinish = false,
  });

  final int concurrency;
  final Duration timeout;

  /// Off until the user asks for it. Turning it on is also the only moment
  /// notification permission is requested — asking at launch, before they have
  /// expressed any interest, is exactly the pattern this avoids.
  final bool notifyOnFinish;

  /// Lowest and highest the user may set.
  ///
  /// The timeout stops at **ten** minutes rather than fifteen on purpose: the
  /// background library's own iOS ceiling is fifteen and is fixed at startup, so
  /// letting the user reach it would let the two meet — and a timeout that
  /// coincides with the transport's own gives two different failures the same
  /// elapsed, which is exactly the ambiguity the verdicts exist to remove.
  static const minConcurrency = 1;
  static const maxConcurrency = 4;
  static const minTimeout = Duration(minutes: 1);
  static const maxTimeout = Duration(minutes: 10);
}

final releaseSearchSettingsProvider =
    NotifierProvider<ReleaseSearchSettingsNotifier, ReleaseSearchSettings>(
      ReleaseSearchSettingsNotifier.new,
    );

class ReleaseSearchSettingsNotifier extends Notifier<ReleaseSearchSettings> {
  static const _concurrencyKey = 'release_search_concurrency';
  static const _timeoutKey = 'release_search_timeout_minutes';
  static const _notifyKey = 'release_search_notify';

  @override
  ReleaseSearchSettings build() {
    // Guarded the way every other persisted notifier here is, so a widget test
    // that never provided SharedPreferences still renders.
    try {
      final prefs = ref.watch(sharedPreferencesProvider);
      return ReleaseSearchSettings(
        concurrency: prefs.getInt(_concurrencyKey) ?? kDefaultSearchConcurrency,
        timeout: Duration(
          minutes:
              prefs.getInt(_timeoutKey) ??
              kReleaseSearchReceiveTimeout.inMinutes,
        ),
        notifyOnFinish: prefs.getBool(_notifyKey) ?? false,
      );
    } catch (_) {
      return ReleaseSearchSettings(
        concurrency: kDefaultSearchConcurrency,
        timeout: kReleaseSearchReceiveTimeout,
      );
    }
  }

  void setConcurrency(int value) {
    final clamped = value.clamp(
      ReleaseSearchSettings.minConcurrency,
      ReleaseSearchSettings.maxConcurrency,
    );
    state = ReleaseSearchSettings(
      concurrency: clamped,
      timeout: state.timeout,
      notifyOnFinish: state.notifyOnFinish,
    );
    _persistInt(_concurrencyKey, clamped);
  }

  void setTimeoutMinutes(int minutes) {
    final clamped = minutes.clamp(
      ReleaseSearchSettings.minTimeout.inMinutes,
      ReleaseSearchSettings.maxTimeout.inMinutes,
    );
    state = ReleaseSearchSettings(
      concurrency: state.concurrency,
      timeout: Duration(minutes: clamped),
      notifyOnFinish: state.notifyOnFinish,
    );
    _persistInt(_timeoutKey, clamped);
  }

  /// Records the user's choice. The caller asks the OS *first* and passes what
  /// it answered, so a denied permission never leaves the toggle claiming to be
  /// on.
  void setNotifyOnFinish(bool value) {
    state = ReleaseSearchSettings(
      concurrency: state.concurrency,
      timeout: state.timeout,
      notifyOnFinish: value,
    );
    try {
      ref.read(sharedPreferencesProvider).setBool(_notifyKey, value);
    } catch (_) {
      // Nothing to persist to; the session still honours the choice.
    }
  }

  void _persistInt(String key, int value) {
    try {
      ref.read(sharedPreferencesProvider).setInt(key, value);
    } catch (_) {
      // Nothing to persist to; the in-memory value still applies this session.
    }
  }
}

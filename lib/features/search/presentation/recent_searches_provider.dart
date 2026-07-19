import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/settings/data/settings_provider.dart';

/// Persisted list of recent search queries (most recent first), backed by
/// SharedPreferences. Shown as quick chips on the search empty state.
final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
      RecentSearchesNotifier.new,
    );

class RecentSearchesNotifier extends Notifier<List<String>> {
  static const _key = 'recent_searches';
  static const _maxEntries = 8;

  @override
  List<String> build() {
    // Guarded so screens still render if SharedPreferences isn't provided
    // (e.g. lightweight widget/router tests).
    try {
      return ref.watch(sharedPreferencesProvider).getStringList(_key) ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  /// Records a query at the front of the list (deduped, capped).
  void add(String query) {
    final trimmed = query.trim();
    if (trimmed.length < 2) return;
    final next = [
      trimmed,
      ...state.where((q) => q.toLowerCase() != trimmed.toLowerCase()),
    ].take(_maxEntries).toList(growable: false);
    _persist(next);
  }

  void remove(String query) {
    _persist(state.where((q) => q != query).toList(growable: false));
  }

  void clear() => _persist(const []);

  void _persist(List<String> next) {
    state = next;
    try {
      ref.read(sharedPreferencesProvider).setStringList(_key, next);
    } catch (_) {
      // No persistence available (tests) — in-memory state still updates.
    }
  }
}

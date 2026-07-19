import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:seekarr/features/settings/data/settings_provider.dart';

/// Initial onboarding-complete value loaded from SharedPreferences before
/// the app starts. Must be overridden in main.dart.
final initialOnboardingCompletedProvider = Provider<bool>((ref) {
  throw UnimplementedError('Initialize this in main.dart');
});

/// Reactive source of truth for whether the user has finished onboarding.
///
/// Seeded from [initialOnboardingCompletedProvider] so it reflects the
/// persisted value on first build. Write `true` here after the user
/// completes onboarding to trigger the router redirect.
final onboardingCompletedProvider = StateProvider<bool>((ref) {
  return ref.watch(initialOnboardingCompletedProvider);
});

/// [ChangeNotifier] that bridges [onboardingCompletedProvider] to
/// [GoRouter.refreshListenable]. Whenever the onboarding flag flips the
/// router re-evaluates its redirect without recreating the [GoRouter].
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    ref.listen<bool>(onboardingCompletedProvider, (_, __) {
      notifyListeners();
    });
  }
}

/// Keeps [RouterRefreshNotifier] alive for the lifetime of [routerProvider].
final routerRefreshNotifierProvider = Provider<RouterRefreshNotifier>((ref) {
  return RouterRefreshNotifier(ref);
});

/// Persists the onboarding-complete flag to SharedPreferences and updates
/// [onboardingCompletedProvider] so the router redirect fires immediately.
Future<void> markOnboardingComplete(WidgetRef ref) async {
  final service = ref.read(settingsServiceProvider);
  await service.saveOnboardingComplete();
  ref.read(onboardingCompletedProvider.notifier).state = true;
}

/// Flips [onboardingCompletedProvider] to false so the router redirect sends
/// the user back to onboarding. The persisted flag is expected to already be
/// cleared (e.g. via [SettingsService.clearAll]).
Future<void> markOnboardingIncomplete(WidgetRef ref) async {
  ref.read(onboardingCompletedProvider.notifier).state = false;
}

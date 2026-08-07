import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/release_search/presentation/release_search_jobs_provider.dart';

/// Whether the app is currently in front of the user.
///
/// The rule it serves: **a finished search never interrupts.** In the foreground
/// the badge lights and the detail page updates instead of a notification taking
/// the screen away from whatever they are doing.
final appInForegroundProvider = NotifierProvider<AppForegroundNotifier, bool>(
  AppForegroundNotifier.new,
);

class AppForegroundNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  // ignore: use_setters_to_change_properties
  void set(bool value) => state = value;
}

/// Keeps the job manager honest about the app's own lifecycle.
///
/// Two jobs, and the first is the one that matters. In Phase 1 a search cannot
/// continue while the app is suspended, but it is **not** cancelled on the way
/// out either: a brief app switch on iOS, and very often Android, leaves the
/// request alive, and pre-emptively failing a search that would have come back
/// with results would be worse than the limitation it is trying to describe.
///
/// So the app records that it went away, and if the request then dies the failure
/// is attributed to the OS — "Stopped when you left Seekarr" — instead of to the
/// user's network, which is the difference between a limitation of this build and
/// a problem they should go and investigate.
///
/// On resume it re-evaluates the grab windows, because a phone can easily sit in
/// a pocket for longer than Sonarr keeps its releases.
class ReleaseSearchLifecycle extends ConsumerStatefulWidget {
  const ReleaseSearchLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReleaseSearchLifecycle> createState() =>
      _ReleaseSearchLifecycleState();
}

class _ReleaseSearchLifecycleState extends ConsumerState<ReleaseSearchLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final notifier = ref.read(releaseSearchJobsProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        ref.read(appInForegroundProvider.notifier).set(false);
        notifier.noteBackgrounded();
      case AppLifecycleState.resumed:
        ref.read(appInForegroundProvider.notifier).set(true);
        notifier.refreshWindows();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

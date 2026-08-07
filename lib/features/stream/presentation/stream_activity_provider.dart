import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:seekarr/features/plex/presentation/plex_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';

/// One playback plus which server is serving it.
///
/// The pairing is the point: `/activity` merges sources, so a row has to be able
/// to say where it came from — the same problem the Recently Added rail solves
/// with an accent dot and a spoken `accentLabel`.
typedef StreamActivityRow = ({ServiceKey service, StreamSession session});

/// Every live playback across both media servers, most expensive first.
///
/// **Deliberately not a `GlobalActivityItem`, and this is the load-bearing
/// decision on this surface.** Forcing a session into that model needs a
/// `ServiceType`, which is a closed `{movies, series, music, discover}` with no
/// legal value for a media server — and adding one breaks **21 exhaustive
/// switches** across the activity feature, plus 6 more on `GlobalActivityKind`,
/// two of which have `_ =>` fallbacks that would silently mis-route a session row
/// instead of failing to compile. A playing session is also genuinely a different
/// record: it has a person, a device and a delivery method, and none of the queue
/// affordances (retry, blocklist, change category) mean anything for it.
///
/// So the Streaming sub-segment carries its own type end to end. That is why
/// `_ActivitySub.custom` exists.
///
/// Sources degrade independently: an unreachable Jellyfin yields no rows rather
/// than emptying the section, which is the project's read-path convention.
/// [streamActivityOfflineProvider] is what lets the UI name the source that went
/// dark instead of implying nobody is watching.
final streamActivityProvider = FutureProvider<List<StreamActivityRow>>((
  ref,
) async {
  final rows = <StreamActivityRow>[];

  for (final service in ServiceDomain.stream.services) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(service)) {
      continue;
    }
    try {
      final sessions = await switch (service) {
        ServiceKey.jellyfin => ref.watch(jellyfinSessionsProvider.future),
        _ => ref.watch(plexSessionsProvider.future),
      };
      rows.addAll(
        sessions.map((session) => (service: service, session: session)),
      );
    } catch (_) {
      // Reported through streamActivityOfflineProvider rather than thrown: one
      // dark server must not hide the other's sessions.
    }
  }

  // Transcodes first — the rows that are costing the box something are the rows
  // worth reading first, and the per-service order underneath has to stay stable
  // so a bitrate updating in place does not reshuffle the list.
  //
  // Decorated with the source index because `List.sort` is *not* guaranteed
  // stable: Dart insertion-sorts 32 elements or fewer and dual-pivot quicksorts
  // above that, so a cost-only comparator can hand back two direct plays in a
  // different order on each poll. Same pattern, and the same reason, as
  // `servicesQueueProvider`.
  final ordered =
      List.generate(
        rows.length,
        (index) => (index: index, row: rows[index]),
        growable: false,
      )..sort((a, b) {
        final aCost = a.row.session.playMethod.isTranscode ? 0 : 1;
        final bCost = b.row.session.playMethod.isTranscode ? 0 : 1;
        final byCost = aCost.compareTo(bCost);
        if (byCost != 0) return byCost;
        return a.index.compareTo(b.index);
      });

  return ordered.map((entry) => entry.row).toList(growable: false);
});

/// Configured media servers that did not answer.
///
/// Separate from [streamActivityProvider] for the reason
/// `servicesSectionOfflineMessage` documents: sources that degrade to `[]` make
/// "nobody is watching" and "the server is down" arrive identically, which sends
/// the user looking for the wrong thing. Naming which source is dark is what makes
/// a merged section safe.
final streamActivityOfflineProvider = FutureProvider<List<ServiceKey>>((
  ref,
) async {
  final offline = <ServiceKey>[];

  for (final service in ServiceDomain.stream.services) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(service)) {
      continue;
    }
    try {
      await switch (service) {
        ServiceKey.jellyfin => ref.watch(jellyfinSessionsProvider.future),
        _ => ref.watch(plexSessionsProvider.future),
      };
    } catch (_) {
      offline.add(service);
    }
  }

  return offline;
});

/// Whether any media server is configured at all.
///
/// The Streaming sub-segment is offered unconditionally — hiding a whole record
/// type because nothing is set up yet would make the feature undiscoverable — so
/// the body needs this to tell "not set up" from "nobody watching".
final hasStreamServiceProvider = Provider<bool>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  return ServiceDomain.stream.services.any(settings.isServiceConfigured);
});

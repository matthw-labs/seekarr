import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// The external ids an arr can offer for one title.
///
/// A record so the family key gets structural equality for free. At least one
/// field must be non-null or the lookup is skipped — matching on a title would be
/// a guess, and this exists to state a fact.
typedef StreamLookupKey = ({String? tmdbId, String? tvdbId, String? imdbId});

/// Where a title sits on a media server, if it is there at all.
typedef StreamMatch = ({ServiceKey service, StreamItem item});

/// Whether an arr's title is on a media server, and how far into it the viewer is.
///
/// **This is the answer to the duplicate-catalogue problem, and it is deliberately
/// a decoration rather than a second search source.** Adding Jellyfin and Plex as
/// their own global-search groups would make one film return in up to six
/// sections: Radarr and Sonarr "search" is a TMDB/TVDB *lookup*, not a library
/// search, so "Dune" already produces four. Instead the Stream fact rides on the
/// arr row that is already there — the same move `ArrMediaExtrasSection` makes for
/// Seerr data inside an arr screen.
///
/// The first server that has it wins. Two media servers indexing the same file is
/// a real setup, but "it is watchable, and you are 34 minutes in" is one fact, and
/// showing it twice would be noise rather than information.
final streamMatchProvider = FutureProvider.autoDispose
    .family<StreamMatch?, StreamLookupKey>((ref, key) async {
      if ((key.tmdbId ?? '').isEmpty &&
          (key.tvdbId ?? '').isEmpty &&
          (key.imdbId ?? '').isEmpty) {
        return null;
      }

      final settings = ref.watch(currentSettingsProvider);
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);

      for (final service in ServiceDomain.stream.services) {
        if (!settings.isServiceConfigured(service)) continue;
        try {
          final client = service == ServiceKey.jellyfin
              ? ref.watch(jellyfinServerProvider)
              : ref.watch(plexServerProvider);
          final item = await client.findByExternalId(
            tmdbId: key.tmdbId,
            tvdbId: key.tvdbId,
            imdbId: key.imdbId,
            cancelToken: cancelToken,
          );
          if (item != null) return (service: service, item: item);
        } catch (_) {
          // An unreachable server is not evidence the title is missing, so it
          // yields nothing and the next one is tried. The section renders nothing
          // when none of them answer — silence beats "not on your server" when the
          // truth is "we could not ask".
          continue;
        }
      }
      return null;
    });

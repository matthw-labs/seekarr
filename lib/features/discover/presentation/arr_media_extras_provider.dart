import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';
import 'package:seekarr/features/discover/presentation/discover_detail_view_model.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';

/// Cast + collection for an *arr library item, sourced from TMDB via Seerr.
typedef ArrMediaExtras = ({
  List<DiscoverCastMember> cast,
  CollectionInfo? collection,
});

typedef ArrMediaExtrasKey = ({int tmdbId, String mediaType});

/// Cast/collection for an *arr item's [tmdbId], or `null` when Seerr is not
/// configured — letting the UI prompt the user to connect Seerr. Reuses the
/// Discover detail parser so cast (with person ids) and collection come for
/// free.
final arrMediaExtrasProvider = FutureProvider.autoDispose
    .family<ArrMediaExtras?, ArrMediaExtrasKey>((ref, key) async {
      final settings = ref.watch(currentSettingsProvider);
      if (settings.seerrUrl.isEmpty || settings.seerrApiKey.isEmpty) {
        return null;
      }
      if (key.tmdbId <= 0) {
        return (cast: const <DiscoverCastMember>[], collection: null);
      }
      try {
        final service = ref.read(seerrServiceProvider);
        final data = key.mediaType == 'tv'
            ? await service.getTv(key.tmdbId)
            : await service.getMovie(key.tmdbId);
        final viewModel = DiscoverDetailViewModel.fromResponse(data);
        return (cast: viewModel.cast, collection: viewModel.collection);
      } catch (_) {
        return (cast: const <DiscoverCastMember>[], collection: null);
      }
    });

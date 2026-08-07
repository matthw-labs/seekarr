import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/person_detail.dart';

final discoverDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({int id, String type})>((ref, arg) async {
      final service = ref.watch(seerrServiceProvider);
      if (arg.type == 'movie') {
        return service.getMovie(arg.id);
      } else {
        return service.getTv(arg.id);
      }
    });

/// Person (cast/crew) details for the Person page.
final personDetailProvider = FutureProvider.autoDispose
    .family<PersonDetail, int>((ref, id) async {
      final service = ref.watch(seerrServiceProvider);
      return PersonDetail.fromJson(await service.getPerson(id));
    });

/// A person's combined filmography for the Person page.
final personCreditsProvider = FutureProvider.autoDispose
    .family<List<MediaPreview>, int>((ref, id) async {
      final service = ref.watch(seerrServiceProvider);
      return service.getPersonCombinedCredits(id);
    });

/// Full collection (with member movies) for the Collection page.
final collectionDetailProvider = FutureProvider.autoDispose
    .family<CollectionDetail, int>((ref, id) async {
      final service = ref.watch(seerrServiceProvider);
      return CollectionDetail.fromJson(await service.getCollection(id));
    });

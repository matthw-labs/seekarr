import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/person_detail.dart';

void main() {
  group('PersonDetail.fromJson', () {
    test('parses camelCase and snake_case fields', () {
      final person = PersonDetail.fromJson(const {
        'id': 287,
        'name': 'Brad Pitt',
        'biography': 'An actor.',
        'profilePath': '/pit.jpg',
        'knownForDepartment': 'Acting',
        'birthday': '1963-12-18',
        'place_of_birth': 'Shawnee, Oklahoma',
      });

      expect(person.id, 287);
      expect(person.name, 'Brad Pitt');
      expect(person.biography, 'An actor.');
      expect(person.profilePath, '/pit.jpg');
      expect(person.knownForDepartment, 'Acting');
      expect(person.birthday, '1963-12-18');
      expect(person.placeOfBirth, 'Shawnee, Oklahoma');
      expect(person.isEmpty, isFalse);
    });

    test('is empty for an error/empty payload', () {
      expect(PersonDetail.fromJson(const {}).isEmpty, isTrue);
    });
  });

  group('CollectionDetail.fromJson', () {
    test('parses metadata and maps parts to movie previews', () {
      final collection = CollectionDetail.fromJson(const {
        'id': 10,
        'name': 'The Matrix Collection',
        'overview': 'Neo.',
        'backdropPath': '/bd.jpg',
        'parts': [
          {'id': 603, 'title': 'The Matrix', 'posterPath': '/m1.jpg'},
          {'id': 604, 'title': 'The Matrix Reloaded'},
        ],
      });

      expect(collection.id, 10);
      expect(collection.name, 'The Matrix Collection');
      expect(collection.overview, 'Neo.');
      expect(collection.backdropPath, '/bd.jpg');
      expect(collection.parts, hasLength(2));
      expect(collection.parts.first.title, 'The Matrix');
      // Parts are forced to the movie media type for routing.
      expect(collection.parts.first.mediaType, 'movie');
      expect(collection.isEmpty, isFalse);
    });

    test('is empty for an error/empty payload', () {
      expect(CollectionDetail.fromJson(const {}).isEmpty, isTrue);
    });
  });
}

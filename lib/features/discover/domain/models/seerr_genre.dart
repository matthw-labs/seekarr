/// A TMDB/Seerr genre used to build per-genre discover rows.
class SeerrGenre {
  final int id;
  final String name;

  const SeerrGenre({required this.id, required this.name});

  factory SeerrGenre.fromJson(Map<String, dynamic> json) {
    return SeerrGenre(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
    );
  }
}

/// A TMDB person as returned by Overseerr/Jellyseerr `/person/{id}`.
class PersonDetail {
  final int id;
  final String name;
  final String? biography;
  final String? profilePath;
  final String? knownForDepartment;
  final String? birthday;
  final String? deathday;
  final String? placeOfBirth;

  const PersonDetail({
    required this.id,
    required this.name,
    this.biography,
    this.profilePath,
    this.knownForDepartment,
    this.birthday,
    this.deathday,
    this.placeOfBirth,
  });

  factory PersonDetail.fromJson(Map<String, dynamic> json) {
    return PersonDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      biography: json['biography']?.toString(),
      profilePath:
          json['profilePath']?.toString() ?? json['profile_path']?.toString(),
      knownForDepartment:
          json['knownForDepartment']?.toString() ??
          json['known_for_department']?.toString(),
      birthday: json['birthday']?.toString(),
      deathday: json['deathday']?.toString(),
      placeOfBirth:
          json['placeOfBirth']?.toString() ??
          json['place_of_birth']?.toString(),
    );
  }

  bool get isEmpty => id == 0 && name.isEmpty;
}

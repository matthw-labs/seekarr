/// Turns Jellyfin's `TranscodeReasons` enum values into phrases a self-hoster
/// can act on.
///
/// This is the focal moment of the whole Stream surface: both web UIs bury the
/// reason a box is burning CPU, and `StreamSession.transcodeReasons` exists to
/// put it on screen. So the strings below are deliberately *not* prettified enum
/// names — `VideoCodecNotSupported` tells you nothing you could not read off the
/// wire, whereas "Client cannot decode this video codec" names the thing the
/// user can change (the client, or the file).
///
/// Kept out of the client and free of any dependency so the mappers that call it
/// stay pure and `Isolate.run`-safe.
///
/// The list covers every `TranscodeReason` documented for 10.10 and 10.11,
/// including the flag 10.11 added (`VideoCodecTagNotSupported`). An unrecognised
/// value — a newer server, or a build with a patched enum — falls back to
/// [jellyfinHumanisedEnumName] rather than being dropped: an unexplained
/// transcode is worse than an awkwardly worded one.
library;

/// Phrase per `TranscodeReason` member, keyed by the exact enum name Jellyfin
/// serialises.
///
/// Every phrase names an actor ("Client…", "Server…") or a property ("Frame
/// rate…") and stays short enough to sit in a session row beside two or three
/// siblings, because Jellyfin routinely reports several reasons at once
/// (`AudioCodecNotSupported` + `ContainerNotSupported` is the classic Chromecast
/// pairing).
const Map<String, String> kJellyfinTranscodeReasonPhrases = {
  // Container / stream compatibility.
  'ContainerNotSupported': 'Client cannot play this container',
  'ContainerBitrateExceedsLimit': 'File bitrate is above the client limit',
  'DirectPlayError': 'Direct play failed on the client',

  // Video.
  'VideoCodecNotSupported': 'Client cannot decode this video codec',
  'VideoCodecTagNotSupported': 'Client rejects this video codec tag',
  'VideoProfileNotSupported': 'Video profile is beyond the client',
  'VideoLevelNotSupported': 'Video level is beyond the client',
  'VideoResolutionNotSupported': 'Resolution is above the client limit',
  'VideoBitDepthNotSupported': 'Colour bit depth is above the client limit',
  'VideoFramerateNotSupported': 'Frame rate is above the client limit',
  'VideoBitrateNotSupported': 'Video bitrate is above the client limit',
  'VideoRangeTypeNotSupported': 'Client cannot display this HDR format',
  'RefFramesNotSupported': 'Too many reference frames for the client',
  'AnamorphicVideoNotSupported': 'Client cannot play anamorphic video',
  'InterlacedVideoNotSupported': 'Client cannot play interlaced video',
  'UnknownVideoStreamInfo': 'Server could not read the video stream',

  // Audio.
  'AudioCodecNotSupported': 'Client cannot decode this audio codec',
  'AudioProfileNotSupported': 'Audio profile is beyond the client',
  'AudioChannelsNotSupported': 'Too many audio channels for the client',
  'AudioSampleRateNotSupported': 'Audio sample rate is above the client limit',
  'AudioBitDepthNotSupported': 'Audio bit depth is above the client limit',
  'AudioBitrateNotSupported': 'Audio bitrate is above the client limit',
  'AudioIsExternal': 'Audio track is a separate file',
  'SecondaryAudioNotSupported': 'Client cannot handle a second audio track',
  'UnknownAudioStreamInfo': 'Server could not read the audio stream',

  // Subtitles.
  'SubtitleCodecNotSupported': 'Subtitles have to be burned in',
};

/// Last-resort rendering for an enum name with no phrase: split the PascalCase
/// into words and lower-case everything after the first.
///
/// `VideoFramerateNotSupported` → `Video framerate not supported`. Ugly, but it
/// still tells the user which stream the server objected to, which is the whole
/// point of showing the reason at all.
///
/// Acronym runs keep their case: the second half of the split handles `HDRTo…`
/// and lower-casing it would turn `HDR` into `Hdr`, which reads as a typo rather
/// than as a format.
String jellyfinHumanisedEnumName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final words = trimmed
      .replaceAllMapped(
        RegExp(r'(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])'),
        (_) => ' ',
      )
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return trimmed;

  String render(String word, {required bool isFirst}) {
    if (word.length > 1 && word == word.toUpperCase()) return word;
    return isFirst
        ? word[0].toUpperCase() + word.substring(1).toLowerCase()
        : word.toLowerCase();
  }

  return [
    render(words.first, isFirst: true),
    ...words.skip(1).map((word) => render(word, isFirst: false)),
  ].join(' ');
}

/// One reason value → one phrase.
String jellyfinTranscodeReasonPhrase(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return kJellyfinTranscodeReasonPhrases[trimmed] ??
      jellyfinHumanisedEnumName(trimmed);
}

/// The whole `TranscodeReasons` field → phrases, de-duplicated, order preserved.
///
/// Accepts a `List` (what the API documents and what 10.x sends) *and* a bare
/// comma-separated `String`, which is how the field arrived in older builds and
/// how some reverse proxies still flatten a single-element array. Duplicates are
/// dropped because `VideoBitrateNotSupported` and `ContainerBitrateExceedsLimit`
/// map to distinct phrases but several video reasons can collapse onto the same
/// sentence, and repeating it reads as a rendering bug.
List<String> jellyfinTranscodeReasonPhrases(Object? raw) {
  final Iterable<String> values;
  if (raw is List) {
    values = raw.map((value) => value.toString());
  } else if (raw is String) {
    values = raw.split(',');
  } else {
    return const [];
  }

  final phrases = <String>[];
  for (final value in values) {
    final phrase = jellyfinTranscodeReasonPhrase(value);
    if (phrase.isEmpty || phrases.contains(phrase)) continue;
    phrases.add(phrase);
  }
  return List.unmodifiable(phrases);
}

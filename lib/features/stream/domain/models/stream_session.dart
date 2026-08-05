/// One playback happening right now, reduced to what the Stream board renders.
///
/// Shared by Jellyfin and Plex on purpose, and designed against **both**
/// payloads at once rather than generalised from one of them: the two servers
/// describe the same event in genuinely different shapes, and picking either as
/// the model would have smuggled that server's accidents into the widget.
///
///  * Jellyfin says `PlayMethod: DirectPlay | DirectStream | Transcode` plus a
///    `TranscodeReasons` array of up to 27 enum values.
///  * Plex says nothing so tidy: it carries a `TranscodeSession` whose
///    `videoDecision` / `audioDecision` / `subtitleDecision` are each
///    independently `directplay`, `copy` or `transcode`.
///
/// So the model keeps the *decision* as a small closed enum and the *reasons* as
/// free text supplied by whichever server produced them. Neither field is
/// derived here; both arrive resolved from the service layer, per the project's
/// rule that a widget renders a status and never computes one.
library;

import 'package:flutter/foundation.dart';

/// How the server is delivering the bytes.
///
/// Ordered least to most expensive, which is also the order the board sorts by:
/// the session that is costing the box something belongs at the top.
enum StreamPlayMethod {
  /// The file is being sent as-is. Free.
  directPlay(label: 'Direct play'),

  /// Container is being rewrapped but the video is untouched. Nearly free.
  directStream(label: 'Direct stream'),

  /// The video is being re-encoded. This is the one that costs a CPU.
  transcode(label: 'Transcode');

  const StreamPlayMethod({required this.label});

  final String label;

  bool get isTranscode => this == StreamPlayMethod.transcode;
}

@immutable
class StreamSession {
  /// Server-side id for write actions.
  ///
  /// On Jellyfin this is `SessionInfoDto.Id`; on Plex it is the nested
  /// `Session.id` — **not** `sessionKey` and not `Player.machineIdentifier`,
  /// which are two other identifiers on the same object that produce a 404 when
  /// substituted.
  final String id;

  /// Whose playback this is, for the board's "who" column.
  final String userName;

  /// What is playing, already composed for one line.
  ///
  /// For an episode this is the series name; [subtitle] carries the episode.
  final String title;

  /// Season/episode, album/track, or year — whatever disambiguates [title].
  final String? subtitle;

  /// The client doing the playing, e.g. `Infuse · iPhone` or `Chrome · Windows`.
  final String deviceLabel;

  /// Relative artwork path on the server, not a resolved URL.
  ///
  /// Resolution needs the credential, and on Plex it needs a transcode-proxy
  /// round trip, so it stays the client layer's job — a model that baked a token
  /// into a string would put it into `CachedNetworkImage`'s cache key.
  final String? posterPath;

  final StreamPlayMethod playMethod;

  /// Why the server is not sending the file untouched, in its own words.
  ///
  /// This is the one fact the whole surface exists to show: both web UIs bury it,
  /// and it is what turns "the box is busy" into something the user can act on.
  ///
  /// Empty for a [StreamPlayMethod.directPlay], and **populated for
  /// [StreamPlayMethod.directStream] as well as [StreamPlayMethod.transcode]** —
  /// a remux still has an explanation ("audio TrueHD → E-AC3 · container rewrap
  /// to MKV") and it is the only one the server offers. Gate on [needsAttention]
  /// rather than on this being empty when you mean "is this costing me a CPU".
  final List<String> transcodeReasons;

  /// Bits per second, and **nominal rather than measured** — see [bitrateIsNominal].
  final int? bitrate;

  /// Whether [bitrate] describes the file rather than the wire.
  ///
  /// Always true for a direct play: neither server reports real outbound
  /// throughput, so the only number available is the source file's own bitrate
  /// (Jellyfin) or a reservation made by Plex's streaming brain. A transcode is
  /// the one case where the figure is the encoder's actual target. The board must
  /// never sum these into a total, and must never label one as measured
  /// throughput — that claim would be fabricated.
  final bool bitrateIsNominal;

  /// Progress through the item, 0..1, or null when the server reports none.
  final double? progress;

  final bool isPaused;

  const StreamSession({
    required this.id,
    required this.userName,
    required this.title,
    required this.subtitle,
    required this.deviceLabel,
    required this.posterPath,
    required this.playMethod,
    required this.transcodeReasons,
    required this.bitrate,
    required this.bitrateIsNominal,
    required this.progress,
    required this.isPaused,
  });

  /// Whether this session is the reason you would look at the board.
  bool get needsAttention => playMethod.isTranscode;

  /// The transcode explanation as one phrase, or null when there is nothing to
  /// explain.
  ///
  /// Joined with `·` for the eye; the spoken form re-separates it, the same way
  /// `spokenFromDotted` handles every other dotted string in the app.
  String? get transcodeReasonLabel =>
      transcodeReasons.isEmpty ? null : transcodeReasons.join(' · ');
}

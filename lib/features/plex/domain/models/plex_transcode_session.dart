/// Plex's `TranscodeSession`, and the prose that turns it into an answer.
///
/// This is the focal moment of the whole Stream surface. Plex's own web app
/// shows a "Converting" badge and buries the reason two clicks deep in a
/// dashboard nobody opens; Tautulli shows the field names. Neither tells the
/// person holding the phone the one thing they can act on — *which* part of the
/// file the box is paying to rewrite, and whether it is losing the race.
///
/// Plex has no equivalent of Jellyfin's single `PlayMethod` plus enumerated
/// `TranscodeReasons`. It reports three independent decisions — video, audio,
/// subtitle — each `directplay`, `copy` or `transcode`, alongside the source and
/// target codec for each. The play method and the reason list are both *derived*
/// from those, here, so that `StreamSession` arrives at the widget already
/// resolved: the project's rule is that a widget renders a status and never
/// computes one.
library;

import 'package:flutter/foundation.dart';

import 'package:seekarr/features/plex/domain/models/plex_models.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';

/// What Plex decided to do with one stream of the file.
enum PlexStreamDecision {
  /// Sent untouched.
  directPlay,

  /// Remuxed into a different container; the encoded stream itself is copied
  /// bit-for-bit. Cheap.
  copy,

  /// Re-encoded. This is the one that costs a CPU.
  transcode,

  /// Burned into the video — subtitles only, and the most expensive subtitle
  /// outcome because it forces the video to be re-encoded too.
  burn,

  /// Plex did not say, or said something this build does not know.
  unknown;

  static PlexStreamDecision fromApi(dynamic value) {
    switch (plexString(value)?.toLowerCase()) {
      case 'directplay':
        return PlexStreamDecision.directPlay;
      case 'copy':
        return PlexStreamDecision.copy;
      case 'transcode':
        return PlexStreamDecision.transcode;
      case 'burn':
        return PlexStreamDecision.burn;
      default:
        return PlexStreamDecision.unknown;
    }
  }
}

/// Display names for the codecs Plex reports, keyed by its own lowercase ids.
///
/// A raw `hevc → h264` reads like a log line; `HEVC → H.264` reads like the spec
/// sheet the user already knows from their own files. Anything unmapped falls
/// back to the id uppercased, which is right for the long tail
/// (`ac4`, `theora`) and never wrong enough to hide the meaning.
const Map<String, String> kPlexCodecLabels = {
  'h264': 'H.264',
  'h265': 'HEVC',
  'hevc': 'HEVC',
  'av1': 'AV1',
  'vp8': 'VP8',
  'vp9': 'VP9',
  'mpeg1video': 'MPEG-1',
  'mpeg2video': 'MPEG-2',
  'mpeg4': 'MPEG-4',
  'msmpeg4v3': 'MPEG-4',
  'vc1': 'VC-1',
  'wmv3': 'WMV',
  'aac': 'AAC',
  'ac3': 'AC3',
  'eac3': 'E-AC3',
  'truehd': 'TrueHD',
  'dca': 'DTS',
  'dca-ma': 'DTS-HD MA',
  'dts': 'DTS',
  'flac': 'FLAC',
  'mp3': 'MP3',
  'opus': 'Opus',
  'vorbis': 'Vorbis',
  'pcm': 'PCM',
  'alac': 'ALAC',
};

/// Display names for the containers Plex reports.
const Map<String, String> kPlexContainerLabels = {
  'mkv': 'MKV',
  'matroska': 'MKV',
  'mp4': 'MP4',
  'mov': 'MOV',
  'avi': 'AVI',
  'mpegts': 'MPEG-TS',
  'hls': 'HLS',
  'webm': 'WebM',
  'flac': 'FLAC',
  'mp3': 'MP3',
};

String? plexCodecLabel(String? codec) {
  if (codec == null || codec.trim().isEmpty) return null;
  final key = codec.trim().toLowerCase();
  return kPlexCodecLabels[key] ?? key.toUpperCase();
}

String? plexContainerLabel(String? container) {
  if (container == null || container.trim().isEmpty) return null;
  final key = container.trim().toLowerCase();
  return kPlexContainerLabels[key] ?? key.toUpperCase();
}

@immutable
class PlexTranscodeSession {
  /// Opaque transcode key. Not a session id — terminating uses `Session.id`.
  final String? key;

  /// Plex has enough buffer and has deliberately slowed the encoder. A healthy
  /// state, and the reason [reasons] does not mention it: the board is for
  /// things the user can act on, and "comfortably ahead" is not one.
  final bool throttled;

  /// The transcode has finished producing output.
  final bool complete;

  /// 0–100.
  final double? progress;

  /// Encoder speed as a multiple of realtime. Below `1.0` the transcode is
  /// falling behind playback, which is what a buffering stream looks like from
  /// the server's side — the single most useful number on the object.
  final double? speed;

  /// Transcode duration in **milliseconds**.
  final int? durationMs;

  final PlexStreamDecision videoDecision;
  final PlexStreamDecision audioDecision;
  final PlexStreamDecision subtitleDecision;

  final String? sourceVideoCodec;
  final String? videoCodec;
  final String? sourceAudioCodec;
  final String? audioCodec;
  final String? container;

  /// Hardware encoding was asked for; [transcodeHwEncoding] says whether it
  /// happened. The pair is the actionable one: a request that silently fell back
  /// to software is why one stream flattens a box that handles four.
  final bool transcodeHwRequested;
  final bool transcodeHwEncoding;

  final String? context;

  const PlexTranscodeSession({
    required this.key,
    required this.throttled,
    required this.complete,
    required this.progress,
    required this.speed,
    required this.durationMs,
    required this.videoDecision,
    required this.audioDecision,
    required this.subtitleDecision,
    required this.sourceVideoCodec,
    required this.videoCodec,
    required this.sourceAudioCodec,
    required this.audioCodec,
    required this.container,
    required this.transcodeHwRequested,
    required this.transcodeHwEncoding,
    required this.context,
  });

  factory PlexTranscodeSession.fromJson(Map<String, dynamic> json) {
    return PlexTranscodeSession(
      key: plexString(json['key']),
      throttled: plexBool(json['throttled']) ?? false,
      complete: plexBool(json['complete']) ?? false,
      progress: plexDouble(json['progress']),
      speed: plexDouble(json['speed']),
      durationMs: plexInt(json['duration']),
      videoDecision: PlexStreamDecision.fromApi(json['videoDecision']),
      audioDecision: PlexStreamDecision.fromApi(json['audioDecision']),
      subtitleDecision: PlexStreamDecision.fromApi(json['subtitleDecision']),
      sourceVideoCodec: plexString(json['sourceVideoCodec']),
      videoCodec: plexString(json['videoCodec']),
      sourceAudioCodec: plexString(json['sourceAudioCodec']),
      audioCodec: plexString(json['audioCodec']),
      container: plexString(json['container']),
      transcodeHwRequested: plexBool(json['transcodeHwRequested']) ?? false,
      transcodeHwEncoding: plexBool(json['transcodeHwEncoding']) ?? false,
      context: plexString(json['context']),
    );
  }

  /// Reads the `TranscodeSession` embedded in a `/status/sessions` entry.
  ///
  /// Absent for a direct play, and absence is the *only* signal Plex gives for
  /// one — there is no `playMethod` field to read.
  static PlexTranscodeSession? maybeFrom(Map<String, dynamic> sessionJson) {
    final raw = sessionJson['TranscodeSession'];
    if (raw is Map) {
      return PlexTranscodeSession.fromJson(raw.cast<String, dynamic>());
    }
    // Some builds nest it as a single-element array, like every other child
    // element in Plex's JSON.
    if (raw is List) {
      final first = raw.whereType<Map>().firstOrNull;
      if (first != null) {
        return PlexTranscodeSession.fromJson(first.cast<String, dynamic>());
      }
    }
    return null;
  }

  /// How the bytes are reaching the client.
  ///
  /// `videoDecision == 'copy'` is a container rewrap with the video untouched,
  /// which is Jellyfin's `DirectStream` under another name — mapping it to
  /// `transcode` would put a nearly-free session at the top of a board sorted by
  /// cost, and mapping it to `directPlay` would hide a remux that some clients
  /// genuinely struggle with.
  StreamPlayMethod get playMethod {
    if (videoDecision == PlexStreamDecision.transcode ||
        subtitleDecision == PlexStreamDecision.burn) {
      return StreamPlayMethod.transcode;
    }
    if (videoDecision == PlexStreamDecision.copy ||
        audioDecision == PlexStreamDecision.transcode) {
      return StreamPlayMethod.directStream;
    }
    return StreamPlayMethod.directPlay;
  }

  /// The transcode explained, most expensive cause first.
  ///
  /// Prose rather than field names, and ordered by what the user would change:
  /// the video re-encode is the CPU bill, the audio one is the cheap fix
  /// (a compatible track), a burned-in subtitle is the surprise cause of a video
  /// re-encode on an otherwise compatible file, and a hardware request that fell
  /// back to software is the misconfiguration worth a trip to the server.
  ///
  /// Deliberately populated for a direct *stream* as well as a transcode. The
  /// `StreamSession` doc says the list is empty unless the method is
  /// `transcode`, and that holds for a direct play — which has no
  /// `TranscodeSession` at all and therefore nothing to explain — but suppressing
  /// "container rewrap · audio TrueHD → AAC" on a remux would throw away the
  /// only explanation the server offered.
  List<String> get reasons {
    final reasons = <String>[];

    final sourceVideo = plexCodecLabel(sourceVideoCodec);
    final targetVideo = plexCodecLabel(videoCodec);
    if (videoDecision == PlexStreamDecision.transcode) {
      reasons.add(
        sourceVideo != null && targetVideo != null && sourceVideo != targetVideo
            ? 'video $sourceVideo → $targetVideo'
            : 'video re-encoded',
      );
    }

    final sourceAudio = plexCodecLabel(sourceAudioCodec);
    final targetAudio = plexCodecLabel(audioCodec);
    if (audioDecision == PlexStreamDecision.transcode) {
      reasons.add(
        sourceAudio != null && targetAudio != null && sourceAudio != targetAudio
            ? 'audio $sourceAudio → $targetAudio'
            : 'audio re-encoded',
      );
    }

    if (subtitleDecision == PlexStreamDecision.burn) {
      reasons.add('subtitle burn-in');
    } else if (subtitleDecision == PlexStreamDecision.transcode) {
      reasons.add('subtitle converted');
    }

    // A rewrap is only worth naming when it is the *reason* — alongside a video
    // re-encode the new container is a consequence, not a cause.
    if (videoDecision == PlexStreamDecision.copy) {
      final target = plexContainerLabel(container);
      reasons.add(
        target == null ? 'container rewrap' : 'container rewrap to $target',
      );
    }

    if (transcodeHwRequested && !transcodeHwEncoding) {
      reasons.add('software encode — hardware not used');
    } else if (transcodeHwEncoding) {
      reasons.add('hardware encoder');
    }

    // Only meaningful while the encoder is still working: a finished or
    // deliberately throttled transcode reports a low speed by design.
    final rate = speed;
    if (!complete && !throttled && rate != null && rate > 0 && rate < 1.0) {
      reasons.add('falling behind at ${rate.toStringAsFixed(1)}× realtime');
    }

    return reasons;
  }
}

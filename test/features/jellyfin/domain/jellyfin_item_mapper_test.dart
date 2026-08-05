import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/jellyfin/domain/models/jellyfin_item_mapper.dart';
import 'package:seekarr/features/stream/domain/models/stream_item.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';

/// The mappers, exercised on the shapes a fixture cannot conveniently hold: a
/// field that is **absent** rather than zero, and the artwork fallback chain.
///
/// Absence is the dangerous one. `UserData` only exists on a response when the
/// request passed both `enableUserData=true` and a `userId`, and an API key has no
/// user of its own — so "we never asked" and "asked, and the answer is none" arrive
/// as the same missing key. Reading either as `0` or `false` produces a badge that
/// states something untrue with no error anywhere to catch it.
void main() {
  group('absent is not zero and not false', () {
    test('an item fetched without a viewer claims nothing about watch state', () {
      // No `UserData` at all: this is every item on a `recentlyAdded` page for an
      // install with no `jellyfinUserId` configured.
      final item = jellyfinStreamItemFromJson({
        'Id': 'a1',
        'Name': 'Arrival',
        'Type': 'Movie',
        'ProductionYear': 2016,
        'RunTimeTicks': 72000000000,
      });

      expect(item.runtimeMs, 7200000);
      expect(item.isPlayed, isFalse);
      expect(item.resumeOffsetMs, isNull);
      expect(item.resumeProgress, isNull);
      expect(item.isInProgress, isFalse);
      // Not 0. A `0` here renders as "nothing left to watch", which is the
      // opposite of "we have not asked".
      expect(item.unplayedChildCount, isNull);
    });

    test('a finished season and an unknown one stay distinguishable', () {
      final finished = jellyfinStreamItemFromJson({
        'Id': 's1',
        'Name': 'Season 1',
        'Type': 'Season',
        'SeriesName': 'Severance',
        'UserData': {'Played': true, 'UnplayedItemCount': 0},
      });
      final unknown = jellyfinStreamItemFromJson({
        'Id': 's2',
        'Name': 'Season 2',
        'Type': 'Season',
        'SeriesName': 'Severance',
        'UserData': {'Played': false},
      });

      expect(finished.kind, StreamItemKind.season);
      // A season contains episodes, so it navigates deeper rather than opening a
      // detail page.
      expect(finished.kind.hasChildren, isTrue);
      expect(finished.subtitle, 'Severance');
      expect(finished.unplayedChildCount, 0);
      expect(finished.isPlayed, isTrue);
      expect(unknown.unplayedChildCount, isNull);
    });

    test('an unprobed file has no runtime rather than a zero-length one', () {
      // `RunTimeTicks: 0` is what a freshly imported file carries until the
      // server has run MediaInfo over it.
      expect(
        jellyfinStreamItemFromJson({
          'Id': 'a1',
          'Name': 'Unprobed',
          'Type': 'Movie',
          'RunTimeTicks': 0,
        }).runtimeMs,
        isNull,
      );
      expect(
        jellyfinStreamItemFromJson({
          'Id': 'a1',
          'Name': 'Unprobed',
          'Type': 'Movie',
        }).runtimeMs,
        isNull,
      );
    });

    test('a position under a millisecond is not a resume point', () {
      // 5 000 ticks is half a millisecond. It truncates to `0` ms, which would
      // slip past the zero guard and pin a progress bar to the left edge of
      // something nobody has watched a frame of.
      final item = jellyfinStreamItemFromJson({
        'Id': 'a1',
        'Name': 'Arrival',
        'Type': 'Movie',
        'RunTimeTicks': 72000000000,
        'UserData': {'PlaybackPositionTicks': 5000, 'Played': false},
      });

      expect(item.resumeOffsetMs, isNull);
      expect(item.isInProgress, isFalse);
    });

    test('PlayedPercentage of zero is not a resume point either', () {
      final item = jellyfinStreamItemFromJson({
        'Id': 'a1',
        'Name': 'Arrival',
        'Type': 'Movie',
        'RunTimeTicks': 72000000000,
        'UserData': {'PlayedPercentage': 0.0, 'Played': false},
      });

      expect(item.resumeOffsetMs, isNull);
    });

    test('PlayedPercentage stands in when the tick field is absent', () {
      // The summarising endpoints send one or the other, never both. 40 is a
      // percentage, so this is 40% of two hours — not 40 ms and not 40x too far.
      final item = jellyfinStreamItemFromJson({
        'Id': 'a1',
        'Name': 'Arrival',
        'Type': 'Movie',
        'RunTimeTicks': 72000000000,
        'UserData': {'PlayedPercentage': 40.0, 'Played': false},
      });

      expect(item.resumeOffsetMs, 2880000);
      expect(item.resumeProgress, closeTo(0.4, 0.0001));
    });
  });

  group('poster path', () {
    test("an item's own art beats its parent's", () {
      // A `Thumb`-only episode that also carries `SeriesPrimaryImageTag`. Asking
      // for a `Primary` it does not have would 404; taking the series poster
      // instead would make one row of an episode list picture the show while the
      // row below it pictures the episode.
      expect(
        jellyfinPosterPath({
          'Id': 'ep1',
          'SeriesId': 'sr1',
          'SeriesPrimaryImageTag': 'seriestag',
          'ImageTags': {'Thumb': 'thumbtag'},
        }),
        '/Items/ep1/Images/Thumb?tag=thumbtag',
      );
    });

    test('an item with no art of its own falls back to the series', () {
      expect(
        jellyfinPosterPath({
          'Id': 'ep1',
          'SeriesId': 'sr1',
          'SeriesPrimaryImageTag': 'seriestag',
          'ImageTags': const <String, dynamic>{},
        }),
        '/Items/sr1/Images/Primary?tag=seriestag',
      );
    });

    test('a track falls back to its album', () {
      expect(
        jellyfinPosterPath({
          'Id': 'tr1',
          'AlbumId': 'al1',
          'AlbumPrimaryImageTag': 'albumtag',
          'ImageTags': const <String, dynamic>{},
        }),
        '/Items/al1/Images/Primary?tag=albumtag',
      );
    });

    test('no art anywhere is null rather than a URL that 404s', () {
      expect(jellyfinPosterPath({'Id': 'a1', 'Name': 'Arrival'}), isNull);
      // A tag present but empty is no tag: the cache-busting query would be
      // `?tag=` and the route would answer with the wrong bytes or none.
      expect(
        jellyfinPosterPath({
          'Id': 'a1',
          'ImageTags': {'Primary': ''},
        }),
        isNull,
      );
    });
  });

  group('session decisions', () {
    Map<String, dynamic> session({
      Object? playMethod,
      Map<String, dynamic>? transcodingInfo,
    }) => {
      'Id': 'se1',
      'UserName': 'matt',
      'Client': 'Jellyfin Web',
      'DeviceName': 'Chrome',
      'PlayState': {
        if (playMethod != null) 'PlayMethod': playMethod,
        'PositionTicks': 13500000000,
      },
      if (transcodingInfo != null) 'TranscodingInfo': transcodingInfo,
      'NowPlayingItem': {
        'Id': 'ep1',
        'Name': "Woe's Hollow",
        'Type': 'Episode',
        'SeriesName': 'Severance',
        'IndexNumber': 4,
        'ParentIndexNumber': 2,
        'RunTimeTicks': 27000000000,
      },
    };

    test('a live TranscodingInfo outranks a PlayMethod that has not arrived', () {
      // `PlayMethod` is populated a beat after playback starts, and the board must
      // not spend those seconds calling a transcode free.
      final mapped = jellyfinStreamSessionFromJson(
        session(
          transcodingInfo: {
            'Bitrate': 5616000,
            'TranscodeReasons': ['VideoCodecNotSupported'],
          },
        ),
      )!;

      expect(mapped.playMethod, StreamPlayMethod.transcode);
      expect(mapped.needsAttention, isTrue);
      expect(mapped.transcodeReasons, [
        'Client cannot decode this video codec',
      ]);
      expect(mapped.bitrate, 5616000);
      // The encoder's own target, so this figure is real.
      expect(mapped.bitrateIsNominal, isFalse);
      // Series leads, episode is the detail — the inverse of `StreamItem`.
      expect(mapped.title, 'Severance');
      expect(mapped.subtitle, "S2E4 · Woe's Hollow");
      expect(mapped.deviceLabel, 'Jellyfin Web · Chrome');
      expect(mapped.progress, 0.5);
      expect(mapped.isPaused, isFalse);
    });

    test('a direct play explains nothing, even carrying a stale reason', () {
      // Some clients leave the previous stream's reasons on the payload. Rendering
      // them would explain a cost that is not being paid.
      final mapped = jellyfinStreamSessionFromJson(
        session(
          playMethod: 'DirectPlay',
          transcodingInfo: {
            'TranscodeReasons': ['VideoCodecNotSupported'],
          },
        ),
      )!;

      expect(mapped.playMethod, StreamPlayMethod.directPlay);
      expect(mapped.transcodeReasons, isEmpty);
      expect(mapped.transcodeReasonLabel, isNull);
      expect(mapped.needsAttention, isFalse);
    });

    test('a connected client with nothing playing is not a session', () {
      expect(
        jellyfinStreamSessionFromJson({
          'Id': 'se1',
          'UserName': 'matt',
          'NowPlayingItem': null,
        }),
        isNull,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/features/jellyfin/domain/models/jellyfin_transcode_reason.dart';

void main() {
  group('jellyfinTranscodeReasonPhrases', () {
    test('turns the enum names into something actionable', () {
      expect(
        jellyfinTranscodeReasonPhrases([
          'VideoCodecNotSupported',
          'AudioCodecNotSupported',
          'SubtitleCodecNotSupported',
        ]),
        [
          'Client cannot decode this video codec',
          'Client cannot decode this audio codec',
          'Subtitles have to be burned in',
        ],
      );
    });

    test('keeps the server order — the first reason is the primary one', () {
      expect(
        jellyfinTranscodeReasonPhrases([
          'ContainerNotSupported',
          'VideoCodecNotSupported',
        ]).first,
        'Client cannot play this container',
      );
    });

    test('covers the documented 10.10/10.11 reason set', () {
      // 26 flags in 10.10, one more in 10.11 (`VideoCodecTagNotSupported`).
      expect(kJellyfinTranscodeReasonPhrases.length, greaterThanOrEqualTo(26));
      expect(
        kJellyfinTranscodeReasonPhrases['VideoCodecTagNotSupported'],
        isNotNull,
      );
      for (final phrase in kJellyfinTranscodeReasonPhrases.values) {
        expect(phrase, isNotEmpty);
        // Nothing may leak a raw enum name to the user.
        expect(phrase, isNot(contains('NotSupported')));
      }
    });

    test('an unknown reason is humanised rather than dropped', () {
      // A newer server, or a patched build: an unexplained transcode is worse
      // than an awkwardly worded one.
      expect(jellyfinTranscodeReasonPhrases(['VideoQuantumFluxNotSupported']), [
        'Video quantum flux not supported',
      ]);
    });

    test('duplicate phrases collapse', () {
      expect(
        jellyfinTranscodeReasonPhrases([
          'VideoCodecNotSupported',
          'VideoCodecNotSupported',
        ]),
        hasLength(1),
      );
    });

    test('a flattened CSV string is accepted as well as an array', () {
      expect(
        jellyfinTranscodeReasonPhrases(
          'DirectPlayError,AudioChannelsNotSupported',
        ),
        [
          'Direct play failed on the client',
          'Too many audio channels for the client',
        ],
      );
    });

    test('nothing to explain yields no phrases', () {
      expect(jellyfinTranscodeReasonPhrases(null), isEmpty);
      expect(jellyfinTranscodeReasonPhrases(const []), isEmpty);
      expect(jellyfinTranscodeReasonPhrases(''), isEmpty);
      expect(jellyfinTranscodeReasonPhrases(42), isEmpty);
    });
  });

  group('jellyfinHumanisedEnumName', () {
    test('splits PascalCase, including acronym runs', () {
      expect(jellyfinHumanisedEnumName('DirectPlayError'), 'Direct play error');
      expect(
        jellyfinHumanisedEnumName('VideoRangeTypeNotSupported'),
        'Video range type not supported',
      );
      expect(
        jellyfinHumanisedEnumName('HDRToSDRToneMapping'),
        'HDR to SDR tone mapping',
      );
    });

    test('an empty value stays empty', () {
      expect(jellyfinHumanisedEnumName('   '), '');
    });
  });
}

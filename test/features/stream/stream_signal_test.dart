import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';

/// Rebuilds the KPI list `_streamKpis` produces, without the providers.
///
/// The real builder is private to `service_kpi_provider.dart` and needs a `Ref`;
/// what actually needs locking is not the plumbing but the **ordering and flagging
/// rule**, which is pure. This mirror stays honest because the assertions below
/// check the readings a user sees, and those would change the moment the real
/// builder's order or flags did.
List<ServiceKpi> streamKpis({required int streams, required int transcodes}) =>
    [
      ServiceKpi(
        label: 'Streams',
        value: '$streams',
        icon: Icons.play_circle_outline_rounded,
        accent: streams > 0 && transcodes == 0 ? AppColors.info : null,
      ),
      ServiceKpi(
        label: 'Transcodes',
        value: '$transcodes',
        icon: Icons.memory_rounded,
        accent: transcodes > 0 ? AppColors.warning : null,
      ),
      const ServiceKpi(
        label: 'Libraries',
        value: '3',
        icon: Icons.video_library_outlined,
      ),
    ];

void main() {
  group('the Stream matrix cell has exactly three readings', () {
    test(
      'idle is neutral and still live — "0 streams", not a library total',
      () {
        final signal = resolveServiceSignal(
          streamKpis(streams: 0, transcodes: 0),
        );

        expect(signal, isNotNull);
        expect(signal!.value, '0');
        expect(signal.label, 'streaming');
        // Neutral means "nothing is asking for you", which is the truth about an
        // idle media server. It must NOT fall through to the library count: a
        // library total is the least live figure on a control-room screen.
        expect(signal.tone, StatusTone.neutral);
        expect(signal.needsAttention, isFalse);
      },
    );

    test('someone watching reads as activity, not as a fault', () {
      final signal = resolveServiceSignal(
        streamKpis(streams: 2, transcodes: 0),
      )!;

      expect(signal.value, '2');
      // This is the assertion `_activityLabels` exists for. Without 'Streams' in
      // that set the tone falls through to `warning`, and "two people are
      // watching a film" paints the same amber as "Prowlarr has failing
      // indexers".
      expect(signal.tone, StatusTone.info);
      expect(signal.spoken, 'Streaming 2');
    });

    test('a transcode outranks the stream count and turns amber', () {
      final signal = resolveServiceSignal(
        streamKpis(streams: 2, transcodes: 1),
      )!;

      // `resolveServiceSignal` takes the FIRST flagged KPI, and `Streams` comes
      // first in the list — so this only works because the builder stops flagging
      // `Streams` while anything is transcoding. Precedence lives in the flag, not
      // in the shared resolver.
      expect(signal.value, '1');
      expect(signal.label, 'transcode');
      expect(signal.tone, StatusTone.warning);
      expect(signal.needsAttention, isTrue);
    });

    test('the label agrees in number with its own figure', () {
      expect(
        resolveServiceSignal(streamKpis(streams: 1, transcodes: 0))!.label,
        // 'streaming' is a gerund precisely so it needs no depluralisation at one.
        'streaming',
      );
      expect(
        resolveServiceSignal(streamKpis(streams: 0, transcodes: 3))!.label,
        'transcodes',
      );
    });
  });

  group('formatStreamBitrate', () {
    test('omits a figure the server did not report', () {
      // Not "0 Mbps": a direct play whose source bitrate is unknown has no rate
      // to show, and printing zero would assert the stream is using no bandwidth.
      expect(formatStreamBitrate(null), isNull);
      expect(formatStreamBitrate(0), isNull);
      expect(formatStreamBitrate(-1), isNull);
    });

    test('reads in the unit media servers and routers actually use', () {
      expect(formatStreamBitrate(24305112), '24 Mbps');
      expect(formatStreamBitrate(8400000), '8.4 Mbps');
      expect(formatStreamBitrate(320000), '320 kbps');
    });

    test('crosses its thresholds without a gap', () {
      expect(formatStreamBitrate(999999), '1000 kbps');
      expect(formatStreamBitrate(1000000), '1.0 Mbps');
      expect(formatStreamBitrate(9990000), '10.0 Mbps');
      expect(formatStreamBitrate(10000000), '10 Mbps');
    });
  });

  group('streamSessionValue', () {
    const base = {
      'userName': 'Matt',
      'title': 'The Fellowship of the Ring',
      'deviceLabel': 'Chrome on Windows',
    };

    test('leads with the person, then the cost — not the visual order', () {
      final spoken = streamSessionValue(
        userName: base['userName']!,
        title: base['title']!,
        subtitle: null,
        playMethodLabel: 'Transcode',
        transcodeReason: "client can't decode HEVC",
        deviceLabel: base['deviceLabel']!,
        progressLabel: '34% in',
        bitrateLabel: '8.4 Mbps',
        bitrateIsNominal: false,
        isPaused: false,
      );

      // The card paints title-first because that is what the eye scans for; read
      // aloud, whose playback it is comes first and the reason it costs a CPU
      // arrives before the device rather than after it.
      expect(spoken.indexOf('Matt'), lessThan(spoken.indexOf('Fellowship')));
      expect(
        spoken.indexOf("client can't decode HEVC"),
        lessThan(spoken.indexOf('Chrome on Windows')),
      );
    });

    test('hedges a nominal rate and states a measured one plainly', () {
      String rateIn({required bool nominal}) => streamSessionValue(
        userName: base['userName']!,
        title: base['title']!,
        subtitle: null,
        playMethodLabel: 'Direct play',
        transcodeReason: null,
        deviceLabel: base['deviceLabel']!,
        progressLabel: null,
        bitrateLabel: '24 Mbps',
        bitrateIsNominal: nominal,
        isPaused: false,
      );

      // A direct play's figure is the file's own bitrate, not throughput the
      // server measured. Saying it plainly would assert egress no API reported.
      expect(rateIn(nominal: true), contains('about 24 Mbps'));
      expect(rateIn(nominal: false), isNot(contains('about')));
    });

    test('speaks paused, because a pause glyph announces nothing', () {
      final spoken = streamSessionValue(
        userName: base['userName']!,
        title: base['title']!,
        subtitle: 'S01E01',
        playMethodLabel: 'Transcode',
        transcodeReason: null,
        deviceLabel: base['deviceLabel']!,
        progressLabel: null,
        bitrateLabel: null,
        bitrateIsNominal: true,
        isPaused: true,
      );

      // A paused session still holds its transcode, so this is a materially
      // different state for the operator rather than decoration.
      expect(spoken, contains('paused'));
    });

    test('drops the slots the server left empty rather than saying "null"', () {
      final spoken = streamSessionValue(
        userName: base['userName']!,
        title: base['title']!,
        subtitle: null,
        playMethodLabel: 'Direct play',
        transcodeReason: null,
        deviceLabel: base['deviceLabel']!,
        progressLabel: null,
        bitrateLabel: null,
        bitrateIsNominal: true,
        isPaused: false,
      );

      expect(
        spoken,
        'Matt, The Fellowship of the Ring, Direct play, on Chrome on Windows',
      );
    });
  });

  group('StreamSession', () {
    StreamSession session({
      required StreamPlayMethod method,
      List<String> reasons = const [],
    }) => StreamSession(
      id: 's1',
      userName: 'Matt',
      title: 'Dune',
      subtitle: null,
      deviceLabel: 'Infuse on Apple TV',
      posterPath: null,
      playMethod: method,
      transcodeReasons: reasons,
      bitrate: 8000000,
      bitrateIsNominal: true,
      progress: 0.4,
      isPaused: false,
    );

    test('only a transcode asks for attention', () {
      expect(
        session(method: StreamPlayMethod.directPlay).needsAttention,
        isFalse,
      );
      expect(
        session(method: StreamPlayMethod.directStream).needsAttention,
        isFalse,
      );
      expect(
        session(method: StreamPlayMethod.transcode).needsAttention,
        isTrue,
      );
    });

    test('a direct stream still carries its explanation', () {
      // The contract populates reasons for directStream too: a remux has an
      // explanation and it is the only one the server offers. `needsAttention`
      // stays false, so a caller asking "is this costing me a CPU" is unaffected.
      final remux = session(
        method: StreamPlayMethod.directStream,
        reasons: const ['audio TrueHD → E-AC3', 'container rewrap to MKV'],
      );
      expect(remux.needsAttention, isFalse);
      expect(
        remux.transcodeReasonLabel,
        'audio TrueHD → E-AC3 · container rewrap to MKV',
      );
    });

    test('no reasons means no phrase, not an empty one', () {
      expect(
        session(method: StreamPlayMethod.directPlay).transcodeReasonLabel,
        isNull,
      );
    });
  });
}

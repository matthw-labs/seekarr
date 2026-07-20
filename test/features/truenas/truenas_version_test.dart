import 'package:flutter_test/flutter_test.dart';
import 'package:seekarr/features/truenas/domain/truenas_version.dart';

void main() {
  group('TrueNasVersion.parse', () {
    test('parses full TrueNAS SCALE version strings', () {
      final v = TrueNasVersion.parse('TrueNAS-SCALE-25.04.1');
      expect(v, isNotNull);
      expect(v!.year, 25);
      expect(v.month, 4);
      expect(v.patch, 1);
    });

    test('parses a bare train without patch', () {
      final v = TrueNasVersion.parse('25.10');
      expect(v!.patch, 0);
      expect(v.toString(), '25.10');
    });

    test('returns null when no version is present', () {
      expect(TrueNasVersion.parse('unknown'), isNull);
      expect(TrueNasVersion.parse(null), isNull);
    });
  });

  group('isSupported', () {
    test('24.10 is unsupported', () {
      expect(TrueNasVersion.parse('24.10.2')!.isSupported, isFalse);
    });

    test('25.04 is the supported floor', () {
      expect(TrueNasVersion.parse('25.04')!.isSupported, isTrue);
    });

    test('newer trains are supported', () {
      expect(TrueNasVersion.parse('25.10')!.isSupported, isTrue);
      expect(TrueNasVersion.parse('26.04')!.isSupported, isTrue);
    });

    test('isVersionSupported fails open on unparseable input', () {
      expect(TrueNasVersion.isVersionSupported('garbage'), isTrue);
      expect(TrueNasVersion.isVersionSupported('24.10'), isFalse);
    });
  });

  group('comparison', () {
    test('orders by year, month, then patch', () {
      expect(
        const TrueNasVersion(25, 4) < const TrueNasVersion(25, 10),
        isTrue,
      );
      expect(
        const TrueNasVersion(25, 4, 1) >= const TrueNasVersion(25, 4),
        isTrue,
      );
    });
  });
}

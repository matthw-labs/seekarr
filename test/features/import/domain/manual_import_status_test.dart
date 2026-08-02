import 'package:flutter_test/flutter_test.dart';

import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/import/domain/manual_import_status.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

ManualImportItem _item(Map<String, dynamic> json) =>
    ManualImportItem.fromJson({'path': '/downloads/x.mkv', ...json});

void main() {
  group('manualImportItemStatus', () {
    test('a matched movie resolves to Ready on the success tone', () {
      final info = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'movie': {'id': 42, 'title': 'Some Movie'},
        }),
      );
      expect(info.label, 'Ready');
      expect(info.tone, StatusTone.success);
    });

    test('a metadata rejection keeps Ready but escalates to warning', () {
      final info = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'movie': {'id': 42, 'title': 'Some Movie'},
          'rejections': [
            {'reason': 'Not a preferred word upgrade', 'type': 'permanent'},
          ],
        }),
      );
      expect(info.label, 'Ready');
      expect(info.tone, StatusTone.warning);
      expect(info.semanticLabel, contains('warning'));
    });

    test('an unmatched file resolves to Needs match on warning', () {
      final info = manualImportItemStatus(ServiceKey.radarr, _item({}));
      expect(info.label, 'Needs match');
      expect(info.tone, StatusTone.warning);
    });

    test('a permanent identity rejection resolves to No match on error', () {
      final info = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'rejections': [
            {'reason': 'Unable to determine movie', 'type': 'permanent'},
          ],
        }),
      );
      expect(info.label, 'No match');
      expect(info.tone, StatusTone.error);
      expect(info.detail, 'Unable to determine movie');
    });

    test('an already imported file resolves to the neutral tone', () {
      final info = manualImportItemStatus(
        ServiceKey.radarr,
        _item({
          'movie': {'id': 42, 'title': 'Some Movie'},
          'movieFileId': 99,
        }),
      );
      expect(info.label, 'Imported');
      expect(info.tone, StatusTone.neutral);
    });
  });

  group('manualImportCommandStatus', () {
    ManualImportCommandStatus command(String status) =>
        ManualImportCommandStatus.fromJson({'id': 1, 'status': status});

    test('maps the lifecycle onto the closed tone vocabulary', () {
      expect(
        manualImportCommandStatus(command('queued')).tone,
        StatusTone.warning,
      );
      expect(
        manualImportCommandStatus(command('started')).tone,
        StatusTone.info,
      );
      expect(
        manualImportCommandStatus(command('completed')).tone,
        StatusTone.success,
      );
      expect(
        manualImportCommandStatus(command('failed')).tone,
        StatusTone.error,
      );
      expect(manualImportCommandStatus(command('failed')).label, 'Failed');
    });
  });
}

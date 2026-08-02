import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/import/presentation/manual_import_widgets.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

Future<void> showImportServicePickerSheet(BuildContext context) {
  return AppBottomSheet.show<void>(
    context: context,
    title: 'Manual import',
    subtitle: 'Pick the service that should take the files',
    icon: Icons.drive_folder_upload_outlined,
    builder: (context) => const _ImportServicePickerSheet(),
  );
}

class _ImportServicePickerSheet extends StatelessWidget {
  const _ImportServicePickerSheet();

  @override
  Widget build(BuildContext context) {
    return SettingsGroupCard(
      children: [
        for (final service in const [
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.lidarr,
        ])
          SettingsCard.grouped(
            leading: Icon(service.icon),
            title: service.title,
            subtitle: service.manualImportSubtitle,
            accentColor: service.accent,
            semanticHint: 'starts a ${service.title} manual import',
            onTap: () {
              Navigator.of(context).pop();
              context.push(
                manualImportLocation(manualImportBrowsePath, service),
              );
            },
          ),
      ],
    );
  }
}

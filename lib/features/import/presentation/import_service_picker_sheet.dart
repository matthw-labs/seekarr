import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/import/presentation/manual_import_routes.dart';
import 'package:seekarr/features/import/presentation/manual_import_widgets.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

Future<void> showImportServicePickerSheet(BuildContext context) {
  return AppBottomSheet.show<void>(
    context: context,
    title: 'Manual import',
    icon: Icons.drive_folder_upload_outlined,
    builder: (context) => const _ImportServicePickerSheet(),
  );
}

class _ImportServicePickerSheet extends StatelessWidget {
  const _ImportServicePickerSheet();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final service in const [
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.lidarr,
        ])
          _ServicePickerRow(service: service),
      ],
    );
  }
}

class _ServicePickerRow extends StatelessWidget {
  final ServiceKey service;

  const _ServicePickerRow({required this.service});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          borderRadius: AppRadius.borderRadiusMd,
          onTap: () {
            Navigator.of(context).pop();
            context.push(manualImportLocation(manualImportBrowsePath, service));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: service.accent.withValues(alpha: 0.14),
                    borderRadius: AppRadius.borderRadiusFull,
                  ),
                  child: Icon(
                    Icons.download_for_offline_rounded,
                    size: 22,
                    color: service.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        service.manualImportSubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/features/settings/domain/service_key.dart';

const manualImportPathPrefix = '/import';

/// Station 1 — Locate. Kept at the historical `/browse` path so existing
/// deep links and entry points keep working.
const manualImportBrowsePath = '$manualImportPathPrefix/browse';

/// Station 2 — Review (selection and matching merged into one screen).
const manualImportReviewPath = '$manualImportPathPrefix/review';

/// Station 3 — Track.
const manualImportProgressPath = '$manualImportPathPrefix/progress';

/// Legacy step paths from the four-screen flow. The router redirects both into
/// [manualImportReviewPath] so an old deep link never dead-ends.
const manualImportFolderPath = '$manualImportPathPrefix/folder';
const manualImportMatchPath = '$manualImportPathPrefix/match';

ServiceKey? manualImportServiceFromRoute(String? value) {
  final normalized = value?.trim().toLowerCase();
  for (final service in ServiceKey.values) {
    if (service.supportsManualImport && service.routeParam == normalized) {
      return service;
    }
  }
  return null;
}

String manualImportLocation(
  String path,
  ServiceKey service, {
  int? targetId,
  String? folderPath,
}) {
  return Uri(
    path: path,
    queryParameters: {
      'service': service.routeParam,
      if (targetId != null && targetId > 0) 'targetId': '$targetId',
      if (folderPath != null && folderPath.isNotEmpty) 'path': folderPath,
    },
  ).toString();
}

VoidCallback? openManualImportCallback(
  BuildContext context,
  ServiceKey service,
  int targetId,
) {
  if (targetId <= 0) return null;
  return () => context.push(
    manualImportLocation(manualImportBrowsePath, service, targetId: targetId),
  );
}

/// Derives a browsable folder from a queue item's `outputPath`.
///
/// The \*arr queue reports where the download client put the data — usually a
/// folder, occasionally the file itself for single-file downloads. The
/// filesystem endpoint only lists folders, so a path whose last segment looks
/// like a file name (a short alphanumeric extension) is trimmed to its parent.
/// Separators are preserved as-is: this is the *server's* path, and a Windows
/// \*arr expects its backslashes back.
String? manualImportFolderFromOutputPath(String? outputPath) {
  final path = outputPath?.trim();
  if (path == null || path.isEmpty) return null;

  final separator = path.contains('\\') ? '\\' : '/';
  final trimmed = path.endsWith(separator)
      ? path.substring(0, path.length - 1)
      : path;
  final lastSeparator = trimmed.lastIndexOf(separator);
  if (lastSeparator <= 0) return trimmed.isEmpty ? null : trimmed;

  final lastSegment = trimmed.substring(lastSeparator + 1);
  final dot = lastSegment.lastIndexOf('.');
  final looksLikeFile =
      dot > 0 &&
      dot < lastSegment.length - 1 &&
      lastSegment.length - dot - 1 <= 5 &&
      RegExp(r'^[A-Za-z0-9]+$').hasMatch(lastSegment.substring(dot + 1));

  return looksLikeFile ? trimmed.substring(0, lastSeparator) : trimmed;
}

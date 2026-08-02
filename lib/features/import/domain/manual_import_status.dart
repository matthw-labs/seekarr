import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// The four classes the Review screen sorts a scan into.
///
/// One taxonomy, named once, because three things have to agree on it: the
/// counts in the filter row, which rows the list builds, and what a filter chip
/// hides. While each of those carried its own booleans, "hide the imported
/// ones" lived in the app bar and "collapse the other ones" lived in a section
/// header — two controls, two mental models, for one question: what am I
/// looking at?
enum ManualImportFacet { ready, attention, imported, other }

/// The count of one facet, resolved into the closed status vocabulary.
///
/// The chip renders this; it never derives a tone from the facet itself.
MediaStatusInfo manualImportFacetStatus(ManualImportFacet facet, int count) {
  return switch (facet) {
    ManualImportFacet.ready => MediaStatusInfo(
      availability: MediaAvailability.available,
      labelOverride: '$count ready',
      toneOverride: StatusTone.success,
    ),
    ManualImportFacet.attention => MediaStatusInfo(
      labelOverride: count == 1 ? '1 needs a match' : '$count need a match',
      toneOverride: StatusTone.warning,
    ),
    ManualImportFacet.imported => MediaStatusInfo(
      availability: MediaAvailability.available,
      labelOverride: '$count imported',
      toneOverride: StatusTone.neutral,
    ),
    ManualImportFacet.other => MediaStatusInfo(
      labelOverride: '$count other',
      toneOverride: StatusTone.neutral,
    ),
  };
}

/// The same count as one spoken phrase.
///
/// The painted chip is a fragment sized for a pill — "1 needs a match", "3
/// imported" — and read out verbatim it produces "1 needs a match files". A
/// screen reader gets the sentence instead; the eye keeps the fragment.
String manualImportFacetSpokenLabel(ManualImportFacet facet, int count) {
  final files = count == 1 ? '1 file' : '$count files';
  return switch (facet) {
    ManualImportFacet.ready => '$files ready to import',
    ManualImportFacet.attention =>
      '$files ${count == 1 ? 'needs' : 'need'} a match',
    ManualImportFacet.imported => '$files already in the library',
    ManualImportFacet.other => '$files of a kind this service cannot import',
  };
}

/// Resolves a scanned file's import state into the closed status vocabulary.
///
/// Lives in `domain/` per the Closed Tone Rule: the Review screen renders
/// whatever arrives here and never re-derives a tone. Five states cover the
/// whole surface:
///
/// - **Imported** (neutral, on disk): the service already has this file. Not an
///   error and not a problem — but the row is still a control, because the user
///   may want it taken again.
/// - **Re-import** (info): an imported file the user ticked to send anyway.
///   [reimportSelected] is what distinguishes it, and it is a distinct status
///   rather than a selected-looking "Imported" because the consequence differs:
///   this file is going into the next batch.
/// - **Ready** (success): fully matched, will be included in the import. When
///   the service also reported a metadata rejection the tone escalates to
///   warning via [MediaStatusInfo.hasWarning] while the label stays honest.
/// - **No match** (error): the service permanently rejected the file's
///   identity; it cannot import until the user assigns one.
/// - **Needs match** (warning): unmatched, but nothing permanent — assigning
///   an identity clears it.
MediaStatusInfo manualImportItemStatus(
  ServiceKey service,
  ManualImportItem item, {
  bool reimportSelected = false,
}) {
  if (item.isAlreadyImported) {
    if (reimportSelected) {
      // `upgradable` for the glyph as much as the state: the arrow-into-a-line
      // says "this replaces what is there", which is precisely the deal.
      return const MediaStatusInfo(
        availability: MediaAvailability.upgradable,
        labelOverride: 'Re-import',
        toneOverride: StatusTone.info,
      );
    }
    return const MediaStatusInfo(
      availability: MediaAvailability.available,
      labelOverride: 'Imported',
      toneOverride: StatusTone.neutral,
    );
  }

  if (item.isReadyForImportFor(service)) {
    return MediaStatusInfo(
      labelOverride: 'Ready',
      toneOverride: StatusTone.success,
      hasWarning: item.hasBlockingMetadataRejection,
      detail: item.hasBlockingMetadataRejection
          ? item.firstRejectionReason
          : null,
    );
  }

  if (item.hasBlockingIdentityRejection) {
    return MediaStatusInfo(
      labelOverride: 'No match',
      toneOverride: StatusTone.error,
      detail: item.firstRejectionReason,
    );
  }

  return MediaStatusInfo(
    labelOverride: 'Needs match',
    toneOverride: StatusTone.warning,
    detail: item.firstRejectionReason,
  );
}

/// Resolves an \*arr `ManualImport` command's state for the Track screen.
///
/// The command is aggregate — the services do not report per-file results — so
/// this is deliberately the only status the Track screen renders as truth.
MediaStatusInfo manualImportCommandStatus(ManualImportCommandStatus command) {
  final (label, tone) = switch (command.status) {
    'queued' => ('Queued', StatusTone.warning),
    'started' => ('Running', StatusTone.info),
    'completed' => ('Completed', StatusTone.success),
    'failed' => ('Failed', StatusTone.error),
    'aborted' => ('Aborted', StatusTone.error),
    'cancelled' => ('Cancelled', StatusTone.error),
    'orphaned' => ('Orphaned', StatusTone.error),
    _ => (command.status, StatusTone.info),
  };
  return MediaStatusInfo(
    labelOverride: label,
    toneOverride: tone,
    detail: command.message,
  );
}

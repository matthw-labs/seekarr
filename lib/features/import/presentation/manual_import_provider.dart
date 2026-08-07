import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/import/data/manual_import_service.dart';
import 'package:seekarr/features/import/domain/manual_import_display.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Preferences key for the folder a service last scanned.
///
/// The rescue scene almost always returns to the same completed-downloads
/// folder, so Locate offers it back as a one-tap shortcut.
String manualImportLastFolderKey(ServiceKey service) =>
    'manual_import.last_folder.${service.name}';

/// The folder this service last scanned, or null when there is none yet.
final manualImportLastFolderProvider = Provider.family<String?, ServiceKey>((
  ref,
  service,
) {
  // Startup overrides the prefs provider; tests that don't override it get the
  // unimplemented throw, which for a convenience shortcut should mean "no
  // shortcut", not a crash.
  try {
    return ref
        .watch(sharedPreferencesProvider)
        .getString(manualImportLastFolderKey(service));
  } catch (_) {
    return null;
  }
});

const Object _noValue = Object();

String mapImportError(Object error, ServiceKey service) {
  if (error is DioException) {
    final title = service.title;
    final status = error.response?.statusCode;
    // A receive timeout means the connection succeeded and $title simply took
    // too long to answer — telling the user to check the URL sends them after
    // the wrong problem.
    if (error.type == DioExceptionType.receiveTimeout) {
      return '$title took too long to answer. Scanning a large folder, or one '
          'on a slow or spun-down drive, can outlast the request — try a '
          'narrower subfolder, or check $title → Activity → Queue in case the '
          'scan is still running.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return "Couldn't reach $title. Check the URL and that the service is running.";
    }
    if (status == 500) {
      final hint = switch (service) {
        ServiceKey.radarr =>
          "the file's name isn't parseable by $title "
              '(missing year, ambiguous title) or the folder name gives no hint. '
              'Try moving the file into a folder named after the movie and '
              'including the year, e.g. `Title (YEAR)/Title (YEAR).ext`, '
              'then rescan.',
        ServiceKey.sonarr =>
          "the file's name doesn't match a known series/episode pattern, "
              'or the folder name gives no hint. '
              'Try naming the folder after the series, e.g. '
              '`Series Title/S01E01.ext`, then rescan.',
        ServiceKey.lidarr =>
          "the file's name doesn't match a known artist/album/track pattern, "
              'or the folder name gives no hint. '
              'Try organising into `Artist/Album/Track.ext`, then rescan.',
        _ => 'check the service logs for the full error.',
      };
      return '$title returned 500 while processing the manual import. '
          'Check $title → System → Logs for the full error. '
          'Common cause: $hint';
    }
    if (status != null) {
      final data = error.response?.data;
      final message = data is Map ? data['message'] : null;
      final messageStr = message is String && message.isNotEmpty ? message : '';
      return messageStr.isEmpty
          ? '$title returned $status.'
          : '$title returned $status: $messageStr';
    }
    return '$title request failed. Check the URL and that the service is running.';
  }
  if (error is Exception) {
    final s = error.toString();
    // Strip the "Exception: " prefix for a cleaner user-facing message.
    if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
    return s;
  }
  return error.toString();
}

String? libraryGuardError(ServiceKey service, ManualImportFixAssignment a) {
  if (a.match.id <= 0) {
    return 'This title isn\'t in your ${service.title} library — add it '
        'from the ${_libraryTabLabel(service)} tab first.';
  }
  switch (service) {
    case ServiceKey.sonarr:
      if (a.episodes.isEmpty) {
        return 'Pick at least one episode from your ${service.title} library '
            'before importing.';
      }
    case ServiceKey.lidarr:
      if (a.tracks.isEmpty || a.album == null) {
        return 'Pick an album and at least one track from your ${service.title} '
            'library before importing.';
      }
    case ServiceKey.radarr:
      // Radarr only needs a movieId; match.id > 0 is sufficient.
      break;
    case _:
      return 'This service does not support manual import.';
  }
  return null;
}

String _libraryTabLabel(ServiceKey service) => switch (service) {
  ServiceKey.radarr => 'Movies',
  ServiceKey.sonarr => 'Series',
  ServiceKey.lidarr => 'Music',
  _ => 'Library',
};

final manualImportFlowProvider =
    NotifierProvider<ManualImportFlowNotifier, ManualImportFlowState>(
      ManualImportFlowNotifier.new,
    );

class ManualImportFlowState {
  final ServiceKey? service;
  final int? targetId;
  final List<ManualImportRootFolder> rootFolders;
  final ManualImportFileSystemResult? fileSystem;
  final String? currentPath;
  final String? selectedFolder;
  final List<ManualImportItem> items;
  final Set<String> selectedPaths;

  /// Unmatched files the user has ticked to assign **together**.
  ///
  /// Separate from [selectedPaths] because they answer different questions:
  /// that one is "import these", this one is "these share an identity". The
  /// distinction is what stopped bulk assignment from being a blunt
  /// instrument — one series applied to every unmatched file in the folder
  /// happily matched playlists and other shows' episodes to it.
  final Set<String> fixSelectionPaths;

  final List<ManualImportItem> submittedItems;

  /// Paths already handed to a `ManualImport` command in this session.
  ///
  /// The flow used to keep the selection intact after submitting, so leaving
  /// Track and pressing Import again re-posted the same files. While the first
  /// command was still running that queued a duplicate import; once it had
  /// finished, the files had been moved into the library and the service
  /// answered with a `FileNotFoundException` for a path it had itself consumed.
  /// Recording what was submitted is what makes the second press impossible.
  final Set<String> submittedPaths;

  final List<ManualImportQualityOption> qualityOptions;
  final List<ManualImportLanguageOption> languageOptions;
  final ManualImportCommandStatus? command;
  final bool isLoadingBrowse;
  final bool isLoadingItems;
  final bool isSubmitting;
  final ManualImportMode importMode;
  final String? error;

  const ManualImportFlowState({
    this.service,
    this.targetId,
    this.rootFolders = const [],
    this.fileSystem,
    this.currentPath,
    this.selectedFolder,
    this.items = const [],
    this.selectedPaths = const {},
    this.fixSelectionPaths = const {},
    this.submittedItems = const [],
    this.submittedPaths = const {},
    this.qualityOptions = const [],
    this.languageOptions = const [],
    this.command,
    this.isLoadingBrowse = false,
    this.isLoadingItems = false,
    this.isSubmitting = false,
    this.importMode = ManualImportMode.auto,
    this.error,
  });

  List<ManualImportItem> get selectedItems => items
      .where((item) => selectedPaths.contains(item.path))
      .toList(growable: false);

  List<ManualImportItem> get selectableItems =>
      items.where((item) => item.isSelectable).toList(growable: false);

  /// Paths that must not be submitted again.
  ///
  /// A batch is spent while its command is running and once it has completed —
  /// the files are being, or have been, moved into the library. A **failed**
  /// command releases them: the file may well still be on disk, and retrying
  /// after fixing the cause is exactly what the user should be able to do.
  Set<String> get blockedPaths {
    final command = this.command;
    if (command == null || command.isFailure) return const {};
    return submittedPaths;
  }

  /// Files handed to the current command, still shown so the list stays honest
  /// about where they went.
  List<ManualImportItem> get inFlightItems {
    final blocked = blockedPaths;
    if (blocked.isEmpty) return const [];
    return items
        .where((item) => blocked.contains(item.path))
        .toList(growable: false);
  }

  /// Fully matched files — the only ones the import checkbox can include.
  List<ManualImportItem> get readyItems {
    final service = this.service;
    if (service == null) return const [];
    final blocked = blockedPaths;
    return items
        .where(
          (item) =>
              item.isReadyForImportFor(service) && !blocked.contains(item.path),
        )
        .toList(growable: false);
  }

  /// Files that need an identity before they can be imported.
  ///
  /// Only files the service could actually import: a Sonarr scan of a real
  /// downloads folder also returns playlists, artwork and music, and counting
  /// those as "needs attention" makes the number unactionable — 26 items to fix
  /// when only a handful are episodes. Those land in [otherItems] instead.
  List<ManualImportItem> get attentionItems {
    final service = this.service;
    if (service == null) return const [];
    final blocked = blockedPaths;
    return items
        .where(
          (item) =>
              item.isSelectable &&
              !item.isReadyForImportFor(service) &&
              !blocked.contains(item.path) &&
              manualImportIsSupportedFile(service, item),
        )
        .toList(growable: false);
  }

  /// Files of a kind this service does not import — kept visible, and still
  /// fixable, but out of the way.
  List<ManualImportItem> get otherItems {
    final service = this.service;
    if (service == null) return const [];
    final blocked = blockedPaths;
    return items
        .where(
          (item) =>
              item.isSelectable &&
              !item.isReadyForImportFor(service) &&
              !blocked.contains(item.path) &&
              !manualImportIsSupportedFile(service, item),
        )
        .toList(growable: false);
  }

  /// The unmatched files ticked for a shared assignment.
  List<ManualImportItem> get fixSelectionItems => items
      .where((item) => fixSelectionPaths.contains(item.path))
      .toList(growable: false);

  /// Files the service already holds.
  ///
  /// The scan asks for them deliberately (`filterExistingFiles: false`), because
  /// with the service's default filter on, an already-imported file is simply
  /// absent — and "did I already take this one?" then has no answer anywhere in
  /// the app. They are listed inline with everything else, and a user who wants
  /// one taken again can tick it; see [ManualImportItem.isReimportableFor].
  List<ManualImportItem> get importedItems {
    final blocked = blockedPaths;
    return items
        .where((item) => item.isAlreadyImported && !blocked.contains(item.path))
        .toList(growable: false);
  }

  /// Already-imported files the user has ticked to send over again.
  List<ManualImportItem> get selectedReimportItems => selectedItems
      .where((item) => item.isAlreadyImported)
      .toList(growable: false);

  bool get hasSelectedItems => selectedPaths.isNotEmpty;

  bool get allReadySelected =>
      readyItems.isNotEmpty &&
      readyItems.every((item) => selectedPaths.contains(item.path));

  bool get canImportSelected =>
      service != null &&
      selectedItems.isNotEmpty &&
      selectedItems.every(
        (item) =>
            item.isSubmittableFor(service!) &&
            !blockedPaths.contains(item.path),
      ) &&
      !isSubmitting;

  ManualImportFlowState copyWith({
    Object? service = _noValue,
    Object? targetId = _noValue,
    List<ManualImportRootFolder>? rootFolders,
    Object? fileSystem = _noValue,
    Object? currentPath = _noValue,
    Object? selectedFolder = _noValue,
    List<ManualImportItem>? items,
    Set<String>? selectedPaths,
    Set<String>? fixSelectionPaths,
    List<ManualImportItem>? submittedItems,
    Set<String>? submittedPaths,
    List<ManualImportQualityOption>? qualityOptions,
    List<ManualImportLanguageOption>? languageOptions,
    Object? command = _noValue,
    bool? isLoadingBrowse,
    bool? isLoadingItems,
    bool? isSubmitting,
    ManualImportMode? importMode,
    Object? error = _noValue,
  }) {
    return ManualImportFlowState(
      service: identical(service, _noValue)
          ? this.service
          : service as ServiceKey?,
      targetId: identical(targetId, _noValue)
          ? this.targetId
          : targetId as int?,
      rootFolders: rootFolders ?? this.rootFolders,
      fileSystem: identical(fileSystem, _noValue)
          ? this.fileSystem
          : fileSystem as ManualImportFileSystemResult?,
      currentPath: identical(currentPath, _noValue)
          ? this.currentPath
          : currentPath as String?,
      selectedFolder: identical(selectedFolder, _noValue)
          ? this.selectedFolder
          : selectedFolder as String?,
      items: items ?? this.items,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      fixSelectionPaths: fixSelectionPaths ?? this.fixSelectionPaths,
      submittedItems: submittedItems ?? this.submittedItems,
      submittedPaths: submittedPaths ?? this.submittedPaths,
      qualityOptions: qualityOptions ?? this.qualityOptions,
      languageOptions: languageOptions ?? this.languageOptions,
      command: identical(command, _noValue)
          ? this.command
          : command as ManualImportCommandStatus?,
      isLoadingBrowse: isLoadingBrowse ?? this.isLoadingBrowse,
      isLoadingItems: isLoadingItems ?? this.isLoadingItems,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      importMode: importMode ?? this.importMode,
      error: identical(error, _noValue) ? this.error : error as String?,
    );
  }
}

class ManualImportFlowNotifier extends Notifier<ManualImportFlowState> {
  @override
  ManualImportFlowState build() => const ManualImportFlowState();

  Future<void> start(
    ServiceKey service, {
    int? targetId,
    bool force = false,
    String? initialPath,
  }) async {
    if (!force &&
        initialPath == null &&
        state.service == service &&
        state.targetId == targetId &&
        state.rootFolders.isNotEmpty) {
      return;
    }

    state = ManualImportFlowState(
      service: service,
      targetId: targetId,
      isLoadingBrowse: true,
    );

    try {
      final api = ref.read(manualImportServiceProvider(service));
      final rootFolders = await api.getRootFolders();
      final defaultPath = initialPath ?? '/';
      state = state.copyWith(
        rootFolders: rootFolders,
        isLoadingBrowse: false,
        currentPath: defaultPath,
        selectedFolder: defaultPath,
        error: null,
      );
      await selectFolder(defaultPath);
    } catch (error) {
      state = state.copyWith(
        isLoadingBrowse: false,
        error: mapImportError(error, service),
      );
    }
  }

  Future<void> selectFolder(String path) async {
    final service = state.service;
    if (service == null || path.isEmpty) return;

    state = state.copyWith(
      currentPath: path,
      selectedFolder: path,
      fileSystem: null,
      isLoadingBrowse: true,
      error: null,
    );

    try {
      final api = ref.read(manualImportServiceProvider(service));
      final fileSystem = await api.getFileSystem(path);
      state = state.copyWith(fileSystem: fileSystem, isLoadingBrowse: false);
    } catch (error) {
      state = state.copyWith(
        isLoadingBrowse: false,
        error: mapImportError(error, service),
      );
    }
  }

  Future<void> loadSelectedFolderItems() async {
    final items = await _refreshSelectedFolderItems(clearItems: true);
    if (items.isNotEmpty || state.error == null) _persistLastFolder();
    await _applyTargetPreselection();
  }

  /// Remembers the scanned folder so Locate can offer it back next time.
  void _persistLastFolder() {
    final service = state.service;
    final folder = state.selectedFolder;
    if (service == null || folder == null || folder.isEmpty || folder == '/') {
      return;
    }
    // Best-effort convenience: tests run without a prefs override, and a
    // missing shortcut must never fail a scan that succeeded.
    try {
      ref
          .read(sharedPreferencesProvider)
          .setString(manualImportLastFolderKey(service), folder);
      ref.invalidate(manualImportLastFolderProvider(service));
    } catch (_) {}
  }

  /// When the flow was launched from a specific movie/series/artist
  /// ([ManualImportFlowState.targetId]), pre-assign that title as the match for
  /// files the server could not identify — so the user doesn't have to re-match
  /// what they already came from. Movies resolve fully; for series/artists this
  /// only fills in files whose season+episode / album+track the server already
  /// parsed. Anything ambiguous is left untouched for the Fix sheet.
  ///
  /// Crucially this reuses the exact same guarded path as the manual bulk-fix
  /// ([applyBulkFixAssignments] + [libraryGuardError]) and only applies an
  /// assignment that is already valid, so it can never produce a broken import
  /// payload; the pre-filled matches remain fully editable before confirming.
  ///
  /// Three things keep the guess from becoming a decision.
  ///
  /// It only ever touches files the service could import at all
  /// ([manualImportIsSupportedFile]) — Radarr's guard is satisfied by a
  /// `movieId` alone, so without that filter a scan of a shared downloads folder
  /// wrote the launch target into every unmatched row it returned: samples,
  /// subtitles, artwork, NFOs.
  ///
  /// It only touches files whose *name* says they are the target
  /// ([manualImportFileNamesTitle]). [targetId] survives every
  /// [selectFolder]/scan for the rest of the flow, and nothing about the launch
  /// pins it to a folder — the entry points that carry a target carry no path —
  /// so "any video file in whatever folder is on screen" meant a scan of the
  /// whole downloads root labelled every unidentified rip in it with the movie
  /// the user happened to come from.
  ///
  /// And it does **not** select what it assigns: a guess the user never reviewed
  /// must not arrive pre-ticked in the batch that "Confirm import" sends.
  Future<void> _applyTargetPreselection() async {
    final service = state.service;
    final targetId = state.targetId;
    if (service == null || targetId == null || targetId <= 0) return;

    final importable = state.items
        .where(
          (item) =>
              item.isSelectable &&
              !item.hasMatchFor(service) &&
              manualImportIsSupportedFile(service, item),
        )
        .toList(growable: false);
    if (importable.isEmpty) return;

    ManualImportLookupResult? target;
    try {
      final matches = await getLibraryMatches();
      for (final option in matches) {
        if (option.id == targetId) {
          target = option;
          break;
        }
      }
    } catch (_) {
      return; // Best-effort: fall back to fully manual matching.
    }
    final match = target;
    if (match == null) return;

    final unmatched = importable
        .where((item) => manualImportFileNamesTitle(match.title, item))
        .toList(growable: false);
    if (unmatched.isEmpty) return;

    final assignments = <ManualImportItem, ManualImportFixAssignment>{};
    for (final item in unmatched) {
      final parsed = _assignmentForItem(service, item);
      final candidate = ManualImportFixAssignment(
        match: match,
        episode: parsed.episode,
        episodes: parsed.episodes,
        album: parsed.album,
        track: parsed.track,
        tracks: parsed.tracks,
      );
      if (libraryGuardError(service, candidate) == null) {
        assignments[item] = candidate;
      }
    }

    if (assignments.isNotEmpty) {
      await applyBulkFixAssignments(assignments, select: false);
    }
  }

  Future<List<ManualImportItem>> _refreshSelectedFolderItems({
    bool preserveSelection = false,
    bool clearItems = false,
    bool preserveCommand = false,
  }) async {
    final service = state.service;
    final folder = state.selectedFolder;
    if (service == null || folder == null || folder.isEmpty) return const [];

    final previousSelected = state.selectedPaths;
    // A fresh scan of a folder starts a new session and drops any command; a
    // refresh *of the same* scan must keep it, or the files it is importing
    // would come back selectable mid-flight.
    final Object? commandArg = preserveCommand ? _noValue : null;
    final blocked = preserveCommand ? state.blockedPaths : const <String>{};

    state = state.copyWith(
      isLoadingItems: true,
      items: clearItems ? const [] : null,
      selectedPaths: preserveSelection ? null : const {},
      fixSelectionPaths: const {},
      command: commandArg,
      submittedPaths: preserveCommand ? null : const {},
      error: null,
    );

    try {
      final api = ref.read(manualImportServiceProvider(service));
      final items = await api.getManualImportItems(
        folder: folder,
        // Always: the files the service already holds are part of the review,
        // not noise. Left filtered, an already-imported file simply vanishes
        // from the scan — which is how "is this one already in the library?"
        // came to have no answer, and how a folder that looked half-empty was
        // actually reporting a successful earlier import.
        filterExistingFiles: false,
      );
      // Only files that are actually importable are preselected. Selecting the
      // unmatched ones too is how the old flow ended up with a confirm button
      // that one bad file could hold hostage — and an already-imported file is
      // never preselected either, because sending one again is a decision the
      // user makes, not a default.
      final readyPaths = items
          .where(
            (item) =>
                item.isReadyForImportFor(service) &&
                !blocked.contains(item.path),
          )
          .map((item) => item.path)
          .toSet();
      // A preserved selection may legitimately hold a ticked re-import, so the
      // surviving set is everything submittable rather than everything ready.
      final selectedPaths = preserveSelection
          ? previousSelected.intersection(
              items
                  .where(
                    (item) =>
                        item.isSubmittableFor(service) &&
                        !blocked.contains(item.path),
                  )
                  .map((item) => item.path)
                  .toSet(),
            )
          : readyPaths;
      state = state.copyWith(
        items: items,
        selectedPaths: selectedPaths,
        isLoadingItems: false,
      );
      return items;
    } catch (error) {
      state = state.copyWith(
        isLoadingItems: false,
        error: mapImportError(error, service),
      );
      return const [];
    }
  }

  void toggleItem(ManualImportItem item, bool selected) {
    final service = state.service;
    // A matched file, or an already-imported one the user is deliberately
    // sending again. An unmatched file gets here through the fix flow, which
    // selects it once it becomes valid. A file already handed to a command in
    // this session is never selectable again.
    if (service == null ||
        !item.isSubmittableFor(service) ||
        state.blockedPaths.contains(item.path)) {
      return;
    }
    final next = {...state.selectedPaths};
    if (selected) {
      next.add(item.path);
    } else {
      next.remove(item.path);
    }
    state = state.copyWith(selectedPaths: next);
  }

  void toggleAllReady() {
    if (state.allReadySelected) {
      state = state.copyWith(selectedPaths: const {});
      return;
    }

    state = state.copyWith(
      selectedPaths: state.readyItems.map((item) => item.path).toSet(),
    );
  }

  /// Replaces the selection with exactly [items].
  ///
  /// The payoff of the filter: narrow to one series, take those and nothing
  /// else. Without it a filtered view still imports whatever was selected off
  /// screen, which is the one thing a user who filtered did not ask for.
  void selectOnly(List<ManualImportItem> items) {
    final service = state.service;
    if (service == null) return;
    state = state.copyWith(
      selectedPaths: items
          .where((item) => item.isReadyForImportFor(service))
          .map((item) => item.path)
          .toSet(),
    );
  }

  /// Selects or clears a whole group of ready files at once.
  ///
  /// The gesture the grouped list exists for: one tap to take every episode of
  /// one series, rather than forty taps down a flat list of four hundred.
  void setGroupSelected(List<ManualImportItem> group, bool selected) {
    final service = state.service;
    if (service == null) return;
    final paths = group
        .where((item) => item.isReadyForImportFor(service))
        .map((item) => item.path)
        .toSet();
    if (paths.isEmpty) return;

    final next = {...state.selectedPaths};
    if (selected) {
      next.addAll(paths);
    } else {
      next.removeAll(paths);
    }
    state = state.copyWith(selectedPaths: next);
  }

  /// Ticks an unmatched file into the shared-assignment selection.
  void toggleFixSelection(ManualImportItem item, bool selected) {
    final next = {...state.fixSelectionPaths};
    if (selected) {
      next.add(item.path);
    } else {
      next.remove(item.path);
    }
    state = state.copyWith(fixSelectionPaths: next);
  }

  void clearFixSelection() {
    if (state.fixSelectionPaths.isEmpty) return;
    state = state.copyWith(fixSelectionPaths: const {});
  }

  Future<List<ManualImportLookupResult>> lookup(String term) async {
    final service = state.service;
    if (service == null) return const [];
    return ref.read(manualImportServiceProvider(service)).lookup(term);
  }

  Future<List<ManualImportLookupResult>> getLibraryMatches() async {
    final service = state.service;
    if (service == null) return const [];
    return ref.read(manualImportServiceProvider(service)).getLibraryMatches();
  }

  Future<List<ManualImportQualityOption>> getQualityOptions() async {
    final service = state.service;
    if (service == null) return const [];
    if (state.qualityOptions.isNotEmpty) return state.qualityOptions;

    try {
      final options = await ref
          .read(manualImportServiceProvider(service))
          .getQualityOptions();
      state = state.copyWith(qualityOptions: options);
      return options;
    } catch (error) {
      state = state.copyWith(error: mapImportError(error, service));
      return const [];
    }
  }

  Future<List<ManualImportLanguageOption>> getLanguageOptions() async {
    final service = state.service;
    if (service == null) return const [];
    if (state.languageOptions.isNotEmpty) return state.languageOptions;

    try {
      final options = await ref
          .read(manualImportServiceProvider(service))
          .getLanguageOptions();
      state = state.copyWith(languageOptions: options);
      return options;
    } catch (error) {
      state = state.copyWith(error: mapImportError(error, service));
      return const [];
    }
  }

  void setImportMode(ManualImportMode importMode) {
    state = state.copyWith(importMode: importMode);
  }

  /// Applies a fix assignment to a single item locally — no API call.
  ///
  /// The actual import is triggered separately via [confirmImport], which
  /// POSTs the `ManualImport` command for all currently selected items.
  /// This method only updates the in-memory item so that
  /// `isReadyForImportFor(service)` returns true and the item can be added
  /// to the selection.
  Future<ManualImportItem?> applyFixAssignment(
    ManualImportItem item,
    ManualImportFixAssignment assignment,
  ) async {
    final service = state.service;
    if (service == null) return null;

    final guardError = libraryGuardError(service, assignment);
    if (guardError != null) {
      state = state.copyWith(error: guardError);
      return null;
    }

    final resolved = item.resolvedWithAssignment(service, assignment);
    state = state.copyWith(
      items: [
        // Matched on the path alone. The id used to be an alternative here, but
        // it is not an identity: `ManualImportItem.fromJson` falls back to
        // `path.hashCode` when the server sends none, so the clause was
        // redundant for every conforming payload while leaving one service that
        // returns a constant id able to splatter one resolved item over every
        // row in the scan. The path is what the import command sends, so the
        // path is what selects the row it belongs to.
        for (final existing in state.items)
          if (existing.path == item.path) resolved else existing,
      ],
      // Auto-select the now-ready item so "Confirm import" picks it up.
      selectedPaths: {...state.selectedPaths, resolved.path},
      error: null,
    );
    return resolved;
  }

  Future<ManualImportItem?> updateItemMetadata(
    ManualImportItem item, {
    ManualImportQualityOption? quality,
    List<ManualImportLanguageOption>? languages,
  }) async {
    final service = state.service;
    if (service == null) return null;
    if (!item.hasMatchFor(service)) return item;

    final qualityOverride = quality?.toQualityModel(
      currentQuality: item.quality,
    );
    final languageOverride = languages
        ?.map((item) => item.toLanguageResource())
        .toList(growable: false);
    final draft = item.withMetadataOverrides(
      quality: qualityOverride,
      languages: languageOverride,
    );

    final assignment = _assignmentForItem(service, draft);

    return applyFixAssignment(draft, assignment);
  }

  /// Applies fix assignments to a batch of items locally — no API call.
  ///
  /// Mirrors [applyFixAssignment] for the bulk fix flow. The actual import
  /// is triggered separately via [confirmImport].
  ///
  /// [select] adds the now-ready files to the import selection, which is right
  /// when the user just assigned them by hand and wrong when the app guessed on
  /// their behalf — see [_applyTargetPreselection].
  Future<List<ManualImportItem>> applyBulkFixAssignments(
    Map<ManualImportItem, ManualImportFixAssignment> assignments, {
    bool select = true,
  }) async {
    final service = state.service;
    if (service == null || assignments.isEmpty) return const [];

    // Library guard — fail fast, don't update state for invalid assignments.
    for (final entry in assignments.entries) {
      final guardError = libraryGuardError(service, entry.value);
      if (guardError != null) {
        state = state.copyWith(error: guardError);
        return const [];
      }
    }

    final updatedByPath = <String, ManualImportItem>{};
    for (final entry in assignments.entries) {
      final resolved = entry.key.resolvedWithAssignment(service, entry.value);
      updatedByPath[entry.key.path] = resolved;
    }
    state = state.copyWith(
      items: [
        for (final existing in state.items)
          updatedByPath[existing.path] ?? existing,
      ],
      // Auto-select the now-ready items so "Confirm import" picks them up.
      selectedPaths: select
          ? {...state.selectedPaths, ...updatedByPath.keys}
          : state.selectedPaths,
      // They are no longer unmatched, so the shared-assignment tick is spent.
      fixSelectionPaths: state.fixSelectionPaths.difference(
        updatedByPath.keys.toSet(),
      ),
      error: null,
    );
    final refreshed = state.items
        .where((item) => updatedByPath.containsKey(item.path))
        .toList(growable: false);
    return refreshed;
  }

  Future<List<ManualImportEpisode>> getEpisodes({
    required int seriesId,
    int? seasonNumber,
  }) async {
    final service = state.service;
    if (service != ServiceKey.sonarr) return const [];
    return ref
        .read(manualImportServiceProvider(service!))
        .getEpisodes(seriesId: seriesId, seasonNumber: seasonNumber);
  }

  Future<List<ManualImportAlbum>> getAlbums(int artistId) async {
    final service = state.service;
    if (service != ServiceKey.lidarr) return const [];
    return ref.read(manualImportServiceProvider(service!)).getAlbums(artistId);
  }

  Future<List<ManualImportTrack>> getTracks(int albumId) async {
    final service = state.service;
    if (service != ServiceKey.lidarr) return const [];
    return ref
        .read(manualImportServiceProvider(service!))
        .getTracks(albumId: albumId);
  }

  /// Posts the selected files as one `ManualImport` command.
  ///
  /// Returns the existing command, without posting, when there is nothing new
  /// to send — so navigating back into Track is always safe and pressing the
  /// button twice can never queue the same files twice.
  Future<ManualImportCommandStatus?> confirmImport() async {
    final service = state.service;
    if (service == null) return null;

    // Everything already handed over: this is a navigation, not a submission.
    final files = state.selectedItems
        .where((item) => !state.blockedPaths.contains(item.path))
        .toList(growable: false);
    if (files.isEmpty) return state.command;
    if (!state.canImportSelected) return null;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final api = ref.read(manualImportServiceProvider(service));
      final command = await api.startManualImport(
        files,
        importMode: state.importMode,
        // Only when the batch genuinely contains a file the service already
        // holds: this flag lets Lidarr overwrite what is in the library, and it
        // has no business being on for an ordinary import.
        replaceExistingFiles: files.any((item) => item.isAlreadyImported),
      );
      final submitted = files.map((item) => item.path).toSet();
      state = state.copyWith(
        command: command,
        submittedItems: files,
        // The batch is spent: drop it from the selection and record it, so the
        // Review screen behind Track offers no way to send it again.
        submittedPaths: {...state.submittedPaths, ...submitted},
        selectedPaths: state.selectedPaths.difference(submitted),
        isSubmitting: false,
      );
      return command;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        error: mapImportError(error, service),
      );
      return null;
    }
  }

  /// Re-reads the folder when the user comes back from Track.
  ///
  /// The service is the authority on what is still on disk: files it imported
  /// are gone, files it failed on are still there. Keeping the command and the
  /// submitted set through the refresh is what stops a still-present file from
  /// quietly becoming selectable again while its import is in flight.
  Future<void> refreshAfterImport() async {
    if (state.command == null || state.isLoadingItems) return;
    await _refreshSelectedFolderItems(
      preserveSelection: true,
      preserveCommand: true,
    );
  }

  Future<void> pollCommand() async {
    final service = state.service;
    final command = state.command;
    if (service == null || command == null || !command.isActive) return;

    try {
      final api = ref.read(manualImportServiceProvider(service));
      final next = await api.getCommand(command.id);
      state = state.copyWith(command: next);
    } catch (error) {
      state = state.copyWith(error: mapImportError(error, service));
    }
  }
}

ManualImportFixAssignment _assignmentForItem(
  ServiceKey service,
  ManualImportItem item,
) {
  final matchPayload = switch (service) {
    ServiceKey.radarr => item.movie ?? const <String, dynamic>{},
    ServiceKey.sonarr => item.series ?? const <String, dynamic>{},
    ServiceKey.lidarr => item.artist ?? const <String, dynamic>{},
    _ => const <String, dynamic>{},
  };
  final episodes = service == ServiceKey.sonarr
      ? item.episodes
            .map(ManualImportEpisode.fromJson)
            .where((item) => item.id > 0)
            .toList(growable: false)
      : const <ManualImportEpisode>[];
  final episode = service == ServiceKey.sonarr && item.episodes.isNotEmpty
      ? ManualImportEpisode.fromJson(item.episodes.first)
      : null;
  final tracks = service == ServiceKey.lidarr
      ? item.tracks
            .map(ManualImportTrack.fromJson)
            .where((item) => item.id > 0)
            .toList(growable: false)
      : const <ManualImportTrack>[];
  final track = service == ServiceKey.lidarr && item.tracks.isNotEmpty
      ? ManualImportTrack.fromJson(item.tracks.first)
      : null;

  return ManualImportFixAssignment(
    match: ManualImportLookupResult.fromJson(service, matchPayload),
    episode: episode,
    episodes: episodes,
    album: service == ServiceKey.lidarr && item.album != null
        ? ManualImportAlbum.fromJson(item.album!)
        : null,
    track: track,
    tracks: tracks,
  );
}

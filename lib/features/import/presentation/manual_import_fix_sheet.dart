import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/import/presentation/manual_import_widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

Future<void> showManualImportFixSheet({
  required BuildContext context,
  required ServiceKey service,
  required ManualImportItem item,
}) {
  return _showFixSheet(
    context: context,
    service: service,
    child: _ManualImportFixSheet(service: service, item: item),
  );
}

Future<void> showManualImportBulkFixSheet({
  required BuildContext context,
  required ServiceKey service,
  required List<ManualImportItem> items,
}) {
  return _showFixSheet(
    context: context,
    service: service,
    child: _ManualImportFixSheet(service: service, bulkItems: items),
  );
}

Future<void> _showFixSheet({
  required BuildContext context,
  required ServiceKey service,
  required Widget child,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    barrierColor: Colors.black.withValues(alpha: isDark ? 0.55 : 0.3),
    backgroundColor: Colors.transparent,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.86,
      child: _FixSheetChrome(service: service, child: child),
    ),
  );
}

class _FixSheetChrome extends StatelessWidget {
  final ServiceKey service;
  final Widget child;

  const _FixSheetChrome({required this.service, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
        boxShadow: AppElevation.level3(colorScheme),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const AppSheetHandle(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ManualImportFixSheet extends ConsumerStatefulWidget {
  final ServiceKey service;
  final ManualImportItem? item;
  final List<ManualImportItem> bulkItems;

  const _ManualImportFixSheet({
    required this.service,
    this.item,
    this.bulkItems = const [],
  });

  bool get isBulk => bulkItems.isNotEmpty;

  @override
  ConsumerState<_ManualImportFixSheet> createState() =>
      _ManualImportFixSheetState();
}

class _ManualImportFixSheetState extends ConsumerState<_ManualImportFixSheet> {
  final _searchController = TextEditingController();
  final _episodeAssignments = <String, ManualImportEpisode>{};
  final _trackAssignments = <String, ManualImportTrack>{};
  Timer? _debounce;
  bool _libraryLoaded = false;
  List<ManualImportLookupResult> _allResults = const [];
  List<ManualImportLookupResult> _results = const [];
  List<ManualImportEpisode> _episodes = const [];
  List<ManualImportAlbum> _albums = const [];
  List<ManualImportTrack> _tracks = const [];
  ManualImportLookupResult? _match;
  ManualImportAlbum? _album;
  int? _seasonNumber;
  int _step = 0;
  bool _loading = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadLibraryResults);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final bulkCount = widget.bulkItems.length;
    final title = switch (service) {
      ServiceKey.radarr => 'Assign movie identity',
      ServiceKey.sonarr => 'Assign episode identity',
      ServiceKey.lidarr => 'Assign music identity',
      _ => 'Assign identity',
    };
    final subtitle = widget.isBulk
        ? 'Applying one identity to $bulkCount files'
        : widget.item?.fileName ?? 'Unmatched file';

    return Column(
      children: [
        _SheetHeader(service: service, title: title, subtitle: subtitle),
        // Naming the files is the guard against a bulk assignment doing
        // something the user did not intend: one identity across a mixed
        // selection is only ever correct if they can see what is in it.
        if (widget.isBulk) _AppliesToStrip(items: widget.bulkItems),
        if (service != ServiceKey.radarr)
          ImportStationBar(
            service: service,
            stations: _stepLabels(service),
            activeIndex: _step,
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppAnimation.durationSm,
            child: _buildStep(context),
          ),
        ),
        _SheetFooter(
          service: service,
          canGoBack: _step > 0,
          canGoNext: _canGoNext,
          canApply: _canApply,
          applying: _applying,
          isLastStep: _isLastStep,
          onBack: _back,
          onCancel: () => Navigator.of(context).pop(),
          onNext: _next,
          onApply: _apply,
        ),
      ],
    );
  }

  Widget _buildStep(BuildContext context) {
    final service = widget.service;
    if (service == ServiceKey.radarr || _step == 0) {
      return _SearchStep(
        key: ValueKey('search-${service.name}'),
        service: service,
        controller: _searchController,
        results: _results,
        selected: _match,
        loading: _loading,
        onChanged: _lookup,
        onSelected: (match) async {
          setState(() => _match = match);
          if (service == ServiceKey.radarr) {
            await _apply();
          }
        },
      );
    }

    if (service == ServiceKey.sonarr) {
      return _step == 1 ? _buildSeasonStep() : _buildEpisodeStep();
    }

    if (service == ServiceKey.lidarr) {
      return _step == 1 ? _buildAlbumStep() : _buildTrackStep();
    }

    return const SizedBox.shrink();
  }

  Widget _buildSeasonStep() {
    final seasons =
        _episodes
            .map((item) => item.seasonNumber)
            .toSet()
            .toList(growable: false)
          ..sort();
    return _ChoiceList<int>(
      key: const ValueKey('season'),
      service: widget.service,
      emptyMessage: 'No episodes found for this series.',
      values: seasons,
      selected: _seasonNumber,
      titleFor: (item) => 'Season $item',
      subtitleFor: (item) =>
          '${_episodes.where((episode) => episode.seasonNumber == item).length} episodes',
      onSelected: (item) => setState(() => _seasonNumber = item),
    );
  }

  Widget _buildEpisodeStep() {
    final episodes = _episodes
        .where((item) => item.seasonNumber == _seasonNumber)
        .toList(growable: false);
    return widget.isBulk
        ? _BulkMap<ManualImportEpisode>(
            key: const ValueKey('episode-bulk'),
            service: widget.service,
            items: widget.bulkItems,
            values: episodes,
            assignments: _episodeAssignments,
            titleFor: (item) => '${item.label} · ${item.title}',
            onChanged: (item, episode) {
              setState(() => _episodeAssignments[item.path] = episode);
            },
          )
        : _ChoiceList<ManualImportEpisode>(
            key: const ValueKey('episode-single'),
            service: widget.service,
            emptyMessage: 'No episodes found for this season.',
            values: episodes,
            selected: _episodeAssignments[widget.item?.path],
            titleFor: (item) => '${item.label} · ${item.title}',
            subtitleFor: (_) => 'Episode',
            onSelected: (item) {
              final path = widget.item?.path;
              if (path != null) {
                setState(() => _episodeAssignments[path] = item);
              }
            },
          );
  }

  Widget _buildAlbumStep() {
    return _ChoiceList<ManualImportAlbum>(
      key: const ValueKey('album'),
      service: widget.service,
      emptyMessage: 'No albums found for this artist.',
      values: _albums,
      selected: _album,
      titleFor: (item) => item.title,
      subtitleFor: (item) => item.year?.toString() ?? 'Album',
      onSelected: (item) => setState(() => _album = item),
    );
  }

  Widget _buildTrackStep() {
    return widget.isBulk
        ? _BulkMap<ManualImportTrack>(
            key: const ValueKey('track-bulk'),
            service: widget.service,
            items: widget.bulkItems,
            values: _tracks,
            assignments: _trackAssignments,
            titleFor: (item) => item.label,
            onChanged: (item, track) {
              setState(() => _trackAssignments[item.path] = track);
            },
          )
        : _ChoiceList<ManualImportTrack>(
            key: const ValueKey('track-single'),
            service: widget.service,
            emptyMessage: 'No tracks found for this album.',
            values: _tracks,
            selected: _trackAssignments[widget.item?.path],
            titleFor: (item) => item.label,
            subtitleFor: (_) => 'Track',
            onSelected: (item) {
              final path = widget.item?.path;
              if (path != null) {
                setState(() => _trackAssignments[path] = item);
              }
            },
          );
  }

  List<String> _stepLabels(ServiceKey service) {
    return switch (service) {
      ServiceKey.sonarr => const ['Series', 'Season', 'Episode'],
      ServiceKey.lidarr => const ['Artist', 'Album', 'Track'],
      ServiceKey.radarr => const ['Movie'],
      _ => const ['Match'],
    };
  }

  bool get _isLastStep {
    return switch (widget.service) {
      ServiceKey.radarr => true,
      ServiceKey.sonarr || ServiceKey.lidarr => _step == 2,
      _ => true,
    };
  }

  bool get _canGoNext {
    return switch (widget.service) {
      ServiceKey.sonarr =>
        (_step == 0 && _match != null) || (_step == 1 && _seasonNumber != null),
      ServiceKey.lidarr =>
        (_step == 0 && _match != null) || (_step == 1 && _album != null),
      _ => false,
    };
  }

  bool get _canApply {
    if (_applying || _match == null) return false;
    return switch (widget.service) {
      ServiceKey.radarr => true,
      ServiceKey.sonarr =>
        widget.isBulk
            ? widget.bulkItems.every(
                (item) => _episodeAssignments.containsKey(item.path),
              )
            : _episodeAssignments.containsKey(widget.item?.path),
      ServiceKey.lidarr =>
        _album != null &&
            (widget.isBulk
                ? widget.bulkItems.every(
                    (item) => _trackAssignments.containsKey(item.path),
                  )
                : _trackAssignments.containsKey(widget.item?.path)),
      _ => false,
    };
  }

  Future<void> _loadLibraryResults() async {
    setState(() => _loading = true);
    final results = await ref
        .read(manualImportFlowProvider.notifier)
        .getLibraryMatches();
    if (!mounted) return;
    setState(() {
      _allResults = results;
      _results = _filterResults('');
      _libraryLoaded = true;
      _loading = false;
    });
  }

  List<ManualImportLookupResult> _filterResults(String term) {
    final query = term.trim().toLowerCase();
    if (query.isEmpty) return _allResults.take(12).toList(growable: false);
    return _allResults
        .where((result) {
          final title = result.title.toLowerCase();
          final subtitle = result.subtitle?.toLowerCase() ?? '';
          return title.contains(query) || subtitle.contains(query);
        })
        .take(12)
        .toList(growable: false);
  }

  Future<void> _loadLookupResults(
    String term, {
    required bool filterOnly,
  }) async {
    final query = term.trim();
    if (!mounted) return;

    if (query.isEmpty) {
      if (!_libraryLoaded) {
        await _loadLibraryResults();
        return;
      }
      setState(() {
        _results = _filterResults(query);
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = !filterOnly;
      _results = _filterResults(query);
    });

    if (filterOnly && _results.isNotEmpty) {
      return;
    }

    final results = await ref
        .read(manualImportFlowProvider.notifier)
        .lookup(query);
    if (!mounted) return;
    setState(() {
      _allResults = _mergeResults(_allResults, results);
      _results = _filterResults(query);
      _loading = false;
    });
  }

  List<ManualImportLookupResult> _mergeResults(
    List<ManualImportLookupResult> current,
    List<ManualImportLookupResult> incoming,
  ) {
    final merged = <int, ManualImportLookupResult>{
      for (final result in current) result.id: result,
    };
    for (final result in incoming) {
      merged[result.id] = result;
    }
    final values = merged.values.toList(growable: false);
    values.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return values;
  }

  void _lookup(String term) {
    _debounce?.cancel();
    final normalized = term.trim();
    setState(() {
      _results = _filterResults(normalized);
    });
    _debounce = Timer(
      AppAnimation.durationSm,
      () => _loadLookupResults(normalized, filterOnly: _allResults.isNotEmpty),
    );
  }

  Future<void> _next() async {
    final match = _match;
    if (match == null) return;

    if (widget.service == ServiceKey.sonarr && _step == 0) {
      setState(() => _loading = true);
      final episodes = await ref
          .read(manualImportFlowProvider.notifier)
          .getEpisodes(seriesId: match.id);
      if (!mounted) return;
      final guessedSeason = widget.item?.seasonNumber;
      setState(() {
        _episodes = episodes;
        _seasonNumber =
            guessedSeason != null &&
                episodes.any((item) => item.seasonNumber == guessedSeason)
            ? guessedSeason
            : null;
        _loading = false;
        _step = 1;
      });
      return;
    }

    if (widget.service == ServiceKey.lidarr && _step == 0) {
      setState(() => _loading = true);
      final albums = await ref
          .read(manualImportFlowProvider.notifier)
          .getAlbums(match.id);
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _loading = false;
        _step = 1;
      });
      return;
    }

    if (widget.service == ServiceKey.lidarr && _step == 1) {
      final album = _album;
      if (album == null) return;
      setState(() => _loading = true);
      final tracks = await ref
          .read(manualImportFlowProvider.notifier)
          .getTracks(album.id);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
        _step = 2;
      });
      return;
    }

    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
  }

  Future<void> _apply() async {
    final match = _match;
    if (match == null || !_canApply) return;
    setState(() => _applying = true);

    final notifier = ref.read(manualImportFlowProvider.notifier);
    final beforeError = ref.read(manualImportFlowProvider).error;
    if (widget.isBulk) {
      await notifier.applyBulkFixAssignments({
        for (final item in widget.bulkItems) item: _assignmentFor(item, match),
      });
    } else {
      final item = widget.item;
      if (item != null) {
        await notifier.applyFixAssignment(item, _assignmentFor(item, match));
      }
    }

    final afterError = ref.read(manualImportFlowProvider).error;
    final hasNewError = afterError != null && afterError != beforeError;
    if (mounted && !hasNewError) {
      setState(() => _applying = false);
      Navigator.of(context).pop();
      return;
    }

    if (mounted) {
      setState(() => _applying = false);
    }
  }

  ManualImportFixAssignment _assignmentFor(
    ManualImportItem item,
    ManualImportLookupResult match,
  ) {
    final episode = _episodeAssignments[item.path];
    final track = _trackAssignments[item.path];
    return ManualImportFixAssignment(
      match: match,
      episode: episode,
      episodes: [if (episode != null) episode],
      album: _album,
      track: track,
      tracks: [if (track != null) track],
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final ServiceKey service;
  final String title;
  final String subtitle;

  const _SheetHeader({
    required this.service,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: serviceThemeFor(service).softContainer,
                borderRadius: AppRadius.borderRadiusMd,
              ),
              child: Icon(service.icon, color: service.accent, size: 20),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium!.weight(FontWeight.w800),
                ),
                // Wraps in full. Assigning an identity means reading the file
                // name for the clues the service could not parse — the year,
                // the date, the episode marker — so eliding it to one line
                // hides the only evidence the decision can be made from.
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The files a bulk assignment will be written to.
class _AppliesToStrip extends StatelessWidget {
  final List<ManualImportItem> items;

  const _AppliesToStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const visible = 3;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: AppCard.filled(
        padding: const EdgeInsets.all(AppSpacing.md),
        backgroundColor: colorScheme.surfaceContainerHigh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Full names, wrapped: this list is the guard against a bulk
            // assignment doing something unintended, and a truncated name
            // cannot be checked.
            for (final item in items.take(visible))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  item.fileName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (items.length > visible)
              Text(
                '+${items.length - visible} more',
                style: theme.textTheme.labelSmall!
                    .weight(FontWeight.w700)
                    .tabular
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchStep extends StatelessWidget {
  final ServiceKey service;
  final TextEditingController controller;
  final List<ManualImportLookupResult> results;
  final ManualImportLookupResult? selected;
  final bool loading;
  final ValueChanged<String> onChanged;
  final ValueChanged<ManualImportLookupResult> onSelected;

  const _SearchStep({
    super.key,
    required this.service,
    required this.controller,
    required this.results,
    required this.selected,
    required this.loading,
    required this.onChanged,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        SearchBar(
          controller: controller,
          hintText: service.manualImportSearchHint,
          leading: Icon(Icons.search_rounded, color: service.accent, size: 18),
          trailing: [
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded, size: 16),
              ),
            if (loading)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
          onChanged: onChanged,
          elevation: WidgetStateProperty.all(0),
          backgroundColor: WidgetStateProperty.all(
            colorScheme.surfaceContainerHighest,
          ),
          side: WidgetStateProperty.all(BorderSide.none),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusMd),
          ),
          constraints: const BoxConstraints(minHeight: 48),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (!loading && results.isEmpty)
          AppEmptyState.compact(
            icon: Icons.manage_search_rounded,
            title: 'No matches available',
            message: controller.text.trim().isEmpty
                ? 'No items were found in your library for this service.'
                : 'Try a different query to filter the library or load more results.',
            accentColor: service.accent,
          ),
        for (final result in results)
          _ResultTile(
            service: service,
            title: result.title,
            subtitle: result.subtitle,
            selected: selected?.id == result.id,
            onTap: () => onSelected(result),
          ),
      ],
    );
  }
}

class _ChoiceList<T> extends StatelessWidget {
  final ServiceKey service;
  final List<T> values;
  final T? selected;
  final String emptyMessage;
  final String Function(T value) titleFor;
  final String? Function(T value) subtitleFor;
  final ValueChanged<T> onSelected;

  const _ChoiceList({
    super.key,
    required this.service,
    required this.values,
    required this.selected,
    required this.emptyMessage,
    required this.titleFor,
    required this.subtitleFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return AppEmptyState.compact(
        icon: Icons.manage_search_rounded,
        title: emptyMessage,
        accentColor: service.accent,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: values.length,
      itemBuilder: (context, index) {
        final value = values[index];
        return _ResultTile(
          service: service,
          title: titleFor(value),
          subtitle: subtitleFor(value),
          selected: selected == value,
          onTap: () => onSelected(value),
        );
      },
    );
  }
}

class _BulkMap<T> extends StatelessWidget {
  final ServiceKey service;
  final List<ManualImportItem> items;
  final List<T> values;
  final Map<String, T> assignments;
  final String Function(T value) titleFor;
  final void Function(ManualImportItem item, T value) onChanged;

  const _BulkMap({
    super.key,
    required this.service,
    required this.items,
    required this.values,
    required this.assignments,
    required this.titleFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (values.isEmpty) {
      return AppEmptyState.compact(
        icon: Icons.manage_search_rounded,
        title: 'No assignable items found',
        accentColor: service.accent,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall!.weight(FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<T>(
                initialValue: assignments[item.path],
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: colorScheme.surfaceContainer,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.borderRadiusSm,
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadius.borderRadiusSm,
                    borderSide: BorderSide(color: service.accent, width: 1.5),
                  ),
                ),
                hint: const Text('Select match'),
                items: values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(
                          titleFor(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) onChanged(item, value);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final ServiceKey service;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ResultTile({
    required this.service,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = service.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        selected: selected,
        selectedColor: colorScheme.onSurface,
        leading: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: serviceThemeFor(service).softContainer,
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Icon(service.icon, size: 16, color: accent),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall!.weight(FontWeight.w700),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: selected
            ? Icon(Icons.check_rounded, size: 18, color: accent)
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _SheetFooter extends StatelessWidget {
  final ServiceKey service;
  final bool canGoBack;
  final bool canGoNext;
  final bool canApply;
  final bool applying;
  final bool isLastStep;
  final VoidCallback onBack;
  final VoidCallback onCancel;
  final VoidCallback onNext;
  final VoidCallback onApply;

  const _SheetFooter({
    required this.service,
    required this.canGoBack,
    required this.canGoNext,
    required this.canApply,
    required this.applying,
    required this.isLastStep,
    required this.onBack,
    required this.onCancel,
    required this.onNext,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          const Spacer(),
          if (canGoBack) ...[
            OutlinedButton(onPressed: onBack, child: const Text('Back')),
            const SizedBox(width: AppSpacing.sm),
          ],
          FilledButton(
            onPressed: isLastStep
                ? (canApply ? onApply : null)
                : (canGoNext ? onNext : null),
            style: FilledButton.styleFrom(
              backgroundColor: service.accent,
              foregroundColor: ServiceTheme.foregroundOn(service.accent),
              minimumSize: const Size(0, 48),
            ),
            child: applying
                ? SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ServiceTheme.foregroundOn(service.accent),
                    ),
                  )
                : Text(isLastStep ? 'Apply' : 'Next'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart' as dynamic_utils;
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/media_search_popup_menu.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/core/widgets/tag_chip.dart';
import 'package:seekarr/features/activity/presentation/activity_provider.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_tab_helpers.dart';
import 'package:seekarr/features/activity/presentation/widgets/detail_sheets.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class QueueItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;

  const QueueItemTile({
    super.key,
    required this.item,
    required this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedStatus = resolveQueueDisplayStatus(item);
    final title = _queueTitle(item, serviceType);
    final subtitle = _queueSubtitle(item, serviceType);
    final progress = dynamic_utils.queueProgress(
      item,
      parseStrings: false,
      includeSizeLeftAlias: false,
    );
    final chips = _buildQueueChips(item, colorScheme);
    final showInlineProgress =
        progress != null &&
        resolvedStatus.pipeline == MediaPipeline.downloading;
    final statusLabel = queueDisplayLabel(
      resolvedStatus,
      includeWarningSuffix: false,
    );
    final inlineStatus = showInlineProgress
        ? '$statusLabel (${(progress * 100).round()}%)'
        : statusLabel;

    return _TileShell(
      onTap: () => DetailSheets.showQueueDetail(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) _SubtitleText(text: subtitle),
                    _SubtitleText(text: inlineStatus),
                    if (showInlineProgress)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: SizedBox(
                          width: 96,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class HistoryItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;

  const HistoryItemTile({
    super.key,
    required this.item,
    required this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final eventType = stringOrNull(item['eventType']) ?? 'unknown';
    final title = _historyTitle(item, serviceType);
    final subtitle = _historySubtitle(item, serviceType);
    final metadata = joinActivityParts([
      formatDateOnly(stringOrNull(item['date'])),
      _historySizeLabel(item),
    ]);
    final episodeCode = serviceType == ServiceType.series
        ? _historyEpisodeCode(item)
        : null;
    final chips = _buildHistoryChips(item, colorScheme);

    return _TileShell(
      onTap: () => DetailSheets.showHistoryDetail(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (episodeCode != null)
                      TagChip(
                        text: episodeCode,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TagChip(
                text: humanizeEventType(eventType),
                color: _eventTypeColor(eventType),
              ),
            ],
          ),
          if (subtitle != null) _SubtitleText(text: subtitle),
          if (metadata.isNotEmpty)
            _SubtitleText(text: metadata, topSpacing: AppSpacing.sm),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class BlocklistItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;

  const BlocklistItemTile({
    super.key,
    required this.item,
    required this.serviceType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitle = _blocklistSubtitle(item, serviceType);
    final chips = _buildBlocklistChips(item, colorScheme);
    final reason = _blocklistReason(item);

    return _TileShell(
      onTap: () => DetailSheets.showBlocklistDetail(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(
            title: _blocklistTitle(item, serviceType),
            titleStyle: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            trailing: Icon(
              Icons.block_rounded,
              color: colorScheme.error,
              size: 20,
            ),
          ),
          if (subtitle != null) _SubtitleText(text: subtitle),
          _ChipRow(chips: chips),
          if (reason != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            formatRelativeActivityDate(stringOrNull(item['date'])),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class WantedItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final ServiceType serviceType;
  final VoidCallback? onAutoSearch;
  final VoidCallback? onInteractiveSearch;
  final bool isCutoff;
  final String? qualityProfileName;

  const WantedItemTile({
    super.key,
    required this.item,
    required this.serviceType,
    this.onAutoSearch,
    this.onInteractiveSearch,
    this.isCutoff = false,
    this.qualityProfileName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = _wantedTitle(item, serviceType);
    final subtitle = isCutoff && serviceType == ServiceType.movies
        ? null
        : _wantedSubtitle(item, serviceType);
    final statusText = isCutoff
        ? formatCutoffSize(item, serviceType)
        : wantedStatusText(item, serviceType);
    final chips = _buildWantedChips(
      item,
      serviceType,
      colorScheme,
      isCutoff: isCutoff,
      qualityProfileName: qualityProfileName,
    );
    final canSearch = onAutoSearch != null && onInteractiveSearch != null;

    return _TileShell(
      onTap: () => DetailSheets.showWantedDetail(context, item, serviceType),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(
            title: title,
            titleStyle: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: isCutoff ? 1 : null,
            trailing: canSearch
                ? MediaSearchPopupMenu(
                    onAutoSearch: onAutoSearch!,
                    onInteractiveSearch: onInteractiveSearch!,
                    iconSize: 18,
                  )
                : null,
          ),
          if (subtitle != null) _SubtitleText(text: subtitle),
          if (statusText != null)
            _SubtitleText(text: statusText, color: colorScheme.error),
          _ChipRow(chips: chips),
        ],
      ),
    );
  }
}

class GlobalActivityItemTile extends ConsumerWidget {
  final GlobalActivityItem item;

  const GlobalActivityItemTile({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = item.service.accent;
    final raw = item.raw;
    final canSearch =
        raw != null &&
        (item.kind == GlobalActivityKind.missing ||
            item.kind == GlobalActivityKind.cutoff) &&
        extractWantedItemId(item.serviceType, raw) != null;
    final icon = switch (item.kind) {
      GlobalActivityKind.request => Icons.person_add_alt_1_rounded,
      GlobalActivityKind.queue => Icons.downloading_rounded,
      GlobalActivityKind.history => Icons.history_rounded,
      GlobalActivityKind.blocklist => Icons.block_rounded,
      GlobalActivityKind.missing => Icons.warning_amber_rounded,
      GlobalActivityKind.cutoff => Icons.trending_up_rounded,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        onTap: item.raw == null ? null : () => _showDetails(context),
        backgroundColor: colorScheme.surfaceContainer,
        borderColor: colorScheme.outlineVariant,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      TagChip(text: item.service.title, color: accent),
                      TagChip(text: item.status, color: _statusColor(context)),
                      if (item.warning != null)
                        TagChip(
                          text: 'Warning',
                          color: colorScheme.error,
                          icon: Icons.warning_amber_rounded,
                        ),
                    ],
                  ),
                  if (item.progress != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 4,
                        color: accent,
                        backgroundColor: colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (item.progress != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${(item.progress! * 100).round()}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (raw != null && canSearch) ...[
              const SizedBox(width: AppSpacing.xs),
              MediaSearchPopupMenu(
                onAutoSearch: () => _runAutoSearch(context, ref, raw),
                onInteractiveSearch: () =>
                    _showInteractiveSearch(context, ref, raw),
                iconSize: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(BuildContext context) {
    return switch (item.kind) {
      GlobalActivityKind.queue => item.service.accent,
      GlobalActivityKind.history => AppColors.success,
      GlobalActivityKind.blocklist => Theme.of(context).colorScheme.error,
      GlobalActivityKind.missing ||
      GlobalActivityKind.cutoff => AppColors.warning,
      GlobalActivityKind.request => item.service.accent,
    };
  }

  void _showDetails(BuildContext context) {
    final raw = item.raw;
    if (raw == null) return;
    switch (item.kind) {
      case GlobalActivityKind.queue:
        DetailSheets.showQueueDetail(context, raw);
        break;
      case GlobalActivityKind.history:
        DetailSheets.showHistoryDetail(context, raw);
        break;
      case GlobalActivityKind.blocklist:
        DetailSheets.showBlocklistDetail(context, raw);
        break;
      case GlobalActivityKind.missing:
      case GlobalActivityKind.cutoff:
        DetailSheets.showWantedDetail(context, raw, item.serviceType);
        break;
      case GlobalActivityKind.request:
        break;
    }
  }

  void _runAutoSearch(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> raw,
  ) {
    runWantedAutoSearch(
      context,
      ref.read(resolvedArrServiceProvider(item.serviceType)),
      item.serviceType,
      raw,
    );
  }

  void _showInteractiveSearch(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> raw,
  ) {
    showWantedInteractiveSearch(
      context,
      ref.read(resolvedArrServiceProvider(item.serviceType)),
      item.serviceType,
      raw,
      title: 'Releases for ${item.title}',
    );
  }
}

class _TileShell extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _TileShell({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        onTap: onTap,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        borderColor: Theme.of(context).colorScheme.outlineVariant,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: child,
      ),
    );
  }
}

class _SubtitleText extends StatelessWidget {
  final String text;
  final Color? color;
  final double topSpacing;

  const _SubtitleText({
    required this.text,
    this.color,
    this.topSpacing = AppSpacing.xs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: topSpacing),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color ?? colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<Widget> chips;

  const _ChipRow({required this.chips});

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: chips,
        ),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  final String title;
  final TextStyle? titleStyle;
  final Widget? trailing;
  final int? maxLines;

  const _TitleRow({
    required this.title,
    this.titleStyle,
    this.trailing,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: titleStyle,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}

List<Widget> _buildQueueChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final quality = extractQualityName(item);
  final protocol = stringOrNull(item['protocol']);
  final downloadClient = stringOrNull(item['downloadClient']);
  final hasWarning = arrQueueHasWarning(item);

  return [
    if (hasWarning)
      TagChip(
        text: 'Warning',
        color: colorScheme.error,
        icon: Icons.warning_amber_rounded,
      ),
    if (quality != null) TagChip(text: quality),
    if (protocol != null) TagChip(text: protocol, color: AppColors.info),
    if (downloadClient != null)
      TagChip(text: downloadClient, color: colorScheme.tertiary),
  ];
}

List<Widget> _buildHistoryChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final quality = extractQualityName(item);
  final indexer = stringOrNull(asActivityMap(item['data'])?['indexer']);

  return [
    if (quality != null) TagChip(text: quality),
    if (indexer != null) TagChip(text: indexer, color: colorScheme.tertiary),
  ];
}

List<Widget> _buildBlocklistChips(
  Map<String, dynamic> item,
  ColorScheme colorScheme,
) {
  final protocol = stringOrNull(item['protocol']);
  final indexer = stringOrNull(item['indexer']);

  return [
    if (protocol != null) TagChip(text: protocol, color: AppColors.info),
    if (indexer != null) TagChip(text: indexer, color: colorScheme.tertiary),
  ];
}

List<Widget> _buildWantedChips(
  Map<String, dynamic> item,
  ServiceType serviceType,
  ColorScheme colorScheme, {
  bool isCutoff = false,
  String? qualityProfileName,
}) {
  final monitored = item['monitored'] == false
      ? TagChip(text: 'Unmonitored', color: colorScheme.error)
      : null;
  final quality = switch (serviceType) {
    ServiceType.movies =>
      qualityProfileName ??
          extractQualityName(item, fileKey: 'movieFile') ??
          extractQualityName(item),
    ServiceType.music =>
      extractQualityName(item, fileKey: 'albumFile') ??
          extractQualityName(item),
    _ => extractQualityName(item),
  };
  final date = switch (serviceType) {
    ServiceType.movies => stringOrNull(
      item['airDateUtc'] ?? item['digitalRelease'] ?? item['inCinemas'],
    ),
    ServiceType.music => stringOrNull(item['releaseDate']),
    _ => stringOrNull(item['airDateUtc']),
  };
  final showDateChip = !(isCutoff && serviceType == ServiceType.movies);

  return [
    if (monitored != null) monitored,
    if (quality != null) TagChip(text: quality),
    if (showDateChip && date != null)
      TagChip(text: formatIsoDate(date), color: AppColors.info),
  ];
}

String _historyTitle(Map<String, dynamic> item, ServiceType serviceType) {
  return arrPrimaryMediaTitle(item, includeMovieYear: true) ??
      stringOrNull(item['sourceTitle']) ??
      'Unknown release';
}

String? _historyEpisodeCode(Map<String, dynamic> item) {
  final episode = asActivityMap(item['episode']);
  return formatEpisodeCode(
    intOrNull(episode?['seasonNumber'] ?? item['seasonNumber']),
    intOrNull(episode?['episodeNumber'] ?? item['episodeNumber']),
  );
}

Color _eventTypeColor(String eventType) {
  switch (eventType) {
    case 'grabbed':
      return AppColors.info;
    case 'downloadFolderImported':
    case 'downloadImported':
      return AppColors.success;
    case 'downloadFailed':
      return AppColors.error;
    case 'episodeFileDeleted':
    case 'movieFileDeleted':
      return AppColors.warning;
    default:
      return AppColors.primaryLight;
  }
}

String? _blocklistReason(Map<String, dynamic> item) {
  final directMessage = stringOrNull(item['message']);
  if (directMessage != null) return directMessage;

  final messages = extractStatusMessages(item['statusMessages']);
  return messages.isEmpty ? null : messages.first;
}

String? _historySizeLabel(Map<String, dynamic> item) {
  final size = formatSizeInGb(
    asActivityMap(item['data'])?['size'] ?? item['size'],
  );
  return size == '—' ? null : size;
}

String _queueTitle(Map<String, dynamic> item, ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies =>
      arrPrimaryMediaTitle(item, includeMovieYear: true) ??
          arrReleaseTitle(item) ??
          'Unknown release',
    ServiceType.series || ServiceType.music =>
      arrPrimaryMediaTitle(item) ?? arrReleaseTitle(item) ?? 'Unknown release',
    ServiceType.discover => arrReleaseTitle(item) ?? 'Unknown release',
  };
}

String? _queueSubtitle(Map<String, dynamic> item, ServiceType serviceType) {
  final release = arrReleaseTitle(item);
  final title = _queueTitle(item, serviceType);
  final uniqueRelease = release == title ? null : release;

  return switch (serviceType) {
    ServiceType.series => _joinSecondaryParts([
      arrEpisodeCode(item),
      arrEpisodeTitle(item),
      uniqueRelease,
    ]),
    ServiceType.movies => _joinSecondaryParts([uniqueRelease]),
    ServiceType.music => _joinSecondaryParts([
      arrArtistName(item),
      uniqueRelease,
    ]),
    ServiceType.discover => null,
  };
}

String? _historySubtitle(Map<String, dynamic> item, ServiceType serviceType) {
  final release = stringOrNull(item['sourceTitle']);
  final title = _historyTitle(item, serviceType);
  final uniqueRelease = release == title ? null : release;

  return switch (serviceType) {
    ServiceType.series => _joinSecondaryParts([
      arrEpisodeCode(item),
      arrEpisodeTitle(item),
      uniqueRelease,
    ]),
    ServiceType.movies => _joinSecondaryParts([uniqueRelease]),
    ServiceType.music => _joinSecondaryParts([
      arrArtistName(item),
      uniqueRelease,
    ]),
    ServiceType.discover => null,
  };
}

String _blocklistTitle(Map<String, dynamic> item, ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies =>
      arrPrimaryMediaTitle(item, includeMovieYear: true) ??
          stringOrNull(item['sourceTitle']) ??
          'Unknown release',
    ServiceType.series || ServiceType.music =>
      arrPrimaryMediaTitle(item) ??
          stringOrNull(item['sourceTitle']) ??
          'Unknown release',
    ServiceType.discover =>
      stringOrNull(item['sourceTitle']) ?? 'Unknown release',
  };
}

String? _blocklistSubtitle(Map<String, dynamic> item, ServiceType serviceType) {
  final release = stringOrNull(item['sourceTitle']);
  final title = _blocklistTitle(item, serviceType);
  final uniqueRelease = release == title ? null : release;

  return switch (serviceType) {
    ServiceType.series => _joinSecondaryParts([
      arrEpisodeCode(item),
      arrEpisodeTitle(item),
      uniqueRelease,
    ]),
    ServiceType.movies => _joinSecondaryParts([uniqueRelease]),
    ServiceType.music => _joinSecondaryParts([
      arrArtistName(item),
      uniqueRelease,
    ]),
    ServiceType.discover => null,
  };
}

String? _joinSecondaryParts(List<String?> parts) {
  final line = joinDisplayParts(parts);
  return line.isEmpty ? null : line;
}

String _wantedTitle(Map<String, dynamic> item, ServiceType serviceType) {
  switch (serviceType) {
    case ServiceType.movies:
      final title = stringOrNull(item['title']) ?? 'Unknown movie';
      final year = intOrNull(item['year']);
      return year == null ? title : '$title ($year)';
    case ServiceType.music:
      return stringOrNull(item['title']) ?? 'Unknown release';
    case ServiceType.series:
      final episodeCode = formatEpisodeCode(
        intOrNull(item['seasonNumber']),
        intOrNull(item['episodeNumber']),
      );
      final title = joinActivityParts([
        episodeCode,
        stringOrNull(item['title']),
      ]);
      return title.isEmpty ? 'Unknown Episode' : title;
    case ServiceType.discover:
      return stringOrNull(item['title']) ?? 'Unknown';
  }
}

String? _wantedSubtitle(Map<String, dynamic> item, ServiceType serviceType) {
  switch (serviceType) {
    case ServiceType.movies:
      final date = stringOrNull(
        item['airDateUtc'] ?? item['digitalRelease'] ?? item['inCinemas'],
      );
      return date == null ? null : 'Release ${formatIsoDate(date)}';
    case ServiceType.music:
      return stringOrNull(asActivityMap(item['artist'])?['artistName']);
    case ServiceType.series:
      return stringOrNull(asActivityMap(item['series'])?['title']) ??
          'Unknown Series';
    case ServiceType.discover:
      return null;
  }
}

import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/arr_activity_display.dart';
import 'package:seekarr/core/widgets/app_bottom_sheet.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/features/activity/presentation/activity_screen.dart';
import 'package:seekarr/features/activity/presentation/widgets/activity_formatters.dart';

const _historyExcludedKeys = {
  'age',
  'ageHours',
  'ageMinutes',
  'protocol',
  'movieMatchType',
};

class DetailSheets {
  DetailSheets._();

  static Future<void> showQueueDetail(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final title =
        arrPrimaryMediaTitle(item, includeMovieYear: true) ??
        arrReleaseTitle(item) ??
        'Queue Item';
    return _show(
      context: context,
      title: title,
      subtitle: _detailHeaderSubtitle(title, arrReleaseTitle(item)),
      sections: _buildQueueSections(item),
    );
  }

  static Future<void> showHistoryDetail(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final title =
        arrPrimaryMediaTitle(item, includeMovieYear: true) ??
        arrReleaseTitle(item) ??
        'History Item';
    return _show(
      context: context,
      title: title,
      subtitle: _detailHeaderSubtitle(title, arrReleaseTitle(item)),
      sections: _buildHistorySections(item),
    );
  }

  static Future<void> showBlocklistDetail(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final title =
        arrPrimaryMediaTitle(item, includeMovieYear: true) ??
        arrReleaseTitle(item) ??
        'Blocklist Item';
    return _show(
      context: context,
      title: title,
      subtitle: _detailHeaderSubtitle(title, arrReleaseTitle(item)),
      sections: _buildBlocklistSections(item),
    );
  }

  static Future<void> showWantedDetail(
    BuildContext context,
    Map<String, dynamic> item,
    ServiceType serviceType,
  ) {
    return _show(
      context: context,
      title: stringOrNull(item['title']) ?? 'Wanted Item',
      sections: _buildWantedSections(item, serviceType),
    );
  }

  static Future<void> _show({
    required BuildContext context,
    required String title,
    required List<_DetailSection> sections,
    String? subtitle,
  }) {
    return AppBottomSheet.showScrollable<void>(
      context: context,
      title: title,
      subtitle: subtitle,
      showClose: true,
      initialSize: 0.5,
      minSize: 0.3,
      maxSize: 0.9,
      builder: (context, scrollController) {
        return ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          itemBuilder: (context, index) => AppCard.outlined(
            padding: EdgeInsets.zero,
            child: _SectionContent(section: sections[index]),
          ),
          separatorBuilder: (context, index) =>
              const SizedBox(height: AppSpacing.lg),
          itemCount: sections.length,
        );
      },
    );
  }
}

List<_DetailSection> _buildQueueSections(Map<String, dynamic> item) {
  final displayStatus = resolveQueueDisplayStatus(item);
  final statusMessages = extractStatusMessages(item['statusMessages']);

  return [
    _DetailSection(
      title: 'Summary',
      fields: _compactFields([
        _detailField('Display Status', displayStatus.label),
        _detailField('Status', item['status']),
        _detailField('Tracked Status', item['trackedDownloadStatus']),
        _detailField('Tracked State', item['trackedDownloadState']),
        _detailField('Quality', extractQualityName(item)),
      ]),
    ),
    _DetailSection(
      title: 'Transfer',
      fields: _compactFields([
        _detailField('Protocol', item['protocol']),
        _detailField('Download Client', item['downloadClient']),
        _detailField('Indexer', item['indexer']),
        _detailField('Size', formatActivityBytes(item['size'])),
        _detailField('Remaining', formatActivityBytes(item['sizeleft'])),
        _detailField(
          'ETA',
          formatActivityDuration(stringOrNull(item['timeleft'])),
        ),
        _detailField(
          'Estimated Completion',
          formatActivityDateTime(stringOrNull(item['estimatedCompletionTime'])),
        ),
        _detailField('Output Path', item['outputPath']),
      ]),
    ),
    if (statusMessages.isNotEmpty)
      _DetailSection(title: 'Status Messages', messages: statusMessages),
  ];
}

List<_DetailSection> _buildHistorySections(Map<String, dynamic> item) {
  final dataFields = _mapEntriesToFields(
    asActivityMap(item['data']),
    excludedKeys: _historyExcludedKeys,
  );

  return [
    _DetailSection(
      title: 'Event',
      fields: _compactFields([
        _detailField(
          'Event Type',
          humanizeEventType(item['eventType']?.toString() ?? 'Unknown'),
        ),
        _detailField('Date', formatDateOnly(stringOrNull(item['date']))),
        _detailField(
          'Relative Time',
          formatRelativeActivityDate(stringOrNull(item['date'])),
        ),
        _detailField(
          'Size',
          formatSizeInGb(asActivityMap(item['data'])?['size'] ?? item['size']),
        ),
        _detailField('Quality', extractQualityName(item)),
      ]),
    ),
    if (dataFields.isNotEmpty)
      _DetailSection(title: 'Additional Data', fields: dataFields),
  ];
}

List<_DetailSection> _buildBlocklistSections(Map<String, dynamic> item) {
  final statusMessages = extractStatusMessages(item['statusMessages']);

  return [
    _DetailSection(
      title: 'Blocked Release',
      fields: _compactFields([
        _detailField(
          'Date',
          formatActivityDateTime(stringOrNull(item['date'])),
        ),
        _detailField(
          'Relative Time',
          formatRelativeActivityDate(stringOrNull(item['date'])),
        ),
        _detailField('Protocol', item['protocol']),
        _detailField('Indexer', item['indexer']),
        _detailField('Reason', item['message']),
      ]),
    ),
    if (statusMessages.isNotEmpty)
      _DetailSection(title: 'Status Messages', messages: statusMessages),
  ];
}

List<_DetailSection> _buildWantedSections(
  Map<String, dynamic> item,
  ServiceType serviceType,
) {
  return [
    _DetailSection(
      title: 'Wanted Item',
      fields: _buildWantedFields(item, serviceType),
    ),
  ];
}

List<_DetailField> _buildWantedFields(
  Map<String, dynamic> item,
  ServiceType serviceType,
) {
  return switch (serviceType) {
    ServiceType.series => _compactFields([
      _detailField('Series', asActivityMap(item['series'])?['title']),
      _detailField('Status', wantedStatusText(item, serviceType)),
      _detailField(
        'Episode Code',
        formatEpisodeCode(
          intOrNull(item['seasonNumber']),
          intOrNull(item['episodeNumber']),
        ),
      ),
      _detailField('Episode Title', item['title']),
      _detailField(
        'Air Date',
        formatActivityDateTime(stringOrNull(item['airDateUtc'])),
      ),
      _detailField('Monitored', item['monitored']),
      _detailField(
        'Current Quality',
        extractQualityName(item, fileKey: 'episodeFile'),
      ),
    ]),
    ServiceType.movies => _compactFields([
      _detailField('Movie', item['title']),
      _detailField('Status', wantedStatusText(item, serviceType)),
      _detailField('Year', item['year']),
      _detailField(
        'Release Date',
        formatActivityDateTime(
          stringOrNull(
            item['airDateUtc'] ?? item['digitalRelease'] ?? item['inCinemas'],
          ),
        ),
      ),
      _detailField('Monitored', item['monitored']),
      _detailField(
        'Current Quality',
        extractQualityName(item, fileKey: 'movieFile'),
      ),
    ]),
    ServiceType.music => _compactFields([
      _detailField('Release', item['title']),
      _detailField('Status', wantedStatusText(item, serviceType)),
      _detailField('Artist', asActivityMap(item['artist'])?['artistName']),
      _detailField('Album', asActivityMap(item['album'])?['title']),
      _detailField(
        'Release Date',
        formatActivityDateTime(stringOrNull(item['releaseDate'])),
      ),
      _detailField('Monitored', item['monitored']),
    ]),
    ServiceType.discover => const <_DetailField>[],
  };
}

class _SectionContent extends StatelessWidget {
  final _DetailSection section;

  const _SectionContent({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Text(
            section.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (section.fields.isNotEmpty || section.messages.isNotEmpty)
          const Divider(height: 1),
        ...section.fields.map((field) => _SectionFieldContent(field: field)),
        ...section.messages.map(
          (message) => _SectionMessageContent(message: message),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _SectionFieldContent extends StatelessWidget {
  const _SectionFieldContent({required this.field});

  final _DetailField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(field.value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SectionMessageContent extends StatelessWidget {
  const _SectionMessageContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: colorScheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _DetailSection {
  final String title;
  final List<_DetailField> fields;
  final List<String> messages;

  const _DetailSection({
    required this.title,
    this.fields = const [],
    this.messages = const [],
  });
}

class _DetailField {
  final String label;
  final String value;

  const _DetailField({required this.label, required this.value});
}

_DetailField? _detailField(String label, dynamic value) {
  final formatted = formatActivityValue(value);
  if (formatted == '—') return null;
  return _DetailField(label: label, value: formatted);
}

List<_DetailField> _compactFields(List<_DetailField?> fields) {
  return fields.whereType<_DetailField>().toList(growable: false);
}

List<_DetailField> _mapEntriesToFields(
  Map<String, dynamic>? map, {
  Set<String> excludedKeys = const {},
}) {
  if (map == null || map.isEmpty) return const [];

  return map.entries
      .where((entry) => !excludedKeys.contains(entry.key))
      .map((entry) => _detailField(humanizeCamelCase(entry.key), entry.value))
      .whereType<_DetailField>()
      .toList(growable: false);
}

String? _detailHeaderSubtitle(String title, String? releaseTitle) {
  if (releaseTitle == null || releaseTitle == title) return null;
  return releaseTitle;
}

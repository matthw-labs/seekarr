import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';

class RequestsSection extends StatelessWidget {
  final List<SeerrRequest> requests;
  final void Function(int) onDeleteRequest;

  const RequestsSection({
    super.key,
    required this.requests,
    required this.onDeleteRequest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Requests',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (requests.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Center(
              child: Text(
                'No requests for this media',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ...requests.map(
            (request) => _RequestCard(
              request: request,
              onDelete: () => onDeleteRequest(request.id),
            ),
          ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final SeerrRequest request;
  final VoidCallback onDelete;

  const _RequestCard({required this.request, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String formattedDate = '';

    try {
      final date = DateTime.parse(request.createdAt);
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      formattedDate = '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      formattedDate = request.createdAt;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      request.requestedBy?.displayName ?? 'Unknown',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (request.is4k)
                      const _Badge(text: '4K', color: AppColors.warning),
                    _StatusBadge(request: request),
                  ],
                ),
                if (request.seasons != null && request.seasons!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Seasons',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: request.seasons!.map((season) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                          borderRadius: AppRadius.borderRadiusXs,
                        ),
                        child: Text(
                          '${season.seasonNumber}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      formattedDate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete from library',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.error.withValues(alpha: 0.1),
              foregroundColor: colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.borderRadiusXs,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final SeerrRequest request;

  const _StatusBadge({required this.request});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final displayStatus = request.displayStatus;

    late final Color color;
    switch (displayStatus.kind) {
      case SeerrRequestDisplayKind.available:
      case SeerrRequestDisplayKind.partiallyAvailable:
      case SeerrRequestDisplayKind.completed:
        color = AppColors.success;
        break;
      case SeerrRequestDisplayKind.pending:
        color = AppColors.warning;
        break;
      case SeerrRequestDisplayKind.approved:
      case SeerrRequestDisplayKind.processing:
        color = colorScheme.primary;
        break;
      case SeerrRequestDisplayKind.declined:
      case SeerrRequestDisplayKind.failed:
      case SeerrRequestDisplayKind.deleted:
        color = AppColors.error;
        break;
      case SeerrRequestDisplayKind.unknown:
        color = colorScheme.onSurfaceVariant;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.borderRadiusXs,
      ),
      child: Text(
        displayStatus.label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

class MediaSection extends StatelessWidget {
  final bool isMovie;
  final bool hasExternalService;
  final bool isDeleting;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  const MediaSection({
    super.key,
    required this.isMovie,
    required this.hasExternalService,
    required this.isDeleting,
    this.onOpen,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final serviceName = isMovie ? 'Radarr' : 'Sonarr';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Media',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: hasExternalService ? onOpen : null,
            icon: const Icon(Icons.open_in_new),
            label: Text('Open in $serviceName'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: hasExternalService && !isDeleting ? onRemove : null,
            icon: isDeleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            label: Text('Remove from $serviceName'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '* This will irreversibly remove this ${isMovie ? 'movie' : 'series'} from $serviceName, including all files.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class AdvancedSection extends StatelessWidget {
  final bool isMovie;
  final bool isDeleting;
  final VoidCallback? onClear;

  const AdvancedSection({
    super.key,
    required this.isMovie,
    required this.isDeleting,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Advanced',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: !isDeleting ? onClear : null,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear Data'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '* This will irreversibly remove all data for this ${isMovie ? 'movie' : 'series'}, '
          'including any requests. If this item exists in your Jellyfin library, '
          'the media information will be recreated during the next scan.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

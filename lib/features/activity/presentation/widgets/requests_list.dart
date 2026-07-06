import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/features/discover/data/seerr_service.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/discover/presentation/discover_provider.dart';

class RequestsList extends ConsumerWidget {
  const RequestsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(requestsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(requestsProvider);
      },
      child: requestsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (requests) {
          if (requests.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: Text('No requests found'),
                  ),
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              final title = request.media?.title ?? 'Unknown';
              final year = request.media?.year ?? '';
              final status = request.displayStatus.label;
              final createdAt =
                  DateTime.tryParse(
                    request.createdAt,
                  )?.toLocal().toString().split(' ')[0] ??
                  request.createdAt;
              final seasons =
                  request.seasons
                      ?.map((season) => season.seasonNumber)
                      .join(', ') ??
                  '';
              final profile =
                  request.profileName ??
                  request.profileId?.toString() ??
                  'Default';
              final type = request.type == 'tv' ? 'TV' : 'Movie';

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '$title ($year)',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (request.is4k)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: AppRadius.borderRadiusXs,
                              ),
                              child: Text(
                                '4K',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          IconButton(
                            icon: Icon(Icons.delete, color: colorScheme.error),
                            onPressed: () async {
                              final result = await showAppConfirmDialog(
                                context: context,
                                title: 'Delete Request?',
                                destructive: true,
                                confirmLabel: 'Delete',
                              );

                              if (result.confirmed) {
                                await ref
                                    .read(seerrServiceProvider)
                                    .deleteRequest(request.id);
                                ref.invalidate(requestsProvider);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _buildInfoRow(context, 'Type:', type),
                      _buildInfoRow(context, 'Status:', status),
                      _buildInfoRow(context, 'Date:', createdAt),
                      if (request.type == 'tv' && seasons.isNotEmpty)
                        _buildInfoRow(context, 'Seasons:', seasons),
                      _buildInfoRow(context, 'Profile:', profile),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

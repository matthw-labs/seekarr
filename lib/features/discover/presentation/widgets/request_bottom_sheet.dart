import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/features/discover/presentation/request_form_provider.dart';

/// Bottom sheet for selecting quality profile and submitting request to Seerr.
///
/// This widget is used from the DiscoverDetailScreen to allow users to select
/// a server, quality profile, and root folder before submitting a media request.
class RequestBottomSheet extends ConsumerWidget {
  final int mediaId;
  final String mediaType;
  final VoidCallback onRequestComplete;

  const RequestBottomSheet({
    super.key,
    required this.mediaId,
    required this.mediaType,
    required this.onRequestComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (mediaId: mediaId, mediaType: mediaType);
    final state = ref.watch(requestFormProvider(args));
    final notifier = ref.read(requestFormProvider(args).notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (state.error != null)
          Text(state.error!, style: TextStyle(color: colorScheme.error))
        else ...[
          if (state.servers.length > 1) ...[
            Text('Server', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              key: ValueKey('request_server_${state.selectedServerId}'),
              initialValue: state.selectedServerId,
              items: state.servers
                  .map(
                    (server) => DropdownMenuItem(
                      value: server.id,
                      child: Text(server.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  notifier.selectServer(value);
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text('Quality Profile', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<int>(
            key: ValueKey('request_profile_${state.selectedProfileId}'),
            initialValue: state.selectedProfileId,
            items: state.profiles
                .map(
                  (profile) => DropdownMenuItem(
                    value: profile.id,
                    child: Text(profile.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                notifier.selectProfile(value);
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.rootFolders.isNotEmpty) ...[
            Text('Root Folder', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: ValueKey('request_root_${state.selectedRootFolder}'),
              initialValue: state.selectedRootFolder,
              items: state.rootFolders
                  .map(
                    (folder) => DropdownMenuItem(
                      value: folder.path,
                      child: Text(folder.path),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  notifier.selectRootFolder(value);
                }
              },
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: state.canSubmit
                  ? () async {
                      final error = await notifier.submitRequest();
                      if (!context.mounted) {
                        return;
                      }

                      if (error == null) {
                        Navigator.pop(context);
                        onRequestComplete();
                        return;
                      }

                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error)));
                    }
                  : null,
              child: state.isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit Request'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

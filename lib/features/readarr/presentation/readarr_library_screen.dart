import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_screen.dart';
import 'package:cupola/features/readarr/presentation/widgets/readarr_tiles.dart';

/// Full author list for Readarr, reached from the dashboard "Authors" section.
class ReadarrLibraryScreen extends ConsumerWidget {
  const ReadarrLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorsAsync = ref.watch(readarrAuthorsProvider);

    return AmbientScaffold(
      accent: AppColors.readarr,
      appBar: const GlassAppBar(title: Text('Authors')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(readarrAuthorsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: authorsAsync.when(
            data: (authors) {
              if (authors.isEmpty) {
                return const _EmptyLibrary();
              }
              final sorted = [...authors]
                ..sort(
                  (a, b) => a.authorName.toLowerCase().compareTo(
                    b.authorName.toLowerCase(),
                  ),
                );
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: 8,
                  bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(
                    context,
                  ),
                ),
                itemCount: sorted.length,
                itemBuilder: (context, index) =>
                    ReadarrAuthorTile(author: sorted[index]),
              );
            },
            loading: () => const ReadarrListShimmer(rows: 8),
            error: (error, _) => ReadarrErrorRetry(
              message: 'Failed to load authors',
              onRetry: () => ref.invalidate(readarrAuthorsProvider),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Center(child: Text('No authors in the library yet.')),
      ],
    );
  }
}

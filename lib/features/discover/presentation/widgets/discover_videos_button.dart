import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';

/// Full-width filled button that opens the related-videos sheet.
class DiscoverVideosButton extends StatelessWidget {
  final List<RelatedVideo> videos;

  const DiscoverVideosButton({super.key, required this.videos});

  /// Returns an icon-only variant for use as a trailing button in
  /// [HeaderActionRow].
  static Widget iconOnly({Key? key, required List<RelatedVideo> videos}) =>
      _DiscoverVideosIconButton(key: key, videos: videos);

  static void show(BuildContext context, List<RelatedVideo> videos) {
    _showVideosSheet(context, videos);
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: videos.isEmpty
          ? null
          : () => _showVideosSheet(context, videos),
      icon: const Icon(Icons.play_circle_outline_rounded),
      label: const Text('Videos'),
      style: HeaderActionRow.expandedButtonStyle(),
    );
  }
}

/// Icon-only square button variant of [DiscoverVideosButton].
class _DiscoverVideosIconButton extends StatelessWidget {
  final List<RelatedVideo> videos;

  const _DiscoverVideosIconButton({super.key, required this.videos});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: videos.isEmpty
          ? null
          : () => _showVideosSheet(context, videos),
      style: HeaderActionRow.iconOnlyButtonStyle(),
      child: const Icon(Icons.play_circle_outline_rounded),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet / launch helpers (shared by both button variants)
// ---------------------------------------------------------------------------

void _showVideosSheet(BuildContext context, List<RelatedVideo> videos) {
  final sortedVideos = [...videos]..sort(_compareVideos);

  AppBottomSheet.show<void>(
    context: context,
    title: 'Videos',
    icon: Icons.play_circle_outline,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < sortedVideos.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_arrow_rounded),
            title: Text(sortedVideos[index].name),
            subtitle: Text(
              '${sortedVideos[index].type} • ${sortedVideos[index].site}',
            ),
            onTap: sortedVideos[index].url.isEmpty
                ? null
                : () => _openVideo(
                    pageContext: context,
                    sheetContext: sheetContext,
                    video: sortedVideos[index],
                  ),
          ),
        ],
      ],
    ),
  );
}

Future<void> _openVideo({
  required BuildContext pageContext,
  required BuildContext sheetContext,
  required RelatedVideo video,
}) async {
  final messenger = ScaffoldMessenger.of(pageContext);
  // `Uri.tryParse` alone is a syntax check: it accepts `javascript:`, `data:`,
  // `intent:` and `file:` just as readily as https, and this URL comes verbatim
  // from the remote Seerr instance. The model already refuses a non-web `url`,
  // and this is the second gate on the one call that leaves the app.
  final uri = Uri.tryParse(video.url);
  if (uri == null || !UrlUtils.isLaunchableWebUri(uri)) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Unable to open this video.')),
    );
    return;
  }

  Navigator.of(sheetContext).pop();
  var launched = false;
  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // A platform with no handler for the URL throws rather than answering
    // false; either way the user gets told, instead of nothing happening.
    launched = false;
  }
  if (!launched && pageContext.mounted) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Unable to open this video.')),
    );
  }
}

int _compareVideos(RelatedVideo left, RelatedVideo right) {
  final leftPriority = _videoTypePriority(left.type);
  final rightPriority = _videoTypePriority(right.type);
  if (leftPriority != rightPriority) {
    return leftPriority.compareTo(rightPriority);
  }

  return left.name.compareTo(right.name);
}

int _videoTypePriority(String type) {
  return switch (type.toLowerCase()) {
    'trailer' => 0,
    'teaser' => 1,
    'clip' => 2,
    'featurette' => 3,
    _ => 99,
  };
}

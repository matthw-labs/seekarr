import 'package:flutter/material.dart';

import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/media_detail_back_button.dart';
import 'package:seekarr/core/widgets/not_configured_placeholder.dart';

/// The full-page state a media detail route shows when it has no media to show.
///
/// Wears the same chrome as the loaded page — a room lit by the service's own
/// accent under a glass bar — so a movie that turns out to be unreachable does
/// not land the user on a differently-dressed screen. The six detail screens
/// each carried a private copy of this that opened with a flat opaque app-bar
/// strip and no ambient light at all, which made the failure look like a
/// different app rather than the same page with nothing in it.
///
/// Two cases, one shape:
/// - [MediaDetailPlaceholderView.error] — the lookup failed. A
///   `<Service> not configured` throw routes to [NotConfiguredPlaceholder],
///   matching the detection `AsyncValueWidget` already uses, because an
///   unconfigured service is a normal daily condition rather than a fault.
/// - [MediaDetailPlaceholderView.notFound] — the service answered and does not
///   have this item. Also not a fault, so it gets the empty-state voice.
///
/// Both cases take [onRetry]. A detail page reached over a reverse proxy that
/// blinks is the single most common failure in this product, and without a way
/// back the only exit was the back button — the page became a dead end for a
/// condition that usually clears on the next request. Callers wire it to
/// `ref.invalidate(...)` of the provider that actually failed, so recovery
/// happens in place instead of costing a navigation round trip.
class MediaDetailPlaceholderView extends StatelessWidget {
  /// The failure, for the `.error` case.
  final Object? error;

  /// Glyph and headline for the `.notFound` case.
  final IconData? icon;
  final String? title;

  /// Optional second line for the `.notFound` case, so "nothing here" can say
  /// which nothing it means without overloading the headline.
  final String? message;

  /// Names the subject in every state's copy ("Couldn't load Radarr").
  final String serviceName;

  /// Per-service accent lighting the room, matching the loaded page.
  final Color? accent;

  /// Passed through to [MediaDetailBackButton]; defaults to `maybePop`.
  final VoidCallback? onBack;

  /// Retries the load in place. Omit it only where a retry cannot help.
  final VoidCallback? onRetry;

  const MediaDetailPlaceholderView.error({
    super.key,
    required this.error,
    required this.serviceName,
    this.accent,
    this.onBack,
    this.onRetry,
  }) : icon = null,
       title = null,
       message = null;

  const MediaDetailPlaceholderView.notFound({
    super.key,
    required this.icon,
    required this.title,
    required this.serviceName,
    this.message,
    this.accent,
    this.onBack,
    this.onRetry,
  }) : error = null;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (error != null) {
      // A missing configuration is not retryable — the fix is in Settings — so
      // that branch keeps its own call to action and drops [onRetry].
      body = error.toString().contains('not configured')
          ? NotConfiguredPlaceholder(serviceName: serviceName)
          : AppErrorState(
              error: error!,
              serviceName: serviceName,
              onRetry: onRetry,
            );
    } else {
      body = AppEmptyState(
        icon: icon ?? Icons.help_outline_rounded,
        title: title ?? "Couldn't load $serviceName",
        message: message,
        accentColor: accent,
        // Deliberately the same affordance [AppErrorState] renders, so the two
        // voices differ in tone and not in how you get out of them.
        action: onRetry == null
            ? null
            : FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
      );
    }

    return AmbientScaffold(
      accent: accent,
      appBar: GlassAppBar(
        automaticallyImplyLeading: false,
        leading: MediaDetailBackButton(onBack: onBack),
      ),
      // Both bodies are leaves that own no viewport: at an accessibility
      // reading size an icon well, a wrapped headline, a message and a button
      // can clear a short phone. The page owns the viewport — `minHeight` keeps
      // the state centred while it fits and lets it grow past that — and the
      // scroll view ends on the floating nav bar's clearance.
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: body,
          ),
        ),
      ),
    );
  }
}

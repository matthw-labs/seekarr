import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/not_configured_placeholder.dart';

/// A widget that handles AsyncValue states with premium, consistent styling.
///
/// Shows loading, error, empty, or data states based on the [AsyncValue].
/// - loading  → [skeleton] (or a centred spinner if none given)
/// - error    → [AppErrorState] with a retry button when [onRetry] is set
///              (the "not configured" case still routes to [NotConfiguredPlaceholder])
/// - data     → [emptyBuilder]/[AppEmptyState] when [isEmpty] returns true,
///              otherwise [data]
class AsyncValueWidget<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final String serviceName;

  /// Optional custom loading widget. Defaults to centered CircularProgressIndicator.
  final Widget? loadingWidget;

  /// Optional skeleton shown while loading (takes precedence over [loadingWidget]).
  final Widget? skeleton;

  /// Called to retry after an error (wired to `ref.invalidate(...)`).
  final VoidCallback? onRetry;

  /// Optional predicate identifying an "empty" data result.
  final bool Function(T data)? isEmpty;

  /// Optional widget shown when [isEmpty] returns true.
  final Widget? emptyBuilder;

  /// What a screen reader hears while [value] is loading.
  ///
  /// A shimmer skeleton is a set of bare `Container`s and a bare spinner has no
  /// text either, so both publish an empty semantics tree: a screen reader lands
  /// on a page with nothing to read and no way to tell "loading" from "empty".
  /// Defaults to `'Loading <serviceName>'`.
  final String? loadingLabel;

  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.data,
    required this.serviceName,
    this.loadingWidget,
    this.skeleton,
    this.onRetry,
    this.isEmpty,
    this.emptyBuilder,
    this.loadingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (value) {
        if (isEmpty != null && isEmpty!(value) && emptyBuilder != null) {
          return emptyBuilder!;
        }
        return data(value);
      },
      loading: () => Semantics(
        container: true,
        // The placeholder is decoration: its shimmer boxes carry no text, and
        // its ListView/GridView would otherwise publish a scroll container over
        // content that does not exist yet.
        //
        // No `liveRegion`: this widget rebuilds on every provider tick, so a
        // polling dashboard would announce "Loading Radarr" on a loop.
        excludeSemantics: true,
        label: loadingLabel ?? 'Loading $serviceName',
        child:
            skeleton ??
            loadingWidget ??
            const Center(child: CircularProgressIndicator()),
      ),
      error: (e, stack) {
        if (e.toString().contains('not configured')) {
          return NotConfiguredPlaceholder(serviceName: serviceName);
        }
        // The same name the loading and not-configured states use, so a region
        // says which service it is talking about in every state.
        return AppErrorState(
          error: e,
          onRetry: onRetry,
          serviceName: serviceName,
        );
      },
    );
  }
}

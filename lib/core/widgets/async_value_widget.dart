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
      loading: () =>
          skeleton ??
          loadingWidget ??
          const Center(child: CircularProgressIndicator()),
      error: (e, stack) {
        if (e.toString().contains('not configured')) {
          return NotConfiguredPlaceholder(serviceName: serviceName);
        }
        return AppErrorState(error: e, onRetry: onRetry);
      },
    );
  }
}

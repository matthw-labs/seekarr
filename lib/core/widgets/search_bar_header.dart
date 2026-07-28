import 'dart:async';
import 'package:flutter/material.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';

/// A reusable, always-visible search bar widget for the top of screens.
///
/// Provides debounced text input, clear button, and Material Design 3 styling.
/// Uses the M3 SearchBar widget with proper color tokens.
class SearchBarHeader extends StatefulWidget {
  /// Callback when the search query changes (debounced).
  final ValueChanged<String> onQueryChanged;

  /// Placeholder text for the search bar.
  final String hintText;

  /// Initial query value.
  final String? initialQuery;

  /// Debounce duration for search input.
  final Duration debounceDuration;

  /// Whether to autofocus the search field
  final bool autofocus;

  /// Accent for the leading search glyph.
  ///
  /// Defaults to the app's primary. It used to be hard-coded to the Seerr
  /// indigo, which left an indigo magnifier sitting on the amber Radarr page and
  /// the pink Lidarr one — the per-service accent is part of the identity, so
  /// every screen passes its own.
  final Color? accent;

  const SearchBarHeader({
    super.key,
    required this.onQueryChanged,
    this.hintText = 'Search...',
    this.initialQuery,
    this.debounceDuration = const Duration(milliseconds: 400),
    this.autofocus = false,
    this.accent,
  });

  @override
  State<SearchBarHeader> createState() => _SearchBarHeaderState();
}

class _SearchBarHeaderState extends State<SearchBarHeader> {
  late final TextEditingController _controller;
  Timer? _debounceTimer;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      widget.onQueryChanged(_controller.text.trim());
    });
  }

  void _clearQuery() {
    _controller.clear();
    widget.onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: SearchBar(
        controller: _controller,
        hintText: widget.hintText,
        autoFocus: widget.autofocus,
        leading: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          child: Icon(
            Icons.search_rounded,
            color: widget.accent ?? colorScheme.primary,
          ),
        ),
        trailing: [
          if (_hasText)
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: _clearQuery,
              tooltip: 'Clear',
            ),
        ],
        elevation: WidgetStateProperty.all(0),
        backgroundColor: WidgetStateProperty.all(colorScheme.surfaceContainer),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusXl,
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        constraints: const BoxConstraints(minHeight: 52),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
      ),
    );
  }
}

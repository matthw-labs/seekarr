import 'package:flutter/material.dart';

import 'package:cupola/core/widgets/ambient_background.dart';

/// A [Scaffold] pre-wired for the premium ambient look: an [AmbientBackground]
/// paints the gradient full-bleed and the Scaffold itself is transparent, so the
/// gradient runs continuously behind a transparent/glass app bar (pair with
/// [GlassAppBar]).
///
/// Because the Scaffold background is transparent and the gradient is painted by
/// an ancestor, the app bar band no longer shows a flat opaque surface strip.
/// [extendBodyBehindAppBar] is left `false` by default: the gradient is already
/// continuous behind the (transparent) app bar, so content does not need to be
/// re-padded.
class AmbientScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Color? accent;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;
  final bool extendBody;

  const AmbientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.accent,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true,
    this.extendBodyBehindAppBar = false,
    this.extendBody = true,
  });

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      accent: accent,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: extendBody,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      ),
    );
  }
}

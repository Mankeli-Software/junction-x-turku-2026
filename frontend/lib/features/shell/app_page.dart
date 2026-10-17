import 'package:flutter/material.dart';

import '../chat/ask_context.dart';
import '../chat/widgets/ask_launcher.dart';
import '../../ds/ds.dart';
import 'top_bar.dart';

/// Page frame: the glow background, the top bar and a scrolling body. The top bar scrolls
/// with the page, as in the design.
///
/// [phoneBar] sticks to the bottom on phones inside the white fade (M-Rules): the ask field,
/// "Show what works", … Use [StickyAskBar] for the common case.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.body,
    this.topBarTrailing,
    this.topBarSubtitle,
    this.glowHeight = 600,
    this.phoneBar,
  });

  final Widget body;
  final Widget? topBarTrailing;
  final String? topBarSubtitle;
  final double glowHeight;
  final Widget? phoneBar;

  @override
  Widget build(BuildContext context) {
    final sticky = phoneBar != null && context.isCompact;
    final page = LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: AmrBackground(
            glowHeight: glowHeight,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TopBar(trailing: topBarTrailing, subtitle: topBarSubtitle),
                  body,
                  if (sticky) const SizedBox(height: 96),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      body: sticky
          ? Stack(
              children: [
                Positioned.fill(child: page),
                Positioned(left: 0, right: 0, bottom: 0, child: StickyBar(child: phoneBar!)),
              ],
            )
          : page,
    );
  }
}

/// The white fade a phone's bottom bar sits in.
class StickyBar extends StatelessWidget {
  const StickyBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00FFFFFF), AmrColors.white],
        stops: [0, 0.35],
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 26), child: child),
    ),
  );
}

/// The ask field for [AppPage.phoneBar]; opens the composer for [about].
class StickyAskBar extends StatelessWidget {
  const StickyAskBar({super.key, required this.about, this.hint = 'Ask anything…'});

  final AskContext about;
  final String hint;

  @override
  Widget build(BuildContext context) => AskLauncher(hint: hint, about: about);
}

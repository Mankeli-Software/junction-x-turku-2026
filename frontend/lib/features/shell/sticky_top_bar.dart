import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../ds/ds.dart';

/// Keeps [bar] pinned to the top while the page scrolls under it. At the top of the page the
/// bar sits on the glow exactly as before; once the content moves, a frosted white backing
/// and a hairline fade in so the content passes cleanly underneath.
///
/// [page] builds the scrolling page and puts the given placeholder where the bar sits at the
/// top of the content, so the layout keeps the bar's height.
class StickyTopBar extends StatefulWidget {
  const StickyTopBar({super.key, required this.bar, required this.page, this.barKey});

  final Widget bar;

  /// On the pinned bar (with its safe area), for pages that need its height.
  final GlobalKey? barKey;
  final Widget Function(BuildContext context, Widget placeholder) page;

  @override
  State<StickyTopBar> createState() => _StickyTopBarState();
}

class _StickyTopBarState extends State<StickyTopBar> {
  /// 0 at the top of the page, 1 once the content has moved [_fadeOver] pixels.
  final _scrolled = ValueNotifier<double>(0);
  static const _fadeOver = 24.0;

  @override
  void dispose() {
    _scrolled.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      // extentBefore, not pixels: a scroll view with a center (the chat) starts below zero.
      _scrolled.value = (n.metrics.extentBefore / _fadeOver).clamp(0.0, 1.0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Visibility(
      visible: false,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: widget.bar,
    );
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          Positioned.fill(child: widget.page(context, placeholder)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _scrolled,
              builder: (context, t, bar) => _Backing(t: t, child: bar!),
              child: KeyedSubtree(
                key: widget.barKey,
                child: SafeArea(bottom: false, child: widget.bar),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Backing extends StatelessWidget {
  const _Backing({required this.t, required this.child});

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (t == 0) return child;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AmrColors.white.withValues(alpha: 0.78 * t),
            border: Border(
              bottom: BorderSide(color: AmrColors.lavenderPale.withValues(alpha: t)),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../tokens.dart';

/// Base for everything tappable: pointer cursor, hover and pressed states, and a small
/// press-down scale so taps feel immediate.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.pressScale = 0.97,
    this.tooltip,
  });

  final VoidCallback? onTap;
  final Widget Function(BuildContext context, PressState state) builder;
  final double pressScale;
  final String? tooltip;

  @override
  State<Pressable> createState() => _PressableState();
}

class PressState {
  const PressState({required this.hovered, required this.pressed, required this.enabled});

  final bool hovered;
  final bool pressed;
  final bool enabled;
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final state = PressState(hovered: _hovered && _enabled, pressed: _pressed, enabled: _enabled);
    Widget child = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? widget.pressScale : 1,
          duration: AmrMotion.fast,
          curve: AmrMotion.curve,
          child: widget.builder(context, state),
        ),
      ),
    );
    if (widget.tooltip != null) child = Tooltip(message: widget.tooltip!, child: child);
    return child;
  }
}

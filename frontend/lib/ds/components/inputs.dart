import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens.dart';
import '../typography.dart';
import 'buttons.dart';

enum AskFieldSize {
  /// Under a page title: 56px field, 18px text, 56px send button.
  large,

  /// Inside cards and headers: 44px field, 16px text.
  medium,
}

enum AskFieldStyle { elevated, outlined, flat }

/// The pill-shaped "ask" input with a round navy send button.
class AskField extends StatefulWidget {
  const AskField({
    super.key,
    required this.hint,
    this.onSubmit,
    this.size = AskFieldSize.medium,
    this.style = AskFieldStyle.elevated,
    this.enabled = true,
    this.controller,
  });

  final String hint;
  final ValueChanged<String>? onSubmit;
  final AskFieldSize size;
  final AskFieldStyle style;
  final bool enabled;
  final TextEditingController? controller;

  @override
  State<AskField> createState() => _AskFieldState();
}

class _AskFieldState extends State<AskField> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final large = widget.size == AskFieldSize.large;
    final fieldHeight = large ? 56.0 : 44.0;
    final fontSize = large ? 18.0 : 16.0;
    final padding = large
        ? const EdgeInsets.fromLTRB(28, 8, 8, 8)
        : const EdgeInsets.fromLTRB(22, 6, 6, 6);
    final textStyle = AmrText.body(fontSize);
    return Opacity(
      opacity: widget.enabled ? 1 : 0.6,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AmrColors.white,
          borderRadius: AmrRadius.pill,
          border: widget.style == AskFieldStyle.outlined ? Border.all(color: AmrColors.ink) : null,
          boxShadow: switch (widget.style) {
            AskFieldStyle.elevated => large ? AmrShadows.md : AmrShadows.input,
            _ => null,
          },
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: fieldHeight,
                child: Center(
                  child: TextField(
                    controller: _controller,
                    enabled: widget.enabled,
                    style: textStyle,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hint,
                      hintStyle: textStyle.copyWith(color: AmrColors.inkHover),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AmrIconButton(
              icon: LucideIcons.arrowRight,
              size: fieldHeight,
              iconSize: large ? 22 : 18,
              onPressed: widget.enabled ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}

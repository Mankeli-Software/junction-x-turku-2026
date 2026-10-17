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
    this.onTap,
    this.accent = false,
  });

  final String hint;
  final ValueChanged<String>? onSubmit;
  final AskFieldSize size;
  final AskFieldStyle style;
  final bool enabled;
  final TextEditingController? controller;

  /// Makes the field a launcher: tapping it (or the send button while it is empty) calls
  /// [onTap] instead of typing in place, e.g. to open a larger composer.
  final VoidCallback? onTap;

  /// A violet send button: the AI's colour.
  final bool accent;

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
    if (!widget.enabled) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.onTap?.call();
      return;
    }
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
                  // Never disabled: on the web a disabled field's input turns read-only and
                  // stays so once enabled again. [enabled] only holds back sending.
                  child: TextField(
                    controller: _controller,
                    readOnly: widget.onTap != null,
                    onTap: widget.onTap,
                    mouseCursor: widget.onTap != null ? SystemMouseCursors.text : null,
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
              variant: widget.accent ? AmrIconButtonVariant.accent : AmrIconButtonVariant.primary,
              onPressed: widget.enabled ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'pressable.dart';

enum AmrButtonVariant {
  /// Navy fill, white text: the main action.
  primary,

  /// 1px navy border, transparent: secondary actions and unselected filters.
  outline,

  /// White with the small shadow: top-bar pills.
  surface,

  /// White, no border, no shadow: suggestion chips on a lavender panel.
  soft,
}

/// Heights, paddings and font sizes used across the design.
enum AmrButtonSize {
  /// 40px: catalog chips, chat actions.
  sm(40, 16, 14),

  /// 44px: suggestion chips, follow-ups.
  md(44, 18, 15),

  /// 48px: top bar, filters, page actions.
  lg(48, 22, 15),

  /// 52px: Edit details / New patient.
  xl(52, 24, 16),

  /// 56px: "Continue as …".
  xxl(56, 30, 17),

  /// 60px: "Show what works".
  hero(60, 34, 18);

  const AmrButtonSize(this.height, this.padding, this.fontSize);

  final double height;
  final double padding;
  final double fontSize;
}

class AmrButton extends StatelessWidget {
  const AmrButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AmrButtonVariant.outline,
    this.size = AmrButtonSize.lg,
    this.leading,
    this.trailing,
    this.fontSize,
    this.fontWeight,
    this.padding,
    this.expand = false,
  });

  /// Filter or toggle chip: navy when [selected], outline otherwise.
  const AmrButton.toggle({
    super.key,
    required this.label,
    required bool selected,
    this.onPressed,
    this.size = AmrButtonSize.lg,
    this.fontSize = 16,
    this.leading,
    this.trailing,
    this.fontWeight,
    this.padding,
    this.expand = false,
  }) : variant = selected ? AmrButtonVariant.primary : AmrButtonVariant.outline;

  final String label;
  final VoidCallback? onPressed;
  final AmrButtonVariant variant;
  final AmrButtonSize size;
  final Widget? leading;
  final Widget? trailing;
  final double? fontSize;
  final FontWeight? fontWeight;
  final EdgeInsetsGeometry? padding;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      builder: (context, s) {
        final (bg, fg, border, shadow) = _colors(s);
        final textStyle = AmrText.inter(
          fontSize ?? size.fontSize,
          weight:
              fontWeight ??
              (variant == AmrButtonVariant.primary && size.index >= 4
                  ? FontWeight.w500
                  : FontWeight.w400),
          color: fg,
        );
        return AnimatedContainer(
          duration: AmrMotion.fast,
          constraints: BoxConstraints(minHeight: size.height),
          padding: padding ?? EdgeInsets.symmetric(horizontal: size.padding),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AmrRadius.pill,
            border: border,
            boxShadow: shadow,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: fg, size: 18),
            child: DefaultTextStyle.merge(
              style: textStyle,
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                  if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  (Color, Color, BoxBorder?, List<BoxShadow>?) _colors(PressState s) {
    final dim = !s.enabled;
    switch (variant) {
      case AmrButtonVariant.primary:
        final bg = s.hovered ? AmrColors.inkHover : AmrColors.ink;
        return (dim ? AmrColors.lavender : bg, AmrColors.white, null, null);
      case AmrButtonVariant.outline:
        return (
          s.hovered ? AmrColors.lavenderSoft : const Color(0x00FFFFFF),
          dim ? AmrColors.inkHover : AmrColors.ink,
          Border.all(color: dim ? AmrColors.lavender : AmrColors.ink),
          null,
        );
      case AmrButtonVariant.surface:
        return (
          s.hovered ? AmrColors.lavenderSoft : AmrColors.white,
          AmrColors.ink,
          null,
          AmrShadows.sm,
        );
      case AmrButtonVariant.soft:
        return (s.hovered ? AmrColors.lavenderSoft : AmrColors.white, AmrColors.ink, null, null);
    }
  }
}

enum AmrIconButtonVariant { primary, soft, surface }

/// Round icon button: the send arrow (navy) and widget options (soft lavender).
class AmrIconButton extends StatelessWidget {
  const AmrIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.iconSize = 18,
    this.variant = AmrIconButtonVariant.primary,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final AmrIconButtonVariant variant;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      tooltip: tooltip,
      pressScale: 0.92,
      builder: (context, s) {
        final (bg, fg) = switch (variant) {
          AmrIconButtonVariant.primary => (
            s.hovered ? AmrColors.inkHover : AmrColors.ink,
            AmrColors.white,
          ),
          AmrIconButtonVariant.soft => (
            s.hovered ? AmrColors.lavenderPale : AmrColors.lavenderSoft,
            AmrColors.ink,
          ),
          AmrIconButtonVariant.surface => (
            s.hovered ? AmrColors.lavenderSoft : AmrColors.white,
            AmrColors.ink,
          ),
        };
        return AnimatedContainer(
          duration: AmrMotion.fast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: variant == AmrIconButtonVariant.surface ? AmrShadows.sm : null,
          ),
          child: Icon(icon, size: iconSize, color: fg),
        );
      },
    );
  }
}

/// An underlined text link ("Open the alert", "Open full answer").
class AmrLink extends StatelessWidget {
  const AmrLink(this.label, {super.key, this.onTap, this.fontSize = 14});

  final String label;
  final VoidCallback? onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressScale: 1,
      builder: (context, s) => Text(
        label,
        style: AmrText.inter(fontSize, color: s.hovered ? AmrColors.inkHover : AmrColors.ink)
            .copyWith(
              decoration: TextDecoration.underline,
              decorationColor: s.hovered ? AmrColors.inkHover : AmrColors.ink,
            ),
      ),
    );
  }
}

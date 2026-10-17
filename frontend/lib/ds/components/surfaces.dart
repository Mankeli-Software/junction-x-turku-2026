import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'pressable.dart';

enum AmrCardTone {
  /// White with the medium shadow.
  raised,

  /// White with the small shadow.
  quiet,

  /// Lavender #C6C4ED.
  accent,

  /// Lavender #F4F3FC.
  subtle,

  /// Blush #FDE3E9: alerts.
  alert,

  /// Subtle with a dashed periwinkle border: "Add a widget".
  dashed,

  /// No fill.
  plain,
}

/// The rounded panel every widget sits on.
class AmrCard extends StatelessWidget {
  const AmrCard({
    super.key,
    required this.child,
    this.tone = AmrCardTone.raised,
    this.padding = const EdgeInsets.all(AmrSpace.x28),
    this.radius = AmrRadius.card,
    this.onTap,
    this.shadow,
  });

  final Widget child;
  final AmrCardTone tone;
  final EdgeInsetsGeometry padding;
  final BorderRadius radius;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return _box(context, hovered: false);
    return Pressable(
      onTap: onTap,
      pressScale: 0.99,
      builder: (context, s) => _box(context, hovered: s.hovered),
    );
  }

  Widget _box(BuildContext context, {required bool hovered}) {
    final (color, shadows) = switch (tone) {
      AmrCardTone.raised => (AmrColors.white, AmrShadows.md),
      AmrCardTone.quiet => (AmrColors.white, AmrShadows.sm),
      AmrCardTone.accent => (AmrColors.lavender, null),
      AmrCardTone.subtle => (AmrColors.lavenderSoft, null),
      AmrCardTone.alert => (AmrColors.blush, null),
      AmrCardTone.dashed => (AmrColors.lavenderSoft, null),
      AmrCardTone.plain => (const Color(0x00FFFFFF), null),
    };
    final hoverShadow = hovered ? AmrShadows.lg : null;
    final box = AnimatedContainer(
      duration: AmrMotion.base,
      curve: AmrMotion.curve,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        boxShadow: shadow ?? hoverShadow ?? shadows,
      ),
      child: child,
    );
    if (tone != AmrCardTone.dashed) return box;
    return CustomPaint(
      foregroundPainter: _DashedBorder(radius: radius, color: AmrColors.periwinkle),
      child: box,
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.radius, required this.color});

  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = radius.toRRect(Offset.zero & size).deflate(0.75);
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color || old.radius != radius;
}

/// Small pill label: "Likely real", "Oral", "In short".
class AmrTag extends StatelessWidget {
  const AmrTag(this.label, {super.key, this.color = AmrColors.lavenderPale, this.fontSize = 12});

  final String label;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: AmrRadius.pill),
      child: Text(label, style: AmrText.label(fontSize)),
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, this.color = AmrColors.magenta, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A label with a leading dot: "● On your ward now".
class DotLabel extends StatelessWidget {
  const DotLabel(this.label, {super.key, this.color = AmrColors.magenta, this.fontSize = 14});

  final String label;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      StatusDot(color: color),
      const SizedBox(width: 10),
      Flexible(child: Text(label, style: AmrText.label(fontSize))),
    ],
  );
}

/// Keyboard hint: [1] – [4].
class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key, this.large = false, this.color, this.textColor});

  final String label;
  final bool large;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    if (large) {
      return AnimatedContainer(
        duration: AmrMotion.fast,
        constraints: const BoxConstraints(minWidth: 30),
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color ?? AmrColors.lavenderPale,
          borderRadius: AmrRadius.kbd,
        ),
        child: Text(label, style: AmrText.label(14).copyWith(color: textColor)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AmrColors.lavenderSoft,
        borderRadius: AmrRadius.kbdSmall,
        border: Border.all(color: AmrColors.lavender),
      ),
      child: Text(label, style: AmrText.label(12)),
    );
  }
}

/// Initials in a circle.
class AmrAvatar extends StatelessWidget {
  const AmrAvatar(
    this.initials, {
    super.key,
    this.size = 36,
    this.color = AmrColors.lavender,
    this.textColor = AmrColors.ink,
  });

  final String initials;
  final double size;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: AmrMotion.fast,
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Text(initials, style: AmrText.label(13).copyWith(color: textColor)),
  );
}

/// "✦", the separator and AI mark used throughout the design.
const sparkle = '✦';

/// "Home ✦ Urology".
class Breadcrumb extends StatelessWidget {
  const Breadcrumb(this.parts, {super.key, this.onTapFirst});

  final List<String> parts;
  final VoidCallback? onTapFirst;

  @override
  Widget build(BuildContext context) {
    final style = AmrText.body(15);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) Text(sparkle, style: style),
          if (i == 0 && onTapFirst != null)
            Pressable(
              onTap: onTapFirst,
              pressScale: 1,
              builder: (_, s) => Text(
                parts[i],
                style: style.copyWith(
                  decoration: TextDecoration.underline,
                  color: s.hovered ? AmrColors.inkHover : AmrColors.ink,
                ),
              ),
            )
          else
            Text(parts[i], style: style),
        ],
      ],
    );
  }
}

/// Sora title with an optional Inter subtitle.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.size = 30,
    this.trailing,
    this.gap = AmrSpace.x6,
  });

  final String title;
  final String? subtitle;
  final double size;
  final Widget? trailing;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AmrText.title(size)),
        if (subtitle != null) ...[
          SizedBox(height: gap),
          Text(subtitle!, style: AmrText.body(size >= 30 ? 15 : 14)),
        ],
      ],
    );
    if (trailing == null) return head;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 12,
      runSpacing: 12,
      children: [head, trailing!],
    );
  }
}

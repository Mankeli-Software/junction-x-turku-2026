import 'package:flutter/material.dart';

import '../responsive.dart';
import '../tokens.dart';

/// White page with the lavender and pink glows in the top corners:
/// `radial-gradient(900px 600px at 0% 0%, #D9D4FB, transparent 70%)` and the pink twin at 100% 0%.
class AmrBackground extends StatelessWidget {
  const AmrBackground({super.key, required this.child, this.glowHeight = 600});

  final Widget child;
  final double glowHeight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GlowPainter(glowHeight), child: child);
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.glowHeight);

  final double glowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AmrColors.white);
    _glow(canvas, Offset.zero, 900, glowHeight, AmrColors.glowLavender);
    _glow(canvas, Offset(size.width, 0), 820, glowHeight, AmrColors.glowPink);
  }

  /// An elliptical radial gradient with radii [rx]×[ry], fading out at 70%.
  void _glow(Canvas canvas, Offset center, double rx, double ry, Color color) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, ry / rx);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
        stops: const [0, 0.7],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: rx));
    canvas.drawCircle(Offset.zero, rx, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.glowHeight != glowHeight;
}

/// Centers page content at max 1320px with the fluid side gutter.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.top = 24,
    this.bottom = AmrSpace.x64,
    this.gap = AmrSpace.x32,
  });

  final List<Widget> children;
  final double top;
  final double bottom;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final g = context.gutter;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AmrBreakpoints.maxContent),
        child: Padding(
          padding: EdgeInsets.fromLTRB(g, top, g, bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Column with a fixed gap between children (CSS flex column + gap).
class ColumnGap extends StatelessWidget {
  const ColumnGap(
    this.children, {
    super.key,
    this.gap = AmrSpace.x14,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final List<Widget> children;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: crossAxisAlignment,
    children: [
      for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
    ],
  );
}

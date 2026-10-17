import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

/// Painted bar chart for weekly or monthly counts (cases per week, cultures per month).
///
/// Bars sit on a 1px navy baseline, scaled from zero; a zero draws no bar, as in the design.
/// [highlight] picks bars drawn in [highlightColor] (the raised weeks, the latest month).
/// [labels] are spread under the chart ("Mar Apr May Jun"). [expected] draws a dashed level.
/// Animates between value sets of the same length.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    this.highlight,
    this.color = AmrColors.periwinkle,
    this.highlightColor = AmrColors.magenta,
    this.aspectRatio = 600 / 104,
    this.barFraction = 0.7,
    this.maxBarFraction = 0.86,
    this.radius = 4,
    this.labels,
    this.labelSize = 13,
    this.expected,
  });

  final List<double> values;

  /// Same length as [values]; null highlights nothing.
  final List<bool>? highlight;
  final Color color;
  final Color highlightColor;
  final double aspectRatio;

  /// Bar width as a share of its slot.
  final double barFraction;

  /// Height of the tallest bar as a share of the chart height.
  final double maxBarFraction;
  final double radius;
  final List<String>? labels;
  final double labelSize;

  /// A dashed horizontal level in the values' units (e.g. the expected weekly count).
  final double? expected;

  @override
  Widget build(BuildContext context) {
    final chart = AspectRatio(
      aspectRatio: aspectRatio,
      child: TweenAnimationBuilder<List<double>>(
        tween: _ListTween(end: values),
        duration: AmrMotion.slow,
        curve: AmrMotion.curve,
        builder: (context, v, _) => CustomPaint(
          painter: _BarPainter(
            values: v,
            highlight: highlight,
            color: color,
            highlightColor: highlightColor,
            barFraction: barFraction,
            maxBarFraction: maxBarFraction,
            radius: radius,
            expected: expected,
          ),
        ),
      ),
    );
    final l = labels;
    if (l == null || l.isEmpty) return chart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        chart,
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (final s in l) Text(s, style: AmrText.body(labelSize))],
        ),
      ],
    );
  }
}

class _ListTween extends Tween<List<double>> {
  _ListTween({required List<double> end}) : super(begin: end, end: end);

  @override
  List<double> lerp(double t) {
    final b = begin!, e = end!;
    if (b.length != e.length) return e;
    return [for (var i = 0; i < e.length; i++) b[i] + (e[i] - b[i]) * t];
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.highlight,
    required this.color,
    required this.highlightColor,
    required this.barFraction,
    required this.maxBarFraction,
    required this.radius,
    required this.expected,
  });

  final List<double> values;
  final List<bool>? highlight;
  final Color color;
  final Color highlightColor;
  final double barFraction;
  final double maxBarFraction;
  final double radius;
  final double? expected;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 0.5;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = AmrColors.ink
        ..strokeWidth = 1,
    );
    if (values.isEmpty) return;
    final top = [...values, expected ?? 0].reduce((a, b) => a > b ? a : b);
    if (top <= 0) return;
    final scale = size.height * maxBarFraction / top;
    final slot = size.width / values.length;
    final w = slot * barFraction;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] * scale;
      if (h <= 0.5) continue;
      final on = highlight != null && i < highlight!.length && highlight![i];
      final x = slot * i + (slot - w) / 2;
      final r = Radius.circular(radius.clamp(0, h / 2).toDouble());
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, base - h, w, h),
          topLeft: r,
          topRight: r,
          bottomLeft: r,
          bottomRight: r,
        ),
        Paint()..color = on ? highlightColor : color,
      );
    }
    final ex = expected;
    if (ex != null && ex > 0) {
      final y = base - ex * scale;
      final paint = Paint()
        ..color = AmrColors.ink
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset((x + 4).clamp(0, size.width), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values ||
      old.highlight != highlight ||
      old.color != color ||
      old.highlightColor != highlightColor ||
      old.expected != expected;
}

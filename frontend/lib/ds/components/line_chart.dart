import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

/// One point of a [ChartSeries]: a date and a share (0–1), with an optional range.
class ChartPoint {
  const ChartPoint(this.x, this.y, {this.low, this.high});

  final DateTime x;
  final double y;
  final double? low;
  final double? high;
}

/// A line on a [LineChart].
class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.points,
    this.color = AmrColors.ink,
    this.dashed = false,
    this.band = false,
  });

  final String label;
  final List<ChartPoint> points;
  final Color color;

  /// Drawn 7/5 dashed: the second group, or the quiet hospital reference.
  final bool dashed;

  /// Shade the low–high range under this line (lavender, as in the design).
  final bool band;
}

/// A highlighted point: a magenta dot with a caption ("March cluster · 13 of 20").
class ChartMark {
  const ChartMark(this.x, this.y, this.label);

  final DateTime x;
  final double y;
  final String label;
}

/// Series colors in order, from the tokens.
const chartPalette = [AmrColors.ink, AmrColors.violet, AmrColors.magenta, AmrColors.periwinkle];

/// Painted line chart for shares over time, styled as the design's trend charts: hairline
/// gridlines with % labels on the left, a navy baseline, 2.5px lines, an optional range band,
/// end labels per line and highlighted marks. The lines draw in from the left on first show
/// and whenever the data changes.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.series,
    this.marks = const [],
    this.xLabels = const [],
    this.height = 200,
    this.endLabels = true,
    this.yAxis = true,
  });

  final List<ChartSeries> series;
  final List<ChartMark> marks;

  /// Spread evenly under the plot ("Jan", "Mar", …).
  final List<String> xLabels;
  final double height;

  /// Label each line at its last point ("Women", "Men"); skipped for a single line.
  final bool endLabels;
  final bool yAxis;

  static const _axisWidth = 40.0;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < AmrBreakpoints.compact;
    final labelled = endLabels && series.length > 1;
    final rightPad = labelled && !compact ? 80.0 : 8.0;
    final leftPad = yAxis ? _axisWidth : 0.0;
    final key = ValueKey(
      Object.hashAll([
        for (final s in series) ...[s.label, s.points.length, s.points.lastOrNull?.y],
      ]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          key: key,
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => SizedBox(
            width: double.infinity,
            height: height,
            child: CustomPaint(
              painter: _LinePainter(
                series: series,
                marks: marks,
                progress: t,
                leftPad: leftPad,
                rightPad: rightPad,
                endLabels: labelled,
                endLabelsAbove: compact,
                axisStyle: AmrText.body(compact ? 11 : 12),
                endStyle: AmrText.body(compact ? 12 : 13),
                markStyle: AmrText.body(compact ? 11 : 13),
              ),
            ),
          ),
        ),
        if (xLabels.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: leftPad, right: rightPad),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (final l in xLabels) Text(l, style: AmrText.body(compact ? 12 : 13))],
            ),
          ),
        ],
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.series,
    required this.marks,
    required this.progress,
    required this.leftPad,
    required this.rightPad,
    required this.endLabels,
    required this.endLabelsAbove,
    required this.axisStyle,
    required this.endStyle,
    required this.markStyle,
  });

  final List<ChartSeries> series;
  final List<ChartMark> marks;
  final double progress;
  final double leftPad;
  final double rightPad;
  final bool endLabels;
  final bool endLabelsAbove;
  final TextStyle axisStyle;
  final TextStyle endStyle;
  final TextStyle markStyle;

  static const _top = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [for (final s in series) ...s.points];
    if (points.isEmpty) return;

    // Scales: dates linearly across the plot; shares on a "nice" 5% or 10% grid.
    final x0 = points.map((p) => p.x).reduce((a, b) => a.isBefore(b) ? a : b);
    final x1 = points.map((p) => p.x).reduce((a, b) => a.isAfter(b) ? a : b);
    final span = math.max(1, x1.difference(x0).inHours);
    final values = [
      for (final s in series)
        for (final p in s.points) ...[p.y, if (s.band) ?p.low, if (s.band) ?p.high],
      for (final m in marks) m.y,
    ];
    var step = 0.05;
    var lo = (values.reduce(math.min) / step).floorToDouble() * step;
    var hi = (values.reduce(math.max) / step).ceilToDouble() * step;
    if (hi - lo > 0.3) {
      step = 0.1;
      lo = (lo / step).floorToDouble() * step;
      hi = (hi / step).ceilToDouble() * step;
    }
    if (hi <= lo) hi = lo + step;

    final plot = Rect.fromLTRB(leftPad, _top, size.width - rightPad, size.height - 1);
    double sx(DateTime d) => plot.left + plot.width * d.difference(x0).inHours / span;
    double sy(double v) => plot.bottom - plot.height * (v - lo) / (hi - lo);

    // Gridlines and the baseline.
    final grid = Paint()..color = AmrColors.line;
    final ticks = ((hi - lo) / step).round();
    for (var i = 0; i <= ticks; i++) {
      final v = lo + i * step;
      final y = sy(v);
      canvas.drawLine(
        Offset(plot.left, y),
        Offset(plot.right, y),
        i == 0 ? (Paint()..color = AmrColors.ink) : grid,
      );
      if (leftPad > 0) {
        final tp = _text('${(v * 100).round()}%', axisStyle);
        tp.paint(canvas, Offset(plot.left - 8 - tp.width, y - tp.height / 2));
      }
    }

    // Reveal from the left.
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(0, 0, plot.left + (plot.width + rightPad) * progress, size.height),
    );

    for (final s in series.where((s) => s.band)) {
      final pts = s.points.where((p) => p.low != null && p.high != null).toList();
      if (pts.length < 2) continue;
      final band = Path()..moveTo(sx(pts.first.x), sy(pts.first.high!));
      for (final p in pts.skip(1)) {
        band.lineTo(sx(p.x), sy(p.high!));
      }
      for (final p in pts.reversed) {
        band.lineTo(sx(p.x), sy(p.low!));
      }
      band.close();
      canvas.drawPath(band, Paint()..color = AmrColors.lavenderPale);
    }

    for (final s in series) {
      if (s.points.isEmpty) continue;
      final line = Path()..moveTo(sx(s.points.first.x), sy(s.points.first.y));
      for (final p in s.points.skip(1)) {
        line.lineTo(sx(p.x), sy(p.y));
      }
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(s.dashed ? _dash(line, 7, 5) : line, paint);
    }
    canvas.restore();

    if (progress < 1) return;

    // End dots and labels ("Women", "Men"). Lines that end close together would print their
    // labels on top of each other, so the labels are pushed apart; a thin line in the series
    // colour joins a moved label to its dot.
    if (endLabels) {
      final ends = <({ChartSeries s, Offset at, TextPainter tp, double top})>[];
      for (final s in series) {
        final last = s.points.lastOrNull;
        if (last == null) continue;
        final at = Offset(sx(last.x), sy(last.y));
        final tp = _text(s.label, endStyle);
        final top = endLabelsAbove ? at.dy - 10 - tp.height : at.dy - tp.height / 2;
        ends.add((s: s, at: at, tp: tp, top: top));
      }
      const gap = 3.0;
      // Beside the line: push down from the top one. Above it: stack upwards from the lowest.
      ends.sort((x, y) => endLabelsAbove ? y.top.compareTo(x.top) : x.top.compareTo(y.top));
      final tops = <double>[];
      for (final e in ends) {
        if (tops.isEmpty) {
          tops.add(e.top);
        } else {
          final prev = tops.last;
          tops.add(
            endLabelsAbove
                ? math.min(e.top, prev - e.tp.height - gap)
                : math.max(e.top, prev + e.tp.height + gap),
          );
        }
      }
      for (var i = 0; i < ends.length; i++) {
        final e = ends[i];
        canvas.drawCircle(e.at, 5, Paint()..color = e.s.color);
        final pos = endLabelsAbove
            ? Offset(e.at.dx - e.tp.width, tops[i])
            : Offset(e.at.dx + 11, tops[i]);
        if ((tops[i] - e.top).abs() > 0.5) {
          final to = Offset(endLabelsAbove ? e.at.dx : pos.dx - 2, tops[i] + e.tp.height / 2);
          canvas.drawLine(
            e.at,
            to,
            Paint()
              ..color = e.s.color
              ..strokeWidth = 1.2,
          );
        }
        e.tp.paint(canvas, pos);
      }
    }

    for (final m in marks) {
      final at = Offset(sx(m.x), sy(m.y));
      canvas.drawCircle(at, 6, Paint()..color = AmrColors.magenta);
      final tp = _text(m.label, markStyle);
      final dx = at.dx + 11 + tp.width > size.width ? at.dx - 11 - tp.width : at.dx + 11;
      tp.paint(canvas, Offset(dx, math.max(0, at.dy - 6 - tp.height)));
    }
  }

  Path _dash(Path source, double on, double off) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      for (double d = 0; d < metric.length; d += on + off) {
        out.addPath(metric.extractPath(d, math.min(d + on, metric.length)), Offset.zero);
      }
    }
    return out;
  }

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress ||
      old.series != series ||
      old.marks != marks ||
      old.leftPad != leftPad ||
      old.rightPad != rightPad ||
      old.endLabelsAbove != endLabelsAbove;
}

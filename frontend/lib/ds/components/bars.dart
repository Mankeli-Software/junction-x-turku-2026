import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

/// Stacked S / I / R bar. Shares are 0–1 and should add up to 1.
///
/// [marker] draws the 12-month level as a vertical line. [heroLabels] puts "S 91%" inside the
/// bar and the [markerCaption] above it, as in the answer hero. Painted, so it is cheap,
/// animates between values and works inside intrinsic-height rows.
class SirBar extends StatelessWidget {
  const SirBar({
    super.key,
    required this.s,
    required this.i,
    required this.r,
    this.height = 22,
    this.radius = 7,
    this.marker,
    this.heroLabels = false,
    this.markerCaption,
  });

  final double s;
  final double i;
  final double r;
  final double height;
  final double radius;
  final double? marker;
  final bool heroLabels;
  final String? markerCaption;

  double get _top => heroLabels ? 22 : (marker != null ? 4 : 0);
  double get _bottom => heroLabels ? 0 : (marker != null ? 4 : 0);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<_Sir>(
      tween: _SirTween(end: _Sir(s, i, marker ?? -1)),
      duration: AmrMotion.slow,
      curve: AmrMotion.curve,
      builder: (context, v, _) => SizedBox(
        width: double.infinity,
        height: _top + height + _bottom,
        child: CustomPaint(
          painter: _SirPainter(
            v: v,
            top: _top,
            height: height,
            radius: radius,
            hero: heroLabels,
            label: heroLabels ? AmrText.label(15).copyWith(color: AmrColors.white) : null,
            caption: markerCaption,
            captionStyle: AmrText.body(12),
          ),
        ),
      ),
    );
  }
}

class _Sir {
  const _Sir(this.s, this.i, this.marker);

  final double s;
  final double i;

  /// Negative: no marker.
  final double marker;
}

class _SirTween extends Tween<_Sir> {
  _SirTween({required _Sir end}) : super(begin: end, end: end);

  @override
  _Sir lerp(double t) => _Sir(
    begin!.s + (end!.s - begin!.s) * t,
    begin!.i + (end!.i - begin!.i) * t,
    end!.marker < 0 ? -1 : begin!.marker + (end!.marker - begin!.marker) * t,
  );
}

class _SirPainter extends CustomPainter {
  _SirPainter({
    required this.v,
    required this.top,
    required this.height,
    required this.radius,
    required this.hero,
    required this.label,
    required this.caption,
    required this.captionStyle,
  });

  final _Sir v;
  final double top;
  final double height;
  final double radius;
  final bool hero;
  final TextStyle? label;
  final String? caption;
  final TextStyle captionStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final bar = Rect.fromLTWH(0, top, w, height);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(bar, Radius.circular(radius)));
    final sw = w * v.s.clamp(0, 1);
    final iw = w * v.i.clamp(0, 1);
    canvas.drawRect(bar, Paint()..color = AmrColors.resistant);
    canvas.drawRect(Rect.fromLTWH(0, top, sw + iw, height), Paint()..color = AmrColors.increased);
    canvas.drawRect(Rect.fromLTWH(0, top, sw, height), Paint()..color = AmrColors.susceptible);
    if (label != null && sw > 60) {
      final tp = _text('S ${_pct(v.s)}', label!);
      tp.paint(canvas, Offset(14, top + (height - tp.height) / 2));
    }
    canvas.restore();

    if (v.marker < 0) return;
    final x = w * v.marker.clamp(0, 1);
    if (hero) {
      canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, top + height + 6), Paint()..color = AmrColors.ink);
      if (caption != null) {
        final tp = _text(caption!, captionStyle);
        tp.paint(canvas, Offset((x - 6 - tp.width).clamp(0, w), 0));
      }
    } else {
      final line = Rect.fromLTWH(x - 1.5, 0, 3, size.height);
      canvas.drawRect(line.inflate(2), Paint()..color = AmrColors.white);
      canvas.drawRect(line, Paint()..color = AmrColors.ink);
    }
  }

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(_SirPainter old) =>
      old.v.s != v.s || old.v.i != v.i || old.v.marker != v.marker || old.caption != caption;
}

String _pct(double v) => '${(v * 100).round()}%';

/// One legend entry: a 14px swatch and a label.
class LegendSwatch extends StatelessWidget {
  const LegendSwatch({super.key, required this.color, required this.label, this.line = false});

  final Color color;
  final String label;

  /// Draw a 2×16 line instead of a square (the 12-month level).
  final bool line;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: line ? 2 : 14,
        height: line ? 16 : 14,
        decoration: BoxDecoration(color: color, borderRadius: line ? null : AmrRadius.swatch),
      ),
      const SizedBox(width: 8),
      Text(label, style: AmrText.body(14)),
    ],
  );
}

/// The S / I / R legend, optionally with the 12-month line.
class SirLegend extends StatelessWidget {
  const SirLegend({super.key, this.long = false, this.withMarker = false, this.s, this.i, this.r});

  /// "Susceptible 91%" instead of "S".
  final bool long;
  final bool withMarker;
  final double? s;
  final double? i;
  final double? r;

  @override
  Widget build(BuildContext context) {
    String l(String short, String full, double? v) =>
        long ? '$full${v == null ? '' : ' ${_pct(v)}'}' : short;
    return Wrap(
      spacing: long ? 22 : 18,
      runSpacing: 8,
      children: [
        LegendSwatch(color: AmrColors.susceptible, label: l('S', 'Susceptible', s)),
        LegendSwatch(
          color: AmrColors.increased,
          label: l('I', 'Susceptible, increased exposure', i),
        ),
        LegendSwatch(color: AmrColors.resistant, label: l('R', 'Resistant', r)),
        if (withMarker)
          const LegendSwatch(color: AmrColors.ink, label: '12-month level', line: true),
      ],
    );
  }
}

/// A single share bar on a track (organism mix).
class ShareBar extends StatelessWidget {
  const ShareBar({
    super.key,
    required this.value,
    this.height = 10,
    this.color = AmrColors.ink,
    this.track = AmrColors.white,
  });

  final double value;
  final double height;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value.clamp(0, 1).toDouble()),
    duration: AmrMotion.slow,
    curve: AmrMotion.curve,
    builder: (context, v, _) => SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(painter: _SharePainter(v, color, track)),
    ),
  );
}

class _SharePainter extends CustomPainter {
  _SharePainter(this.value, this.color, this.track);

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    if (value <= 0) return;
    final w = (size.width * value).clamp(size.height, size.width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SharePainter old) => old.value != value || old.color != color;
}

/// Step progress: 28×6 pills, filled up to the current step.
class StepDots extends StatelessWidget {
  const StepDots({super.key, required this.count, required this.current});

  final int count;

  /// Zero-based.
  final int current;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        AnimatedContainer(
          duration: AmrMotion.base,
          width: 28,
          height: 6,
          decoration: BoxDecoration(
            color: i <= current ? AmrColors.ink : AmrColors.line,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ],
    ],
  );
}

/// Shares side by side in one bar with 2px gaps (organism mix in chat).
class StackedBar extends StatelessWidget {
  const StackedBar({super.key, required this.segments, this.height = 20, this.radius = 8});

  /// (share 0–1, color), in order.
  final List<(double, Color)> segments;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: height,
    child: CustomPaint(painter: _StackedPainter(segments, radius)),
  );
}

class _StackedPainter extends CustomPainter {
  _StackedPainter(this.segments, this.radius);

  final List<(double, Color)> segments;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.0;
    final total = segments.fold<double>(0, (a, s) => a + s.$1);
    if (total <= 0) return;
    final free = size.width - gap * (segments.length - 1);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    var x = 0.0;
    for (final (v, color) in segments) {
      final w = free * v / total;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), Paint()..color = color);
      x += w + gap;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StackedPainter old) => old.segments != segments;
}

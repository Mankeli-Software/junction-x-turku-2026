import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/data.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/components/line_chart.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final resistanceTrendEntry = CatalogEntry(
  name: 'ResistanceTrend',
  title: 'Resistance trend',
  description: 'Slow change over months or years for one organism and drug, per ward.',
  builder: (context, params, slot) =>
      ResistanceTrend(query: SeriesQuery.fromJson(params), slot: slot),
);

/// Connected trend: loads `/v1/susceptibility/series` and draws one line per ward plus the
/// hospital reference.
class ResistanceTrend extends StatelessWidget {
  const ResistanceTrend({super.key, required this.query, this.slot = WidgetSlot.page});

  final SeriesQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<SeriesQuery, Series>(
    query: query,
    fetch: (repo, q) => repo.series(q),
    builder: (context, s) => ResistanceTrendView(
      organism: s.organism,
      drug: s.drug,
      place: _place(query),
      lines: linesFromSeries(s, query),
      slot: slot,
    ),
  );
}

String _place(SeriesQuery q) {
  final wards = {...q.wards, ?q.filters.ward}.toList();
  if (wards.isEmpty) return 'Whole hospital';
  return wards.map((w) => w.short).join(' and ');
}

/// One line of a trend: a label and its weekly points.
class TrendLine {
  const TrendLine(this.label, this.points, {this.reference = false});

  final String label;
  final List<WeeklyPoint> points;

  /// The quiet 12-month hospital line, drawn dashed.
  final bool reference;
}

/// Lines from a `/v1/susceptibility/series` response: the asked wards first, then the hospital.
List<TrendLine> linesFromSeries(Series s, SeriesQuery q) {
  final wards = {...q.wards, ?q.filters.ward}.toList();
  return [
    for (final w in wards)
      if (s.series[w.code] case final pts?) TrendLine(w.short, pts),
    if (s.series['hospital'] case final pts?)
      TrendLine('Hospital', pts, reference: wards.isNotEmpty),
  ];
}

/// Weekly points thinned to one per month (the last week of each month) when a line covers
/// more than 16 weeks. Each weekly point is already a rolling estimate over the trailing window,
/// so the month's last point is that month's figure; nothing is averaged.
List<WeeklyPoint> monthlyPoints(List<WeeklyPoint> pts) {
  if (pts.length <= 16) return pts;
  final byMonth = <int, WeeklyPoint>{};
  for (final p in pts) {
    byMonth[p.weekStart.year * 12 + p.weekStart.month] = p;
  }
  return byMonth.values.toList();
}

final _mon = DateFormat('MMM');
final _monYear = DateFormat('MMM y');

/// What a set of trend lines covers, for captions and notes.
class TrendSpan {
  TrendSpan._(this.first, this.last, this.monthly, this.smallSample);

  factory TrendSpan.of(List<TrendLine> lines) {
    final points = [for (final l in lines) ...l.points];
    final dates = points.map((p) => p.weekStart);
    return TrendSpan._(
      dates.reduce((a, b) => a.isBefore(b) ? a : b),
      dates.reduce((a, b) => a.isAfter(b) ? a : b),
      lines.any((l) => monthlyPoints(l.points).length != l.points.length),
      lines.isNotEmpty && lines.first.points.any((p) => p.n < minIsolates),
    );
  }

  final DateTime first;
  final DateTime last;
  final bool monthly;

  /// The main line has points under 30 isolates.
  final bool smallSample;

  bool get oneYear => first.year == last.year;
  String get unit => monthly ? 'month' : 'week';

  /// "Jan–Sep 2026" or "Oct 2023 – Sep 2026".
  String get period => oneYear
      ? '${_mon.format(first)}–${_mon.format(last)} ${last.year}'
      : '${_monYear.format(first)} – ${_monYear.format(last)}';
}

/// The chart part of a trend: lines (main one with its range band, hospital dashed), the peak
/// marked when it stands out, and month labels.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.lines,
    this.height = 180,
    this.labels = 5,
    this.yAxis = true,
    this.band = true,
  });

  final List<TrendLine> lines;

  /// Shade the main line's range; off when several groups share the chart.
  final bool band;
  final double height;
  final int labels;
  final bool yAxis;

  @override
  Widget build(BuildContext context) {
    final shown = [for (final l in lines) (l, monthlyPoints(l.points))];
    final span = TrendSpan.of(lines);
    // Groups take ink, then violet (dashed, as the design's second line), then magenta; the
    // hospital reference is a quiet dashed periwinkle.
    final series = <ChartSeries>[];
    var group = 0;
    for (final (line, pts) in shown) {
      final i = line.reference ? -1 : group++;
      series.add(
        ChartSeries(
          label: line.label,
          color: i < 0 ? AmrColors.periwinkle : chartPalette[i % 3],
          dashed: i != 0,
          band: band && i == 0,
          points: [
            for (final p in pts) ChartPoint(p.weekStart, p.shrunkRate, low: p.low, high: p.high),
          ],
        ),
      );
    }
    final primary = shown.first.$2;
    final marks = <ChartMark>[];
    if (primary.length >= 3) {
      final sorted = [...primary.map((p) => p.shrunkRate)]..sort();
      final median = sorted[sorted.length ~/ 2];
      final peak = primary.reduce((a, b) => a.shrunkRate >= b.shrunkRate ? a : b);
      if (peak.shrunkRate - median >= 0.05 && peak.n > 0) {
        marks.add(
          ChartMark(
            peak.weekStart,
            peak.shrunkRate,
            '${DateFormat('MMMM').format(peak.weekStart)} · ${peak.r} of ${peak.n}',
          ),
        );
      }
    }
    return LineChart(
      series: series,
      marks: marks,
      height: height,
      xLabels: _xLabels(primary, span.oneYear),
      yAxis: yAxis,
    );
  }

  List<String> _xLabels(List<WeeklyPoint> pts, bool oneYear) {
    if (pts.length < 2) return const [];
    final n = labels.clamp(2, pts.length);
    final fmt = oneYear ? _mon : _monYear;
    return [
      for (var k = 0; k < n; k++)
        fmt.format(pts[((pts.length - 1) * k / (n - 1)).round()].weekStart),
    ];
  }
}

/// The trend card: Sora caption with the organism in italics, the chart, and what the line is.
class ResistanceTrendView extends StatelessWidget {
  const ResistanceTrendView({
    super.key,
    required this.organism,
    required this.drug,
    required this.lines,
    this.place = 'Whole hospital',
    this.slot = WidgetSlot.page,
  });

  final Organism organism;
  final Drug drug;
  final List<TrendLine> lines;
  final String place;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) {
    if (lines.every((l) => l.points.isEmpty)) {
      return const NoteCard(title: 'No isolates for this organism and drug in this period.');
    }
    final span = TrendSpan.of(lines);
    final note = span.smallSample
        ? 'Fewer than 30 isolates a ${span.unit}, so raw percentages are hidden and the line uses '
              'the shrunk estimate.'
        : 'Each point is the shrunk estimate over the trailing window; the band shows the range.';
    final card = slot == WidgetSlot.card;
    final captionSize = card ? 20.0 : (slot == WidgetSlot.chat ? 26.0 : 22.0);
    final year = span.oneYear && slot != WidgetSlot.chat ? ', ${span.last.year}' : '';
    final caption = Text.rich(
      TextSpan(
        style: AmrText.title(captionSize),
        children: [
          TextSpan(text: '$place · '),
          TextSpan(
            text: organism.short,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          TextSpan(text: ' · ${trendMetric(organism, drug)}$year'),
        ],
      ),
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!card) ...[
          caption,
          const SizedBox(height: 4),
          Text(
            '${span.period} · ${span.monthly ? 'monthly' : 'weekly'} · the band shows the range',
            style: AmrText.body(14),
          ),
          const SizedBox(height: 10),
        ],
        TrendChart(
          lines: lines,
          height: card ? 120 : (context.isCompact ? 150 : 180),
          labels: card ? 3 : 5,
          yAxis: !card,
        ),
        const SizedBox(height: 10),
        Text(note, style: AmrText.body(13, height: 1.45)),
      ],
    );
    if (card) return body;
    return AmrCard(
      tone: AmrCardTone.quiet,
      padding: EdgeInsets.all(slot == WidgetSlot.chat ? 26 : AmrSpace.x24),
      child: body,
    );
  }
}

/// "share that is MRSA" for S. aureus and the cefoxitin screen, else "ceftriaxone resistance".
String trendMetric(Organism organism, Drug drug) => organism == Organism.sAureus && drug == Drug.fox
    ? 'share that is MRSA'
    : '${drug.label.toLowerCase()} resistance';

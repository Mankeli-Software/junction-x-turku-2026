import 'package:flutter/material.dart';

import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/components/bar_chart.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final samplingVolumeEntry = CatalogEntry(
  name: 'SamplingVolume',
  title: 'Testing volume',
  description: 'Cultures per week or month, to tell a real rise apart from more testing.',
  builder: (context, params, slot) =>
      SamplingVolume(query: VolumeQuery.fromJson(params), slot: slot),
);

class SamplingVolume extends StatelessWidget {
  const SamplingVolume({super.key, required this.query, this.slot = WidgetSlot.page});

  final VolumeQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<VolumeQuery, Volume>(
    query: query,
    fetch: (repo, q) => repo.volume(q),
    loading: const AmrCard(tone: AmrCardTone.subtle, child: SkeletonBlock(lines: 3)),
    builder: (context, v) {
      // Several wards or specimens: add them up week by week.
      final byWeek = <DateTime, int>{};
      for (final row in v.rows) {
        for (final p in row.points) {
          byWeek[p.weekStart] = (byWeek[p.weekStart] ?? 0) + p.cultures;
        }
      }
      final weeks = byWeek.keys.toList()..sort();
      final specimens = v.rows.map((r) => r.specimen).toSet();
      return SamplingVolumeView(
        points: [for (final w in weeks) VolumePoint(weekStart: w, cultures: byWeek[w]!)],
        specimen: specimens.length == 1 ? specimens.first : query.specimen,
        compact: slot != WidgetSlot.page,
      );
    },
  );
}

/// One bar of the volume chart: a week or a month.
class VolumeBucket {
  const VolumeBucket(this.start, this.cultures);

  final DateTime start;
  final int cultures;
}

/// Weekly points as months when they span two months or more, else as weeks.
(List<VolumeBucket>, bool monthly) volumeBuckets(List<VolumePoint> points) {
  if (points.length < 8) {
    return ([for (final p in points) VolumeBucket(p.weekStart, p.cultures)], false);
  }
  final months = <DateTime, int>{};
  for (final p in points) {
    final m = DateTime.utc(p.weekStart.year, p.weekStart.month);
    months[m] = (months[m] ?? 0) + p.cultures;
  }
  final keys = months.keys.toList()..sort();
  return ([for (final k in keys) VolumeBucket(k, months[k]!)], true);
}

/// "About 98 → 131 a month (+34%)": the earlier average against the latest bar.
String volumeReading(List<VolumeBucket> buckets, {required bool monthly}) {
  if (buckets.isEmpty) return 'No cultures in this period.';
  final unit = monthly ? 'month' : 'week';
  final last = buckets.last.cultures;
  if (buckets.length == 1) return 'About $last a $unit.';
  final before = buckets.sublist(0, buckets.length - 1);
  final usual = before.fold<int>(0, (s, b) => s + b.cultures) / before.length;
  final change = usual == 0 ? 0 : ((last - usual) / usual * 100).round();
  final trend = change.abs() < 5 ? 'about the same' : '${change > 0 ? '+' : ''}$change%';
  return 'About ${usual.round()} → $last a $unit ($trend).';
}

/// "Urine cultures per month": lavender bars, the latest one navy, and the reading under it.
class SamplingVolumeView extends StatelessWidget {
  const SamplingVolumeView({
    super.key,
    required this.points,
    this.specimen,
    this.note,
    this.compact = false,
    this.showReading = true,
  });

  /// Weekly culture counts.
  final List<VolumePoint> points;
  final Specimen? specimen;

  /// Appended to the reading, e.g. "Cases tripled."
  final String? note;
  final bool compact;
  final bool showReading;

  @override
  Widget build(BuildContext context) {
    final (buckets, monthly) = volumeBuckets(points);
    final small = compact || context.isCompact;
    final what = specimen == null ? 'Cultures' : '${specimen!.label} cultures';
    return AmrCard(
      tone: AmrCardTone.subtle,
      padding: EdgeInsets.all(small ? 18 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$what per ${monthly ? 'month' : 'week'}',
            style: AmrText.body(14, weight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          if (buckets.isNotEmpty)
            BarChart(
              values: [for (final b in buckets) b.cultures.toDouble()],
              highlight: [for (var i = 0; i < buckets.length; i++) i == buckets.length - 1],
              color: AmrColors.lavender,
              highlightColor: AmrColors.ink,
              aspectRatio: 300 / 80,
              barFraction: 0.67,
              maxBarFraction: 0.725,
            ),
          if (showReading) ...[
            const SizedBox(height: 8),
            Text(
              [volumeReading(buckets, monthly: monthly), ?note].join(' '),
              style: AmrText.body(12),
            ),
          ],
        ],
      ),
    );
  }
}

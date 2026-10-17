import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models/alerts.dart';
import '../../core/query/query_view.dart';
import '../../ds/components/bar_chart.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final epiCurveEntry = CatalogEntry(
  name: 'EpiCurve',
  title: 'Cases per week',
  description: 'The epidemic curve behind an alert: new cases per week.',
  builder: (context, params, slot) =>
      EpiCurve(query: AlertDetailQuery.fromJson(params), slot: slot),
);

/// Month names under a time axis, at most [max] spread evenly ("Mar Apr May Jun").
List<String> monthLabels(List<DateTime> dates, {int max = 6}) {
  final months = <String>[];
  DateTime? last;
  for (final d in dates) {
    if (last == null || d.month != last.month || d.year != last.year) months.add(month(d));
    last = d;
  }
  if (months.length <= max) return months;
  final step = (months.length / max).ceil();
  return [for (var i = 0; i < months.length; i += step) months[i]];
}

class EpiCurve extends StatelessWidget {
  const EpiCurve({super.key, required this.query, this.slot = WidgetSlot.page});

  final AlertDetailQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<AlertDetailQuery, AlertDetail>(
    query: query,
    fetch: (repo, q) => repo.alertDetail(q),
    loading: const AmrCard(tone: AmrCardTone.subtle, child: SkeletonBlock(lines: 3)),
    builder: (context, d) => EpiCurveView(detail: d, compact: slot != WidgetSlot.page),
  );
}

/// "New ESBL cases per week": weekly bars, the raised weeks in pink.
class EpiCurveView extends StatelessWidget {
  const EpiCurveView({super.key, required this.detail, this.compact = false, this.caption});

  final AlertDetail detail;

  /// Phone and chat: tighter padding, 300×80 proportions, smaller labels.
  final bool compact;

  /// Defaults to "New ESBL cases per week" (the alert's phenotype).
  final String? caption;

  /// A week is raised when it has at least twice the usual count (and at least 2 cases).
  static bool raised(EpiPoint p) => p.cases >= 2 && p.cases >= 2 * p.expected;

  @override
  Widget build(BuildContext context) {
    final points = detail.epiCurve;
    final phenotype = detail.alert.phenotype?.code;
    final small = compact || context.isCompact;
    return AmrCard(
      tone: AmrCardTone.subtle,
      padding: EdgeInsets.all(small ? 18 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            caption ?? 'New ${phenotype == null ? '' : '$phenotype '}cases per week',
            style: AmrText.body(small ? 14 : 15, weight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          if (points.isEmpty)
            Text('No cases in this period.', style: AmrText.body(14))
          else
            BarChart(
              values: [for (final p in points) p.cases.toDouble()],
              highlight: [for (final p in points) raised(p)],
              aspectRatio: small ? 300 / 80 : 600 / 104,
              barFraction: small ? 0.74 : 0.7,
              maxBarFraction: small ? 0.75 : 0.86,
              radius: small ? 3 : 4,
              labels: monthLabels([for (final p in points) p.weekStart], max: small ? 4 : 6),
              labelSize: small ? 12 : 13,
            ),
        ],
      ),
    );
  }
}

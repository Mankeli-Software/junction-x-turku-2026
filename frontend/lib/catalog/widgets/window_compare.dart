import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models/common.dart';
import '../../core/models/data.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final windowCompareEntry = CatalogEntry(
  name: 'WindowCompare',
  title: '4 weeks vs 12 months',
  description: 'One drug against one organism: the last 4 weeks next to the last 12 months.',
  builder: (context, params, slot) =>
      WindowCompare(query: SusceptibilityQuery.fromJson(params), slot: slot),
);

/// Connected compare: loads `/v1/susceptibility` for one organism and drug.
class WindowCompare extends StatelessWidget {
  const WindowCompare({super.key, required this.query, this.slot = WidgetSlot.page});

  final SusceptibilityQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) {
    if (query.organism == null || query.drug == null) {
      return const NoteCard(title: 'Pick one organism and one antibiotic to compare.');
    }
    return QueryView<SusceptibilityQuery, Susceptibility>(
      query: query,
      fetch: (repo, q) => repo.susceptibility(q),
      builder: (context, s) => WindowCompareView(
        recent: _match(s.recent.rows),
        annual: _match(s.annual.rows),
        recentLabel: windowLabel(s.recent.window),
        title: _title(),
        slot: slot,
      ),
    );
  }

  /// The row for the asked organism, drug and ward; with no specimen filter the biggest one.
  SusceptibilityRow? _match(List<SusceptibilityRow> rows) => rows
      .where(
        (r) =>
            r.organism == query.organism &&
            r.drug == query.drug &&
            r.ward == query.ward &&
            (query.specimen == null || r.specimen == query.specimen),
      )
      .firstOrNull;

  String _title() => [
    query.organism!.short,
    query.drug!.label.toLowerCase(),
    query.ward?.label ?? 'Whole hospital',
  ].join(' · ');
}

/// "E. coli · ceftriaxone · Urology": resistance in the last 4 weeks next to 12 months.
class WindowCompareView extends StatelessWidget {
  const WindowCompareView({
    super.key,
    required this.recent,
    required this.annual,
    required this.title,
    this.recentLabel = 'last 4 weeks',
    this.slot = WidgetSlot.page,
  });

  final SusceptibilityRow? recent;
  final SusceptibilityRow? annual;
  final String title;
  final String recentLabel;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) {
    final r = recent?.resistance;
    final a = annual?.resistance;
    // Blush only when the recent range sits clearly above the 12-month range.
    final higher = r != null && a != null && r.low > a.high;
    final card = slot == WidgetSlot.card;
    final tiles = [
      _Tile(label: '${_cap(recentLabel)} · resistant', estimate: r, alert: higher, small: card),
      _Tile(label: 'Last 12 months · resistant', estimate: a, small: card),
    ];
    final note = recent?.note ?? annual?.note;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!card) ...[Text(title, style: AmrText.title(22)), const SizedBox(height: 14)],
        EqualRow(gap: card ? 10 : 16, children: tiles),
        if (note != null) ...[
          const SizedBox(height: 12),
          Text(note, style: AmrText.body(13, height: 1.45)),
        ],
      ],
    );
    if (card) return body;
    return AmrCard(
      tone: AmrCardTone.quiet,
      padding: const EdgeInsets.all(AmrSpace.x24),
      child: body,
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.estimate,
    this.alert = false,
    this.small = false,
  });

  final String label;
  final Estimate? estimate;
  final bool alert;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final e = estimate;
    return Container(
      padding: EdgeInsets.all(small ? 14 : 18),
      decoration: BoxDecoration(
        color: alert ? AmrColors.blush : AmrColors.lavenderSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AmrText.body(13)),
          const SizedBox(height: 6),
          Text(
            e == null ? '–' : estimateFigure(e),
            style: AmrText.sora(small ? 32 : 44, em: -0.03, height: 1.1),
          ),
          const SizedBox(height: 6),
          Text(
            e == null
                ? 'No isolates in this period'
                : e.smallSample
                ? 'few patients, range shown · ${patients(e.n)}'
                : 'range ${pctRange(e.low, e.high)} · ${patients(e.n)}',
            style: AmrText.body(12),
          ),
        ],
      ),
    );
  }
}

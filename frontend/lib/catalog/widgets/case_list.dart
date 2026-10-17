import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/models/alerts.dart';
import '../../core/models/common.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final caseListEntry = CatalogEntry(
  name: 'CaseList',
  title: 'Cases behind an alert',
  description: 'The isolates behind an alert, for lab staff. Dates and wards, no identifiers.',
  builder: (context, params, slot) =>
      CaseList(query: AlertDetailQuery.fromJson(params), slot: slot),
);

class CaseList extends StatelessWidget {
  const CaseList({super.key, required this.query, this.slot = WidgetSlot.page});

  final AlertDetailQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<AlertDetailQuery, AlertDetail>(
    query: query,
    fetch: (repo, q) => repo.alertDetail(q),
    loading: const AmrCard(tone: AmrCardTone.quiet, child: SkeletonBlock(lines: 4)),
    builder: (context, d) => CaseListView(cases: d.cases, alertId: d.alert.alertId),
  );
}

/// The cases as CSV, newest first.
String casesCsv(List<CaseRow> cases) => [
  'sample_date,ward,specimen,organism,phenotype',
  for (final c in cases)
    '${formatDate(c.sampleDate)},${c.ward.code},${c.specimen.code},${c.organism.code},'
        '${c.phenotype?.code ?? ''}',
].join('\n');

/// Cases newest first: date, ward, organism · specimen, phenotype. Shows [initial] rows,
/// then "Show all N"; "Export CSV" hands the CSV to [onExport] (default: the clipboard).
class CaseListView extends StatefulWidget {
  const CaseListView({
    super.key,
    required this.cases,
    this.alertId,
    this.initial = 6,
    this.onExport,
  });

  final List<CaseRow> cases;
  final String? alertId;
  final int initial;
  final void Function(String filename, String csv)? onExport;

  @override
  State<CaseListView> createState() => _CaseListViewState();
}

class _CaseListViewState extends State<CaseListView> {
  bool _all = false;

  List<CaseRow> get _sorted =>
      [...widget.cases]..sort((a, b) => b.sampleDate.compareTo(a.sampleDate));

  Future<void> _export() async {
    final name = 'cases_${widget.alertId ?? 'alert'}.csv';
    final csv = casesCsv(_sorted);
    if (widget.onExport != null) return widget.onExport!(name, csv);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: csv));
    messenger?.showSnackBar(SnackBar(content: Text('$name copied as CSV')));
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    final shown = _all ? sorted : sorted.take(widget.initial).toList();
    final compact = context.isCompact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AmrCard(
          tone: AmrCardTone.quiet,
          padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24, vertical: 8),
          child: AnimatedSize(
            duration: AmrMotion.base,
            curve: AmrMotion.curve,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sorted.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text('No cases in this period.', style: AmrText.body(14)),
                  )
                else if (!compact)
                  const _Header(),
                for (var i = 0; i < shown.length; i++)
                  compact ? _CaseCard(row: shown[i], first: i == 0) : _CaseRow(row: shown[i]),
              ],
            ),
          ),
        ),
        if (sorted.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (sorted.length > widget.initial)
                AmrButton(
                  label: _all ? 'Show fewer' : 'Show all ${sorted.length}',
                  size: AmrButtonSize.md,
                  fontSize: 14,
                  onPressed: () => setState(() => _all = !_all),
                ),
              AmrButton(
                label: 'Export CSV',
                size: AmrButtonSize.md,
                fontSize: 14,
                onPressed: _export,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

const _w = [120.0, 130.0, 160.0];

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final s = AmrText.label(13);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          SizedBox(
            width: _w[0],
            child: Text('Sampled', style: s),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _w[1],
            child: Text('Ward', style: s),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('Organism', style: s)),
          const SizedBox(width: 12),
          SizedBox(
            width: _w[2],
            child: Text('Type', style: s, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

Widget _organism(CaseRow c, {double size = 14}) => Text.rich(
  TextSpan(
    children: [
      TextSpan(
        text: c.organism.short,
        style: AmrText.inter(size, style: FontStyle.italic),
      ),
      TextSpan(text: ' · ${c.specimen.code}', style: AmrText.body(size)),
    ],
  ),
);

Widget _tags(CaseRow c) => c.phenotype == null
    ? const SizedBox.shrink()
    : AmrTag(c.phenotype!.code, color: AmrColors.blush);

class _CaseRow extends StatelessWidget {
  const _CaseRow({required this.row});

  final CaseRow row;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 46),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AmrColors.line)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: _w[0],
          child: Text(day(row.sampleDate), style: AmrText.body(14)),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: _w[1],
          child: Text(row.ward.short, style: AmrText.body(14)),
        ),
        const SizedBox(width: 12),
        Expanded(child: _organism(row)),
        const SizedBox(width: 12),
        SizedBox(
          width: _w[2],
          child: Align(alignment: Alignment.centerRight, child: _tags(row)),
        ),
      ],
    ),
  );
}

/// Phone: one card-like row per case.
class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.row, required this.first});

  final CaseRow row;
  final bool first;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: first ? null : const Border(top: BorderSide(color: AmrColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(day(row.sampleDate), style: AmrText.label(14))),
            _tags(row),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          children: [
            _organism(row),
            Text(' · ${row.ward.short}', style: AmrText.body(14)),
          ],
        ),
      ],
    ),
  );
}

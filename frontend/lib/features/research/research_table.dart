import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../catalog/widgets/export_ready.dart';
import '../../core/format.dart';
import '../../core/models/common.dart';
import '../../ds/ds.dart';
import 'research_data.dart';

final _count = NumberFormat('#,##0');

/// "15.8%": one decimal, as researchers read it.
String _pct1(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// The resistant cell: the raw share from 30 isolates up, the shrunk range below that.
String resistantText(ResearchCell c) {
  if (c.n == 0) return '–';
  if (c.rate != null) return _pct1(c.rate!);
  final e = c.estimate;
  return e == null ? 'n < 30' : pctRange(e.low, e.high);
}

/// Periods × groups: first isolates and the share resistant.
class ResearchTableView extends StatelessWidget {
  const ResearchTableView({super.key, required this.table});

  final ResearchTable table;

  @override
  Widget build(BuildContext context) =>
      context.isCompact ? _Cards(table: table) : _Grid(table: table);
}

class _Grid extends StatelessWidget {
  const _Grid({required this.table});

  final ResearchTable table;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final groups = table.groups;
    final cols = groups.length * 2;
    final minWidth = 180 + cols * 90 + cols * _gap;
    Widget row(List<Widget> cells, {bool header = false}) => Container(
      constraints: BoxConstraints(minHeight: header ? 0 : 52),
      padding: EdgeInsets.only(bottom: header ? 10 : 0),
      decoration: header
          ? null
          : const BoxDecoration(
              border: Border(top: BorderSide(color: AmrColors.ink)),
            ),
      child: Row(
        children: [
          Expanded(flex: 14, child: cells.first),
          for (final c in cells.skip(1)) ...[
            const SizedBox(width: _gap),
            Expanded(flex: 10, child: c),
          ],
        ],
      ),
    );
    final head = AmrText.label(13);
    final body = AmrText.body(16);
    final strong = AmrText.body(16, weight: FontWeight.w500);
    final single = groups.length == 1;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(header: true, [
          Text('Period', style: head),
          for (final g in groups) ...[
            Text(single ? 'Patients' : '${g.label} · n', style: head, textAlign: TextAlign.right),
            Text(
              single ? 'Resistant' : '${g.label} · resistant',
              style: head,
              textAlign: TextAlign.right,
            ),
          ],
        ]),
        for (var p = 0; p < table.periods.length; p++)
          row([
            Text(table.periods[p].label, style: body),
            for (final c in table.cells[p]) ...[
              Text(_count.format(c.n), style: body, textAlign: TextAlign.right),
              Text(resistantText(c), style: strong, textAlign: TextAlign.right),
            ],
          ]),
        const Divider(height: 1, thickness: 1, color: AmrColors.ink),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= minWidth) return content;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: math.max(minWidth, box.maxWidth), child: content),
        );
      },
    );
  }
}

/// Phone: one card per period.
class _Cards extends StatelessWidget {
  const _Cards({required this.table});

  final ResearchTable table;

  @override
  Widget build(BuildContext context) => ColumnGap(
    [
      for (var p = 0; p < table.periods.length; p++)
        AmrCard(
          tone: AmrCardTone.subtle,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: ColumnGap(
            [
              Text(table.periods[p].label, style: AmrText.label(15)),
              AutoGrid(
                minItemWidth: 130,
                gap: 8,
                stretch: false,
                children: [
                  for (var g = 0; g < table.groups.length; g++)
                    _CardCell(group: table.groups[g], cell: table.cells[p][g]),
                ],
              ),
            ],
            gap: AmrSpace.x8,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          ),
        ),
    ],
    gap: AmrSpace.x12,
    crossAxisAlignment: CrossAxisAlignment.stretch,
  );
}

class _CardCell extends StatelessWidget {
  const _CardCell({required this.group, required this.cell});

  final SplitGroup group;
  final ResearchCell cell;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: AmrText.body(14, height: 1.45),
      children: [
        TextSpan(text: '${group.label} · ${_count.format(cell.n)} patients\n'),
        TextSpan(
          text: resistantText(cell),
          style: AmrText.body(20, weight: FontWeight.w500),
        ),
        const TextSpan(text: ' resistant'),
      ],
    ),
  );
}

/// The table as a long CSV: one row per period and group.
CsvExport researchCsv(ResearchFilters f, ResearchTable t) {
  final organism = f.organism.short.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  final split = f.split == SplitBy.none ? '' : '_by_${f.split.name}';
  String share(double? v) => v == null ? '' : (v * 100).toStringAsFixed(1);
  return CsvExport(
    fileName: '${organism}_${f.drug.code.toLowerCase()}$split.csv',
    detail: t.periods.length == 1 ? 'first isolates only' : '${t.periods.length} periods',
    header: const [
      'period_from',
      'period_to',
      'group',
      'first_isolates',
      'resistant',
      'resistant_pct',
      'range_low_pct',
      'range_high_pct',
    ],
    rows: [
      for (var p = 0; p < t.periods.length; p++)
        for (var g = 0; g < t.groups.length; g++)
          [
            formatDate(t.periods[p].from),
            formatDate(t.periods[p].to),
            t.groups[g].label,
            t.cells[p][g].n,
            t.cells[p][g].r,
            share(t.cells[p][g].rate),
            share(t.cells[p][g].estimate?.low),
            share(t.cells[p][g].estimate?.high),
          ],
    ],
  );
}

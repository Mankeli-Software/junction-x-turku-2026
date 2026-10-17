import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models/common.dart';
import '../../core/models/data.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final coverageRankingEntry = CatalogEntry(
  name: 'CoverageRanking',
  title: 'Coverage',
  description:
      'Narrowest drug that covers 90% or more, then every drug with S / I / R and the 12-month '
      'level.',
  builder: (context, params, slot) => CoverageRanking(
    query: CoverageQuery.fromJson(params),
    filter: CoverageFilter.fromJson(params),
    slot: slot,
  ),
);

/// Display filters on top of the backend query ("Only oral options", "allergic to
/// penicillin"). Applied on the client to the same numbers; never sent to the backend.
class CoverageFilter {
  const CoverageFilter({this.oralOnly = false, this.exclude = const {}});

  factory CoverageFilter.fromJson(Json j) => CoverageFilter(
    oralOnly: j['oral_only'] == true,
    exclude: {for (final c in j['exclude'] as List? ?? const []) byCode(Drug.values, c as String)},
  );

  /// Penicillins in antibiotics.csv (class "penicillins" and "penicillins + BLI").
  static const penicillins = {Drug.amp, Drug.mec, Drug.tzp};

  final bool oralOnly;
  final Set<Drug> exclude;

  bool get isEmpty => !oralOnly && exclude.isEmpty;

  bool allows(RegimenCoverage o) =>
      o.regimen.every((d) => !exclude.contains(d) && (!oralOnly || d.oral));

  /// "penicillins", "non-oral drugs": what the filter hides, for titles.
  String get hiddenLabel => [
    if (exclude.containsAll(penicillins))
      'penicillins'
    else if (exclude.isNotEmpty)
      exclude.map((d) => d.label).join(', '),
    if (oralOnly) 'non-oral drugs',
  ].join(' and ');
}

/// Connected coverage widget: loads `/v1/coverage` and lays the views out for the [slot].
class CoverageRanking extends StatelessWidget {
  const CoverageRanking({
    super.key,
    required this.query,
    this.filter = const CoverageFilter(),
    this.slot = WidgetSlot.page,
  });

  final CoverageQuery query;
  final CoverageFilter filter;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) {
    return QueryView<CoverageQuery, Coverage>(
      query: query,
      fetch: (repo, q) => repo.coverage(q),
      builder: (context, c) {
        if (CoverageEmpty.applies(c)) return CoverageEmpty(coverage: c);
        if (!filter.isEmpty && slot != WidgetSlot.card) {
          return CoverageFilteredCard(coverage: c, filter: filter);
        }
        return switch (slot) {
          WidgetSlot.card => CoverageMiniList(coverage: c),
          WidgetSlot.chat => CoverageChatCard(coverage: c),
          WidgetSlot.page => ColumnGap(
            [NarrowestDrugHero(coverage: c), CoverageTable(coverage: c)],
            gap: AmrSpace.x32,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          ),
        };
      },
    );
  }
}

// View model ------------------------------------------------------------------

/// One drug (or pair) with its 4-week and 12-month coverage.
class CoverageLine {
  CoverageLine(this.recent, this.annual, {required this.narrowest});

  final RegimenCoverage recent;
  final RegimenCoverage? annual;
  final bool narrowest;

  /// The data has only S and R; I is carried as zero so the UI never changes when it arrives.
  double get s => recent.coverage.value;
  double get i => 0;
  double get r => (1 - s - i).clamp(0, 1);
  double? get year => annual?.coverage.value;

  /// Change from the 12-month level in points; null without a 12-month figure.
  int? get delta => year == null ? null : points(s, year!);
  bool get dropped => (delta ?? 0) <= -4;

  List<(String, Color)> get tags => [
    if (narrowest) ('Narrowest at 90%+', AmrColors.lavender),
    if (recent.regimen.any((d) => d.reserve)) ('Broad · keep in reserve', AmrColors.lavenderPale),
    if (recent.isSingle && recent.regimen.first.oral) ('Oral', AmrColors.lavenderPale),
    if (dropped) ('Lower than usual', AmrColors.blush),
  ];

  static List<CoverageLine> from(
    Coverage c, {
    bool singles = true,
    CoverageFilter filter = const CoverageFilter(),
  }) {
    final key = filter.isEmpty ? c.recent.narrowest?.key : null;
    return [
      for (final o in c.recent.options)
        if (o.isSingle == singles && filter.allows(o))
          CoverageLine(o, c.annual.byKey(o.key), narrowest: o.key == key),
    ];
  }

  /// The narrowest line at 90%+, else the best covering one.
  static CoverageLine? pick(Coverage c) {
    final lines = [...from(c), ...from(c, singles: false)];
    return lines.where((l) => l.narrowest).firstOrNull ??
        (lines..sort((a, b) => b.s.compareTo(a.s))).firstOrNull;
  }

  /// "▼ 12 pts" when clearly below the 12-month level, else "steady" (or nothing).
  String get deltaLabel => dropped ? '▼ ${-delta!} pts' : (delta == null ? '' : 'steady');
}

// Views -----------------------------------------------------------------------

/// Pneumonia, or no isolates at all: say so instead of showing empty bars.
class CoverageEmpty extends StatelessWidget {
  const CoverageEmpty({super.key, required this.coverage});

  final Coverage coverage;

  static bool applies(Coverage c) => c.recent.options.isEmpty;

  @override
  Widget build(BuildContext context) {
    final noData = coverage.note != null;
    return NoteCard(
      title: noData ? 'This infection is not in the data yet.' : 'No isolates match this patient.',
      body:
          coverage.note ??
          'There are no first isolates for this ward, sample and period. Try the last 12 months '
              'or the whole hospital.',
    );
  }
}

/// The lavender hero: the narrowest drug at 90% or more, its figure and the S / I / R bar.
class NarrowestDrugHero extends StatelessWidget {
  const NarrowestDrugHero({super.key, required this.coverage});

  final Coverage coverage;

  @override
  Widget build(BuildContext context) {
    final lines = [...CoverageLine.from(coverage), ...CoverageLine.from(coverage, singles: false)];
    final pick = lines.where((l) => l.narrowest).firstOrNull;
    final best = pick ?? (lines..sort((a, b) => b.s.compareTo(a.s))).first;
    final e = best.recent.coverage;
    final window = windowLabel(coverage.recent.window);
    return AmrCard(
      tone: AmrCardTone.accent,
      padding: EdgeInsets.all(fluid(context, 24, 3, 40)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pick != null ? 'Narrowest drug that covers 90% or more' : 'No drug reaches 90% here',
            style: AmrText.body(15, weight: FontWeight.w500),
          ),
          const SizedBox(height: 18),
          Text(
            pick != null ? best.recent.label : 'Best available: ${best.recent.label}',
            style: AmrText.headline(context),
          ),
          const SizedBox(height: 18),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 32,
            runSpacing: 12,
            children: [
              Text(estimateFigure(e), style: AmrText.metric(context)),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('likely to work', style: AmrText.body(16, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      e.smallSample
                          ? 'few patients, range shown · ${patients(e.n)}, $window'
                          : 'range ${pctRange(e.low, e.high)} · ${patients(e.n)}, $window',
                      style: AmrText.body(16),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _HeroBar(line: best),
        ],
      ),
    );
  }
}

class _HeroBar extends StatelessWidget {
  const _HeroBar({required this.line});

  final CoverageLine line;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AmrColors.white, borderRadius: AmrRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AmrSpace.x20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SirBar(
              s: line.s,
              i: line.i,
              r: line.r,
              height: 36,
              radius: 10,
              heroLabels: true,
              marker: line.year,
              markerCaption: line.year == null ? null : '12 months ${pct(line.year!)}',
            ),
            const SizedBox(height: 12),
            SirLegend(long: true, s: line.s, i: line.i, r: line.r),
          ],
        ),
      ),
    );
  }
}

/// "How sure is this?": sample size, prior weight and the 4-week vs 12-month gap, in words.
class CoverageConfidence extends StatelessWidget {
  const CoverageConfidence({super.key, required this.coverage});

  final Coverage coverage;

  @override
  Widget build(BuildContext context) {
    final lines = CoverageLine.from(coverage);
    final pick =
        [
          ...lines,
          ...CoverageLine.from(coverage, singles: false),
        ].where((l) => l.narrowest).firstOrNull ??
        lines.firstOrNull;
    final e = pick?.recent.coverage;
    final window = windowLabel(coverage.recent.window);
    final bullets = [
      'Based on ${patients(coverage.recent.nFirstIsolates)} in the $window',
      if (e != null) priorPhrase(e),
      if (e != null && e.smallSample) 'Fewer than 30 patients, so read the range, not the number',
      if (lines.any((l) => l.dropped)) 'Some drugs are lower now than over 12 months',
    ];
    return AmrCard(
      tone: AmrCardTone.quiet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How sure is this?', style: AmrText.label(16)),
          const SizedBox(height: 10),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 10, 0),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(color: AmrColors.ink, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(child: Text(b, style: AmrText.body(15, height: 1.4))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "All antibiotics": every drug with its bar, figure, S · I · R and the 12-month level.
class CoverageTable extends StatelessWidget {
  const CoverageTable({super.key, required this.coverage, this.showPairs = true});

  final Coverage coverage;
  final bool showPairs;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final singles = CoverageLine.from(coverage);
    final pairs = CoverageLine.from(coverage, singles: false).take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'All antibiotics',
          size: 34,
          gap: 4,
          subtitle:
              "EUCAST results for this patient's likely bacteria, "
              '${windowLabel(coverage.recent.window)}. Best first.',
          trailing: compact ? null : const SirLegend(withMarker: true),
        ),
        const SizedBox(height: 14),
        if (compact) ...[
          const SirLegend(withMarker: true),
          const SizedBox(height: 14),
          for (final l in singles) _DrugCard(line: l),
        ] else ...[
          const _HeaderRow(),
          for (final l in singles) _DrugRow(line: l),
          const Divider(height: 1, thickness: 1, color: AmrColors.ink),
        ],
        if (showPairs && pairs.isNotEmpty) ...[
          const SizedBox(height: 32),
          Text('Two-drug combinations', style: AmrText.title(26)),
          const SizedBox(height: 14),
          if (compact)
            for (final l in pairs) _DrugCard(line: l)
          else ...[
            for (final l in pairs) _DrugRow(line: l),
            const Divider(height: 1, thickness: 1, color: AmrColors.ink),
          ],
        ],
      ],
    );
  }
}

const _colGap = 20.0;

class _Cols extends StatelessWidget {
  const _Cols(this.cells);

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 12, child: cells[0]),
      const SizedBox(width: _colGap),
      Expanded(flex: 22, child: cells[1]),
      const SizedBox(width: _colGap),
      SizedBox(width: 110, child: cells[2]),
      const SizedBox(width: _colGap),
      SizedBox(width: 130, child: cells[3]),
      const SizedBox(width: _colGap),
      SizedBox(width: 90, child: cells[4]),
    ],
  );
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final s = AmrText.label(13);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Cols([
        Text('Antibiotic', style: s),
        Text('Susceptible · Increased exposure · Resistant', style: s),
        Text('Likely works', style: s, textAlign: TextAlign.right),
        Text('S · I · R', style: s, textAlign: TextAlign.right),
        Text('12 months', style: s, textAlign: TextAlign.right),
      ]),
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags(this.tags);

  final List<(String, Color)> tags;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 6, runSpacing: 6, children: [for (final (t, c) in tags) AmrTag(t, color: c)]);
}

String _sir(CoverageLine l) => '${pctNum(l.s)} · ${pctNum(l.i)} · ${pctNum(l.r)}';

class _DrugRow extends StatelessWidget {
  const _DrugRow({required this.line});

  final CoverageLine line;

  @override
  Widget build(BuildContext context) {
    final e = line.recent.coverage;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AmrColors.ink)),
      ),
      child: _Cols([
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(line.recent.label, style: AmrText.body(18, weight: FontWeight.w500)),
            if (line.tags.isNotEmpty) ...[const SizedBox(height: 6), _Tags(line.tags)],
          ],
        ),
        SirBar(s: line.s, i: line.i, r: line.r, marker: line.year),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              estimateFigure(e),
              style: AmrText.body(e.smallSample ? 18 : 24, weight: FontWeight.w500),
            ),
            Text(
              e.smallSample ? 'n = ${e.n}' : 'range ${pctRange(e.low, e.high)}',
              style: AmrText.body(12),
            ),
          ],
        ),
        Text(_sir(line), style: AmrText.body(15), textAlign: TextAlign.right),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(line.year == null ? '–' : pct(line.year!), style: AmrText.body(17)),
            Text(
              line.deltaLabel,
              style: AmrText.label(
                12,
              ).copyWith(color: line.dropped ? AmrColors.danger : AmrColors.ink),
            ),
          ],
        ),
      ]),
    );
  }
}

/// Phone layout: one card per drug.
class _DrugCard extends StatelessWidget {
  const _DrugCard({required this.line});

  final CoverageLine line;

  @override
  Widget build(BuildContext context) {
    final e = line.recent.coverage;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AmrColors.ink)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(line.recent.label, style: AmrText.body(17, weight: FontWeight.w500)),
              ),
              Text(estimateFigure(e), style: AmrText.body(22, weight: FontWeight.w500)),
            ],
          ),
          if (line.tags.isNotEmpty) ...[const SizedBox(height: 6), _Tags(line.tags)],
          const SizedBox(height: 10),
          SirBar(s: line.s, i: line.i, r: line.r, marker: line.year),
          const SizedBox(height: 8),
          Text(
            [
              'S · I · R ${_sir(line)}',
              if (line.year != null) '12 months ${pct(line.year!)} ${line.deltaLabel}',
              e.smallSample ? 'n = ${e.n}' : 'range ${pctRange(e.low, e.high)}',
            ].join('  ·  '),
            style: AmrText.body(12),
          ),
        ],
      ),
    );
  }
}

/// Pinned-card version: the top drugs as thin bars with their figure.
class CoverageMiniList extends StatelessWidget {
  const CoverageMiniList({super.key, required this.coverage, this.limit = 3});

  final Coverage coverage;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final lines = CoverageLine.from(coverage).take(limit);
    return ColumnGap([
      for (final l in lines)
        Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(
                l.recent.shortLabel,
                style: AmrText.body(14, weight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SirBar(s: l.s, i: l.i, r: l.r, height: 14, radius: 5),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 44,
              child: Text(pct(l.s), textAlign: TextAlign.right, style: AmrText.label(14)),
            ),
          ],
        ),
    ], crossAxisAlignment: CrossAxisAlignment.stretch);
  }
}

/// Chat version (Chat-doctor): the pick and its figure on one line, then a white list of every
/// drug with its bar, figure and change from the 12-month level.
class CoverageChatCard extends StatelessWidget {
  const CoverageChatCard({super.key, required this.coverage, this.limit = 6});

  final Coverage coverage;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final best = CoverageLine.pick(coverage)!;
    final e = best.recent.coverage;
    final lines = CoverageLine.from(coverage).take(limit);
    final caption = [
      'S navy · I lavender · R pink · line = 12-month level',
      '${patients(coverage.recent.nFirstIsolates)} in the ${windowLabel(coverage.recent.window)}',
      priorPhrase(e, own: "this ward's data").toLowerCase(),
    ].join(' · ');
    return AmrCard(
      tone: AmrCardTone.accent,
      padding: EdgeInsets.all(compact ? 18 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            best.narrowest ? 'Narrowest drug that covers 90% or more' : 'No drug reaches 90% here',
            style: AmrText.body(compact ? 12 : 14, weight: FontWeight.w500),
          ),
          SizedBox(height: compact ? 12 : 16),
          Wrap(
            spacing: 28,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                best.recent.label,
                style: AmrText.sora(compact ? 26 : 40, em: -0.03, height: 1.1),
              ),
              Text(
                estimateFigure(e),
                style: AmrText.sora(compact ? 56 : 64, em: -0.045, height: 1),
              ),
            ],
          ),
          SizedBox(height: compact ? 12 : 16),
          Container(
            padding: EdgeInsets.all(compact ? 12 : 18),
            decoration: BoxDecoration(
              color: AmrColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ColumnGap(
              [for (final l in lines) _ChatRow(line: l, compact: compact)],
              gap: compact ? 0 : 10,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(caption, style: AmrText.body(compact ? 11 : 13)),
        ],
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.line, required this.compact, this.tag});

  final CoverageLine line;
  final bool compact;

  /// Replaces the change column with a tag ("Oral · narrow"), as in the filtered list.
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final bar = SirBar(
      s: line.s,
      i: line.i,
      r: line.r,
      height: compact ? 12 : 18,
      radius: compact ? 4 : 6,
      marker: tag == null ? line.year : null,
    );
    final figure = Text(pct(line.s), style: AmrText.label(compact ? 14 : 15));
    final delta = Text(
      compact ? (line.dropped ? '▼ ${-line.delta!}' : '') : line.deltaLabel,
      textAlign: TextAlign.right,
      style: AmrText.label(
        compact ? 11 : 12,
      ).copyWith(color: line.dropped ? AmrColors.danger : AmrColors.ink),
    );
    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0EFF8))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: line.recent.shortLabel,
                          style: AmrText.body(14, weight: FontWeight.w500),
                        ),
                        if (tag?.isNotEmpty ?? false)
                          TextSpan(text: ' · $tag', style: AmrText.body(11)),
                      ],
                    ),
                  ),
                ),
                figure,
                if (tag == null) ...[const SizedBox(width: 4), delta],
              ],
            ),
            const SizedBox(height: 5),
            bar,
          ],
        ),
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 200,
          child: Text(line.recent.label, style: AmrText.body(15, weight: FontWeight.w500)),
        ),
        const SizedBox(width: 14),
        Expanded(child: bar),
        const SizedBox(width: 14),
        SizedBox(
          width: 60,
          child: Align(alignment: Alignment.centerRight, child: figure),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: tag == null ? 90 : 170,
          child: tag == null
              ? delta
              : (tag!.isEmpty
                    ? const SizedBox()
                    : Align(alignment: Alignment.centerLeft, child: AmrTag(tag!))),
        ),
      ],
    );
  }
}

/// The same patient with drugs hidden ("She is allergic to penicillin", "Only oral options").
class CoverageFilteredCard extends StatelessWidget {
  const CoverageFilteredCard({super.key, required this.coverage, required this.filter});

  final Coverage coverage;
  final CoverageFilter filter;

  static String _tag(Drug d) =>
      [if (d.reserve) 'Broad · keep in reserve', if (d.oral) 'Oral'].join(' · ');

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final lines = CoverageLine.from(coverage, filter: filter).take(6).toList();
    final covers = lines.where((l) => l.recent.coversTarget).firstOrNull;
    final hidden = filter.hiddenLabel;
    final title = covers != null
        ? 'Without $hidden, ${covers.recent.label} still covers 90% or more'
        : 'Without $hidden, no drug reaches 90% here';
    return AmrCard(
      tone: AmrCardTone.quiet,
      padding: EdgeInsets.all(compact ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AmrText.sora(compact ? 19 : 24, em: -0.015, height: 1.25)),
          SizedBox(height: compact ? 6 : 12),
          if (lines.isEmpty)
            Text('No drug in the data fits this filter.', style: AmrText.body(15))
          else
            ColumnGap(
              [
                for (final l in lines)
                  _ChatRow(
                    line: l,
                    compact: compact,
                    tag: l.recent.isSingle ? _tag(l.recent.regimen.first) : 'Combination',
                  ),
              ],
              gap: compact ? 0 : 12,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            ),
          SizedBox(height: compact ? 6 : 12),
          Text(
            filter.exclude.isNotEmpty
                ? "Check the type of allergy against your hospital's guideline. This is local "
                      'coverage data, not a prescription.'
                : 'Local coverage data, not a prescription.',
            style: AmrText.body(compact ? 12 : 13),
          ),
        ],
      ),
    );
  }
}

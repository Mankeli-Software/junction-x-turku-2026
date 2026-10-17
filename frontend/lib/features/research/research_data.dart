import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../catalog/widgets/resistance_trend.dart';
import '../../core/models/common.dart';
import '../../core/models/data.dart';
import '../../core/models/vocab.dart';
import '../../core/repository.dart';

enum ResearchPeriod {
  year('Last 12 months', 365),
  twoYears('Last 2 years', 730),
  all('All data', null);

  const ResearchPeriod(this.label, this.days);

  final String label;
  final int? days;

  /// First day of the period for a replay date, never before the data starts.
  DateTime start(DateTime asOf) {
    if (days == null) return dataStart;
    final d = asOf.subtract(Duration(days: days! - 1));
    return d.isBefore(dataStart) ? dataStart : d;
  }
}

enum SplitBy {
  none('No split'),
  sex('Sex'),
  age('Age group'),
  onset('Onset');

  const SplitBy(this.label);

  final String label;
}

/// Everything the Explore filters panel sets.
class ResearchFilters extends Equatable {
  const ResearchFilters({
    this.period = ResearchPeriod.all,
    this.ward,
    this.specimen = Specimen.urine,
    this.organism = Organism.eColi,
    this.drug = Drug.tmp,
    this.split = SplitBy.sex,
    this.ageBand,
    this.onset,
  });

  final ResearchPeriod period;
  final Ward? ward;
  final Specimen? specimen;
  final Organism organism;
  final Drug drug;
  final SplitBy split;
  final AgeBand? ageBand;
  final Onset? onset;

  ResearchFilters copyWith({
    ResearchPeriod? period,
    Ward? Function()? ward,
    Specimen? Function()? specimen,
    Organism? organism,
    Drug? drug,
    SplitBy? split,
    AgeBand? Function()? ageBand,
    Onset? Function()? onset,
  }) => ResearchFilters(
    period: period ?? this.period,
    ward: ward != null ? ward() : this.ward,
    specimen: specimen != null ? specimen() : this.specimen,
    organism: organism ?? this.organism,
    drug: drug ?? this.drug,
    split: split ?? this.split,
    ageBand: ageBand != null ? ageBand() : this.ageBand,
    onset: onset != null ? onset() : this.onset,
  );

  /// The query for one period and group; [group] overrides the age, sex or onset filter.
  SusceptibilityQuery query(DateTime asOf, DateTime from, DateTime to, [SplitGroup? group]) =>
      SusceptibilityQuery(
        window: WindowSpec(asOf: asOf, window: TimeWindow.custom, dateFrom: from, dateTo: to),
        ward: ward,
        specimen: specimen,
        organism: organism,
        drug: drug,
        sex: group?.sex,
        ageBand: group?.ageBand ?? ageBand,
        onset: group?.onset ?? onset,
      );

  /// Filters from a URL or a pinned trend's params; anything missing or unknown keeps its
  /// default, and an empty map gives the defaults.
  static ResearchFilters? fromParams(Map<String, Object?> p) {
    if (p.isEmpty) return null;
    const d = ResearchFilters();
    return ResearchFilters(
      ward: byCodeOrNull(Ward.values, p['ward']),
      // A trend saved with all samples has no specimen key.
      specimen: p.containsKey('organism')
          ? byCodeOrNull(Specimen.values, p['specimen'])
          : d.specimen,
      organism: byCodeOrNull(Organism.values, p['organism']) ?? d.organism,
      drug: byCodeOrNull(Drug.values, p['drug']) ?? d.drug,
      ageBand: byCodeOrNull(AgeBand.values, p['age_band']),
      onset: byCodeOrNull(Onset.values, p['onset']),
    );
  }

  /// Saved to the home dashboard as a `ResistanceTrend`; no dates, so it always shows the latest.
  Json get trendParams => {
    'organism': organism.code,
    'drug': drug.code,
    'ward': ?ward?.code,
    'specimen': ?specimen?.code,
    'age_band': ?ageBand?.code,
    'onset': ?onset?.code,
  };

  @override
  List<Object?> get props => [period, ward, specimen, organism, drug, split, ageBand, onset];
}

/// One column group of the table and one line of the chart.
class SplitGroup extends Equatable {
  const SplitGroup(this.label, {this.sex, this.ageBand, this.onset});

  final String label;
  final Sex? sex;
  final AgeBand? ageBand;
  final Onset? onset;

  static List<SplitGroup> of(ResearchFilters f) => switch (f.split) {
    SplitBy.none => const [SplitGroup('All')],
    SplitBy.sex => const [SplitGroup('Women', sex: Sex.female), SplitGroup('Men', sex: Sex.male)],
    SplitBy.age => [for (final a in AgeBand.values) SplitGroup(a.short, ageBand: a)],
    SplitBy.onset => const [
      SplitGroup('Home', onset: Onset.community),
      SplitGroup('Hospital', onset: Onset.hospital),
    ],
  };

  @override
  List<Object?> get props => [label, sex, ageBand, onset];
}

final _monYear = DateFormat('MMM y');

/// A table period: twelve months counted back from the replay date.
class PeriodSpan extends Equatable {
  const PeriodSpan(this.from, this.to);

  final DateTime from;
  final DateTime to;

  /// "Oct 2023 – Sep 2024".
  String get label => '${_monYear.format(from)} – ${_monYear.format(to)}';

  /// Twelve-month blocks ending on [asOf], oldest first; a sliver under 60 days joins the next.
  static List<PeriodSpan> of(ResearchFilters f, DateTime asOf) {
    final start = f.period.start(asOf);
    final spans = <PeriodSpan>[];
    var to = asOf;
    while (!to.isBefore(start)) {
      var from = to.subtract(const Duration(days: 364));
      if (from.isBefore(start)) from = start;
      spans.insert(0, PeriodSpan(from, to));
      to = from.subtract(const Duration(days: 1));
    }
    if (spans.length > 1 && spans.first.to.difference(spans.first.from).inDays < 60) {
      final merged = PeriodSpan(spans.first.from, spans[1].to);
      spans
        ..removeRange(0, 2)
        ..insert(0, merged);
    }
    return spans;
  }

  @override
  List<Object?> get props => [from, to];
}

/// One table cell: first isolates and resistant ones, with the shrunk estimate when there is a
/// single matching row.
class ResearchCell {
  const ResearchCell({required this.n, required this.r, this.estimate});

  final int n;
  final int r;
  final Estimate? estimate;

  /// Raw share, only from 30 first isolates up; below that the range is shown instead.
  double? get rate => n >= minIsolates && n > 0 ? r / n : null;
}

class ResearchTable {
  const ResearchTable({required this.periods, required this.groups, required this.cells});

  final List<PeriodSpan> periods;
  final List<SplitGroup> groups;

  /// `cells[period][group]`.
  final List<List<ResearchCell>> cells;
}

/// The table and the chart load through [QueryView], so they are queries too: the filters plus
/// the replay date.
class ResearchQuery extends Equatable implements AsOfQuery<ResearchQuery> {
  const ResearchQuery(this.filters, {this.asOf});

  final ResearchFilters filters;
  final DateTime? asOf;

  @override
  ResearchQuery resolve(DateTime sessionAsOf) => ResearchQuery(filters, asOf: asOf ?? sessionAsOf);

  @override
  Json toQuery() => filters
      .query(asOf ?? dataEnd, filters.period.start(asOf ?? dataEnd), asOf ?? dataEnd)
      .toQuery();

  @override
  List<Object?> get props => [filters, asOf];
}

/// Rows for the asked organism and drug; without a specimen filter, every specimen's row.
List<SusceptibilityRow> _matching(List<SusceptibilityRow> rows, ResearchFilters f) => rows
    .where(
      (r) =>
          r.organism == f.organism &&
          r.drug == f.drug &&
          r.ward == f.ward &&
          (f.specimen == null || r.specimen == f.specimen),
    )
    .toList();

Future<ResearchTable> fetchResearchTable(AmrRepository repo, ResearchQuery q) async {
  final f = q.filters;
  final asOf = q.asOf ?? dataEnd;
  final periods = PeriodSpan.of(f, asOf);
  final groups = SplitGroup.of(f);
  final cells = await Future.wait([
    for (final p in periods)
      Future.wait([
        for (final g in groups)
          repo.susceptibility(f.query(asOf, p.from, p.to, g)).then((s) {
            final rows = _matching(s.recent.rows, f);
            return ResearchCell(
              n: rows.fold(0, (a, r) => a + r.counts.total),
              r: rows.fold(0, (a, r) => a + r.counts.r),
              estimate: rows.length == 1 ? rows.single.resistance : null,
            );
          }),
      ]),
  ]);
  return ResearchTable(periods: periods, groups: groups, cells: cells);
}

/// One line per group over the whole period, as 12-month rolling estimates: the ward's line
/// when a ward is chosen, else the hospital line (which the backend computes over 12 months).
Future<List<TrendLine>> fetchResearchLines(AmrRepository repo, ResearchQuery q) async {
  final f = q.filters;
  final asOf = q.asOf ?? dataEnd;
  final groups = SplitGroup.of(f);
  final series = await Future.wait([
    for (final g in groups)
      repo.series(
        SeriesQuery(
          organism: f.organism,
          drug: f.drug,
          wards: [?f.ward],
          filters: SusceptibilityQuery(
            window: WindowSpec(
              asOf: asOf,
              window: TimeWindow.d365,
              dateFrom: f.period.start(asOf),
              dateTo: asOf,
            ),
            specimen: f.specimen,
            sex: g.sex,
            ageBand: g.ageBand ?? f.ageBand,
            onset: g.onset ?? f.onset,
          ),
        ),
      ),
  ]);
  return [
    for (var i = 0; i < groups.length; i++)
      TrendLine(groups[i].label, series[i].series[f.ward?.code ?? 'hospital'] ?? const []),
  ];
}

/// "Rising about 2.4 points a year in women and 1.6 in men." from a least-squares slope.
String trendSentence(List<TrendLine> lines) {
  final slopes = <(String, double)>[];
  for (final l in lines) {
    final pts = monthlyPoints(l.points);
    if (pts.length < 3) continue;
    final t0 = pts.first.weekStart;
    final xs = [for (final p in pts) p.weekStart.difference(t0).inDays / 365.25];
    final ys = [for (final p in pts) p.shrunkRate * 100];
    final mx = xs.reduce((a, b) => a + b) / xs.length;
    final my = ys.reduce((a, b) => a + b) / ys.length;
    var num = 0.0, den = 0.0;
    for (var i = 0; i < xs.length; i++) {
      num += (xs[i] - mx) * (ys[i] - my);
      den += math.pow(xs[i] - mx, 2);
    }
    if (den > 0) slopes.add((l.label, num / den));
  }
  if (slopes.isEmpty) return '';
  if (slopes.every((s) => s.$2.abs() < 0.5)) return 'Flat: under half a point a year.';
  String pts(double v) => v.abs().toStringAsFixed(1);
  if (slopes.length == 1) {
    final s = slopes.single.$2;
    return '${s >= 0 ? 'Rising' : 'Falling'} about ${pts(s)} points a year.';
  }
  final first = slopes.first;
  final rest = slopes.skip(1).map((s) {
    final dir = (s.$2 >= 0) == (first.$2 >= 0) ? '' : (s.$2 >= 0 ? 'rising ' : 'falling ');
    return '$dir${pts(s.$2)} in ${s.$1.toLowerCase()}';
  });
  return '${first.$2 >= 0 ? 'Rising' : 'Falling'} about ${pts(first.$2)} points a year in '
      '${first.$1.toLowerCase()} and ${rest.join(' and ')}.';
}

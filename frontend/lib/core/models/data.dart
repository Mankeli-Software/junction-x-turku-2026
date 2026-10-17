import 'package:equatable/equatable.dart';

import 'common.dart';
import 'vocab.dart';

/// A query the session can stamp with its replay date before it is sent.
abstract interface class AsOfQuery<Q> {
  Q resolve(DateTime sessionAsOf);
  Json toQuery();
}

// Organisms -----------------------------------------------------------------

class OrganismMixQuery extends Equatable implements AsOfQuery<OrganismMixQuery> {
  const OrganismMixQuery({this.profile = const PatientProfile(), this.window = const WindowSpec()});

  factory OrganismMixQuery.fromJson(Json j) =>
      OrganismMixQuery(profile: PatientProfile.fromJson(j), window: WindowSpec.fromJson(j));

  final PatientProfile profile;
  final WindowSpec window;

  @override
  OrganismMixQuery resolve(DateTime asOf) =>
      OrganismMixQuery(profile: profile, window: window.resolve(asOf));

  @override
  Json toQuery() => {...window.toQuery(), ...profile.toQuery()};

  @override
  List<Object?> get props => [profile, window];
}

class OrganismShare extends Equatable {
  const OrganismShare({required this.organism, required this.share, required this.n});

  factory OrganismShare.fromJson(Json j) => OrganismShare(
    organism: byCode(Organism.values, j['organism']! as String),
    share: toDouble(j['share']),
    n: toInt(j['n']),
  );

  final Organism organism;

  /// WISCA weight, 0–1.
  final double share;
  final int n;

  @override
  List<Object?> get props => [organism, share, n];
}

class OrganismMix extends Equatable {
  const OrganismMix({
    required this.window,
    required this.ward,
    required this.specimen,
    required this.nFirstIsolates,
    required this.organisms,
    this.note,
  });

  factory OrganismMix.fromJson(Json j) => OrganismMix(
    window: WindowOut.fromJson(j['window']! as Json),
    ward: byCodeOrNull(Ward.values, j['ward']),
    specimen: byCodeOrNull(Specimen.values, j['specimen']),
    nFirstIsolates: toInt(j['n_first_isolates']),
    note: j['note'] as String?,
    organisms: jsonList(j['organisms']).map(OrganismShare.fromJson).toList(),
  );

  final WindowOut window;
  final Ward? ward;
  final Specimen? specimen;
  final int nFirstIsolates;
  final String? note;
  final List<OrganismShare> organisms;

  @override
  List<Object?> get props => [window, ward, specimen, nFirstIsolates, note, organisms];
}

// Coverage ------------------------------------------------------------------

class CoverageQuery extends Equatable implements AsOfQuery<CoverageQuery> {
  const CoverageQuery({
    this.profile = const PatientProfile(),
    this.window = const WindowSpec(),
    this.maxRegimenSize = 2,
  });

  factory CoverageQuery.fromJson(Json j) => CoverageQuery(
    profile: PatientProfile.fromJson(j),
    window: WindowSpec.fromJson(j),
    maxRegimenSize: (j['max_regimen_size'] as num?)?.toInt() ?? 2,
  );

  final PatientProfile profile;
  final WindowSpec window;
  final int maxRegimenSize;

  @override
  CoverageQuery resolve(DateTime asOf) =>
      CoverageQuery(profile: profile, window: window.resolve(asOf), maxRegimenSize: maxRegimenSize);

  @override
  Json toQuery() => {
    ...window.toQuery(),
    ...profile.toQuery(),
    'max_regimen_size': '$maxRegimenSize',
  };

  @override
  List<Object?> get props => [profile, window, maxRegimenSize];
}

class RegimenCoverage extends Equatable {
  const RegimenCoverage({
    required this.regimen,
    required this.coverage,
    required this.coversTarget,
  });

  factory RegimenCoverage.fromJson(Json j) => RegimenCoverage(
    regimen: [for (final c in j['regimen']! as List) byCode(Drug.values, c as String)],
    coverage: Estimate.fromJson(j['coverage']! as Json),
    coversTarget: j['covers_target'] == true,
  );

  final List<Drug> regimen;
  final Estimate coverage;

  /// The lower bound of coverage is at least 0.90.
  final bool coversTarget;

  bool get isSingle => regimen.length == 1;
  String get key => regimen.map((d) => d.code).join('+');
  String get label => regimen.map((d) => d.label).join(' + ');
  String get shortLabel => regimen.map((d) => d.short).join(' + ');

  @override
  List<Object?> get props => [regimen, coverage, coversTarget];
}

class CoverageWindowSet extends Equatable {
  const CoverageWindowSet({
    required this.window,
    required this.nFirstIsolates,
    required this.options,
    required this.narrowestEffective,
  });

  factory CoverageWindowSet.fromJson(Json j) => CoverageWindowSet(
    window: WindowOut.fromJson(j['window']! as Json),
    nFirstIsolates: toInt(j['n_first_isolates']),
    options: jsonList(j['options']).map(RegimenCoverage.fromJson).toList(),
    narrowestEffective: (j['narrowest_effective'] as List?)
        ?.map((c) => byCode(Drug.values, c as String))
        .toList(),
  );

  final WindowOut window;
  final int nFirstIsolates;
  final List<RegimenCoverage> options;
  final List<Drug>? narrowestEffective;

  RegimenCoverage? byKey(String key) => options.where((o) => o.key == key).firstOrNull;

  RegimenCoverage? get narrowest {
    final n = narrowestEffective;
    return n == null ? null : byKey(n.map((d) => d.code).join('+'));
  }

  @override
  List<Object?> get props => [window, nFirstIsolates, options, narrowestEffective];
}

/// "In short" for a results page (`GET /v1/agent/in-short`): the one line the AI writes from the
/// page's own numbers, checked on the server. Null text: no checked line came back.
class InShort extends Equatable {
  const InShort({this.text, this.builtFrom = const []});

  factory InShort.fromJson(Json j) => InShort(
    text: j['text'] as String?,
    builtFrom: (j['built_from'] as List? ?? const []).cast<String>(),
  );

  final String? text;
  final List<String> builtFrom;

  @override
  List<Object?> get props => [text, builtFrom];
}

class Coverage extends Equatable {
  const Coverage({
    required this.ward,
    required this.specimen,
    required this.recent,
    required this.annual,
    this.note,
  });

  factory Coverage.fromJson(Json j) => Coverage(
    ward: byCodeOrNull(Ward.values, j['ward']),
    specimen: byCodeOrNull(Specimen.values, j['specimen']),
    note: j['note'] as String?,
    recent: CoverageWindowSet.fromJson(j['recent']! as Json),
    annual: CoverageWindowSet.fromJson(j['annual']! as Json),
  );

  final Ward? ward;
  final Specimen? specimen;
  final String? note;

  /// The requested window, e.g. 28d.
  final CoverageWindowSet recent;

  /// The last 365 days for comparison.
  final CoverageWindowSet annual;

  @override
  List<Object?> get props => [ward, specimen, note, recent, annual];
}

// Susceptibility ------------------------------------------------------------

class SusceptibilityQuery extends Equatable implements AsOfQuery<SusceptibilityQuery> {
  const SusceptibilityQuery({
    this.window = const WindowSpec(),
    this.ward,
    this.specimen,
    this.organism,
    this.drug,
    this.sex,
    this.ageBand,
    this.onset,
  });

  factory SusceptibilityQuery.fromJson(Json j) => SusceptibilityQuery(
    window: WindowSpec.fromJson(j),
    ward: byCodeOrNull(Ward.values, j['ward']),
    specimen: byCodeOrNull(Specimen.values, j['specimen']),
    organism: byCodeOrNull(Organism.values, j['organism']),
    drug: byCodeOrNull(Drug.values, j['drug']),
    sex: byCodeOrNull(Sex.values, j['sex']),
    ageBand: byCodeOrNull(AgeBand.values, j['age_band']),
    onset: byCodeOrNull(Onset.values, j['onset']),
  );

  final WindowSpec window;
  final Ward? ward;
  final Specimen? specimen;
  final Organism? organism;
  final Drug? drug;
  final Sex? sex;
  final AgeBand? ageBand;
  final Onset? onset;

  @override
  SusceptibilityQuery resolve(DateTime asOf) => SusceptibilityQuery(
    window: window.resolve(asOf),
    ward: ward,
    specimen: specimen,
    organism: organism,
    drug: drug,
    sex: sex,
    ageBand: ageBand,
    onset: onset,
  );

  @override
  Json toQuery() => {
    ...window.toQuery(),
    ...query({
      'ward': ward,
      'specimen': specimen,
      'organism': organism,
      'drug': drug,
      'sex': sex,
      'age_band': ageBand,
      'onset': onset,
    }),
  };

  @override
  List<Object?> get props => [window, ward, specimen, organism, drug, sex, ageBand, onset];
}

class SirCounts extends Equatable {
  const SirCounts({required this.s, required this.i, required this.r});

  factory SirCounts.fromJson(Json j) =>
      SirCounts(s: toInt(j['s']), i: toInt(j['i']), r: toInt(j['r']));

  final int s;
  final int i;
  final int r;

  int get total => s + i + r;

  @override
  List<Object?> get props => [s, i, r];
}

class SusceptibilityRow extends Equatable {
  const SusceptibilityRow({
    required this.ward,
    required this.specimen,
    required this.organism,
    required this.drug,
    required this.counts,
    required this.resistance,
    this.outbreakInflated = false,
    this.rateWithoutOutbreak,
    this.note,
  });

  factory SusceptibilityRow.fromJson(Json j) => SusceptibilityRow(
    ward: byCodeOrNull(Ward.values, j['ward']),
    specimen: byCode(Specimen.values, j['specimen']! as String),
    organism: byCode(Organism.values, j['organism']! as String),
    drug: byCode(Drug.values, j['drug']! as String),
    counts: SirCounts.fromJson(j['counts']! as Json),
    resistance: Estimate.fromJson(j['resistance']! as Json),
    outbreakInflated: j['outbreak_inflated'] == true,
    rateWithoutOutbreak: toDoubleOrNull(j['rate_without_outbreak']),
    note: j['note'] as String?,
  );

  final Ward? ward;
  final Specimen specimen;
  final Organism organism;
  final Drug drug;
  final SirCounts counts;
  final Estimate resistance;
  final bool outbreakInflated;
  final double? rateWithoutOutbreak;
  final String? note;

  @override
  List<Object?> get props => [ward, specimen, organism, drug, counts, resistance, outbreakInflated];
}

class SusceptibilityWindow extends Equatable {
  const SusceptibilityWindow({required this.window, required this.rows});

  factory SusceptibilityWindow.fromJson(Json j) => SusceptibilityWindow(
    window: WindowOut.fromJson(j['window']! as Json),
    rows: jsonList(j['rows']).map(SusceptibilityRow.fromJson).toList(),
  );

  final WindowOut window;
  final List<SusceptibilityRow> rows;

  @override
  List<Object?> get props => [window, rows];
}

class Susceptibility extends Equatable {
  const Susceptibility({required this.recent, required this.annual});

  factory Susceptibility.fromJson(Json j) => Susceptibility(
    recent: SusceptibilityWindow.fromJson(j['recent']! as Json),
    annual: SusceptibilityWindow.fromJson(j['annual']! as Json),
  );

  final SusceptibilityWindow recent;
  final SusceptibilityWindow annual;

  @override
  List<Object?> get props => [recent, annual];
}

// Weekly series -------------------------------------------------------------

class SeriesQuery extends Equatable implements AsOfQuery<SeriesQuery> {
  const SeriesQuery({
    required this.organism,
    required this.drug,
    this.filters = const SusceptibilityQuery(),
    this.wards = const [],
  });

  factory SeriesQuery.fromJson(Json j) => SeriesQuery(
    organism: byCode(Organism.values, j['organism']! as String),
    drug: byCode(Drug.values, j['drug']! as String),
    filters: SusceptibilityQuery.fromJson(j),
    wards: [for (final w in j['wards'] as List? ?? const []) byCode(Ward.values, w as String)],
  );

  final Organism organism;
  final Drug drug;

  /// Ward, specimen, sex, age, onset and the window; its organism and drug are ignored.
  final SusceptibilityQuery filters;
  final List<Ward> wards;

  @override
  SeriesQuery resolve(DateTime asOf) =>
      SeriesQuery(organism: organism, drug: drug, filters: filters.resolve(asOf), wards: wards);

  @override
  Json toQuery() => {
    ...filters.toQuery(),
    ...query({'organism': organism, 'drug': drug, 'wards': wards}),
  };

  @override
  List<Object?> get props => [organism, drug, filters, wards];
}

class WeeklyPoint extends Equatable {
  const WeeklyPoint({
    required this.weekStart,
    required this.n,
    required this.r,
    required this.rawRate,
    required this.shrunkRate,
    required this.low,
    required this.high,
  });

  factory WeeklyPoint.fromJson(Json j) => WeeklyPoint(
    weekStart: parseDate(j['week_start']),
    n: toInt(j['n']),
    r: toInt(j['r']),
    rawRate: toDoubleOrNull(j['raw_rate']),
    shrunkRate: toDouble(j['shrunk_rate']),
    low: toDouble(j['low']),
    high: toDouble(j['high']),
  );

  final DateTime weekStart;
  final int n;
  final int r;
  final double? rawRate;
  final double shrunkRate;
  final double low;
  final double high;

  @override
  List<Object?> get props => [weekStart, n, r, rawRate, shrunkRate, low, high];
}

class Series extends Equatable {
  const Series({
    required this.organism,
    required this.drug,
    required this.asOf,
    required this.series,
  });

  factory Series.fromJson(Json j) => Series(
    organism: byCode(Organism.values, j['organism']! as String),
    drug: byCode(Drug.values, j['drug']! as String),
    asOf: parseDate(j['as_of']),
    series: {
      for (final e in (j['series']! as Json).entries)
        e.key: jsonList(e.value).map(WeeklyPoint.fromJson).toList(),
    },
  );

  final Organism organism;
  final Drug drug;
  final DateTime asOf;

  /// By ward code; 'hospital' is the 12-month hospital rate.
  final Map<String, List<WeeklyPoint>> series;

  @override
  List<Object?> get props => [organism, drug, asOf, series];
}

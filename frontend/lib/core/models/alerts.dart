import 'package:equatable/equatable.dart';

import 'common.dart';
import 'data.dart';
import 'vocab.dart';

class AlertsQuery extends Equatable implements AsOfQuery<AlertsQuery> {
  const AlertsQuery({this.window = const WindowSpec(), this.ward, this.severity, this.status});

  factory AlertsQuery.fromJson(Json j) => AlertsQuery(
    window: WindowSpec.fromJson(j),
    ward: byCodeOrNull(Ward.values, j['ward']),
    severity: byCodeOrNull(Severity.values, j['severity']),
    status: byCodeOrNull(AlertStatus.values, j['status']),
  );

  final WindowSpec window;
  final Ward? ward;
  final Severity? severity;
  final AlertStatus? status;

  @override
  AlertsQuery resolve(DateTime asOf) =>
      AlertsQuery(window: window.resolve(asOf), ward: ward, severity: severity, status: status);

  @override
  Json toQuery() => {
    ...window.toQuery(),
    ...query({'ward': ward, 'severity': severity, 'status': status}),
  };

  @override
  List<Object?> get props => [window, ward, severity, status];
}

class Alert extends Equatable {
  const Alert({
    required this.alertId,
    required this.type,
    required this.severity,
    required this.status,
    required this.ward,
    required this.firstSeen,
    required this.asOf,
    required this.nCases,
    required this.summary,
    required this.verdict,
    this.organism,
    this.phenotype,
    this.drugs = const [],
  });

  factory Alert.fromJson(Json j) => Alert(
    alertId: j['alert_id']! as String,
    type: byCode(AlertType.values, j['type']! as String),
    severity: byCode(Severity.values, j['severity']! as String),
    status: byCode(AlertStatus.values, j['status']! as String),
    ward: byCode(Ward.values, j['ward']! as String),
    organism: byCodeOrNull(Organism.values, j['organism']),
    phenotype: byCodeOrNull(Phenotype.values, j['phenotype']),
    drugs: [for (final d in j['drugs'] as List? ?? const []) byCode(Drug.values, d as String)],
    firstSeen: parseDate(j['first_seen']),
    asOf: parseDate(j['as_of']),
    nCases: toInt(j['n_cases']),
    summary: j['summary']! as String,
    verdict: byCode(Verdict.values, j['verdict']! as String),
  );

  final String alertId;
  final AlertType type;
  final Severity severity;
  final AlertStatus status;
  final Ward ward;
  final Organism? organism;
  final Phenotype? phenotype;

  /// One outbreak groups its drugs.
  final List<Drug> drugs;
  final DateTime firstSeen;
  final DateTime asOf;
  final int nCases;
  final String summary;
  final Verdict verdict;

  /// "E. coli with ESBL", "MRSA", …
  String get title => [
    if (organism != null) organism!.short,
    if (phenotype != null) (organism != null ? 'with ${phenotype!.code}' : phenotype!.code),
  ].join(' ');

  @override
  List<Object?> get props => [alertId, type, severity, status, ward, asOf, nCases, verdict];
}

class Alerts extends Equatable {
  const Alerts({required this.asOf, required this.alerts});

  factory Alerts.fromJson(Json j) => Alerts(
    asOf: parseDate(j['as_of']),
    alerts: jsonList(j['alerts']).map(Alert.fromJson).toList(),
  );

  final DateTime asOf;
  final List<Alert> alerts;

  @override
  List<Object?> get props => [asOf, alerts];
}

class AlertDetailQuery extends Equatable implements AsOfQuery<AlertDetailQuery> {
  const AlertDetailQuery({required this.alertId, this.window = const WindowSpec()});

  factory AlertDetailQuery.fromJson(Json j) =>
      AlertDetailQuery(alertId: j['alert_id']! as String, window: WindowSpec.fromJson(j));

  final String alertId;
  final WindowSpec window;

  @override
  AlertDetailQuery resolve(DateTime asOf) =>
      AlertDetailQuery(alertId: alertId, window: window.resolve(asOf));

  @override
  Json toQuery() => {...window.toQuery(), 'alert_id': alertId};

  @override
  List<Object?> get props => [alertId, window];
}

class EpiPoint extends Equatable {
  const EpiPoint({required this.weekStart, required this.cases, required this.expected});

  factory EpiPoint.fromJson(Json j) => EpiPoint(
    weekStart: parseDate(j['week_start']),
    cases: toInt(j['cases']),
    expected: toDouble(j['expected']),
  );

  final DateTime weekStart;
  final int cases;
  final double expected;

  @override
  List<Object?> get props => [weekStart, cases, expected];
}

/// Aggregate-safe case row: no patient identifiers.
class CaseRow extends Equatable {
  const CaseRow({
    required this.sampleDate,
    required this.ward,
    required this.specimen,
    required this.organism,
    this.phenotype,
  });

  factory CaseRow.fromJson(Json j) => CaseRow(
    sampleDate: parseDate(j['sample_date']),
    ward: byCode(Ward.values, j['ward']! as String),
    specimen: byCode(Specimen.values, j['specimen']! as String),
    organism: byCode(Organism.values, j['organism']! as String),
    phenotype: byCodeOrNull(Phenotype.values, j['phenotype']),
  );

  final DateTime sampleDate;
  final Ward ward;
  final Specimen specimen;
  final Organism organism;
  final Phenotype? phenotype;

  @override
  List<Object?> get props => [sampleDate, ward, specimen, organism, phenotype];
}

class VolumePoint extends Equatable {
  const VolumePoint({required this.weekStart, required this.cultures});

  factory VolumePoint.fromJson(Json j) =>
      VolumePoint(weekStart: parseDate(j['week_start']), cultures: toInt(j['cultures']));

  final DateTime weekStart;
  final int cultures;

  @override
  List<Object?> get props => [weekStart, cultures];
}

class AlertDetail extends Equatable {
  const AlertDetail({
    required this.alert,
    required this.epiCurve,
    required this.cases,
    required this.volume,
    required this.wardComparison,
    required this.verdictReason,
  });

  factory AlertDetail.fromJson(Json j) => AlertDetail(
    alert: Alert.fromJson(j['alert']! as Json),
    epiCurve: jsonList(j['epi_curve']).map(EpiPoint.fromJson).toList(),
    cases: jsonList(j['cases']).map(CaseRow.fromJson).toList(),
    volume: jsonList(j['volume']).map(VolumePoint.fromJson).toList(),
    wardComparison: {
      for (final e in (j['ward_comparison'] as Json? ?? const {}).entries) e.key: toDouble(e.value),
    },
    verdictReason: j['verdict_reason']! as String,
  );

  final Alert alert;
  final List<EpiPoint> epiCurve;
  final List<CaseRow> cases;
  final List<VolumePoint> volume;

  /// Case rate by ward code.
  final Map<String, double> wardComparison;
  final String verdictReason;

  @override
  List<Object?> get props => [alert, epiCurve, cases, volume, wardComparison, verdictReason];
}

// Volume --------------------------------------------------------------------

class VolumeQuery extends Equatable implements AsOfQuery<VolumeQuery> {
  const VolumeQuery({this.window = const WindowSpec(), this.ward, this.specimen});

  factory VolumeQuery.fromJson(Json j) => VolumeQuery(
    window: WindowSpec.fromJson(j),
    ward: byCodeOrNull(Ward.values, j['ward']),
    specimen: byCodeOrNull(Specimen.values, j['specimen']),
  );

  final WindowSpec window;
  final Ward? ward;
  final Specimen? specimen;

  @override
  VolumeQuery resolve(DateTime asOf) =>
      VolumeQuery(window: window.resolve(asOf), ward: ward, specimen: specimen);

  @override
  Json toQuery() => {
    ...window.toQuery(),
    ...query({'ward': ward, 'specimen': specimen}),
  };

  @override
  List<Object?> get props => [window, ward, specimen];
}

class VolumeRow extends Equatable {
  const VolumeRow({
    required this.ward,
    required this.specimen,
    required this.points,
    required this.total,
    required this.baselineWeekly,
  });

  factory VolumeRow.fromJson(Json j) => VolumeRow(
    ward: byCode(Ward.values, j['ward']! as String),
    specimen: byCode(Specimen.values, j['specimen']! as String),
    points: jsonList(j['points']).map(VolumePoint.fromJson).toList(),
    total: toInt(j['total']),
    baselineWeekly: toDouble(j['baseline_weekly']),
  );

  final Ward ward;
  final Specimen specimen;
  final List<VolumePoint> points;
  final int total;
  final double baselineWeekly;

  @override
  List<Object?> get props => [ward, specimen, points, total, baselineWeekly];
}

class Volume extends Equatable {
  const Volume({required this.window, required this.rows});

  factory Volume.fromJson(Json j) => Volume(
    window: WindowOut.fromJson(j['window']! as Json),
    rows: jsonList(j['rows']).map(VolumeRow.fromJson).toList(),
  );

  final WindowOut window;
  final List<VolumeRow> rows;

  @override
  List<Object?> get props => [window, rows];
}

// Spreading -----------------------------------------------------------------

class SpreadingQuery extends Equatable implements AsOfQuery<SpreadingQuery> {
  const SpreadingQuery({this.window = const WindowSpec(), this.wards = const []});

  factory SpreadingQuery.fromJson(Json j) => SpreadingQuery(
    window: WindowSpec.fromJson(j),
    wards: [for (final w in j['wards'] as List? ?? const []) byCode(Ward.values, w as String)],
  );

  final WindowSpec window;
  final List<Ward> wards;

  @override
  SpreadingQuery resolve(DateTime asOf) =>
      SpreadingQuery(window: window.resolve(asOf), wards: wards);

  @override
  Json toQuery() => {
    ...window.toQuery(),
    ...query({'wards': wards}),
  };

  @override
  List<Object?> get props => [window, wards];
}

class SpreadingRow extends Equatable {
  const SpreadingRow({
    required this.ward,
    required this.phenotype,
    required this.count,
    required this.normal,
    required this.aboveNormal,
  });

  factory SpreadingRow.fromJson(Json j) => SpreadingRow(
    ward: byCode(Ward.values, j['ward']! as String),
    phenotype: byCode(Phenotype.values, j['phenotype']! as String),
    count: toInt(j['count']),
    normal: toDouble(j['normal']),
    aboveNormal: j['above_normal'] == true,
  );

  final Ward ward;
  final Phenotype phenotype;
  final int count;

  /// Typical count for the same window length.
  final double normal;
  final bool aboveNormal;

  @override
  List<Object?> get props => [ward, phenotype, count, normal, aboveNormal];
}

class Spreading extends Equatable {
  const Spreading({required this.window, required this.rows});

  factory Spreading.fromJson(Json j) => Spreading(
    window: WindowOut.fromJson(j['window']! as Json),
    rows: jsonList(j['rows']).map(SpreadingRow.fromJson).toList(),
  );

  final WindowOut window;
  final List<SpreadingRow> rows;

  @override
  List<Object?> get props => [window, rows];
}

// Ward links ----------------------------------------------------------------

class WardLinksQuery extends Equatable implements AsOfQuery<WardLinksQuery> {
  const WardLinksQuery({required this.ward, this.window = const WindowSpec()});

  factory WardLinksQuery.fromJson(Json j) => WardLinksQuery(
    ward: byCode(Ward.values, j['ward']! as String),
    window: WindowSpec.fromJson(j),
  );

  final Ward ward;
  final WindowSpec window;

  @override
  WardLinksQuery resolve(DateTime asOf) => WardLinksQuery(ward: ward, window: window.resolve(asOf));

  @override
  Json toQuery() => {...window.toQuery(), 'ward': ward.code};

  @override
  List<Object?> get props => [ward, window];
}

class WardLink extends Equatable {
  const WardLink({
    required this.ward,
    required this.sharedPatients30d,
    this.warning,
    this.organism,
    this.phenotype,
  });

  factory WardLink.fromJson(Json j) => WardLink(
    ward: byCode(Ward.values, j['ward']! as String),
    sharedPatients30d: toInt(j['shared_patients_30d']),
    warning: j['warning'] as String?,
    organism: byCodeOrNull(Organism.values, j['organism']),
    phenotype: byCodeOrNull(Phenotype.values, j['phenotype']),
  );

  final Ward ward;
  final int sharedPatients30d;
  final String? warning;
  final Organism? organism;
  final Phenotype? phenotype;

  @override
  List<Object?> get props => [ward, sharedPatients30d, warning, organism, phenotype];
}

class WardLinks extends Equatable {
  const WardLinks({required this.ward, required this.asOf, required this.links});

  factory WardLinks.fromJson(Json j) => WardLinks(
    ward: byCode(Ward.values, j['ward']! as String),
    asOf: parseDate(j['as_of']),
    links: jsonList(j['links']).map(WardLink.fromJson).toList(),
  );

  final Ward ward;
  final DateTime asOf;
  final List<WardLink> links;

  @override
  List<Object?> get props => [ward, asOf, links];
}

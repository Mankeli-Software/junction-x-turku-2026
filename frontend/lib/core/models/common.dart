import 'package:equatable/equatable.dart';

import 'vocab.dart';

typedef Json = Map<String, Object?>;

// JSON helpers ---------------------------------------------------------------

DateTime parseDate(Object? v) => DateTime.parse(v! as String);
DateTime? parseDateOrNull(Object? v) => v == null ? null : DateTime.parse(v as String);

/// `2026-09-27`, the wire format of every date.
String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

double toDouble(Object? v) => (v! as num).toDouble();
double? toDoubleOrNull(Object? v) => (v as num?)?.toDouble();
int toInt(Object? v) => (v! as num).toInt();
List<Json> jsonList(Object? v) => (v as List? ?? const []).cast<Json>();

/// Builds a query map, dropping nulls and encoding codes, dates and lists.
Json query(Map<String, Object?> params) => {
  for (final e in params.entries)
    if (e.value != null && !(e.value is Iterable && (e.value! as Iterable).isEmpty))
      e.key: switch (e.value) {
        final Coded c => c.code,
        final DateTime d => formatDate(d),
        final Iterable<Object?> it => [for (final x in it) x is Coded ? x.code : '$x'],
        final other => '$other',
      },
};

// Shared output models -------------------------------------------------------

/// A shrunk rate with its range and how much it leans on the prior.
class Estimate extends Equatable {
  const Estimate({
    required this.value,
    required this.low,
    required this.high,
    required this.n,
    required this.priorLevel,
    required this.priorWeight,
    required this.smallSample,
    this.rawRate,
  });

  factory Estimate.fromJson(Json j) => Estimate(
    value: toDouble(j['value']),
    low: toDouble(j['low']),
    high: toDouble(j['high']),
    n: toInt(j['n']),
    priorLevel: byCode(PriorLevel.values, j['prior_level']! as String),
    priorWeight: toDouble(j['prior_weight']),
    smallSample: j['small_sample'] == true,
    rawRate: toDoubleOrNull(j['raw_rate']),
  );

  final double value;
  final double low;
  final double high;

  /// First isolates behind the number.
  final int n;
  final PriorLevel priorLevel;

  /// Share of the estimate that comes from the prior (0–1).
  final double priorWeight;

  /// n below the minimum: show the range, not a bare percentage.
  final bool smallSample;
  final double? rawRate;

  @override
  List<Object?> get props => [value, low, high, n, priorLevel, priorWeight, smallSample, rawRate];
}

class WindowOut extends Equatable {
  const WindowOut({
    required this.window,
    required this.asOf,
    required this.dateFrom,
    required this.dateTo,
  });

  factory WindowOut.fromJson(Json j) => WindowOut(
    window: j['window']! as String,
    asOf: parseDate(j['as_of']),
    dateFrom: parseDate(j['date_from']),
    dateTo: parseDate(j['date_to']),
  );

  final String window;
  final DateTime asOf;
  final DateTime dateFrom;
  final DateTime dateTo;

  @override
  List<Object?> get props => [window, asOf, dateFrom, dateTo];
}

// Shared query parts ---------------------------------------------------------

/// Every query takes as_of; the window is named or custom. A null [asOf] means "the session's
/// replay date", filled in by [resolve] before the request.
class WindowSpec extends Equatable {
  const WindowSpec({this.asOf, this.window = TimeWindow.d28, this.dateFrom, this.dateTo});

  factory WindowSpec.fromJson(Json j) => WindowSpec(
    asOf: parseDateOrNull(j['as_of']),
    window: byCodeOrNull(TimeWindow.values, j['window']) ?? TimeWindow.d28,
    dateFrom: parseDateOrNull(j['date_from']),
    dateTo: parseDateOrNull(j['date_to']),
  );

  final DateTime? asOf;
  final TimeWindow window;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  WindowSpec resolve(DateTime sessionAsOf) => asOf != null
      ? this
      : WindowSpec(asOf: sessionAsOf, window: window, dateFrom: dateFrom, dateTo: dateTo);

  Json toQuery() =>
      query({'as_of': asOf, 'window': window, 'date_from': dateFrom, 'date_to': dateTo});

  @override
  List<Object?> get props => [asOf, window, dateFrom, dateTo];
}

/// The described patient: the quick-patient inputs (backend ProfileQuery without the window).
class PatientProfile extends Equatable {
  const PatientProfile({
    this.ward,
    this.infectionType,
    this.specimen,
    this.sex,
    this.ageBand,
    this.onset,
  });

  factory PatientProfile.fromJson(Json j) => PatientProfile(
    ward: byCodeOrNull(Ward.values, j['ward']),
    infectionType: byCodeOrNull(InfectionType.values, j['infection_type']),
    specimen: byCodeOrNull(Specimen.values, j['specimen']),
    sex: byCodeOrNull(Sex.values, j['sex']),
    ageBand: byCodeOrNull(AgeBand.values, j['age_band']),
    onset: byCodeOrNull(Onset.values, j['onset']),
  );

  final Ward? ward;
  final InfectionType? infectionType;
  final Specimen? specimen;
  final Sex? sex;
  final AgeBand? ageBand;
  final Onset? onset;

  /// The specimen the numbers come from: explicit, or implied by the infection type.
  Specimen? get effectiveSpecimen => specimen ?? infectionType?.specimen;

  /// Pneumonia and other types with no specimen in the data.
  bool get notInData => infectionType != null && !infectionType!.inData;

  PatientProfile copyWith({
    Ward? ward,
    InfectionType? infectionType,
    Specimen? specimen,
    Sex? sex,
    AgeBand? ageBand,
    Onset? onset,
  }) => PatientProfile(
    ward: ward ?? this.ward,
    infectionType: infectionType ?? this.infectionType,
    specimen: specimen ?? this.specimen,
    sex: sex ?? this.sex,
    ageBand: ageBand ?? this.ageBand,
    onset: onset ?? this.onset,
  );

  Json toQuery() => query({
    'ward': ward,
    'infection_type': infectionType,
    'specimen': specimen,
    'sex': sex,
    'age_band': ageBand,
    'onset': onset,
  });

  @override
  List<Object?> get props => [ward, infectionType, specimen, sex, ageBand, onset];
}

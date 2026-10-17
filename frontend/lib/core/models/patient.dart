import 'package:equatable/equatable.dart';

import 'common.dart';
import 'data.dart';
import 'vocab.dart';

/// Earlier findings for one patient (the optional patient-context endpoint). Facts only; they
/// never change a ranking.
class PatientHistoryQuery extends Equatable implements AsOfQuery<PatientHistoryQuery> {
  const PatientHistoryQuery({required this.patientId, this.asOf});

  factory PatientHistoryQuery.fromJson(Json j) =>
      PatientHistoryQuery(patientId: j['patient_id']! as String, asOf: parseDateOrNull(j['as_of']));

  final String patientId;
  final DateTime? asOf;

  @override
  PatientHistoryQuery resolve(DateTime sessionAsOf) =>
      PatientHistoryQuery(patientId: patientId, asOf: asOf ?? sessionAsOf);

  @override
  Json toQuery() => query({'patient_id': patientId, 'as_of': asOf});

  @override
  List<Object?> get props => [patientId, asOf];
}

class PatientFinding extends Equatable {
  const PatientFinding({
    required this.sampleDate,
    required this.organism,
    required this.specimen,
    this.phenotype,
  });

  factory PatientFinding.fromJson(Json j) => PatientFinding(
    sampleDate: parseDate(j['sample_date']),
    organism: byCode(Organism.values, j['organism']! as String),
    specimen: byCode(Specimen.values, j['specimen']! as String),
    phenotype: byCodeOrNull(Phenotype.values, j['phenotype']),
  );

  final DateTime sampleDate;
  final Organism organism;
  final Specimen specimen;
  final Phenotype? phenotype;

  @override
  List<Object?> get props => [sampleDate, organism, specimen, phenotype];
}

class PatientHistory extends Equatable {
  const PatientHistory({required this.patientId, required this.findings});

  factory PatientHistory.fromJson(Json j) => PatientHistory(
    patientId: j['patient_id']! as String,
    findings: jsonList(j['findings']).map(PatientFinding.fromJson).toList(),
  );

  final String patientId;
  final List<PatientFinding> findings;

  /// Nothing after [asOf] may show.
  PatientHistory upTo(DateTime asOf) => PatientHistory(
    patientId: patientId,
    findings: [
      for (final f in findings)
        if (!f.sampleDate.isAfter(asOf)) f,
    ],
  );

  @override
  List<Object?> get props => [patientId, findings];
}

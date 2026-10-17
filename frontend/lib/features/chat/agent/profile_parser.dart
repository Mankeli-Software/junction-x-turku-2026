import '../../../core/models/common.dart';
import '../../../core/models/vocab.dart';

/// Reads a patient out of a sentence ("My 80-year-old female patient on Urology has a UTI").
/// A stand-in for the agent's understanding; only fields it is sure of are set.
PatientProfile parseProfile(String text) {
  final t = text.toLowerCase();
  Sex? sex;
  if (RegExp(r'\b(woman|female|she|her|lady|girl)\b').hasMatch(t)) sex = Sex.female;
  if (RegExp(r'\b(man|male|he|his|boy)\b').hasMatch(t)) sex = Sex.male;

  AgeBand? age;
  final years = RegExp(
    r'(\d{1,3})[- ]?(?:year|yr|y\.?o\b|v\b)|aged (\d{1,3})|over (\d{1,3})',
  ).firstMatch(t);
  if (years != null) {
    final n = int.parse((years.group(1) ?? years.group(2) ?? years.group(3))!);
    age = n < 18
        ? AgeBand.a0_17
        : n < 45
        ? AgeBand.a18_44
        : n < 65
        ? AgeBand.a45_64
        : n < 75
        ? AgeBand.a65_74
        : AgeBand.a75;
  } else if (t.contains('75+') || t.contains('elderly')) {
    age = AgeBand.a75;
  }

  Ward? ward;
  for (final w in Ward.values) {
    if (t.contains(w.label.toLowerCase()) || RegExp('\\b${w.code.toLowerCase()}\\b').hasMatch(t)) {
      ward = w;
    }
  }
  if (t.contains('emergency')) ward = Ward.ed;
  if (t.contains('intensive')) ward = Ward.icu;

  InfectionType? infection;
  if (RegExp(r'\buti\b|urinary|urine|cystitis|pyelo').hasMatch(t)) infection = InfectionType.uti;
  if (RegExp(r'sepsis|bacter[a]?emia|blood').hasMatch(t)) infection = InfectionType.sepsis;
  if (RegExp(r'wound|surgical site|ulcer').hasMatch(t)) infection = InfectionType.wound;
  if (RegExp(r'pneumonia|respiratory|lung').hasMatch(t)) infection = InfectionType.pneumonia;

  Onset? onset;
  if (RegExp(
    r'in hospital|hospital onset|hospital-onset|day 3|nosocomial|after surgery',
  ).hasMatch(t)) {
    onset = Onset.hospital;
  }
  if (RegExp(r'at home|community|from home|home onset').hasMatch(t)) onset = Onset.community;

  return PatientProfile(sex: sex, ageBand: age, ward: ward, infectionType: infection, onset: onset);
}

/// True when the sentence is about a patient at all.
bool mentionsPatient(PatientProfile p, String text) =>
    p.infectionType != null ||
    RegExp(r'patient|what works|cover|treat|antibiotic').hasMatch(text.toLowerCase());

PatientProfile mergeProfile(PatientProfile base, PatientProfile update) => PatientProfile(
  sex: update.sex ?? base.sex,
  ageBand: update.ageBand ?? base.ageBand,
  ward: update.ward ?? base.ward,
  infectionType: update.infectionType ?? base.infectionType,
  specimen: update.specimen ?? base.specimen,
  onset: update.onset ?? base.onset,
);

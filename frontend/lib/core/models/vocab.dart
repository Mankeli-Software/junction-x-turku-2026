/// Shared vocabulary, mirroring backend/app/vocab.py. `code` is the wire value.
library;

/// An enum value with a wire code.
abstract interface class Coded {
  String get code;
}

T byCode<T extends Coded>(List<T> values, String code) => values.firstWhere(
  (v) => v.code == code,
  orElse: () => throw FormatException('Unknown code $code'),
);

T? byCodeOrNull<T extends Coded>(List<T> values, Object? code) =>
    code is String ? values.where((v) => v.code == code).firstOrNull : null;

/// The last day of the data, and the default as_of.
final dataEnd = DateTime.utc(2026, 9, 27);

/// The first day of the data: the replay slider starts here.
final dataStart = DateTime.utc(2023, 10, 2);

/// Below this many first isolates a percentage is shrunk toward the hospital rate.
const minIsolates = 30;

/// The lower bound of coverage must reach this.
const coverageTarget = 0.90;

enum Ward implements Coded {
  ed('ED', 'Emergency department', 'Emergency dept.'),
  medA('MED-A', 'Internal medicine A', 'Medicine A'),
  medB('MED-B', 'Internal medicine B', 'Medicine B'),
  surg('SURG', 'Surgery', 'Surgery'),
  uro('URO', 'Urology', 'Urology'),
  icu('ICU', 'Intensive care', 'ICU'),
  ger('GER', 'Geriatrics', 'Geriatrics'),
  phcN('PHC-N', 'Health centre North', 'Health centre N'),
  phcS('PHC-S', 'Health centre South', 'Health centre S');

  const Ward(this.code, this.label, this.short);

  @override
  final String code;
  final String label;
  final String short;
}

enum Specimen implements Coded {
  urine('urine', 'Urine'),
  blood('blood', 'Blood'),
  wound('wound', 'Wound');

  const Specimen(this.code, this.label);

  @override
  final String code;
  final String label;
}

enum InfectionType implements Coded {
  uti('uti', 'Urinary tract', 'a urinary tract infection', Specimen.urine),
  sepsis('sepsis', 'Sepsis', 'sepsis', Specimen.blood),
  wound('wound', 'Wound infection', 'a wound infection', Specimen.wound),
  pneumonia('pneumonia', 'Pneumonia', 'pneumonia', null);

  const InfectionType(this.code, this.label, this.inSentence, this.specimen);

  @override
  final String code;
  final String label;
  final String inSentence;

  /// Specimen that stands in for the infection type; pneumonia has none in the data.
  final Specimen? specimen;

  bool get inData => specimen != null;
}

enum Sex implements Coded {
  female('F', 'Woman', 'woman'),
  male('M', 'Man', 'man');

  const Sex(this.code, this.label, this.inSentence);

  @override
  final String code;
  final String label;
  final String inSentence;
}

enum AgeBand implements Coded {
  a0_17('0-17', '0–17'),
  a18_44('18-44', '18–44'),
  a45_64('45-64', '45–64'),
  a65_74('65-74', '65–74'),
  a75('75+', '75 or older');

  const AgeBand(this.code, this.label);

  @override
  final String code;
  final String label;

  String get short => code.replaceAll('-', '–');
}

enum Onset implements Coded {
  community('community', 'At home', 'at home', 'Or in the first 2 days in hospital'),
  hospital('hospital', 'In hospital', 'in hospital', 'Day 3 of the stay or later');

  const Onset(this.code, this.label, this.inSentence, this.hint);

  @override
  final String code;
  final String label;
  final String inSentence;
  final String hint;
}

enum TimeWindow implements Coded {
  d28('28d', 'Last 4 weeks'),
  d365('365d', 'Last 12 months'),
  custom('custom', 'Custom');

  const TimeWindow(this.code, this.label);

  @override
  final String code;
  final String label;
}

enum Interpretation implements Coded {
  s('S'),
  i('I'),
  r('R');

  const Interpretation(this.code);

  @override
  final String code;
}

enum Phenotype implements Coded {
  esbl('ESBL'),
  mrsa('MRSA'),
  vre('VRE'),
  cpe('CPE');

  const Phenotype(this.code);

  @override
  final String code;
}

/// WHONET codes as in antibiotics.csv. [oral] and [reserve] drive display tags only.
enum Drug implements Coded {
  amp('AMP', 'Ampicillin', 'Ampicillin'),
  mec('MEC', 'Mecillinam', 'Mecillinam', oral: true),
  tzp('TZP', 'Piperacillin–tazobactam', 'Pip–tazo'),
  fox('FOX', 'Cefoxitin (screen)', 'Cefoxitin'),
  cxm('CXM', 'Cefuroxime', 'Cefuroxime'),
  cro('CRO', 'Ceftriaxone', 'Ceftriaxone'),
  caz('CAZ', 'Ceftazidime', 'Ceftazidime'),
  mem('MEM', 'Meropenem', 'Meropenem', reserve: true),
  cip('CIP', 'Ciprofloxacin', 'Ciprofloxacin', oral: true),
  tmp('TMP', 'Trimethoprim', 'Trimethoprim', oral: true),
  nit('NIT', 'Nitrofurantoin', 'Nitrofurantoin', oral: true),
  van('VAN', 'Vancomycin', 'Vancomycin', reserve: true),
  cli('CLI', 'Clindamycin', 'Clindamycin', oral: true);

  const Drug(this.code, this.label, this.short, {this.oral = false, this.reserve = false});

  @override
  final String code;
  final String label;
  final String short;
  final bool oral;
  final bool reserve;
}

enum Organism implements Coded {
  eColi('Escherichia coli', 'E. coli'),
  sAureus('Staphylococcus aureus', 'S. aureus'),
  eFaecalis('Enterococcus faecalis', 'Enterococcus'),
  kPneumoniae('Klebsiella pneumoniae', 'Klebsiella'),
  pMirabilis('Proteus mirabilis', 'Proteus'),
  pAeruginosa('Pseudomonas aeruginosa', 'Pseudomonas'),
  cFreundii('Citrobacter freundii', 'Citrobacter'),
  kOxytoca('Klebsiella oxytoca', 'K. oxytoca'),
  sSaprophyticus('Staphylococcus saprophyticus', 'S. saprophyticus');

  const Organism(this.code, this.short);

  /// The full species name, which is also the wire value.
  @override
  final String code;
  final String short;
}

enum Role implements Coded {
  doctor('doctor', 'Physician'),
  hygiene('hygiene', 'Infection control'),
  careWorker('care_worker', 'Care worker'),
  lab('lab', 'Lab'),
  researcher('researcher', 'Research');

  const Role(this.code, this.label);

  @override
  final String code;
  final String label;
}

enum PriorLevel implements Coded {
  ward('ward'),
  wardType('ward_type'),
  hospital('hospital');

  const PriorLevel(this.code);

  @override
  final String code;
}

enum AlertType implements Coded {
  sentinel('sentinel', 'Single rare find'),
  statistical('statistical', 'Cluster'),
  trend('trend', 'Slow trend'),
  missingData('missing_data', 'Missing data');

  const AlertType(this.code, this.label);

  @override
  final String code;
  final String label;
}

enum Severity implements Coded {
  low('low'),
  medium('medium'),
  high('high'),
  critical('critical');

  const Severity(this.code);

  @override
  final String code;
}

enum AlertStatus implements Coded {
  active('active'),
  acknowledged('acknowledged'),
  resolved('resolved');

  const AlertStatus(this.code);

  @override
  final String code;
}

enum Verdict implements Coded {
  likelyReal('likely_real', 'Likely real'),
  samplingArtefact('possible_sampling_artefact', 'Maybe more testing'),
  tooFewCases('too_few_cases', 'Too few cases yet');

  const Verdict(this.code, this.label);

  @override
  final String code;
  final String label;
}

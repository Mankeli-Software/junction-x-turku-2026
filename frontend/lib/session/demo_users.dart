import 'package:equatable/equatable.dart';

import '../core/models/vocab.dart';

enum UserGroup {
  clinicians(
    'Clinicians',
    'Describe a patient, see which antibiotics are likely to work on your ward.',
  ),
  prevention(
    'Infection prevention & care',
    'See what is spreading where, and which wards to warn or clean more.',
  ),
  labResearch(
    'Lab & research',
    'Investigate alerts, check data quality, explore trends and export.',
  );

  const UserGroup(this.label, this.description);

  final String label;
  final String description;
}

/// A predefined demo profile. There are no passwords in the proof of concept: picking a
/// profile sets the `user_id`, the role and the home ward.
class DemoUser extends Equatable {
  const DemoUser({
    required this.id,
    required this.name,
    required this.initials,
    required this.title,
    required this.role,
    required this.group,
    this.ward,
    this.wards = const [],
  });

  final String id;
  final String name;
  final String initials;

  /// "Physician · Urology"
  final String title;
  final Role role;
  final UserGroup group;

  /// Home ward, pre-filled in the patient form and the alert banner.
  final Ward? ward;

  /// Extra wards for people who work on several (care workers).
  final List<Ward> wards;

  /// "Urology", "Infection control", "Lab": shown after the name in the top bar.
  String get context => ward?.label ?? role.label;

  @override
  List<Object?> get props => [id];
}

const demoUsers = <DemoUser>[
  DemoUser(
    id: 'aino',
    name: 'Aino Virtanen',
    initials: 'AV',
    title: 'Physician · Urology',
    role: Role.doctor,
    group: UserGroup.clinicians,
    ward: Ward.uro,
  ),
  DemoUser(
    id: 'mikko',
    name: 'Mikko Lahti',
    initials: 'ML',
    title: 'Physician · Emergency dept.',
    role: Role.doctor,
    group: UserGroup.clinicians,
    ward: Ward.ed,
  ),
  DemoUser(
    id: 'leena',
    name: 'Leena Salo',
    initials: 'LS',
    title: 'GP · Health centre North',
    role: Role.doctor,
    group: UserGroup.clinicians,
    ward: Ward.phcN,
  ),
  DemoUser(
    id: 'sanna',
    name: 'Sanna Korhonen',
    initials: 'SK',
    title: 'Infection control nurse · Hospital',
    role: Role.hygiene,
    group: UserGroup.prevention,
  ),
  DemoUser(
    id: 'jari',
    name: 'Jari Mäkinen',
    initials: 'JM',
    title: 'Care worker · ICU and Surgery',
    role: Role.careWorker,
    group: UserGroup.prevention,
    ward: Ward.icu,
    wards: [Ward.icu, Ward.surg],
  ),
  DemoUser(
    id: 'elina',
    name: 'Elina Nieminen',
    initials: 'EN',
    title: 'Clinical microbiologist · Lab',
    role: Role.lab,
    group: UserGroup.labResearch,
  ),
  DemoUser(
    id: 'tomi',
    name: 'Tomi Heikkinen',
    initials: 'TH',
    title: 'Researcher · AMR epidemiology',
    role: Role.researcher,
    group: UserGroup.labResearch,
  ),
];

DemoUser? demoUserById(String? id) => demoUsers.where((u) => u.id == id).firstOrNull;

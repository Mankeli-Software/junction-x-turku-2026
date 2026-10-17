import '../../catalog/widgets/context_chips.dart';
import '../../core/models/common.dart';
import '../../core/models/vocab.dart';
import 'chat_page.dart' show roleQuestions;

/// Where an ask field was opened: the composer's title, the line under it and the suggested
/// questions. A patient travels with the question, so follow-ups ("only oral options") are
/// answered for that patient.
class AskContext {
  const AskContext._({required this.title, required this.suggestions, this.subtitle, this.patient});

  /// Doctor home: describe a patient or ask about the ward.
  factory AskContext.patientForm({Ward? ward}) => AskContext._(
    title: 'Ask the AI',
    subtitle:
        'Describe your patient in your own words, or ask about '
        '${ward == null ? 'resistance' : ward.label}.',
    suggestions: roleQuestions(Role.doctor),
  );

  /// The answer page: follow-ups about the patient on screen.
  factory AskContext.answer(PatientProfile patient) {
    final who = switch (patient.sex) {
      Sex.female => 'she is',
      Sex.male => 'he is',
      null => 'the patient is',
    };
    return AskContext._(
      title: 'Ask about this patient',
      subtitle: patientSentence(patient),
      patient: patient,
      suggestions: [
        'What if $who allergic to penicillin?',
        'Only oral options',
        'Compare with the whole hospital',
      ],
    );
  }

  /// Infection control and care workers: spreading and the wards to warn.
  factory AskContext.spreading(Role? role) => AskContext._(
    title: role == Role.careWorker ? 'Ask about your wards' : 'Ask about spreading',
    subtitle: 'Resistant bacteria on every ward, against a usual period.',
    suggestions: roleQuestions(role == Role.careWorker ? Role.careWorker : Role.hygiene),
  );

  /// The lab inbox: whether an alert is real.
  factory AskContext.alerts() => AskContext._(
    title: 'Ask about alerts',
    subtitle: 'Open alerts, the isolates behind them and the testing volume.',
    suggestions: roleQuestions(Role.lab),
  );

  /// Research: a chart described in words.
  factory AskContext.research() => const AskContext._(
    title: 'Make a chart',
    subtitle: 'Describe the organism, drug, split and time step you want.',
    suggestions: [
      'E. coli trimethoprim trend by sex',
      'ICU MRSA trend in 2026',
      'Compare Urology and Surgery for ceftriaxone',
    ],
  );

  /// The pinned home: a widget described in words.
  factory AskContext.dashboard({Ward? ward}) => AskContext._(
    title: 'Add a widget',
    subtitle: 'Describe what you want to see; pin the answer to your home.',
    suggestions: [
      'MRSA on ${ward?.label ?? 'my ward'} this year',
      'What is spreading this week?',
      'What works for a UTI on my ward?',
    ],
  );

  final String title;
  final String? subtitle;
  final List<String> suggestions;
  final PatientProfile? patient;
}

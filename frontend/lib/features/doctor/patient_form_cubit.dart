import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/common.dart';
import '../../core/models/vocab.dart';

/// The five words of "My patient is a [woman] aged [75+] on [Urology] with [a UTI] that
/// started [in hospital]", in order.
enum PatientField {
  sex('Sex', 'My patient is a'),
  age('Age group', 'aged'),
  ward('Ward', 'on'),
  infection('What kind of infection?', 'with'),
  onset('Where did it start?', 'that started');

  const PatientField(this.question, this.lead);

  final String question;

  /// The words before the token in the sentence.
  final String lead;
}

class PatientFormState extends Equatable {
  const PatientFormState({required this.profile, this.active = PatientField.infection});

  final PatientProfile profile;
  final PatientField active;

  int get step => active.index;

  @override
  List<Object?> get props => [profile, active];
}

/// The quick patient flow: tap a word, pick a tile, it moves on to the next word.
class PatientFormCubit extends Cubit<PatientFormState> {
  PatientFormCubit({required Ward? homeWard, PatientProfile? initial})
    : super(PatientFormState(profile: _defaults(homeWard).merge(initial)));

  /// "Your ward and the usual choices are filled in for you."
  static PatientProfile _defaults(Ward? ward) => PatientProfile(
    sex: Sex.female,
    ageBand: AgeBand.a75,
    ward: ward ?? Ward.uro,
    infectionType: InfectionType.uti,
    onset: Onset.hospital,
  );

  void focus(PatientField field) => emit(PatientFormState(profile: state.profile, active: field));

  /// Sets the active word to [value] and moves to the next one.
  void pick(Object value) {
    final p = state.profile;
    final next = switch (value) {
      final Sex v => p.copyWith(sex: v),
      final AgeBand v => p.copyWith(ageBand: v),
      final Ward v => p.copyWith(ward: v),
      final InfectionType v => p.copyWith(infectionType: v),
      final Onset v => p.copyWith(onset: v),
      _ => p,
    };
    final i = state.active.index;
    final active = PatientField.values[i < PatientField.values.length - 1 ? i + 1 : i];
    emit(PatientFormState(profile: next, active: active));
  }
}

extension on PatientProfile {
  PatientProfile merge(PatientProfile? other) => other == null
      ? this
      : copyWith(
          sex: other.sex,
          ageBand: other.ageBand,
          ward: other.ward,
          infectionType: other.infectionType,
          onset: other.onset,
        );
}

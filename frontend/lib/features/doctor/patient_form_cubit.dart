import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/common.dart';
import '../../core/models/vocab.dart';

/// The five words of "My patient is a [woman] aged [75+] on [Urology] with [a UTI] that
/// started [in hospital]", in order.
enum PatientField {
  sex('Sex', 'My patient is a', 'sex'),
  age('Age group', 'aged', 'age'),
  ward('Ward', 'on', 'ward'),
  infection('What kind of infection?', 'with', 'infection'),
  onset('Where did it start?', 'that started', 'where');

  const PatientField(this.question, this.lead, this.placeholder);

  final String question;

  /// Shown in the sentence until the word is chosen ("My patient is a [sex] aged [age]").
  final String placeholder;

  /// The words before the token in the sentence.
  final String lead;
}

class PatientFormState extends Equatable {
  const PatientFormState({
    required this.profile,
    this.active = PatientField.sex,
    this.confirmed = const {},
  });

  final PatientProfile profile;

  /// The word being chosen; null once every word is confirmed ("All set").
  final PatientField? active;

  /// Words the user has gone through (an "Edit details" patient counts only once picked).
  final Set<PatientField> confirmed;

  bool get done => active == null;

  /// Zero-based step for the progress dots; 5 when all set.
  int get step => active?.index ?? PatientField.values.length;

  @override
  List<Object?> get props => [profile, active, confirmed];
}

/// The quick patient flow: tap a word, pick a tile, it moves on to the next word. After the
/// last word the form is "All set" and offers "Show what works".
class PatientFormCubit extends Cubit<PatientFormState> {
  PatientFormCubit({PatientProfile? initial})
    // Starts blank on the first word; a patient from "Edit details" stays filled in.
    : super(PatientFormState(profile: initial ?? const PatientProfile()));

  void focus(PatientField field) =>
      emit(PatientFormState(profile: state.profile, active: field, confirmed: state.confirmed));

  /// Sets the active word to [value], then moves to the next unconfirmed word, or to
  /// "All set" when there is none.
  void pick(Object value) {
    final current = state.active;
    if (current == null) return;
    final p = state.profile;
    final next = switch (value) {
      final Sex v => p.copyWith(sex: v),
      final AgeBand v => p.copyWith(ageBand: v),
      final Ward v => p.copyWith(ward: v),
      final InfectionType v => p.copyWith(infectionType: v),
      final Onset v => p.copyWith(onset: v),
      _ => p,
    };
    final confirmed = {...state.confirmed, current};
    final fields = PatientField.values;
    final after = [...fields.skip(current.index + 1), ...fields.take(current.index)];
    final active = after.where((f) => !confirmed.contains(f)).firstOrNull;
    emit(PatientFormState(profile: next, active: active, confirmed: confirmed));
  }

  /// Back to the first word with the usual choices.
  void startOver() => emit(const PatientFormState(profile: PatientProfile()));
}

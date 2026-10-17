import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/alerts.dart';
import '../../core/models/common.dart';
import '../../core/models/vocab.dart';

class HygieneState extends Equatable {
  const HygieneState({this.phenotype, this.window = TimeWindow.d28, this.focus});

  /// Only this resistant type; null is "All resistant types".
  final Phenotype? phenotype;

  /// 4 weeks against a usual 4 weeks, or 12 months against a usual year.
  final TimeWindow window;

  /// The ward picked on the grid; its linked wards are shown. Null: the most raised ward.
  final Ward? focus;

  SpreadingQuery get query => SpreadingQuery(window: WindowSpec(window: window));

  HygieneState copyWith({
    Phenotype? phenotype,
    bool allTypes = false,
    TimeWindow? window,
    Ward? focus,
  }) => HygieneState(
    phenotype: allTypes ? null : (phenotype ?? this.phenotype),
    window: window ?? this.window,
    focus: focus ?? this.focus,
  );

  @override
  List<Object?> get props => [phenotype, window, focus];
}

/// Filters on the infection-control screen.
class HygieneCubit extends Cubit<HygieneState> {
  HygieneCubit() : super(const HygieneState());

  void showType(Phenotype? p) => emit(state.copyWith(phenotype: p, allTypes: p == null));

  void toggleYear() => emit(
    state.copyWith(window: state.window == TimeWindow.d365 ? TimeWindow.d28 : TimeWindow.d365),
  );

  void focus(Ward w) => emit(state.copyWith(focus: w));
}

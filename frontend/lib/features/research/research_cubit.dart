import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/widgets/export_ready.dart';
import '../../core/models/dashboard.dart';
import 'research_data.dart';

class ResearchState extends Equatable {
  const ResearchState({this.filters = const ResearchFilters(), this.pinned, this.export});

  final ResearchFilters filters;

  /// The placement just saved to the home dashboard, for the "Pinned" pill and its undo.
  final WidgetPlacement? pinned;

  /// The last export, for the "file.csv · Download" pill.
  final CsvExport? export;

  @override
  List<Object?> get props => [filters, pinned, export];
}

/// Explore: the filters and the two confirmations. The numbers load through QueryView.
class ResearchCubit extends Cubit<ResearchState> {
  ResearchCubit() : super(const ResearchState());

  /// A new filter clears the confirmations, which belonged to the old view.
  void setFilters(ResearchFilters f) => emit(ResearchState(filters: f));

  void pinned(WidgetPlacement? p) =>
      emit(ResearchState(filters: state.filters, pinned: p, export: state.export));

  void exported(CsvExport e) =>
      emit(ResearchState(filters: state.filters, pinned: state.pinned, export: e));
}

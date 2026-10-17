import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';

/// The inbox filter chips. Data quality has no alert type in the backend yet, so it shows an
/// empty inbox until one exists.
enum AlertFilter {
  all('All', 'All', null),
  clusters('Clusters', 'Clusters', AlertType.statistical),
  rareFinds('Single rare finds', 'Rare finds', AlertType.sentinel),
  trends('Slow trends', 'Trends', AlertType.trend),
  missingData('Missing data', 'Missing data', AlertType.missingData),
  dataQuality('Data quality', null, null);

  const AlertFilter(this.label, this.shortLabel, this.type);

  final String label;

  /// Phone chip label; null hides the chip on a phone.
  final String? shortLabel;
  final AlertType? type;

  bool matches(Alert a) => switch (this) {
    AlertFilter.all => true,
    AlertFilter.dataQuality => false,
    _ => a.type == type,
  };
}

class LabState extends Equatable {
  const LabState({this.filter = AlertFilter.all, this.selected, this.reviewed = const {}});

  final AlertFilter filter;

  /// The alert open on the right (desktop); null means the first in the list.
  final String? selected;

  /// Alerts marked as reviewed in this session.
  final Set<String> reviewed;

  @override
  List<Object?> get props => [filter, selected, reviewed];
}

/// Inbox filter, selection and "mark as reviewed". Reviewing is local for now: the backend
/// has no acknowledge endpoint yet.
class LabCubit extends Cubit<LabState> {
  LabCubit({String? selected}) : super(LabState(selected: selected));

  void setFilter(AlertFilter f) =>
      emit(LabState(filter: f, selected: state.selected, reviewed: state.reviewed));

  void select(String id) =>
      emit(LabState(filter: state.filter, selected: id, reviewed: state.reviewed));

  void toggleReviewed(String id) {
    final reviewed = {...state.reviewed};
    if (!reviewed.remove(id)) reviewed.add(id);
    emit(LabState(filter: state.filter, selected: state.selected, reviewed: reviewed));
  }
}

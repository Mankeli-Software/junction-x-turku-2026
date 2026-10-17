import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/dashboard.dart';
import '../../core/repository.dart';
import '../../session/demo_users.dart';

class DashboardState extends Equatable {
  const DashboardState({this.dashboard, this.loading = false, this.error});

  final Dashboard? dashboard;
  final bool loading;
  final Object? error;

  List<WidgetPlacement> get layout => dashboard?.layout ?? const [];

  @override
  List<Object?> get props => [dashboard, loading, error];
}

/// The signed-in user's pinned widgets (`GET/PUT /v1/dashboard`). Changes show at once and
/// are saved in the background; a failed save rolls back.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repo, this._user) : super(const DashboardState(loading: true));

  final AmrRepository _repo;
  final DemoUser _user;

  Future<void> load() async {
    try {
      final d = await _repo.dashboard(_user.id);
      // A new user gets the backend's default layout with its own role.
      emit(DashboardState(dashboard: d));
    } catch (e) {
      emit(DashboardState(error: e));
    }
  }

  Future<bool> pin(WidgetPlacement p) {
    if (state.layout.contains(p)) return Future.value(true);
    return _save([...state.layout, p]);
  }

  Future<bool> unpin(WidgetPlacement p) => _save([...state.layout]..remove(p));

  Future<bool> move(int from, int to) {
    final layout = [...state.layout];
    layout.insert(to, layout.removeAt(from));
    return _save(layout);
  }

  Future<bool> _save(List<WidgetPlacement> layout) async {
    final before = state.dashboard;
    final next = (before ?? _empty).copyWith(layout: layout);
    emit(DashboardState(dashboard: next));
    try {
      emit(DashboardState(dashboard: await _repo.saveDashboard(next)));
      return true;
    } catch (e) {
      emit(DashboardState(dashboard: before, error: e));
      return false;
    }
  }

  Dashboard get _empty => Dashboard(userId: _user.id, role: _user.role, layout: const []);
}

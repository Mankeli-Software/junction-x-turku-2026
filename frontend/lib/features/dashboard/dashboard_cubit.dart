import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/dashboard.dart';
import '../../core/repository.dart';
import '../../session/demo_users.dart';

class DashboardState extends Equatable {
  const DashboardState({this.dashboard, this.loading = false, this.error, this.added});

  final Dashboard? dashboard;
  final bool loading;
  final Object? error;

  /// The placement added or changed last, so its card can say so once.
  final WidgetPlacement? added;

  List<WidgetPlacement> get layout => dashboard?.layout ?? const [];

  @override
  List<Object?> get props => [dashboard, loading, error, added];
}

/// The signed-in user's pinned widgets (`GET/PUT/DELETE /v1/dashboard`). A user with nothing
/// saved gets the default for their role and ward. Changes show at once and are saved in the
/// background; a failed save rolls back.
class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit(this._repo, this._user) : super(const DashboardState(loading: true));

  final AmrRepository _repo;
  final DemoUser _user;

  Future<void> load() async {
    try {
      emit(
        DashboardState(
          dashboard: await _repo.dashboard(_user.id, role: _user.role, ward: _user.ward),
        ),
      );
    } catch (e) {
      emit(DashboardState(error: e));
    }
  }

  /// Back to the default layout for the user's role and ward.
  Future<bool> reset() async {
    final before = state.dashboard;
    emit(DashboardState(dashboard: before, loading: true));
    try {
      emit(
        DashboardState(
          dashboard: await _repo.resetDashboard(_user.id, role: _user.role, ward: _user.ward),
        ),
      );
      return true;
    } catch (e) {
      emit(DashboardState(dashboard: before, error: e));
      return false;
    }
  }

  Future<bool> pin(WidgetPlacement p) {
    if (state.layout.contains(p)) return Future.value(true);
    return _save([...state.layout, p], added: p);
  }

  Future<bool> unpin(WidgetPlacement p) => _save([...state.layout]..remove(p));

  /// Puts [next] where [old] was (its settings were edited).
  Future<bool> replace(WidgetPlacement old, WidgetPlacement next) {
    final i = state.layout.indexOf(old);
    if (i < 0 || old == next) return Future.value(i >= 0);
    final layout = [...state.layout]..[i] = next;
    // The same widget with the same settings twice is one card.
    return _save([
      for (final (j, p) in layout.indexed)
        if (j == i || p != next) p,
    ], added: next);
  }

  Future<bool> move(int from, int to) {
    if (from == to || to < 0 || to >= state.layout.length) return Future.value(true);
    final layout = [...state.layout];
    layout.insert(to, layout.removeAt(from));
    return _save(layout);
  }

  Future<bool> _save(List<WidgetPlacement> layout, {WidgetPlacement? added}) async {
    final before = state.dashboard;
    final next = (before ?? _empty).copyWith(layout: layout);
    emit(DashboardState(dashboard: next, added: added));
    try {
      emit(DashboardState(dashboard: await _repo.saveDashboard(next), added: added));
      return true;
    } catch (e) {
      emit(DashboardState(dashboard: before, error: e));
      return false;
    }
  }

  Dashboard get _empty => Dashboard(userId: _user.id, role: _user.role, layout: const []);
}

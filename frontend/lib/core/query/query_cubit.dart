import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The state of one backend read. Keeps the last [data] while a new request runs, so a
/// changed filter or replay date updates in place instead of flashing a spinner.
class QueryState<T> extends Equatable {
  const QueryState({this.data, this.error, this.loading = false});

  final T? data;
  final Object? error;
  final bool loading;

  bool get hasData => data != null;

  @override
  List<Object?> get props => [data, error, loading];
}

class QueryCubit<T> extends Cubit<QueryState<T>> {
  QueryCubit() : super(QueryState<T>());

  int _seq = 0;

  /// Runs [fetch]; only the latest call may emit, so fast slider moves never show stale data.
  Future<void> load(Future<T> Function() fetch) async {
    final seq = ++_seq;
    emit(QueryState(data: state.data, loading: true));
    try {
      final data = await fetch();
      if (seq == _seq && !isClosed) emit(QueryState(data: data));
    } catch (e) {
      if (seq == _seq && !isClosed) emit(QueryState(data: state.data, error: e));
    }
  }
}

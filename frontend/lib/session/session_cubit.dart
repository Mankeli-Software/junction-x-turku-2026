import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/common.dart';
import '../core/models/vocab.dart';
import 'demo_users.dart';

/// Who is using the app and the replay date every query is stamped with.
class SessionState extends Equatable {
  const SessionState({this.user, required this.asOf});

  final DemoUser? user;

  /// The replay slider: nothing after this date may influence a number.
  final DateTime asOf;

  bool get signedIn => user != null;
  bool get isLive => asOf == dataEnd;

  SessionState copyWith({DemoUser? user, bool clearUser = false, DateTime? asOf}) =>
      SessionState(user: clearUser ? null : (user ?? this.user), asOf: asOf ?? this.asOf);

  @override
  List<Object?> get props => [user, asOf];
}

/// Remembers the picked profile and replay date across reloads.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._prefs, SessionState initial) : super(initial);

  static const _userKey = 'session.user';
  static const _asOfKey = 'session.as_of';

  final SharedPreferences _prefs;

  /// Where per-user state (the chat history) is kept between reloads.
  SharedPreferences get prefs => _prefs;

  static Future<SessionCubit> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final asOf = DateTime.tryParse(prefs.getString(_asOfKey) ?? '');
    return SessionCubit(
      prefs,
      SessionState(
        user: demoUserById(prefs.getString(_userKey)),
        asOf: asOf != null ? DateTime.utc(asOf.year, asOf.month, asOf.day) : dataEnd,
      ),
    );
  }

  void signIn(DemoUser user) {
    _prefs.setString(_userKey, user.id);
    emit(state.copyWith(user: user));
  }

  void signOut() {
    _prefs.remove(_userKey);
    emit(state.copyWith(clearUser: true));
  }

  /// Clamped to the data range.
  void setAsOf(DateTime date) {
    final d = DateTime.utc(date.year, date.month, date.day);
    final clamped = d.isBefore(dataStart) ? dataStart : (d.isAfter(dataEnd) ? dataEnd : d);
    _prefs.setString(_asOfKey, formatDate(clamped));
    emit(state.copyWith(asOf: clamped));
  }
}

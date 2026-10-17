import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';
import '../../session/session_cubit.dart';
import 'agent/chat_agent.dart';
import 'chat_models.dart';

class ChatState extends Equatable {
  const ChatState({this.entries = const [], this.aiUnavailable = false});

  final List<ChatEntry> entries;

  /// The agent answered 503 or failed: show the quick-form fallback, keep the numbers working.
  final bool aiUnavailable;

  bool get busy => entries.whereType<AnswerEntry>().any((a) => a.streaming);

  AnswerEntry? get lastAnswer => entries.whereType<AnswerEntry>().lastOrNull;

  /// The patient of the conversation: the most recent answer about one.
  PatientProfile? get profile =>
      entries.whereType<AnswerEntry>().map((a) => a.profile).nonNulls.lastOrNull;

  @override
  List<Object?> get props => [entries, aiUnavailable];
}

/// One conversation per signed-in user. Sends questions to the [ChatAgent] and folds its
/// streamed events into the last answer.
class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._agent, this._session) : super(const ChatState());

  final ChatAgent _agent;
  final SessionCubit _session;
  StreamSubscription<AgentEvent>? _sub;
  int _nextId = 0;

  Future<void> send(String text, {bool short = false}) async {
    final user = _session.state.user;
    if (user == null || text.trim().isEmpty || state.busy) return;
    final context = ChatContext(user: user, asOf: _session.state.asOf, profile: state.profile);
    final answerId = _nextId + 1;
    _nextId += 2;
    emit(
      ChatState(
        entries: [
          ...state.entries,
          UserEntry(answerId - 1, text.trim(), short: short),
          AnswerEntry(answerId),
        ],
        aiUnavailable: state.aiUnavailable,
      ),
    );
    unawaited(_sub?.cancel()); // the previous answer is finished or being replaced
    final done = Completer<void>();
    _sub = _agent
        .answer(text.trim(), context)
        .listen(
          (e) => _apply(answerId, e),
          onError: (Object _) => _apply(answerId, const AgentUnavailable()),
          onDone: () {
            _update(answerId, (a) => a.copyWith(streaming: false, clearStatus: true));
            done.complete();
          },
        );
    return done.future;
  }

  /// A tapped answer to a clarifying question: mark it chosen, then send it.
  Future<void> choose(int answerId, ClarifyPart part, String option) {
    _update(
      answerId,
      (a) => a.copyWith(
        parts: [for (final p in a.parts) identical(p, part) ? part.choose(option) : p],
      ),
    );
    return send(option, short: true);
  }

  /// A chip changed on "Selected patient": the same widgets re-query; no agent call.
  void changePatient(int answerId, PatientProfile profile) {
    const keys = {'ward', 'infection_type', 'specimen', 'sex', 'age_band', 'onset'};
    _update(
      answerId,
      (a) => a.copyWith(
        profile: profile,
        parts: [
          for (final p in a.parts)
            if (p is WidgetPart && p.placement.params.keys.any(keys.contains))
              WidgetPart(
                WidgetPlacement(
                  widget: p.placement.widget,
                  params: {
                    for (final e in p.placement.params.entries)
                      if (!keys.contains(e.key)) e.key: e.value,
                    ...profile.toQuery(),
                  },
                ),
              )
            else
              p,
        ],
      ),
    );
  }

  void stop() {
    _sub?.cancel();
    final a = state.lastAnswer;
    if (a != null) _update(a.id, (x) => x.copyWith(streaming: false, clearStatus: true));
  }

  void clear() {
    _sub?.cancel();
    emit(ChatState(aiUnavailable: state.aiUnavailable));
  }

  void _apply(int id, AgentEvent e) {
    switch (e) {
      case AgentHeader(:final builtFrom, :final note, :final profile):
        _update(id, (a) => a.copyWith(builtFrom: builtFrom, note: note, profile: profile));
      case AgentStatus(:final text):
        _update(id, (a) => a.copyWith(status: text));
      case AgentPart(:final part):
        _update(id, (a) => a.copyWith(parts: [...a.parts, part]));
      case AgentActions(:final actions, :final suggestions):
        _update(id, (a) => a.copyWith(actions: actions, suggestions: suggestions));
      case AgentUnavailable():
        emit(
          ChatState(
            entries: [
              for (final x in state.entries)
                if (x.id != id) x,
            ],
            aiUnavailable: true,
          ),
        );
        _sub?.cancel();
    }
  }

  void _update(int id, AnswerEntry Function(AnswerEntry) f) {
    if (isClosed) return;
    emit(
      ChatState(
        entries: [for (final e in state.entries) e is AnswerEntry && e.id == id ? f(e) : e],
        aiUnavailable: state.aiUnavailable,
      ),
    );
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

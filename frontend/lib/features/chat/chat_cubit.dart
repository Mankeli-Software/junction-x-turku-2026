import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';
import '../../session/session_cubit.dart';
import 'agent/chat_agent.dart';
import 'chat_models.dart';

class ChatState extends Equatable {
  const ChatState({
    required this.currentId,
    required this.updatedAt,
    this.entries = const [],
    this.history = const [],
    this.aiUnavailable = false,
  });

  /// The open conversation.
  final String currentId;
  final List<ChatEntry> entries;
  final DateTime updatedAt;

  /// The other conversations, newest first.
  final List<Conversation> history;

  /// The agent answered 503 or failed: show the quick-form fallback, keep the numbers working.
  final bool aiUnavailable;

  bool get busy => entries.whereType<AnswerEntry>().any((a) => a.streaming);

  AnswerEntry? get lastAnswer => entries.whereType<AnswerEntry>().lastOrNull;

  /// The patient of the conversation: the most recent answer about one.
  PatientProfile? get profile =>
      entries.whereType<AnswerEntry>().map((a) => a.profile).nonNulls.lastOrNull;

  /// Every conversation with something in it, the open one included, newest first.
  List<Conversation> get chats => [
    if (entries.isNotEmpty) Conversation(id: currentId, entries: entries, updatedAt: updatedAt),
    ...history,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  ChatState copyWith({
    String? currentId,
    List<ChatEntry>? entries,
    DateTime? updatedAt,
    List<Conversation>? history,
    bool? aiUnavailable,
  }) => ChatState(
    currentId: currentId ?? this.currentId,
    entries: entries ?? this.entries,
    updatedAt: updatedAt ?? this.updatedAt,
    history: history ?? this.history,
    aiUnavailable: aiUnavailable ?? this.aiUnavailable,
  );

  @override
  List<Object?> get props => [currentId, entries, updatedAt, history, aiUnavailable];
}

/// The signed-in user's conversations: the open one and the history, kept in the browser
/// between reloads. Sends questions to a [ChatAgent] (a fresh one per conversation) and folds
/// its streamed events into the last answer.
class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._newAgent, this._session)
    : super(ChatState(currentId: _newId(), updatedAt: DateTime.now())) {
    _restore();
  }

  /// At most this many conversations are kept.
  static const maxChats = 30;

  final ChatAgent Function() _newAgent;
  final SessionCubit _session;
  late ChatAgent _agent = _newAgent();
  StreamSubscription<AgentEvent>? _sub;
  int _nextId = 0;

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String get _key => 'chat.history.${_session.state.user?.id}';

  /// Starts an empty conversation; the open one moves to the history. Every ask field outside
  /// the chat starts one, so a question from the home screen never lands in an old thread.
  void newChat() {
    if (state.entries.isEmpty) return;
    stop();
    _agent = _newAgent();
    _nextId = 0;
    emit(
      ChatState(
        currentId: _newId(),
        updatedAt: DateTime.now(),
        history: state.chats,
        aiUnavailable: state.aiUnavailable,
      ),
    );
    _save();
  }

  /// Opens a conversation from the history.
  void open(String id) {
    if (id == state.currentId) return;
    final chat = state.history.where((c) => c.id == id).firstOrNull;
    if (chat == null) return;
    stop();
    _agent = _newAgent();
    _nextId = _after(chat.entries);
    emit(
      ChatState(
        currentId: chat.id,
        entries: chat.entries,
        updatedAt: chat.updatedAt,
        history: [
          for (final c in state.chats)
            if (c.id != id) c,
        ],
        aiUnavailable: state.aiUnavailable,
      ),
    );
    _save();
  }

  /// Removes a conversation; deleting the open one leaves an empty chat.
  void delete(String id) {
    if (id == state.currentId) {
      stop();
      _agent = _newAgent();
      _nextId = 0;
      emit(
        ChatState(
          currentId: _newId(),
          updatedAt: DateTime.now(),
          history: state.history,
          aiUnavailable: state.aiUnavailable,
        ),
      );
    } else {
      emit(
        state.copyWith(
          history: [
            for (final c in state.history)
              if (c.id != id) c,
          ],
        ),
      );
    }
    _save();
  }

  /// Asks [text]; [patient] (a question from an answer page) replaces the patient of the
  /// conversation so far.
  Future<void> send(String text, {bool short = false, PatientProfile? patient}) async {
    final user = _session.state.user;
    if (user == null || text.trim().isEmpty || state.busy) return;
    final context = ChatContext(
      user: user,
      asOf: _session.state.asOf,
      profile: patient ?? state.profile,
    );
    final answerId = _nextId + 1;
    _nextId += 2;
    emit(
      state.copyWith(
        entries: [
          ...state.entries,
          UserEntry(answerId - 1, text.trim(), short: short),
          AnswerEntry(answerId),
        ],
        updatedAt: DateTime.now(),
      ),
    );
    _save();
    unawaited(_sub?.cancel()); // the previous answer is finished or being replaced
    final done = Completer<void>();
    _sub = _agent
        .answer(text.trim(), context)
        .listen(
          (e) => _apply(answerId, e),
          onError: (Object _) => _apply(answerId, const AgentUnavailable()),
          onDone: () {
            _update(answerId, (a) => a.copyWith(streaming: false, clearStatus: true));
            _save();
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
    _save();
  }

  void stop() {
    _sub?.cancel();
    final a = state.lastAnswer;
    if (a != null) _update(a.id, (x) => x.copyWith(streaming: false, clearStatus: true));
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
          state.copyWith(
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
      state.copyWith(
        entries: [for (final e in state.entries) e is AnswerEntry && e.id == id ? f(e) : e],
      ),
    );
  }

  /// The next free entry id after [entries].
  static int _after(List<ChatEntry> entries) => entries.fold(-1, (m, e) => math.max(m, e.id)) + 1;

  /// Brings back the saved conversations and reopens the one that was open.
  void _restore() {
    final raw = _session.prefs.getString(_key);
    if (raw == null) return;
    try {
      final saved = jsonDecode(raw) as Json;
      final chats = jsonList(saved['chats']).map(Conversation.fromJson).toList();
      final open = chats.where((c) => c.id == saved['current']).firstOrNull;
      _nextId = open == null ? 0 : _after(open.entries);
      emit(
        state.copyWith(
          currentId: open?.id,
          entries: open?.entries,
          updatedAt: open?.updatedAt,
          history: [
            for (final c in chats)
              if (c != open) c,
          ],
        ),
      );
    } on Object {
      _session.prefs.remove(_key); // an unreadable save starts afresh
    }
  }

  void _save() {
    if (isClosed || _session.state.user == null) return;
    _session.prefs.setString(
      _key,
      jsonEncode({
        'current': state.currentId,
        'chats': [for (final c in state.chats.take(maxChats)) c.toJson()],
      }),
    );
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

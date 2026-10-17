import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:a2ui_core/a2ui_core.dart' as a2ui;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:genui/genui.dart' show Catalog, SurfaceController;

import '../../core/models/common.dart';
import '../../session/session_cubit.dart';
import 'agent/answer_surface.dart';
import 'agent/chat_agent.dart';
import 'answer_catalog.dart';
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

  /// The AI is switched off (no API key, or the key was rejected): show the quick-form fallback,
  /// keep the numbers working. A failed or slow answer never sets it; that answer shows an error.
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
///
/// Each answer is an A2UI surface: the agent's messages go to [surfaces] (genui's
/// [SurfaceController]), which the chat renders with genui's `Surface`, and the components are
/// kept on the [AnswerEntry] so a saved conversation can be shown again.
class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._newAgent, this._session, {required Catalog catalog})
    : surfaces = SurfaceController(catalogs: [catalog]),
      super(ChatState(currentId: _newId(), updatedAt: DateTime.now())) {
    _restore();
  }

  /// The open conversation's answer surfaces.
  final SurfaceController surfaces;

  /// At most this many conversations are kept.
  static const maxChats = 30;

  final ChatAgent Function() _newAgent;
  final SessionCubit _session;
  late ChatAgent _agent = _newAgent();
  StreamSubscription<AgentEvent>? _sub;
  Completer<void>? _done;
  int _nextId = 0;

  /// Sends the question the AI being off swallowed again, for [retry].
  Future<void> Function()? _again;

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String get _key => 'chat.history.${_session.state.user?.id}';

  /// Starts an empty conversation; the open one moves to the history. Every ask field outside
  /// the chat starts one, so a question from the home screen never lands in an old thread.
  void newChat() {
    if (state.entries.isEmpty) return;
    stop();
    _unmount(state.entries);
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
    _unmount(state.entries);
    _agent = _newAgent();
    _nextId = _after(chat.entries);
    emit(
      ChatState(
        currentId: chat.id,
        entries: _mount(chat.entries),
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
      _unmount(state.entries);
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
    _again = () => send(text, short: short, patient: patient);
    final context = ChatContext(
      user: user,
      asOf: _session.state.asOf,
      profile: patient ?? state.profile,
      history: _history(),
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
    _finish();
    final done = _done = Completer<void>();
    _sub = _agent
        .answer(text.trim(), context)
        .listen(
          (e) => _apply(answerId, e),
          // A broken stream fails this answer only; the composer comes back for the next one.
          onError: (Object _) => _update(
            answerId,
            (a) => a.copyWith(
              error: a.error ?? 'The answer stopped part-way. Try again.',
              streaming: false,
              clearStatus: true,
            ),
          ),
          onDone: () {
            _update(answerId, (a) => a.copyWith(streaming: false, clearStatus: true));
            _save();
            _finish();
          },
        );
    return done.future;
  }

  /// Completes the open [send] (it ends with the stream, or when the answer is stopped).
  void _finish() {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// "Try again" on the AI-unavailable panel: the composer comes back and the question that
  /// found the AI off is asked again.
  Future<void> retry() {
    final again = _again;
    final entries = state.entries;
    emit(
      state.copyWith(
        // The unanswered question is asked again below, so it is not shown twice.
        entries: again != null && entries.lastOrNull is UserEntry
            ? entries.sublist(0, entries.length - 1)
            : null,
        aiUnavailable: false,
      ),
    );
    _again = null;
    return again?.call() ?? Future.value();
  }

  /// The conversation so far for the agent, oldest first: the last [maxHistory] turns, each
  /// cut to what the backend accepts.
  List<(String, String)> _history() {
    final turns = [
      for (final e in state.entries)
        switch (e) {
          UserEntry(:final text) => ('user', text),
          final AnswerEntry a => ('assistant', a.describe()),
        },
    ];
    return [
      for (final (role, text) in turns.skip(math.max(0, turns.length - maxHistory)))
        (role, text.length > 1500 ? text.substring(0, 1500) : text),
    ];
  }

  /// How many earlier turns go with a question (the backend takes at most 24).
  static const maxHistory = 12;

  /// A tapped answer to a clarifying question (component [componentId]): mark it chosen on the
  /// surface, then send it.
  Future<void> choose(int answerId, String componentId, String option) {
    if (state.busy) return Future.value(); // nothing is sent, so nothing is marked chosen
    _rewrite(answerId, (c) => c['id'] == componentId ? {...c, 'chosen': option} : null);
    return send(option, short: true);
  }

  /// Replaces the components [f] returns a new version of, on the surface and in the entry.
  void _rewrite(int answerId, Json? Function(Json component) f) {
    final a = state.entries.whereType<AnswerEntry>().where((e) => e.id == answerId).firstOrNull;
    final surfaceId = a?.surfaceId;
    if (a == null || surfaceId == null) return;
    final changed = <Json>[];
    final components = [
      for (final c in a.components)
        if (f(c) case final Json next) (changed..add(next)).last else c,
    ];
    if (changed.isEmpty) return;
    _handle(AnswerSurface.updateMessage(surfaceId, changed));
    _update(answerId, (x) => x.copyWith(components: components));
    _save();
  }

  /// A chip changed on "Selected patient": the same widgets re-query; no agent call.
  void changePatient(int answerId, PatientProfile profile) {
    const keys = {'ward', 'infection_type', 'specimen', 'sex', 'age_band', 'onset'};
    const own = {'id', 'component', AnswerComponents.inShort, AnswerComponents.clarify};
    _update(answerId, (a) => a.copyWith(profile: profile));
    _rewrite(
      answerId,
      (c) => own.contains(c['component']) || !c.keys.any(keys.contains)
          ? null
          : {
              for (final e in c.entries)
                if (!keys.contains(e.key)) e.key: e.value,
              ...profile.toQuery(),
            },
    );
  }

  void stop() {
    _sub?.cancel();
    _again = null; // a question from this conversation is not retried in another
    final a = state.lastAnswer;
    if (a != null && a.streaming) {
      _update(a.id, (x) => x.copyWith(streaming: false, clearStatus: true));
      _save();
    }
    _finish();
  }

  void _apply(int id, AgentEvent e) {
    switch (e) {
      case AgentHeader(:final builtFrom, :final note, :final profile):
        _update(id, (a) => a.copyWith(builtFrom: builtFrom, note: note, profile: profile));
      case AgentStatus(:final text):
        _update(id, (a) => a.copyWith(status: text));
      case AgentSurface(:final message):
        _applySurface(id, message);
      case AgentError(:final message):
        _update(id, (a) => a.copyWith(error: message));
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
        _finish();
    }
  }

  /// Hands one A2UI message to the surfaces and keeps its components on answer [id].
  void _applySurface(int id, Json message) {
    final a2ui.A2uiMessage parsed;
    try {
      parsed = a2ui.A2uiMessage.fromJson(message);
    } on Object {
      return; // a malformed message is skipped; the rest of the answer still shows
    }
    switch (parsed) {
      case a2ui.CreateSurfaceMessage(:final surfaceId):
        if (surfaces.activeSurfaceIds.contains(surfaceId)) return;
        _handle(message);
        _update(id, (a) => a.copyWith(surfaceId: surfaceId));
      case a2ui.UpdateComponentsMessage(:final components):
        _handle(message);
        _update(id, (a) {
          final byId = {for (final c in a.components) c['id']: c};
          for (final c in components) {
            byId[c['id']] = Map<String, Object?>.from(c);
          }
          return a.copyWith(components: byId.values.toList());
        });
      default:
        _handle(message);
    }
  }

  void _handle(Json message) {
    if (isClosed) return;
    try {
      surfaces.handleMessage(a2ui.A2uiMessage.fromJson(message));
    } on Object {
      // genui reports what it cannot apply on its own error stream; the chat carries on.
    }
  }

  /// Puts the saved answers of [entries] back on surfaces; an answer saved before surfaces
  /// existed gets a new surface id.
  List<ChatEntry> _mount(List<ChatEntry> entries) => [
    for (final e in entries)
      if (e is AnswerEntry && e.components.isNotEmpty)
        () {
          final id = e.surfaceId ?? AnswerSurface().id;
          if (!surfaces.activeSurfaceIds.contains(id)) {
            _handle(AnswerSurface.createMessage(id));
            _handle(AnswerSurface.updateMessage(id, e.components));
          }
          return e.copyWith(surfaceId: id);
        }()
      else
        e,
  ];

  void _unmount(List<ChatEntry> entries) {
    for (final e in entries) {
      if (e case AnswerEntry(:final String surfaceId)) {
        _handle({
          'version': 'v0.9',
          'deleteSurface': {'surfaceId': surfaceId},
        });
      }
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
          entries: open == null ? null : _mount(open.entries),
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
    _finish();
    final done = super.close();
    surfaces.dispose();
    return done;
  }
}

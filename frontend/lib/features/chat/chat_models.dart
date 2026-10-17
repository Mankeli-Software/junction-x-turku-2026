import 'package:equatable/equatable.dart';

import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';
import 'answer_catalog.dart';

/// One piece of an answer, as the scripted agent builds it. On screen every part is an A2UI
/// component of the answer surface ([component]); the AI never sends numbers.
sealed class AnswerPart extends Equatable {
  const AnswerPart();

  /// A part saved by an earlier version of the app, which kept parts instead of components.
  factory AnswerPart.fromJson(Json j) => switch (j['t']) {
    'widget' => WidgetPart(WidgetPlacement.fromJson(j['placement']! as Json)),
    'clarify' => ClarifyPart(
      j['question']! as String,
      (j['options']! as List).cast<String>(),
      chosen: j['chosen'] as String?,
    ),
    _ => InShortPart(j['text'] as String?),
  };

  /// (A2UI component name, properties).
  (String, Json) get component => switch (this) {
    WidgetPart(:final placement) => (placement.widget, placement.params),
    InShortPart(:final text) => (AnswerComponents.inShort, {'text': ?text}),
    ClarifyPart(:final question, :final options, :final chosen) => (
      AnswerComponents.clarify,
      {'question': question, 'options': options, 'chosen': ?chosen},
    ),
  };
}

/// A catalog widget; it loads its own numbers.
class WidgetPart extends AnswerPart {
  const WidgetPart(this.placement);

  final WidgetPlacement placement;

  @override
  List<Object?> get props => [placement];
}

/// "In short": the only free text the AI writes. Null text shows the placeholder.
class InShortPart extends AnswerPart {
  const InShortPart(this.text);

  final String? text;

  @override
  List<Object?> get props => [text];
}

/// A question back with tappable answers, the likeliest first; none is chosen until tapped.
class ClarifyPart extends AnswerPart {
  const ClarifyPart(this.question, this.options, {this.chosen});

  final String question;
  final List<String> options;
  final String? chosen;

  @override
  List<Object?> get props => [question, options, chosen];
}

enum ChatActionKind { ask, openAnswer, pin, newPatient, navigate }

/// A follow-up under an answer. Works without the AI: asks a fixed question, opens a page, or
/// pins a widget.
class ChatAction extends Equatable {
  const ChatAction(this.label, this.kind, {this.primary = false, this.payload});

  const ChatAction.ask(this.label) : kind = ChatActionKind.ask, primary = false, payload = null;

  factory ChatAction.fromJson(Json j) {
    final kind = ChatActionKind.values.byName(j['kind']! as String);
    final p = j['payload'];
    return ChatAction(
      j['label']! as String,
      kind,
      primary: j['primary'] == true,
      payload: switch (kind) {
        ChatActionKind.openAnswer => PatientProfile.fromJson(p! as Json),
        ChatActionKind.pin => WidgetPlacement.fromJson(p! as Json),
        _ => p,
      },
    );
  }

  Json toJson() => {
    'label': label,
    'kind': kind.name,
    'primary': primary,
    'payload': switch (payload) {
      final PatientProfile p => p.toQuery(),
      final WidgetPlacement w => w.toJson(),
      final other => other,
    },
  };

  final String label;
  final ChatActionKind kind;
  final bool primary;

  /// [PatientProfile] for openAnswer, [WidgetPlacement] for pin, a path for navigate.
  final Object? payload;

  @override
  List<Object?> get props => [label, kind, primary, payload];
}

sealed class ChatEntry extends Equatable {
  const ChatEntry(this.id);

  /// A saved entry; an answer that was still building comes back finished.
  factory ChatEntry.fromJson(Json j) => j['t'] == 'user'
      ? UserEntry(j['id']! as int, j['text']! as String, short: j['short'] == true)
      : AnswerEntry(
          j['id']! as int,
          builtFrom: (j['builtFrom'] as List? ?? const []).cast<String>(),
          note: j['note'] as String?,
          surfaceId: j['surfaceId'] as String?,
          components: j.containsKey('components')
              ? jsonList(j['components'])
              : _legacyComponents(jsonList(j['parts']).map(AnswerPart.fromJson)),
          error: j['error'] as String?,
          actions: jsonList(j['actions']).map(ChatAction.fromJson).toList(),
          suggestions: (j['suggestions'] as List? ?? const []).cast<String>(),
          streaming: false,
          profile: j['profile'] == null ? null : PatientProfile.fromJson(j['profile']! as Json),
        );

  final int id;

  /// Parts from an older save as A2UI components (the root last), shown on a new surface.
  static List<Json> _legacyComponents(Iterable<AnswerPart> parts) {
    final ids = <String>[];
    return [
      for (final (i, p) in parts.indexed)
        {...p.component.$2, 'id': (ids..add('p${i + 1}')).last, 'component': p.component.$1},
      if (ids.isNotEmpty)
        {'id': AnswerComponents.rootId, 'component': AnswerComponents.root, 'children': ids},
    ];
  }

  Json toJson() => switch (this) {
    UserEntry(:final text, :final short) => {'t': 'user', 'id': id, 'text': text, 'short': short},
    final AnswerEntry a => {
      't': 'answer',
      'id': id,
      'builtFrom': a.builtFrom,
      'note': a.note,
      'surfaceId': a.surfaceId,
      'components': a.components,
      'error': a.error,
      'actions': [for (final x in a.actions) x.toJson()],
      'suggestions': a.suggestions,
      'profile': a.profile?.toQuery(),
    },
  };
}

class UserEntry extends ChatEntry {
  const UserEntry(super.id, this.text, {this.short = false});

  final String text;

  /// A tapped choice rather than a typed question: drawn smaller.
  final bool short;

  @override
  List<Object?> get props => [id, text, short];
}

class AnswerEntry extends ChatEntry {
  const AnswerEntry(
    super.id, {
    this.builtFrom = const [],
    this.note,
    this.status,
    this.surfaceId,
    this.components = const [],
    this.error,
    this.actions = const [],
    this.suggestions = const [],
    this.streaming = true,
    this.profile,
  });

  /// Tools used ("coverage", "organism mix"), shown as "Built from".
  final List<String> builtFrom;

  /// Replaces "Built from" ("Same patient, penicillins hidden").
  final String? note;

  /// While building: "checking coverage on Urology…".
  final String? status;

  /// The A2UI surface that shows the answer; null until its first part arrives.
  final String? surfaceId;

  /// The surface's components, the root included: what is saved, and what rebuilds the surface
  /// when the conversation is opened again.
  final List<Json> components;

  /// Why the answer stopped early (a refusal, a timeout); the parts so far stay.
  final String? error;
  final List<ChatAction> actions;

  /// Next questions for the composer.
  final List<String> suggestions;
  final bool streaming;

  /// The patient this answer is about, when it is about one.
  final PatientProfile? profile;

  AnswerEntry copyWith({
    List<String>? builtFrom,
    String? note,
    String? status,
    bool clearStatus = false,
    String? surfaceId,
    List<Json>? components,
    String? error,
    List<ChatAction>? actions,
    List<String>? suggestions,
    bool? streaming,
    PatientProfile? profile,
  }) => AnswerEntry(
    id,
    builtFrom: builtFrom ?? this.builtFrom,
    note: note ?? this.note,
    status: clearStatus ? null : (status ?? this.status),
    surfaceId: surfaceId ?? this.surfaceId,
    components: components ?? this.components,
    error: error ?? this.error,
    actions: actions ?? this.actions,
    suggestions: suggestions ?? this.suggestions,
    streaming: streaming ?? this.streaming,
    profile: profile ?? this.profile,
  );

  /// The parts on the surface, in order (the root is not one).
  List<Json> get parts {
    final root = components.where((c) => c['id'] == AnswerComponents.rootId).firstOrNull;
    final byId = {for (final c in components) c['id']: c};
    return [
      for (final id in (root?['children'] as List? ?? const []))
        if (byId[id] case final Json c) c,
    ];
  }

  /// What this answer showed or asked, in words, for the agent's history of the conversation.
  String describe() {
    String params(Json c) => [
      for (final e in c.entries)
        if (!const {'id', 'component', 'as_of', 'window'}.contains(e.key)) '${e.key}=${e.value}',
    ].join(', ');
    final lines = [
      for (final c in parts)
        switch (c['component']) {
          AnswerComponents.clarify =>
            'Asked: ${c['question']} Options: ${(c['options'] as List? ?? const []).join(' | ')}'
                '${c['chosen'] == null ? '' : ' (chosen: ${c['chosen']})'}',
          AnswerComponents.inShort => 'In short: ${c['text'] ?? '(none)'}',
          final type => 'Showed $type(${params(c)})',
        },
      if (error != null) 'Stopped: $error',
    ];
    return lines.isEmpty ? '(no answer)' : lines.join('\n');
  }

  /// The catalog widgets on the surface, as placements (for pinning and follow-ups).
  List<WidgetPlacement> get widgets => [
    for (final c in parts)
      if (c['component'] case final String type
          when type != AnswerComponents.inShort && type != AnswerComponents.clarify)
        WidgetPlacement(
          widget: type,
          params: {
            for (final e in c.entries)
              if (e.key != 'id' && e.key != 'component') e.key: e.value,
          },
        ),
  ];

  @override
  List<Object?> get props => [
    id,
    builtFrom,
    note,
    status,
    surfaceId,
    components,
    error,
    actions,
    suggestions,
    streaming,
  ];
}

/// One chat in the history: its entries and when it last changed.
class Conversation extends Equatable {
  const Conversation({required this.id, required this.entries, required this.updatedAt});

  factory Conversation.fromJson(Json j) => Conversation(
    id: j['id']! as String,
    entries: jsonList(j['entries']).map(ChatEntry.fromJson).toList(),
    updatedAt: DateTime.parse(j['updatedAt']! as String),
  );

  final String id;
  final List<ChatEntry> entries;
  final DateTime updatedAt;

  /// The first question asked.
  String get title => entries.whereType<UserEntry>().firstOrNull?.text ?? 'New chat';

  Json toJson() => {
    'id': id,
    'entries': [for (final e in entries) e.toJson()],
    'updatedAt': updatedAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [id, entries, updatedAt];
}

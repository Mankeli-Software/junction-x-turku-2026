import 'package:equatable/equatable.dart';

import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';

/// One piece of an answer. Mirrors what an A2UI surface carries: catalog widgets by name and
/// params, the one free-text summary, and the interactive pieces. The AI never sends numbers.
sealed class AnswerPart extends Equatable {
  const AnswerPart();

  factory AnswerPart.fromJson(Json j) => switch (j['t']) {
    'widget' => WidgetPart(WidgetPlacement.fromJson(j['placement']! as Json)),
    'clarify' => ClarifyPart(
      j['question']! as String,
      (j['options']! as List).cast<String>(),
      chosen: j['chosen'] as String?,
    ),
    _ => InShortPart(j['text'] as String?),
  };

  Json toJson() => switch (this) {
    WidgetPart(:final placement) => {'t': 'widget', 'placement': placement.toJson()},
    InShortPart(:final text) => {'t': 'inShort', 'text': text},
    ClarifyPart(:final question, :final options, :final chosen) => {
      't': 'clarify',
      'question': question,
      'options': options,
      'chosen': chosen,
    },
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

/// A question back with tappable answers; the first option is the likely one.
class ClarifyPart extends AnswerPart {
  const ClarifyPart(this.question, this.options, {this.chosen});

  final String question;
  final List<String> options;
  final String? chosen;

  ClarifyPart choose(String option) => ClarifyPart(question, options, chosen: option);

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
          parts: jsonList(j['parts']).map(AnswerPart.fromJson).toList(),
          actions: jsonList(j['actions']).map(ChatAction.fromJson).toList(),
          suggestions: (j['suggestions'] as List? ?? const []).cast<String>(),
          streaming: false,
          profile: j['profile'] == null ? null : PatientProfile.fromJson(j['profile']! as Json),
        );

  final int id;

  Json toJson() => switch (this) {
    UserEntry(:final text, :final short) => {'t': 'user', 'id': id, 'text': text, 'short': short},
    final AnswerEntry a => {
      't': 'answer',
      'id': id,
      'builtFrom': a.builtFrom,
      'note': a.note,
      'parts': [for (final p in a.parts) p.toJson()],
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
    this.parts = const [],
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
  final List<AnswerPart> parts;
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
    List<AnswerPart>? parts,
    List<ChatAction>? actions,
    List<String>? suggestions,
    bool? streaming,
    PatientProfile? profile,
  }) => AnswerEntry(
    id,
    builtFrom: builtFrom ?? this.builtFrom,
    note: note ?? this.note,
    status: clearStatus ? null : (status ?? this.status),
    parts: parts ?? this.parts,
    actions: actions ?? this.actions,
    suggestions: suggestions ?? this.suggestions,
    streaming: streaming ?? this.streaming,
    profile: profile ?? this.profile,
  );

  @override
  List<Object?> get props => [id, builtFrom, note, status, parts, actions, suggestions, streaming];
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

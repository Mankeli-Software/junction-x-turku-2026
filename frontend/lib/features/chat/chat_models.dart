import 'package:equatable/equatable.dart';

import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';

/// One piece of an answer. Mirrors what an A2UI surface carries: catalog widgets by name and
/// params, the one free-text summary, and the interactive pieces. The AI never sends numbers.
sealed class AnswerPart extends Equatable {
  const AnswerPart();
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

  final int id;
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

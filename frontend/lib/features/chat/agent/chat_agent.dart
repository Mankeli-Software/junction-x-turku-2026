import '../../../core/models/common.dart';
import '../../../session/demo_users.dart';
import '../chat_models.dart';

/// What the agent knows besides the question: who asks, the replay date, the patient of the
/// conversation so far, and the conversation itself.
class ChatContext {
  const ChatContext({
    required this.user,
    required this.asOf,
    this.profile,
    this.history = const [],
  });

  final DemoUser user;
  final DateTime asOf;
  final PatientProfile? profile;

  /// Earlier turns, oldest first, as (role, text): `user` for a question, `assistant` for
  /// what an answer showed or asked. A short reply is read as the answer to the last question.
  final List<(String, String)> history;
}

/// Events streamed while an answer is built, in order: header, status, the answer's A2UI
/// messages, actions. The answer itself is an A2UI surface rendered by genui; the other events
/// are the chat's chrome around it (backend/app/agent/schema.py has the wire format).
sealed class AgentEvent {
  const AgentEvent();
}

class AgentHeader extends AgentEvent {
  const AgentHeader({this.builtFrom = const [], this.note, this.profile});

  final List<String> builtFrom;
  final String? note;
  final PatientProfile? profile;
}

class AgentStatus extends AgentEvent {
  const AgentStatus(this.text);

  final String text;
}

/// One A2UI v0.9 message for the answer's surface (createSurface, then updateComponents per
/// part), as JSON.
class AgentSurface extends AgentEvent {
  const AgentSurface(this.message);

  final Json message;
}

/// The answer could not be finished (a refusal, a timeout); what arrived so far stays.
class AgentError extends AgentEvent {
  const AgentError(this.message);

  final String message;
}

class AgentActions extends AgentEvent {
  const AgentActions(this.actions, {this.suggestions = const []});

  final List<ChatAction> actions;
  final List<String> suggestions;
}

/// The AI is off or failed (503, no key): the app falls back to the quick form.
class AgentUnavailable extends AgentEvent {
  const AgentUnavailable([this.message = 'AI answers are paused right now.']);

  final String message;
}

abstract interface class ChatAgent {
  Stream<AgentEvent> answer(String question, ChatContext context);
}

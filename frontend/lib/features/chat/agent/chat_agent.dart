import '../../../core/models/common.dart';
import '../../../session/demo_users.dart';
import '../chat_models.dart';

/// What the agent knows besides the question: who asks, the replay date, and the patient of
/// the conversation so far.
class ChatContext {
  const ChatContext({required this.user, required this.asOf, this.profile});

  final DemoUser user;
  final DateTime asOf;
  final PatientProfile? profile;
}

/// Events streamed while an answer is built, in order: header, status, parts, actions, done.
/// The remote agent maps A2UI messages from the backend (#12) onto these.
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

class AgentPart extends AgentEvent {
  const AgentPart(this.part);

  final AnswerPart part;
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

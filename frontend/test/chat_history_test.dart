import 'package:amiright/features/chat/agent/chat_agent.dart';
import 'package:amiright/features/chat/chat_cubit.dart';
import 'package:amiright/features/chat/chat_models.dart';
import 'package:amiright/session/session_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every question with one "In short".
class _EchoAgent implements ChatAgent {
  @override
  Stream<AgentEvent> answer(String question, ChatContext context) => Stream.fromIterable([
    const AgentHeader(),
    AgentPart(InShortPart('About: $question')),
    const AgentActions([]),
  ]);
}

void main() {
  late SessionCubit session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'flutter.session.user': 'aino'});
    session = await SessionCubit.restore();
  });

  ChatCubit cubit() => ChatCubit(_EchoAgent.new, session);

  List<String> questions(ChatState s) =>
      s.entries.whereType<UserEntry>().map((e) => e.text).toList();

  test('new chat moves the open one to the history; open and delete', () async {
    final chat = cubit();
    await chat.send('What is causing UTIs now?');
    await chat.send('Only oral options');
    final first = chat.state.currentId;

    chat.newChat();
    expect(chat.state.entries, isEmpty);
    expect(chat.state.history.single.title, 'What is causing UTIs now?');

    await chat.send('Is trimethoprim still OK?');
    expect(chat.state.chats.map((c) => c.title), [
      'Is trimethoprim still OK?',
      'What is causing UTIs now?',
    ]);

    chat.open(first);
    expect(questions(chat.state), ['What is causing UTIs now?', 'Only oral options']);
    expect(chat.state.history.single.title, 'Is trimethoprim still OK?');

    // Answers keep numbering after the reopened ones.
    await chat.send('Compare with the whole hospital');
    final ids = chat.state.entries.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);

    chat.delete(chat.state.history.single.id);
    expect(chat.state.history, isEmpty);
    chat.delete(first);
    expect(chat.state.chats, isEmpty);
  });

  test('the history comes back after a reload, with the open chat reopened', () async {
    final chat = cubit();
    await chat.send('What is causing UTIs now?');
    chat.newChat();
    await chat.send('Is trimethoprim still OK?');
    await chat.close();

    final again = cubit();
    expect(questions(again.state), ['Is trimethoprim still OK?']);
    final answer = again.state.lastAnswer!;
    expect(answer.streaming, isFalse);
    expect((answer.parts.single as InShortPart).text, 'About: Is trimethoprim still OK?');
    expect(again.state.history.single.title, 'What is causing UTIs now?');
  });
}

import 'dart:async';

import 'package:amiright/catalog/default_catalog.dart';
import 'package:amiright/features/chat/agent/answer_surface.dart';
import 'package:amiright/features/chat/agent/chat_agent.dart';
import 'package:amiright/features/chat/answer_catalog.dart';
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
    ...AnswerSurface().add(InShortPart('About: $question')),
    const AgentActions([]),
  ]);
}

void main() {
  late SessionCubit session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'flutter.session.user': 'aino'});
    session = await SessionCubit.restore();
  });

  ChatCubit cubit() =>
      ChatCubit(_EchoAgent.new, session, catalog: buildGenUiCatalog(buildCatalog()));

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
    expect(answer.parts.single['text'], 'About: Is trimethoprim still OK?');
    // The saved answer is back on a live surface.
    expect(again.surfaces.activeSurfaceIds, [answer.surfaceId]);
    expect(again.state.history.single.title, 'What is causing UTIs now?');
  });

  test('an answer saved as parts by the old app comes back as A2UI components', () {
    final entry =
        ChatEntry.fromJson({
              't': 'answer',
              'id': 1,
              'parts': [
                {
                  't': 'widget',
                  'placement': {
                    'widget': 'OrganismMix',
                    'params': {'ward': 'URO'},
                  },
                },
                {'t': 'inShort', 'text': 'E. coli leads.'},
              ],
            })
            as AnswerEntry;
    expect(entry.parts.map((c) => c['component']), ['OrganismMix', 'InShort']);
    expect(entry.widgets.single.params, {'ward': 'URO'});
  });

  test(
    'each question carries the conversation so far, so a short reply has its question',
    () async {
      final agent = _RecordingAgent();
      final chat = ChatCubit(() => agent, session, catalog: buildGenUiCatalog(buildCatalog()));
      await chat.send('my patient has an infection');
      final answer = chat.state.lastAnswer!;
      await chat.choose(answer.id, answer.parts.single['id']! as String, 'At home');
      expect(agent.contexts.first.history, isEmpty);
      expect(agent.contexts.last.history, [
        ('user', 'my patient has an infection'),
        (
          'assistant',
          'Asked: Where did it start? Options: At home | In hospital (chosen: At home)',
        ),
      ]);
    },
  );

  test('a chosen answer to a clarifying question is marked on the surface', () async {
    final chat = ChatCubit(_ClarifyAgent.new, session, catalog: buildGenUiCatalog(buildCatalog()));
    await chat.send('my patient has an infection');
    final first = chat.state.lastAnswer!;
    final clarify = first.parts.single;
    expect(clarify['component'], AnswerComponents.clarify);
    await chat.choose(first.id, clarify['id']! as String, 'At home');
    final marked = chat.state.entries.whereType<AnswerEntry>().first.parts.single;
    expect(marked['chosen'], 'At home');
    final definition = chat.surfaces.contextFor(first.surfaceId!).definition.value!;
    expect(definition.components[clarify['id']]!.properties['chosen'], 'At home');
    expect(chat.state.entries.whereType<UserEntry>().last.short, isTrue);
  });

  test('a broken stream fails that answer only: the next question can still be asked', () async {
    final chat = ChatCubit(_BrokenAgent.new, session, catalog: buildGenUiCatalog(buildCatalog()));
    await chat.send('first');
    expect(chat.state.busy, isFalse);
    expect(chat.state.aiUnavailable, isFalse);
    expect(chat.state.lastAnswer!.error, isNotNull);
    await chat.send('second');
    expect(questions(chat.state), ['first', 'second']);
  });

  test('Stop frees the composer and finishes the pending send', () async {
    final hanging = StreamController<AgentEvent>();
    final chat = ChatCubit(
      () => _StreamAgent(hanging.stream),
      session,
      catalog: buildGenUiCatalog(buildCatalog()),
    );
    final sent = chat.send('slow question');
    expect(chat.state.busy, isTrue);
    chat.stop();
    expect(chat.state.busy, isFalse);
    await sent.timeout(const Duration(seconds: 1));
    await hanging.close();
  });

  test('the AI switched off can be retried, and the swallowed question goes again', () async {
    final agent = _OffOnceAgent();
    final chat = ChatCubit(() => agent, session, catalog: buildGenUiCatalog(buildCatalog()));
    await chat.send('is trimethoprim OK?');
    expect(chat.state.aiUnavailable, isTrue);
    expect(questions(chat.state), ['is trimethoprim OK?']); // the question stays, unanswered
    await chat.retry();
    expect(chat.state.aiUnavailable, isFalse);
    expect(questions(chat.state), ['is trimethoprim OK?']);
    expect(chat.state.busy, isFalse);
  });

  test('a clarify option tapped while an answer is still coming is not marked chosen', () async {
    final hanging = StreamController<AgentEvent>();
    var first = true;
    final chat = ChatCubit(
      () => first ? _ClarifyAgent() : _StreamAgent(hanging.stream),
      session,
      catalog: buildGenUiCatalog(buildCatalog()),
    );
    await chat.send('my patient has an infection');
    final answer = chat.state.lastAnswer!;
    final clarify = answer.parts.single;
    first = false;
    chat.newChat(); // a fresh agent that never finishes
    chat.open(chat.state.history.first.id);
    unawaited(chat.send('something slow'));
    await chat.choose(answer.id, clarify['id']! as String, 'At home');
    expect(chat.state.entries.whereType<AnswerEntry>().first.parts.single['chosen'], isNull);
    chat.stop();
    await hanging.close();
  });
}

/// Starts an answer, then the connection breaks.
class _BrokenAgent implements ChatAgent {
  @override
  Stream<AgentEvent> answer(String question, ChatContext context) async* {
    yield const AgentHeader();
    throw StateError('connection reset');
  }
}

/// Answers with whatever [events] brings.
class _StreamAgent implements ChatAgent {
  _StreamAgent(this.events);

  final Stream<AgentEvent> events;

  @override
  Stream<AgentEvent> answer(String question, ChatContext context) => events;
}

/// Off for the first question, answering after that.
class _OffOnceAgent implements ChatAgent {
  var _calls = 0;

  @override
  Stream<AgentEvent> answer(String question, ChatContext context) => _calls++ == 0
      ? Stream.value(const AgentUnavailable())
      : _EchoAgent().answer(question, context);
}

/// Asks where the infection started.
class _ClarifyAgent implements ChatAgent {
  @override
  Stream<AgentEvent> answer(String question, ChatContext context) => Stream.fromIterable([
    const AgentHeader(),
    ...AnswerSurface().add(const ClarifyPart('Where did it start?', ['At home', 'In hospital'])),
    const AgentActions([]),
  ]);
}

/// Asks where the infection started, and remembers what it was sent.
class _RecordingAgent extends _ClarifyAgent {
  final contexts = <ChatContext>[];

  @override
  Stream<AgentEvent> answer(String question, ChatContext context) {
    contexts.add(context);
    return super.answer(question, context);
  }
}

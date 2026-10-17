import 'dart:async';
import 'dart:convert';

import 'package:amiright/core/models/common.dart';
import 'package:amiright/core/models/vocab.dart';
import 'package:amiright/features/chat/agent/chat_agent.dart';
import 'package:amiright/features/chat/agent/remote_agent.dart';
import 'package:amiright/features/chat/chat_models.dart';
import 'package:amiright/session/demo_users.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The stream the backend sends for the demo sentence (backend/app/agent/schema.py), in chunks
/// that split lines the way a network does.
const _surface = 'answer-1';
final _events = [
  (
    'header',
    {
      'built_from': <String>[],
      'note': null,
      'profile': {'ward': 'URO', 'sex': 'F'},
    },
  ),
  ('status', {'text': 'Checking antibiotic coverage…'}),
  (
    'a2ui',
    {
      'version': 'v0.9',
      'createSurface': {
        'surfaceId': _surface,
        'catalogId': 'https://amright.app/a2ui/v0_9/catalog.json',
      },
    },
  ),
  (
    'a2ui',
    {
      'version': 'v0.9',
      'updateComponents': {
        'surfaceId': _surface,
        'components': [
          {
            'id': 'p1',
            'component': 'CoverageRanking',
            'ward': 'URO',
            'infection_type': 'uti',
            'as_of': '2026-09-27',
          },
          {
            'id': 'root',
            'component': 'Answer',
            'children': ['p1'],
          },
        ],
      },
    },
  ),
  ('done', {'ok': true, 'usage': <String, int>{}}),
];

String _sse() =>
    [': ping\n\n', for (final (e, d) in _events) 'event: $e\ndata: ${jsonEncode(d)}\n\n'].join();

ChatContext _ctx() => ChatContext(
  user: demoUsers.firstWhere((u) => u.role == Role.doctor),
  asOf: DateTime(2026, 9, 27),
  profile: const PatientProfile(infectionType: InfectionType.uti),
  history: const [
    ('user', 'My patient has an infection'),
    ('assistant', 'Asked: Which infection? Options: Urinary tract | Sepsis'),
  ],
);

void main() {
  test('server-sent events are parsed across chunk boundaries, pings skipped', () async {
    final text = utf8.encode(_sse());
    final chunks = [
      for (var i = 0; i < text.length; i += 7) text.sublist(i, (i + 7).clamp(0, text.length)),
    ];
    final events = await parseSse(Stream.fromIterable(chunks)).toList();
    expect(events.map((e) => e.$1), ['header', 'status', 'a2ui', 'a2ui', 'done']);
  });

  test('the remote agent sends the context and maps the stream onto chat events', () async {
    late Map<String, Object?> sent;
    final agent = RemoteAgent(
      'http://api',
      client: MockClient.streaming((req, body) async {
        sent = jsonDecode(await body.bytesToString()) as Map<String, Object?>;
        expect(req.url.path, '/v1/agent/screen');
        return http.StreamedResponse(Stream.value(utf8.encode(_sse())), 200);
      }),
    );
    final events = await agent.answer('72-year-old woman, urology', _ctx()).toList();
    expect(sent['message'], '72-year-old woman, urology');
    expect(sent['as_of'], '2026-09-27');
    expect(sent['role'], 'doctor');
    expect(sent['profile'], {'infection_type': 'uti'});
    expect(sent['history'], [
      {'role': 'user', 'text': 'My patient has an infection'},
      {'role': 'assistant', 'text': 'Asked: Which infection? Options: Urinary tract | Sepsis'},
    ]);

    expect(events[0], isA<AgentHeader>());
    expect((events[0] as AgentHeader).profile?.ward, Ward.uro);
    expect(events[1], isA<AgentStatus>());
    expect(events.whereType<AgentSurface>().length, 2);
    final actions = events.last as AgentActions;
    final pin = actions.actions.firstWhere((a) => a.kind == ChatActionKind.pin);
    expect((pin.payload! as dynamic).params, {'ward': 'URO', 'infection_type': 'uti'}); // no as_of
    expect(actions.suggestions.first, 'She is allergic to penicillin');
  });

  test('503 means the AI is off: the app shows the quick form', () async {
    final agent = RemoteAgent(
      'http://api',
      client: MockClient((_) async => http.Response('{"detail":"no key"}', 503)),
    );
    expect(await agent.answer('hi', _ctx()).toList(), [isA<AgentUnavailable>()]);
  });

  test('429 says the limit was reached', () async {
    final agent = RemoteAgent(
      'http://api',
      client: MockClient((_) async => http.Response('{"detail":"slow down"}', 429)),
    );
    final events = await agent.answer('hi', _ctx()).toList();
    expect((events.single as AgentError).message, contains('Too many questions'));
  });

  test('an error event keeps the answer and says why it stopped', () async {
    final agent = RemoteAgent(
      'http://api',
      client: MockClient(
        (_) async => http.Response(
          'event: error\ndata: {"code":"timeout","message":"The AI took too long to answer."}\n\n'
          'event: done\ndata: {"ok":false}\n\n',
          200,
        ),
      ),
    );
    final events = await agent.answer('hi', _ctx()).toList();
    expect((events.first as AgentError).message, 'The AI took too long to answer.');
    expect(events.last, isA<AgentActions>());
  });

  test('a 503 from a restarting host is an error on the answer, not the AI switched off', () async {
    final agent = RemoteAgent(
      'http://api',
      client: MockClient((_) async => http.Response('<html>Service Unavailable</html>', 503)),
    );
    final events = await agent.answer('hi', _ctx()).toList();
    expect(events.single, isA<AgentError>());
  });

  test('an unreachable service is an error on the answer', () async {
    final agent = RemoteAgent(
      'http://api',
      client: MockClient((_) async => throw http.ClientException('connection refused')),
    );
    final events = await agent.answer('hi', _ctx()).toList();
    expect((events.single as AgentError).message, startsWith('Could not reach'));
  });

  test('a stream cut part-way keeps what arrived and says it stopped', () async {
    final head = utf8.encode('event: status\ndata: {"text":"Checking…"}\n\n');
    final agent = RemoteAgent(
      'http://api',
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(() async* {
          yield head;
          throw http.ClientException('reset');
        }(), 200),
      ),
    );
    final events = await agent.answer('hi', _ctx()).toList();
    expect(events.map((e) => e.runtimeType), [AgentStatus, AgentError, AgentActions]);
  });

  test('a connection that goes silent, pings and all, times out', () async {
    final silent = StreamController<List<int>>();
    final agent = RemoteAgent(
      'http://api',
      client: MockClient.streaming((_, _) async => http.StreamedResponse(silent.stream, 200)),
      idleTimeout: const Duration(milliseconds: 50),
    );
    final events = await agent.answer('hi', _ctx()).toList().timeout(const Duration(seconds: 2));
    expect((events.first as AgentError).message, contains('too long'));
    expect(events.last, isA<AgentActions>());
    await silent.close();
  });

  test('an answer past the total time stops even while pings keep coming', () async {
    final pings = Stream.periodic(
      const Duration(milliseconds: 10),
      (_) => utf8.encode(': ping\n\n'),
    );
    final agent = RemoteAgent(
      'http://api',
      client: MockClient.streaming((_, _) async => http.StreamedResponse(pings, 200)),
      totalTimeout: const Duration(milliseconds: 80),
    );
    final events = await agent.answer('hi', _ctx()).toList().timeout(const Duration(seconds: 2));
    expect((events.first as AgentError).message, contains('too long'));
  });
}

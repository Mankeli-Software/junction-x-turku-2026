import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/models/common.dart';
import '../../../core/models/dashboard.dart';
import '../../../core/models/vocab.dart';
import '../answer_catalog.dart';
import '../chat_models.dart';
import 'chat_agent.dart';

/// The Claude agent behind `POST /v1/agent/screen` (#12), read as server-sent events.
///
/// The answer arrives as A2UI messages (`a2ui` events) and goes to genui untouched; `header`,
/// `status` and `error` become the chat's own events. Follow-up actions and suggested questions
/// are not sent by the AI: they are built here from the widgets it placed ([followUps]).
class RemoteAgent implements ChatAgent {
  RemoteAgent(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Stream<AgentEvent> answer(String question, ChatContext ctx) async* {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(
            'POST',
            Uri.parse('$baseUrl/v1/agent/screen'),
            abortTrigger: abort.future,
          )
          ..headers.addAll({'content-type': 'application/json', 'accept': 'text/event-stream'})
          ..body = jsonEncode(requestBody(question, ctx));
    final components = <String, Json>{};
    PatientProfile? profile = ctx.profile;
    try {
      final http.StreamedResponse res;
      try {
        res = await _client.send(request);
      } on Object {
        yield const AgentUnavailable('Could not reach the AI service.');
        return;
      }
      if (res.statusCode == 503) {
        yield const AgentUnavailable();
        return;
      }
      if (res.statusCode == 429) {
        yield const AgentError('Too many questions from this network. Try again in a few minutes.');
        return;
      }
      if (res.statusCode != 200) {
        yield AgentError('The AI service answered ${res.statusCode}.');
        return;
      }
      await for (final (event, data) in parseSse(res.stream)) {
        switch (event) {
          case 'header':
            final p = data['profile'];
            if (p is Json) profile = PatientProfile.fromJson(p);
            yield AgentHeader(
              builtFrom: (data['built_from'] as List? ?? const []).cast<String>(),
              note: data['note'] as String?,
              profile: p is Json ? profile : null,
            );
          case 'status':
            yield AgentStatus(data['text'] as String? ?? '');
          case 'a2ui':
            for (final c in jsonList((data['updateComponents'] as Json?)?['components'])) {
              components[c['id']! as String] = c;
            }
            yield AgentSurface(data);
          case 'error':
            if (data['code'] == 'unavailable') {
              yield AgentUnavailable(data['message'] as String? ?? 'AI answers are paused.');
              return;
            }
            yield AgentError(data['message'] as String? ?? 'Something went wrong.');
          case 'done':
            yield followUps(_widgets(components), profile);
            return;
        }
      }
      yield followUps(_widgets(components), profile); // the stream ended without "done"
    } finally {
      if (!abort.isCompleted) abort.complete(); // stopped or left the chat: stop the request
    }
  }

  /// The body of `POST /v1/agent/screen` (backend/app/agent/schema.py, AgentRequest).
  static Json requestBody(String question, ChatContext ctx) => {
    'message': question,
    'as_of': formatDate(ctx.asOf),
    'role': ctx.user.role.code,
    'ward': ?ctx.user.ward?.code,
    'wards': [for (final w in ctx.user.wards) w.code],
    if (ctx.profile case final p?) 'profile': p.toQuery(),
    if (ctx.history.isNotEmpty)
      'history': [
        for (final (role, text) in ctx.history) {'role': role, 'text': text},
      ],
  };

  static List<WidgetPlacement> _widgets(Map<String, Json> components) {
    final root = components[AnswerComponents.rootId];
    return AnswerEntry(
      0,
      components: [...components.values.where((c) => c != root), ?root],
    ).widgets;
  }
}

/// Server-sent events as (event, data) pairs; comment lines (`: ping`) are skipped.
Stream<(String, Json)> parseSse(Stream<List<int>> bytes) async* {
  var event = 'message';
  final data = StringBuffer();
  await for (final line in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        final decoded = jsonDecode(data.toString());
        if (decoded is Json) yield (event, decoded);
      }
      event = 'message';
      data.clear();
    } else if (line.startsWith(':')) {
      continue;
    } else if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trimLeft());
    }
  }
}

/// What to offer under an answer, built from the widgets on it without the AI (#1): the
/// follow-ups a doctor, the lab or infection control would tap next.
AgentActions followUps(List<WidgetPlacement> widgets, PatientProfile? profile) {
  WidgetPlacement? placed(String name) => widgets.where((w) => w.widget == name).firstOrNull;
  WidgetPlacement pinnable(WidgetPlacement w) => WidgetPlacement(
    widget: w.widget,
    params: {
      for (final e in w.params.entries)
        if (e.key != 'as_of') e.key: e.value, // a pinned widget follows the replay date
    },
  );
  final coverage = placed('CoverageRanking');
  final alert = placed('AlertCard');
  final trend = placed('ResistanceTrend');
  final spreading = placed('SpreadingCounts') ?? placed('CrossWardWarning');
  final actions = <ChatAction>[];
  var suggestions = <String>[];

  if (coverage != null) {
    final exclude = coverage.params['exclude'];
    final filtered =
        coverage.params['oral_only'] == true || (exclude is List && exclude.isNotEmpty);
    final pronoun = switch (profile?.sex) {
      Sex.female => 'She is',
      Sex.male => 'He is',
      _ => 'The patient is',
    };
    actions.addAll([
      if (coverage.params['oral_only'] != true) const ChatAction.ask('Only oral options'),
      if (coverage.params['ward'] != null) const ChatAction.ask('Compare with the whole hospital'),
      if (profile?.infectionType != null)
        ChatAction('Open full answer page', ChatActionKind.openAnswer, payload: profile),
      ChatAction('Pin to my home', ChatActionKind.pin, primary: true, payload: pinnable(coverage)),
    ]);
    suggestions = [
      if (!filtered) '$pronoun allergic to penicillin',
      'Show the last 12 months',
      'New patient',
    ];
  } else if (alert != null) {
    final id = alert.params['alert_id'];
    actions.addAll([
      if (placed('CaseList') == null) const ChatAction.ask('Show the isolates'),
      if (id is String)
        ChatAction('Open the alert', ChatActionKind.navigate, payload: '/lab/alerts/$id'),
      const ChatAction('Warn linked wards', ChatActionKind.navigate, payload: '/hygiene'),
    ]);
    suggestions = ['Show the isolates', 'Is it real or more testing?'];
  } else if (trend != null) {
    actions.addAll([
      ChatAction('Pin to my home', ChatActionKind.pin, primary: true, payload: pinnable(trend)),
      const ChatAction('Open in Explore', ChatActionKind.navigate, payload: '/research'),
    ]);
    suggestions = ['Compare with the whole hospital', 'Show it by sex'];
  } else if (spreading != null) {
    actions.addAll([
      const ChatAction('See all wards', ChatActionKind.navigate, payload: '/hygiene'),
      ChatAction('Pin to my home', ChatActionKind.pin, payload: pinnable(spreading)),
    ]);
    suggestions = ['Which wards should we warn?', 'Compare with last month'];
  }
  return AgentActions(actions, suggestions: suggestions);
}

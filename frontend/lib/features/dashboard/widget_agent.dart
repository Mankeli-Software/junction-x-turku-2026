import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';
import '../../session/demo_users.dart';
import '../chat/agent/remote_agent.dart' show parseSse;

/// What the widget agent knows besides the message: who asks, the replay date, what is pinned
/// now and the conversation so far as (role, text), oldest first.
class WidgetAgentContext {
  const WidgetAgentContext({
    required this.user,
    required this.asOf,
    this.layout = const [],
    this.history = const [],
  });

  final DemoUser user;
  final DateTime asOf;
  final List<WidgetPlacement> layout;
  final List<(String, String)> history;
}

/// Events of `POST /v1/agent/widget` (backend/app/agent/builder.py).
sealed class WidgetAgentEvent {
  const WidgetAgentEvent();
}

class WidgetAgentStatus extends WidgetAgentEvent {
  const WidgetAgentStatus(this.text);

  final String text;
}

/// One widget the agent suggests, with its settings and one plain line on why it fits.
class WidgetProposal extends WidgetAgentEvent {
  const WidgetProposal(this.placement, {this.why});

  final WidgetPlacement placement;
  final String? why;
}

class WidgetAgentQuestion extends WidgetAgentEvent {
  const WidgetAgentQuestion(this.question, this.options);

  final String question;
  final List<String> options;
}

class WidgetAgentError extends WidgetAgentEvent {
  const WidgetAgentError(this.message);

  final String message;
}

/// No key (503) or no backend: the dialog offers the catalog instead.
class WidgetAgentUnavailable extends WidgetAgentEvent {
  const WidgetAgentUnavailable([this.message = 'AI suggestions are paused right now.']);

  final String message;
}

/// Suggests one widget for the home page per message, or asks one question back.
abstract interface class WidgetAgent {
  Stream<WidgetAgentEvent> suggest(String message, WidgetAgentContext context);
}

/// The Claude widget agent on the backend, read as server-sent events.
class RemoteWidgetAgent implements WidgetAgent {
  RemoteWidgetAgent(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Stream<WidgetAgentEvent> suggest(String message, WidgetAgentContext ctx) async* {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(
            'POST',
            Uri.parse('$baseUrl/v1/agent/widget'),
            abortTrigger: abort.future,
          )
          ..headers.addAll({'content-type': 'application/json', 'accept': 'text/event-stream'})
          ..body = jsonEncode(requestBody(message, ctx));
    try {
      final http.StreamedResponse res;
      try {
        res = await _client.send(request);
      } on Object {
        yield const WidgetAgentUnavailable('Could not reach the AI service.');
        return;
      }
      if (res.statusCode == 503) {
        yield const WidgetAgentUnavailable();
        return;
      }
      if (res.statusCode == 429) {
        yield const WidgetAgentError(
          'Too many suggestions from this network. Try again in a few minutes.',
        );
        return;
      }
      if (res.statusCode != 200) {
        yield WidgetAgentError('The AI service answered ${res.statusCode}.');
        return;
      }
      await for (final (event, data) in parseSse(res.stream)) {
        switch (event) {
          case 'status':
            yield WidgetAgentStatus(data['text'] as String? ?? '');
          case 'proposal':
            yield WidgetProposal(
              WidgetPlacement(
                widget: data['widget']! as String,
                params: {
                  for (final e in ((data['params'] as Json?) ?? const {}).entries)
                    if (e.key != 'as_of') e.key: e.value,
                },
              ),
              why: data['why'] as String?,
            );
          case 'clarify':
            yield WidgetAgentQuestion(
              data['question'] as String? ?? '',
              (data['options'] as List? ?? const []).cast<String>(),
            );
          case 'error':
            if (data['code'] == 'unavailable') {
              yield WidgetAgentUnavailable(data['message'] as String? ?? 'AI is paused.');
              return;
            }
            yield WidgetAgentError(data['message'] as String? ?? 'Something went wrong.');
          case 'done':
            return;
        }
      }
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// The body of `POST /v1/agent/widget` (WidgetAgentRequest).
  static Json requestBody(String message, WidgetAgentContext ctx) => {
    'message': message,
    'as_of': formatDate(ctx.asOf),
    'role': ctx.user.role.code,
    'ward': ?ctx.user.ward?.code,
    'wards': [for (final w in ctx.user.wards) w.code],
    'layout': [for (final p in ctx.layout.take(30)) p.toJson()],
    if (ctx.history.isNotEmpty)
      'history': [
        for (final (role, text) in ctx.history) {'role': role, 'text': text},
      ],
  };
}

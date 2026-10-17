import 'package:amiright/core/models/common.dart';
import 'package:amiright/core/models/dashboard.dart';
import 'package:amiright/core/models/vocab.dart';
import 'package:amiright/features/chat/agent/answer_surface.dart';
import 'package:amiright/features/chat/agent/chat_agent.dart';
import 'package:amiright/features/chat/agent/remote_agent.dart';
import 'package:amiright/features/chat/chat_models.dart';

/// Stands in for the Claude agent in widget tests: a few fixed answers, sent as the same A2UI
/// messages the backend sends, so the chat, genui and the follow-ups run for real.
class CannedAgent implements ChatAgent {
  static const onsetQuestion = 'Did the infection start at home or in hospital?';
  static const patient = PatientProfile(
    ward: Ward.uro,
    infectionType: InfectionType.uti,
    sex: Sex.female,
    ageBand: AgeBand.a75,
    onset: Onset.hospital,
  );

  @override
  Stream<AgentEvent> answer(String question, ChatContext context) async* {
    final surface = AnswerSurface();
    final q = question.toLowerCase();
    if (q.contains('dose')) {
      yield const AgentHeader();
      yield* Stream.fromIterable(
        surface.add(
          const WidgetPart(WidgetPlacement(widget: 'OutsideScope', params: {'reason': 'dosing'})),
        ),
      );
      yield const AgentActions([]);
    } else if (q.contains('oral')) {
      final p = context.profile ?? patient;
      yield AgentHeader(note: 'Same patient, oral options only', profile: p);
      final coverage = WidgetPlacement(
        widget: 'CoverageRanking',
        params: {...p.toQuery(), 'oral_only': true},
      );
      yield* Stream.fromIterable(surface.add(WidgetPart(coverage)));
      yield followUps([coverage], p);
    } else if (q.contains('in hospital')) {
      yield const AgentHeader(builtFrom: ['coverage'], profile: patient);
      final params = patient.toQuery();
      final widgets = [
        WidgetPlacement(widget: 'ContextChips', params: params),
        WidgetPlacement(widget: 'CoverageRanking', params: params),
      ];
      for (final w in widgets) {
        yield* Stream.fromIterable(surface.add(WidgetPart(w)));
      }
      yield* Stream.fromIterable(surface.add(const InShortPart('E. coli leads.')));
      yield followUps(widgets, patient);
    } else if (q.contains('not sure what kind of infection')) {
      yield const AgentHeader();
      yield* Stream.fromIterable(
        surface.add(
          const ClarifyPart('Which infection do you suspect?', [
            'Urinary tract (urine)',
            'Sepsis (blood)',
            'Wound infection',
          ]),
        ),
      );
      yield const AgentActions([]);
    } else if (q.contains('patient') || q.contains('urinary tract')) {
      yield const AgentHeader();
      yield* Stream.fromIterable(
        surface.add(
          const ClarifyPart(onsetQuestion, ['In hospital, day 3 or later', 'At home', 'Not sure']),
        ),
      );
      yield const AgentActions([]);
    } else {
      yield const AgentHeader();
      yield* Stream.fromIterable(surface.add(InShortPart('About: $question')));
      yield const AgentActions([]);
    }
  }
}

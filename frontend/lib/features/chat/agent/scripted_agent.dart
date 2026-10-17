import 'dart:async';

import '../../../catalog/widgets/coverage_ranking.dart';
import '../../../core/models/alerts.dart';
import '../../../core/models/common.dart';
import '../../../core/models/dashboard.dart';
import '../../../core/models/vocab.dart';
import '../../../core/repository.dart';
import '../chat_models.dart';
import 'chat_agent.dart';
import 'profile_parser.dart';

/// A rule-based stand-in for the Claude agent (#12), so the chat works end to end today.
///
/// It reads the question with simple patterns and answers with the same catalog widgets the
/// real agent will place, streamed one by one. Every number still comes from the backend; this
/// class only decides which widgets to show. Replace it with the remote agent in `app.dart`.
class ScriptedAgent implements ChatAgent {
  ScriptedAgent(this._repo, {this.step = const Duration(milliseconds: 260)});

  final AmrRepository _repo;
  final Duration step;

  /// The patient waiting for an answer to a clarifying question.
  PatientProfile? _pending;

  static const _onsetChoices = ['In hospital, day 3 or later', 'At home', 'Not sure, show both'];

  /// Answers to "Which infection do you suspect?", by the specimen that stands in for each.
  static const _infectionChoices = {
    'Urinary tract (urine)': InfectionType.uti,
    'Sepsis (blood)': InfectionType.sepsis,
    'Wound infection': InfectionType.wound,
  };

  @override
  Stream<AgentEvent> answer(String question, ChatContext ctx) async* {
    final q = question.toLowerCase().trim();
    final last = ctx.profile;

    // A reply to "Did the infection start at home or in hospital?"
    // A reply to "Which infection do you suspect?": continue with the same patient.
    final suspected = _infectionChoices[question];
    if (_pending != null && suspected != null) {
      final p = _pending!.copyWith(infectionType: suspected);
      if (p.onset == null) {
        _pending = p;
        yield* _clarify('Did the infection start at home or in hospital?', _onsetChoices);
      } else {
        _pending = null;
        yield* _coverage(p, ctx);
      }
      return;
    }

    if (_pending != null && _onsetChoices.contains(question)) {
      final p = _pending!;
      _pending = null;
      final onset = switch (question) {
        'At home' => Onset.community,
        'In hospital, day 3 or later' => Onset.hospital,
        _ => null,
      };
      yield* _coverage(onset == null ? p : p.copyWith(onset: onset), ctx);
      return;
    }
    _pending = null;

    final topic = q.contains('esbl') && q.startsWith('what is')
        ? 'esbl'
        : q.contains('mrsa') && q.startsWith('what is')
        ? 'mrsa'
        : RegExp(r's, i and r|what do s|sir mean').hasMatch(q)
        ? 'sir'
        : RegExp(r'how is this calculated|why is this number uncertain').hasMatch(q)
        ? 'calculation'
        : null;
    if (topic != null) {
      yield* _single(WidgetPart(WidgetPlacement(widget: 'Explain', params: {'topic': topic})));
      return;
    }
    if (RegExp(r'\bdose|dosing|how much .* give|prescri|mg\b').hasMatch(q)) {
      yield* _single(
        const WidgetPart(WidgetPlacement(widget: 'OutsideScope', params: {'reason': 'dosing'})),
      );
      return;
    }
    if (RegExp(r'pneumonia|respiratory|lung').hasMatch(q)) {
      yield* _single(
        const WidgetPart(WidgetPlacement(widget: 'NotInThisData', params: {'topic': 'pneumonia'})),
      );
      return;
    }
    if (RegExp(r"[A-Z][a-zäö]+ [A-Z][a-zäö]+(’|')s results").hasMatch(question) ||
        q.contains('look up')) {
      yield* _single(
        const WidgetPart(WidgetPlacement(widget: 'OutsideScope', params: {'reason': 'identity'})),
      );
      return;
    }
    if (RegExp(r'letter|email|write|summary of the patient|referral').hasMatch(q)) {
      yield* _single(
        const WidgetPart(WidgetPlacement(widget: 'OutsideScope', params: {'reason': 'off_topic'})),
      );
      return;
    }

    // Follow-ups on the patient of the conversation.
    if (last != null && q.contains('allergic') && q.contains('penicillin')) {
      yield* _filtered(last, {
        'exclude': [for (final d in CoverageFilter.penicillins) d.code],
      }, 'Same patient, penicillins hidden');
      return;
    }
    if (last != null && q.contains('oral')) {
      yield* _filtered(last, {'oral_only': true}, 'Same patient, oral options only');
      return;
    }
    if (last != null && q.contains('whole hospital')) {
      yield* _coverage(
        PatientProfile(
          sex: last.sex,
          ageBand: last.ageBand,
          infectionType: last.infectionType,
          onset: last.onset,
        ),
        ctx,
        note: 'Same patient, whole hospital',
      );
      return;
    }

    // Surveillance.
    final user = ctx.user;
    if (RegExp(r'clean|is my ward ok').hasMatch(q) ||
        (user.role == Role.careWorker && q.contains('ward'))) {
      yield const AgentHeader(builtFrom: ['spreading']);
      yield* _parts([
        WidgetPart(
          WidgetPlacement(
            widget: 'WardStatus',
            params: {
              'wards': [
                for (final w in user.wards.isEmpty ? [?user.ward] : user.wards) w.code,
              ],
            },
          ),
        ),
      ]);
      yield const AgentActions(
        [ChatAction.ask('What is ESBL?')],
        suggestions: ['What is ESBL?', 'Is my ward OK?'],
      );
      return;
    }
    if (RegExp(r'spread|outbreak|which wards|warn|mrsa|esbl|vre|cpe').hasMatch(q) &&
        !q.contains('trend')) {
      final ward = await _mostRaisedWard(ctx) ?? Ward.uro;
      yield const AgentHeader(builtFrom: ['spreading', 'linked wards']);
      yield AgentStatus('Checking resistant bacteria on every ward…');
      yield* _parts([
        const WidgetPart(WidgetPlacement(widget: 'SpreadingCounts')),
        WidgetPart(WidgetPlacement(widget: 'CrossWardWarning', params: {'ward': ward.code})),
      ]);
      yield const AgentActions(
        [ChatAction('See all wards', ChatActionKind.navigate, payload: '/hygiene')],
        suggestions: ['Which wards should we warn?', 'Compare with last month'],
      );
      return;
    }
    if (RegExp(r'alert|real|more testing|isolates|cluster').hasMatch(q)) {
      yield* _alert(ctx, isolates: q.contains('isolate'));
      return;
    }
    if (RegExp(r'trend|over time|by month|by year|rising').hasMatch(q)) {
      yield* _trend(question, ctx);
      return;
    }

    // A patient.
    final parsed = parseProfile(question);
    if (mentionsPatient(parsed, question)) {
      final p = mergeProfile(PatientProfile(ward: user.ward), parsed);
      if (p.infectionType == null) {
        // Not sure of the infection (also the "Ask the AI" tile): ask once, remember the rest.
        _pending = p;
        yield* _clarify('Which infection do you suspect?', [..._infectionChoices.keys]);
        return;
      }
      if (p.onset == null && p.infectionType!.inData) {
        _pending = p;
        yield* _clarify('Did the infection start at home or in hospital?', _onsetChoices);
        return;
      }
      yield* _coverage(p, ctx);
      return;
    }

    // Not sure what was asked: offer the main things, once.
    yield* _clarify('What would you like to check?', [
      'Alerts on my ward',
      'A patient I have now',
      'What is spreading this week?',
    ]);
  }

  // Answers -------------------------------------------------------------------

  Stream<AgentEvent> _coverage(PatientProfile p, ChatContext ctx, {String? note}) async* {
    yield AgentHeader(
      builtFrom: const ['coverage', 'organism mix', 'ward alerts'],
      note: note,
      profile: p,
    );
    yield AgentStatus('Checking coverage on ${p.ward?.label ?? 'the whole hospital'}…');
    final params = p.toQuery();
    if (p.notInData) {
      yield* _parts([
        const WidgetPart(WidgetPlacement(widget: 'NotInThisData', params: {'topic': 'pneumonia'})),
      ]);
      yield const AgentActions([]);
      return;
    }
    yield* _parts([
      WidgetPart(WidgetPlacement(widget: 'ContextChips', params: params)),
      WidgetPart(WidgetPlacement(widget: 'CoverageRanking', params: params)),
      WidgetPart(WidgetPlacement(widget: 'OrganismMix', params: params)),
      if (p.ward != null)
        WidgetPart(WidgetPlacement(widget: 'AlertBanner', params: {'ward': p.ward!.code})),
      const InShortPart(null),
    ]);
    yield AgentActions(
      [
        const ChatAction.ask('Only oral options'),
        const ChatAction.ask('Compare with the whole hospital'),
        ChatAction('Open full answer page', ChatActionKind.openAnswer, payload: p),
        ChatAction(
          'Pin to my home',
          ChatActionKind.pin,
          primary: true,
          payload: WidgetPlacement(widget: 'CoverageRanking', params: params),
        ),
      ],
      suggestions: const [
        'She is allergic to penicillin',
        'Show the last 12 months',
        'New patient',
      ],
    );
  }

  Stream<AgentEvent> _filtered(PatientProfile p, Map<String, Object> filter, String note) async* {
    yield AgentHeader(note: note, profile: p);
    yield* _parts([
      WidgetPart(WidgetPlacement(widget: 'CoverageRanking', params: {...p.toQuery(), ...filter})),
    ]);
    yield AgentActions(
      [ChatAction('Open full answer page', ChatActionKind.openAnswer, payload: p)],
      suggestions: const ['Why is ceftriaxone lower?', 'Show the last 12 months', 'New patient'],
    );
  }

  Stream<AgentEvent> _alert(ChatContext ctx, {required bool isolates}) async* {
    yield const AgentHeader(builtFrom: ['alert detail', 'sampling volume', 'susceptibility']);
    yield const AgentStatus('Looking at the alert and the testing volume…');
    final alerts = await _repo.alerts(
      AlertsQuery(
        window: WindowSpec(asOf: ctx.asOf),
        status: AlertStatus.active,
      ),
    );
    final list = [...alerts.alerts]..sort((a, b) => b.severity.index.compareTo(a.severity.index));
    final alert = list.firstOrNull;
    if (alert == null) {
      yield* _parts([const WidgetPart(WidgetPlacement(widget: 'AlertBanner'))]);
      yield const AgentActions([]);
      return;
    }
    final id = {'alert_id': alert.alertId};
    yield* _parts([
      WidgetPart(WidgetPlacement(widget: 'AlertCard', params: id)),
      if (isolates)
        WidgetPart(WidgetPlacement(widget: 'CaseList', params: id))
      else ...[
        WidgetPart(WidgetPlacement(widget: 'EpiCurve', params: id)),
        WidgetPart(WidgetPlacement(widget: 'SamplingVolume', params: {'ward': ?alert.ward?.code})),
        if (alert.organism != null && alert.drugs.isNotEmpty)
          WidgetPart(
            WidgetPlacement(
              widget: 'WindowCompare',
              params: {
                'ward': ?alert.ward?.code,
                'organism': alert.organism!.code,
                'drug': alert.drugs.first.code,
              },
            ),
          ),
        const InShortPart(null),
      ],
    ]);
    yield AgentActions(
      [
        if (!isolates) const ChatAction.ask('Show the isolates'),
        ChatAction(
          'Open the alert',
          ChatActionKind.navigate,
          payload: '/lab/alerts/${alert.alertId}',
        ),
        const ChatAction('Warn linked wards', ChatActionKind.navigate, payload: '/hygiene'),
      ],
      suggestions: const ['Show the isolates', 'Compare Urology with Surgery'],
    );
  }

  Stream<AgentEvent> _trend(String question, ChatContext ctx) async* {
    final p = parseProfile(question);
    final mrsa = question.toLowerCase().contains('mrsa');
    final organism = mrsa ? Organism.sAureus : Organism.eColi;
    final drug = mrsa
        ? Drug.fox
        : Drug.values
                  .where((d) => question.toLowerCase().contains(d.label.toLowerCase()))
                  .firstOrNull ??
              Drug.tmp;
    final ward = p.ward ?? (mrsa ? Ward.icu : null);
    yield const AgentHeader(builtFrom: ['trend', 'alerts']);
    yield* _parts([
      WidgetPart(
        WidgetPlacement(
          widget: 'ResistanceTrend',
          params: {
            'organism': organism.code,
            'drug': drug.code,
            'ward': ?ward?.code,
            'window': '365d',
          },
        ),
      ),
    ]);
    yield AgentActions(
      [
        ChatAction(
          'Pin to my home',
          ChatActionKind.pin,
          primary: true,
          payload: WidgetPlacement(
            widget: 'ResistanceTrend',
            params: {'organism': organism.code, 'drug': drug.code, 'ward': ?ward?.code},
          ),
        ),
        const ChatAction('Open in Explore', ChatActionKind.navigate, payload: '/research'),
      ],
      suggestions: const ['Add Surgery to the chart', 'Export as CSV'],
    );
  }

  // Helpers -------------------------------------------------------------------

  Stream<AgentEvent> _single(AnswerPart part) async* {
    yield const AgentHeader();
    yield* _parts([part]);
    yield const AgentActions([]);
  }

  Stream<AgentEvent> _clarify(String question, List<String> options) async* {
    yield const AgentHeader();
    yield* _parts([ClarifyPart(question, options)]);
    yield const AgentActions([]);
  }

  Stream<AgentEvent> _parts(List<AnswerPart> parts) async* {
    for (final p in parts) {
      await Future<void>.delayed(step);
      yield AgentPart(p);
    }
  }

  Future<Ward?> _mostRaisedWard(ChatContext ctx) async {
    try {
      final s = await _repo.spreading(const SpreadingQuery().resolve(ctx.asOf));
      final rows = [...s.rows]..sort((a, b) => (b.count - b.normal).compareTo(a.count - a.normal));
      return rows.firstOrNull?.ward;
    } on Object {
      return null;
    }
  }
}

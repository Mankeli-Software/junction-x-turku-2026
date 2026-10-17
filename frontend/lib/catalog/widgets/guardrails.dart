import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../ds/ds.dart';
import '../actions.dart';
import '../catalog.dart';

/// A follow-up offered under a notice: a label and what tapping it does.
typedef NoticeAction = (String label, VoidCallback onTap);

/// The calm "no", "not yet" or "wait": a title, a sentence and what the person can do next.
/// The AI picks the notice and its topic; the wording here is fixed, so it never invents facts.
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.alert = false,
  });

  final String title;
  final String body;
  final List<NoticeAction> actions;

  /// Blush for limits (dosing, identities); white for "not in this data".
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return AmrCard(
      tone: alert ? AmrCardTone.alert : AmrCardTone.quiet,
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: ColumnGap(
        [
          Text(title, style: AmrText.sora(compact ? 20 : 24, em: -0.015, height: 1.25)),
          Text(body, style: AmrText.body(compact ? 14 : 15, height: 1.45)),
          if (actions.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, onTap) in actions)
                  AmrButton(
                    label: label,
                    size: compact ? AmrButtonSize.sm : AmrButtonSize.md,
                    fontSize: compact ? 13 : 14,
                    variant: alert ? AmrButtonVariant.soft : AmrButtonVariant.outline,
                    padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
                    onPressed: onTap,
                  ),
              ],
            ),
        ],
        gap: 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

final notInThisDataEntry = CatalogEntry(
  name: 'NotInThisData',
  title: 'Not in this data',
  description:
      'An honest "this is not in the data" for a topic, offering what can be shown instead. '
      'Params: topic (pneumonia, respiratory, outpatients, …).',
  builder: (context, params, slot) {
    final ask = context.read<CatalogActions>().ask;
    final topic = (params['topic'] as String? ?? 'pneumonia').toLowerCase();
    if (topic == 'pneumonia' || topic == 'respiratory') {
      return NoticeCard(
        title: 'Pneumonia is not in this data yet',
        body:
            'There are only urine, blood and wound cultures here, and no respiratory samples, so '
            'any number would be a guess.',
        actions: [
          ('Show sepsis (blood) instead', () => ask('What works for sepsis on my ward?')),
          ('Ask the lab', () => ask('Ask the lab about respiratory samples')),
        ],
      );
    }
    return NoticeCard(
      title: '${topic[0].toUpperCase()}${topic.substring(1)} is not in this data yet',
      body: 'The data has urine, blood and wound cultures from nine wards and two health centres.',
      actions: [('What can you show?', () => ask('What can you show?'))],
    );
  },
);

final outsideScopeEntry = CatalogEntry(
  name: 'OutsideScope',
  title: 'Outside what we do',
  description:
      'For dosing, prescribing, identifying patients or off-topic requests: says what it can do '
      'instead. Params: reason (dosing | identity | off_topic).',
  builder: (context, params, slot) {
    final actions = context.read<CatalogActions>();
    return switch (params['reason']) {
      'identity' => NoticeCard(
        alert: true,
        title: 'I can’t look people up by name.',
        body:
            'Describe the patient instead (age, sex, ward, infection) and I’ll show what usually '
            'works. If you have a lab sample ID, you can open that patient’s earlier findings.',
        actions: [('Describe the patient', actions.newPatient)],
      ),
      'off_topic' => NoticeCard(
        title: 'I only answer questions about local resistance data.',
        body: 'I can show what works on your ward, what is spreading, or explain an alert.',
        actions: [
          ('What works on my ward?', () => actions.ask('What works on my ward?')),
          ('What is spreading?', () => actions.ask('What is spreading this week?')),
        ],
      ),
      _ => NoticeCard(
        alert: true,
        title: 'I can’t suggest doses or prescribe.',
        body:
            'I show how often drugs work against bacteria found locally. For dosing, use your '
            'hospital’s guideline or ask a pharmacist.',
        actions: [('Show coverage for this patient', actions.newPatient)],
      ),
    };
  },
);

/// Fixed, checked wording for the questions anyone asks; the AI picks the topic only.
const _explanations = {
  'esbl': (
    'What is ESBL?',
    'ESBL bacteria make an enzyme that breaks down many penicillins and cephalosporins, such as '
        'ceftriaxone. Infections with them need other antibiotics, and contact precautions help '
        'stop them spreading between patients.',
  ),
  'mrsa': (
    'What is MRSA?',
    'MRSA is Staphylococcus aureus that resists the usual anti-staphylococcal penicillins. It '
        'spreads by touch, so hand hygiene and cleaning shared equipment matter most.',
  ),
  'sir': (
    'What do S, I and R mean?',
    'S, susceptible: the drug usually works at a normal dose. I, susceptible with increased '
        'exposure: it works at a higher dose or exposure. R, resistant: it is not expected to work.',
  ),
  'calculation': (
    'How is this calculated?',
    'Each number uses the first isolate per patient in the period, so one patient never counts '
        'twice. With few patients the number leans toward the hospital-wide level, and the range '
        'shows how sure it is.',
  ),
};

final explainEntry = CatalogEntry(
  name: 'Explain',
  title: 'Plain explanation',
  description:
      'A short plain-language explanation. Params: topic (esbl | mrsa | sir | calculation).',
  builder: (context, params, slot) {
    final (title, body) = _explanations[params['topic']] ?? _explanations['sir']!;
    return AmrCard(
      tone: AmrCardTone.subtle,
      padding: EdgeInsets.all(context.isCompact ? 18 : 24),
      child: ColumnGap(
        [
          Text(title, style: AmrText.title(22, em: -0.015)),
          Text(body, style: AmrText.body(15, height: 1.5)),
        ],
        gap: 10,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  },
);

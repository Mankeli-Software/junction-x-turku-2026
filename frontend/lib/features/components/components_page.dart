import 'package:flutter/material.dart';
import '../shell/top_bar.dart';

import '../../catalog/catalog.dart';
import '../../catalog/widgets/in_short.dart';
import '../../core/models/alerts.dart';
import '../../core/models/dashboard.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../chat/widgets/chat_blocks.dart';
import '../shell/app_page.dart';

const _patient = {
  'ward': 'URO',
  'infection_type': 'uti',
  'sex': 'F',
  'age_band': '75+',
  'onset': 'hospital',
};

/// The component catalog (design: "What the AI can place"), live: every chat building block
/// and every catalog widget with sample params, loading real numbers.
class ComponentsPage extends StatelessWidget {
  const ComponentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetPlacement w(String name, [Map<String, Object?> params = const {}]) =>
        WidgetPlacement(widget: name, params: params);
    return AppPage(
      topBarSubtitle: 'Component catalog',
      body: PageBody(
        top: 32,
        gap: AmrSpace.x40,
        children: [
          ColumnGap([
            Breadcrumb(['AMRight', 'Component catalog'], onTapFirst: () => goHome(context)),
            Text('What the AI can place', style: AmrText.display(context, max: 76)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Text(
                'These are the only pieces the AI can use. Number widgets take query settings '
                '(ward, sample, organism, drug, period, date) and fetch their own numbers from the '
                'lab data. Each one shows how many patients it is based on, and they work the same '
                'on the home page, in the answer page and in chat.',
                style: AmrText.lede,
              ),
            ),
          ], gap: AmrSpace.x16),
          const _Section('1 · Chat building blocks'),
          _Item(
            name: 'Composer',
            about:
                'Always at the bottom of the chat. The suggestions come from your role, ward, '
                'active alerts and what you usually ask. They show up instantly, without the AI.',
            child: Composer(
              onSend: (_) {},
              suggestions: const [
                'What works for a UTI on my ward?',
                'Why is ceftriaxone lower?',
                'What is causing UTIs now?',
              ],
            ),
          ),
          const _Item(
            name: 'UserMessage · AnswerHeader',
            about:
                'The question on the right in navy. Every answer starts by saying which tools it '
                'used, so it is clear the numbers came from the data.',
            child: ColumnGap(
              [
                UserBubble('My 80-year-old female patient on Urology has a UTI. What works?'),
                AnswerHeader(
                  builtFrom: ['coverage', 'organism mix', 'ward alerts'],
                  dataTo: '27 Sep 2026',
                ),
              ],
              gap: 16,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            ),
          ),
          const _Item(
            name: 'Building (streaming)',
            about:
                'Widgets appear one by one: the patient summary first, then the coverage, and the '
                'short text last.',
            child: BuildingCard(status: 'checking coverage on Urology…'),
          ),
          _Item(
            name: 'ClarifyingQuestion',
            about:
                'When something important is missing, the AI asks once and offers tappable '
                'answers. Your own ward comes first.',
            child: ClarifyCard(
              question: 'Did the infection start at home or in hospital?',
              options: const ['In hospital, day 3 or later', 'At home', 'Not sure, show both'],
              onChoose: (_) {},
            ),
          ),
          _Item(
            name: 'AnswerActions',
            about:
                'Under every answer: follow-ups that work without the AI, pin to home, and feedback.',
            child: AnswerActionsBar(
              actions: [
                ('Only oral options', false, null, () {}),
                ('Compare with the whole hospital', false, null, () {}),
                ('Pin to my home', true, null, () {}),
              ],
              onFeedback: (_) {},
            ),
          ),
          const _Section('2 · For the patient in front of you'),
          _Item(
            name: 'ContextChips',
            about:
                'Shows what the AI understood. Tap a chip to change it: the numbers update without '
                'asking the AI again.',
            params: 'ward · infection · sex · age · onset',
            child: CatalogWidget(w('ContextChips', _patient), slot: WidgetSlot.chat),
          ),
          _Item(
            name: 'CoverageRanking',
            about:
                'The main doctor widget. Shows the narrowest drug that covers 90% or more first, '
                'then every drug with its S / I / R bar and the 12-month level.',
            params: 'patient settings · period · oral_only · exclude',
            child: CatalogWidget(w('CoverageRanking', _patient), slot: WidgetSlot.chat),
          ),
          _Item(
            name: 'CoverageRanking · filtered',
            about: 'The same numbers with drugs hidden, e.g. "She is allergic to penicillin".',
            child: CatalogWidget(
              w('CoverageRanking', {
                ..._patient,
                'exclude': ['AMP', 'MEC', 'TZP'],
              }),
              slot: WidgetSlot.chat,
            ),
          ),
          _Item(
            name: 'OrganismMix',
            about:
                '"What is causing it right now." These shares are also what the coverage numbers '
                'are weighted by.',
            params: 'ward · sample · period',
            child: CatalogWidget(w('OrganismMix', _patient), slot: WidgetSlot.chat),
          ),
          _Item(
            name: 'WindowCompare',
            about: 'One drug against one organism: the last 4 weeks next to the last 12 months.',
            params: 'organism · drug · ward',
            child: CatalogWidget(
              w('WindowCompare', {'ward': 'URO', 'organism': 'Escherichia coli', 'drug': 'CRO'}),
              slot: WidgetSlot.chat,
            ),
          ),
          _Item(
            name: 'AlertBanner · InShort',
            about:
                'The banner opens the alert. "In short" is the only free text the AI writes. The '
                'server rejects it if it contains a number.',
            child: ColumnGap(
              [
                CatalogWidget(w('AlertBanner', {'status': 'active'}), slot: WidgetSlot.chat),
                const InShortCard(
                  text:
                      'Mostly E. coli on Urology. An ESBL rise means cephalosporins work less often '
                      'than usual.',
                ),
              ],
              gap: 12,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            ),
          ),
          _Item(
            name: 'NotInThisData',
            about: 'An honest "we can\'t answer this" that always offers what it can show instead.',
            params: 'topic',
            child: CatalogWidget(w('NotInThisData', {'topic': 'pneumonia'})),
          ),
          _Item(
            name: 'PatientHistory (optional)',
            about:
                'Only when a patient ID is given. It shows facts and does not change the ranking.',
            params: 'patient id · date',
            child: CatalogWidget(w('PatientHistory', {'patient_id': 'demo'})),
          ),
          const _Section('3 · For wards, the lab and research'),
          _Item(
            name: 'SpreadingCounts',
            about: 'MRSA, ESBL, VRE and CPE per ward, now compared with a usual 4 weeks.',
            params: 'wards · types · period',
            child: CatalogWidget(w('SpreadingCounts'), slot: WidgetSlot.chat),
          ),
          _Item(
            name: 'CrossWardWarning',
            about:
                'Wards that share many patients with the ward that has the alert. Only totals are '
                'shown, never patient details.',
            params: 'ward',
            child: CatalogWidget(w('CrossWardWarning', {'ward': 'URO'}), slot: WidgetSlot.chat),
          ),
          _Item(
            name: 'WardStatus',
            about: 'For care workers: is my ward as usual, and where to clean more.',
            params: 'wards',
            child: CatalogWidget(
              w('WardStatus', {
                'wards': ['ICU', 'SURG'],
              }),
              slot: WidgetSlot.chat,
            ),
          ),
          _AlertItems(w: w),
          _Item(
            name: 'SamplingVolume',
            about: 'The testing volume, to tell real change apart from more testing.',
            params: 'ward · sample · range',
            child: CatalogWidget(w('SamplingVolume', {'ward': 'URO'}), slot: WidgetSlot.chat),
          ),
          _Item(
            name: 'ResistanceTrend',
            about: 'For slow change over months or years. Lines can be split by ward or by sex.',
            params: 'organism · drug · wards · range · split',
            child: CatalogWidget(
              w('ResistanceTrend', {
                'organism': 'Staphylococcus aureus',
                'drug': 'FOX',
                'ward': 'ICU',
                'window': '365d',
              }),
              slot: WidgetSlot.chat,
            ),
          ),
          const _Section('4 · Actions and limits'),
          const _Item(
            name: 'Pinned · ExportReady',
            about: 'Confirms that an action is done, with an undo.',
            child: ColumnGap(
              [
                ActionPill(message: 'Pinned to your home', actionLabel: 'Undo'),
                ActionPill(
                  message: 'ecoli_tmp_by_sex.csv · 2 periods',
                  actionLabel: 'Download',
                  dark: false,
                ),
              ],
              gap: 12,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            ),
          ),
          _Item(
            name: 'OutsideScope',
            about: 'For dosing, prescribing or identifying patients. Says what it can do instead.',
            params: 'reason',
            child: CatalogWidget(w('OutsideScope', {'reason': 'dosing'})),
          ),
          _Item(
            name: 'Explain',
            about:
                'Plain words for what anyone asks: S, I and R, ESBL, MRSA, how it is calculated.',
            params: 'topic',
            child: CatalogWidget(w('Explain', {'topic': 'sir'})),
          ),
          const _Item(
            name: 'AI unavailable',
            about: 'When the agent is off, everything else still works.',
            child: AiUnavailablePanel(onQuickForm: _noop),
          ),
        ],
      ),
    );
  }
}

void _noop() {}

/// The alert widgets need a real alert id: take the first active alert.
class _AlertItems extends StatelessWidget {
  const _AlertItems({required this.w});

  final WidgetPlacement Function(String, [Map<String, Object?>]) w;

  @override
  Widget build(BuildContext context) => QueryView<AlertsQuery, Alerts>(
    query: const AlertsQuery(),
    fetch: (repo, q) => repo.alerts(q),
    builder: (context, data) {
      final id = data.alerts.firstOrNull?.alertId;
      if (id == null) return const NoteCard(title: 'No alerts at this date to show.');
      final p = {'alert_id': id};
      return ColumnGap(
        [
          _Item(
            name: 'AlertCard',
            about: 'One grouped alert per ward, organism and type, with a plain verdict.',
            params: 'alert id',
            child: CatalogWidget(w('AlertCard', p), slot: WidgetSlot.chat),
          ),
          _Item(
            name: 'EpiCurve',
            about: 'The epidemic curve: new cases per week against the usual level.',
            params: 'alert id',
            child: CatalogWidget(w('EpiCurve', p), slot: WidgetSlot.chat),
          ),
          _Item(
            name: 'CaseList',
            about: 'The isolates behind an alert, for lab staff only. No names, no IDs.',
            params: 'alert id',
            child: CatalogWidget(w('CaseList', p), slot: WidgetSlot.chat),
          ),
        ],
        gap: AmrSpace.x40,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      );
    },
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(top: 16, bottom: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AmrColors.ink)),
    ),
    child: Text(title, style: AmrText.title(38, em: -0.025)),
  );
}

/// Name and description on the left (260px+), the live widget on the right.
class _Item extends StatelessWidget {
  const _Item({required this.name, required this.about, required this.child, this.params});

  final String name;
  final String about;
  final String? params;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final code = AmrText.inter(14, weight: FontWeight.w600).copyWith(fontFamily: 'monospace');
    final left = ColumnGap([
      Text(name, style: code),
      Text(about, style: AmrText.body(14, height: 1.45)),
      if (params != null) Text(params!, style: code.copyWith(fontSize: 12)),
    ], gap: 6);
    if (context.screenWidth < 1000) {
      return ColumnGap([left, child], gap: 16, crossAxisAlignment: CrossAxisAlignment.stretch);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 300, child: left),
        const SizedBox(width: 40),
        Expanded(child: child),
      ],
    );
  }
}

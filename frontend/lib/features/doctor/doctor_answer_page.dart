import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/actions.dart';
import '../../catalog/widgets/alert_banner.dart';
import '../../catalog/widgets/context_chips.dart';
import '../../catalog/widgets/coverage_ranking.dart';
import '../../catalog/widgets/in_short.dart';
import '../../catalog/widgets/organism_mix.dart';
import '../../core/models/alerts.dart';
import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/data.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../chat/ask_context.dart';
import '../chat/widgets/ask_launcher.dart';
import '../dashboard/dashboard_cubit.dart';
import '../shell/app_page.dart';

/// Doctor · 2: the answer for one described patient. Every number comes from the catalog
/// widgets' own queries; this page only arranges them.
class DoctorAnswerPage extends StatelessWidget {
  const DoctorAnswerPage({super.key, required this.profile});

  final PatientProfile profile;

  @override
  Widget build(BuildContext context) {
    final actions = context.read<CatalogActions>();
    final coverage = CoverageQuery(profile: profile);
    return AppPage(
      glowHeight: 520,
      phoneBar: StickyAskBar(hint: 'Ask a follow-up…', about: AskContext.answer(profile)),
      body: PageBody(
        children: [
          ColumnGap(
            [
              Breadcrumb(const ['Home', 'Your patient'], onTapFirst: actions.newPatient),
              SelectedPatientCard(profile: profile),
            ],
            gap: AmrSpace.x16,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          ),
          if (profile.notInData)
            NoteCard(
              title: '${profile.infectionType!.label} is not in this data yet.',
              body:
                  'There are only urine, blood and wound cultures here, and no respiratory '
                  'samples, so any number would be a guess.',
              actions: [
                AmrButton(
                  label: 'Show sepsis (blood) instead',
                  size: AmrButtonSize.sm,
                  onPressed: () =>
                      actions.openAnswer(profile.copyWith(infectionType: InfectionType.sepsis)),
                ),
              ],
            )
          else
            QueryView<CoverageQuery, Coverage>(
              query: coverage,
              fetch: (repo, q) => repo.coverage(q),
              loading: const _AnswerSkeleton(),
              builder: (context, c) => CoverageEmpty.applies(c)
                  ? CoverageEmpty(coverage: c)
                  : _Answer(coverage: c, profile: profile, query: coverage),
            ),
          Text(
            'Local susceptibility coverage from lab data, not a prescription.',
            style: AmrText.body(13),
          ),
        ],
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.coverage, required this.profile, required this.query});

  final Coverage coverage;
  final PatientProfile profile;
  final CoverageQuery query;

  @override
  Widget build(BuildContext context) {
    return ColumnGap(
      [
        // The side column keeps its 380px (a little wider than the design's 320, for balance),
        // the answer takes the rest.
        FlexSplit(
          basis: const [560, 380],
          flex: const [999, 1],
          growFromBasis: true,
          children: [
            NarrowestDrugHero(coverage: coverage),
            // "How sure is this?" takes the height the alert leaves, so both columns end level.
            FillColumn(
              gap: AmrSpace.x20,
              children: [
                AlertBanner(
                  query: AlertsQuery(ward: profile.ward, status: AlertStatus.active),
                ),
                CoverageConfidence(coverage: coverage),
              ],
            ),
          ],
        ),
        AiInShort(query: query, fetch: (repo, q) => repo.inShort(q)),
        CoverageTable(coverage: coverage),
        FlexSplit(
          basis: const [380, 380],
          stretch: false,
          children: [
            OrganismMixWidget(query: OrganismMixQuery(profile: profile)),
            _FollowUp(query: query),
          ],
        ),
      ],
      gap: AmrSpace.x32,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );
  }
}

class _FollowUp extends StatelessWidget {
  const _FollowUp({required this.query});

  final CoverageQuery query;

  Future<void> _pin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context.read<DashboardCubit>().pin(
      WidgetPlacement(
        widget: 'CoverageRanking',
        params: {...query.profile.toQuery(), 'window': query.window.window.code},
      ),
    );
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? 'Pinned to your home' : 'Could not pin it, try again')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = context.read<CatalogActions>();
    final about = AskContext.answer(query.profile);
    return AmrCard(
      tone: AmrCardTone.quiet,
      child: ColumnGap([
        Text('Ask a follow-up', style: AmrText.title(26)),
        AskLauncher(
          hint: 'e.g. ${about.suggestions.first.toLowerCase()}',
          style: AskFieldStyle.outlined,
          about: about,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AmrButton(
              label: 'Only oral options',
              size: AmrButtonSize.md,
              onPressed: () => actions.ask('Only oral options', patient: query.profile),
            ),
            AmrButton(
              label: 'Compare with the whole hospital',
              size: AmrButtonSize.md,
              onPressed: () =>
                  actions.ask('Compare with the whole hospital', patient: query.profile),
            ),
            AmrButton(
              label: 'Pin to my home',
              size: AmrButtonSize.md,
              variant: AmrButtonVariant.primary,
              onPressed: () => _pin(context),
            ),
          ],
        ),
      ], crossAxisAlignment: CrossAxisAlignment.stretch),
    );
  }
}

class _AnswerSkeleton extends StatelessWidget {
  const _AnswerSkeleton();

  @override
  Widget build(BuildContext context) => const ColumnGap(
    [
      AmrCard(tone: AmrCardTone.accent, child: SkeletonBlock(lines: 4, lineHeight: 28)),
      SkeletonBlock(lines: 6),
    ],
    gap: AmrSpace.x32,
    crossAxisAlignment: CrossAxisAlignment.stretch,
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../shell/top_bar.dart';

import '../../catalog/actions.dart';
import '../../catalog/widgets/export_ready.dart';
import '../../catalog/widgets/resistance_trend.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../core/repository.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import '../chat/ask_context.dart';
import '../chat/widgets/ask_launcher.dart';
import '../dashboard/dashboard_cubit.dart';
import '../shell/app_page.dart';
import 'research_cubit.dart';
import 'research_data.dart';
import 'research_filters.dart';
import 'research_table.dart';

/// Researcher · Explore: filters on the left, a chart made from them (or from words), the table
/// of periods × groups, and export.
class ResearchPage extends StatelessWidget {
  const ResearchPage({super.key, this.initial});

  /// Filters to start from (a pinned trend opened here); the defaults otherwise.
  final ResearchFilters? initial;

  @override
  Widget build(BuildContext context) =>
      BlocProvider(create: (_) => ResearchCubit(initial), child: const _ResearchView());
}

class _ResearchView extends StatefulWidget {
  const _ResearchView();

  @override
  State<_ResearchView> createState() => _ResearchViewState();
}

class _ResearchViewState extends State<_ResearchView> {
  final _promptKey = GlobalKey();

  ResearchFilters get _filters => context.read<ResearchCubit>().state.filters;
  DateTime get _asOf => context.read<SessionCubit>().state.asOf;

  Future<void> _pin() async {
    final messenger = ScaffoldMessenger.of(context);
    final research = context.read<ResearchCubit>();
    final p = WidgetPlacement(widget: 'ResistanceTrend', params: _filters.trendParams);
    if (await context.read<DashboardCubit>().pin(p)) {
      research.pinned(p);
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save it, try again')));
    }
  }

  void _unpin(WidgetPlacement p) {
    context.read<DashboardCubit>().unpin(p);
    context.read<ResearchCubit>().pinned(null);
  }

  Future<void> _export() async {
    final research = context.read<ResearchCubit>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final table = await fetchResearchTable(
        context.read<AmrRepository>(),
        ResearchQuery(_filters, asOf: _asOf),
      );
      final file = researchCsv(_filters, table);
      downloadCsv(file);
      research.exported(file);
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not build the export, try again')),
      );
    }
  }

  void _editPrompt() {
    final target = _promptKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, duration: AmrMotion.slow, curve: AmrMotion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final state = context.watch<ResearchCubit>().state;
    final pills = [
      if (state.pinned != null)
        ActionPill(
          message: 'Pinned to your home. It will show the latest data each time.',
          actionLabel: 'Undo',
          onAction: () => _unpin(state.pinned!),
        ),
      if (state.export != null) ExportReadyPill(export: state.export!),
    ];
    final chart = _ChartCard(onPin: _pin, onEditPrompt: _editPrompt);
    final table = _Table(filters: state.filters);

    if (compact) {
      return AppPage(
        phoneBar: _StickyActions(onSave: _pin, onExport: _export),
        body: PageBody(
          top: 12,
          gap: AmrSpace.x16,
          children: [
            Breadcrumb(['Home', 'Explore'], onTapFirst: () => goHome(context)),
            Text('Explore the data', style: AmrText.sora(40, em: -0.035, height: 1.02)),
            const FiltersSummary(),
            ...pills,
            chart,
            table,
          ],
        ),
      );
    }

    return AppPage(
      body: PageBody(
        top: fluid(context, 24, 4, 48),
        gap: AmrSpace.x28,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 20,
            runSpacing: 20,
            children: [
              ColumnGap([
                Breadcrumb(['Home', 'Explore'], onTapFirst: () => goHome(context)),
                Text('Explore the data', style: AmrText.display(context, max: 80)),
              ], gap: AmrSpace.x18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AmrButton(label: 'Save view', onPressed: _pin),
                  AmrButton(
                    label: 'Export CSV',
                    variant: AmrButtonVariant.primary,
                    onPressed: _export,
                  ),
                ],
              ),
            ],
          ),
          FlexSplit(
            basis: const [300, 620],
            flex: const [26, 74],
            gap: AmrSpace.x24,
            stretch: false,
            children: [
              const FiltersPanel(),
              ColumnGap(
                [...pills, KeyedSubtree(key: _promptKey, child: const _PromptCard()), chart, table],
                gap: AmrSpace.x20,
                crossAxisAlignment: CrossAxisAlignment.stretch,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Make a chart by describing it": the words go to the chat; the first suggestion is a preset
/// that sets the filters directly.
class _PromptCard extends StatelessWidget {
  const _PromptCard();

  @override
  Widget build(BuildContext context) {
    final actions = context.read<CatalogActions>();
    final research = context.read<ResearchCubit>();
    final suggestions = <(String, VoidCallback)>[
      (
        'ICU MRSA share by month in 2026',
        () => research.setFilters(
          const ResearchFilters(
            period: ResearchPeriod.year,
            ward: Ward.icu,
            specimen: null,
            organism: Organism.sAureus,
            drug: Drug.fox,
            split: SplitBy.none,
          ),
        ),
      ),
      (
        'Compare Urology and Surgery for ceftriaxone',
        () => actions.ask('Compare Urology and Surgery for ceftriaxone'),
      ),
      (
        'Cultures per week, all health centres',
        () => actions.ask('Cultures per week, all health centres'),
      ),
    ];
    return AmrCard(
      tone: AmrCardTone.subtle,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: ColumnGap(
        [
          Text('Make a chart by describing it', style: AmrText.body(15, weight: FontWeight.w500)),
          AskLauncher(
            hint: 'e.g. E. coli resistance to trimethoprim by sex, urine, every 3 months',
            about: AskContext.research(),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, onTap) in suggestions)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AmrColors.white,
                    borderRadius: AmrRadius.pill,
                  ),
                  child: AmrButton(
                    label: label,
                    size: AmrButtonSize.sm,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    onPressed: onTap,
                  ),
                ),
            ],
          ),
          Text(
            'The AI sets the filters on the left from your words. You can change any of them '
            'afterwards.',
            style: AmrText.body(13),
          ),
        ],
        gap: AmrSpace.x12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

final _monYear = DateFormat('MMM y');

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.onPin, required this.onEditPrompt});

  final VoidCallback onPin;
  final VoidCallback onEditPrompt;

  @override
  Widget build(BuildContext context) {
    final f = context.select((ResearchCubit c) => c.state.filters);
    final asOf = context.select((SessionCubit c) => c.state.asOf);
    final compact = context.isCompact;
    final split = f.split == SplitBy.none ? '' : ', by ${f.split.label.toLowerCase()}';
    final mrsa = f.organism == Organism.sAureus && f.drug == Drug.fox;
    final titleStyle = compact
        ? AmrText.title(22)
        : AmrText.sora(fluid(context, 26, 2.6, 36), em: -0.025, height: 1.15);
    final title = Text.rich(
      TextSpan(
        style: titleStyle,
        children: [
          TextSpan(
            text: f.organism.short,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          TextSpan(
            text: mrsa
                ? ' · ${trendMetric(f.organism, f.drug)}$split'
                : ' resistance to ${f.drug.label.toLowerCase()}$split',
          ),
        ],
      ),
    );
    final place = [f.specimen?.label ?? 'All samples', f.ward?.label ?? 'all wards'];
    final subtitle = compact
        ? [...place, 'monthly'].join(' · ')
        : [
            ...place,
            '${_monYear.format(f.period.start(asOf))} to ${_monYear.format(asOf)}',
            'monthly, 12-month rolling',
          ].join(' · ');
    final head = ColumnGap([
      title,
      Text(subtitle, style: AmrText.body(compact ? 13 : 15)),
    ], gap: compact ? 4 : 6);
    return AmrCard(
      shadow: compact ? AmrShadows.input : AmrShadows.md,
      padding: EdgeInsets.all(compact ? 18 : fluid(context, 24, 3, 36)),
      child: ColumnGap(
        [
          if (compact)
            head
          else
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 12,
              children: [
                head,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AmrButton(
                      label: 'Edit prompt',
                      size: AmrButtonSize.md,
                      fontSize: 14,
                      onPressed: onEditPrompt,
                    ),
                    AmrButton(
                      label: 'Save to my home',
                      size: AmrButtonSize.md,
                      fontSize: 14,
                      variant: AmrButtonVariant.primary,
                      leading: const Icon(LucideIcons.pin),
                      onPressed: onPin,
                    ),
                  ],
                ),
              ],
            ),
          QueryView<ResearchQuery, List<TrendLine>>(
            query: ResearchQuery(f),
            fetch: fetchResearchLines,
            loading: const SkeletonBlock(lines: 5, lineHeight: 24),
            builder: (context, lines) {
              if (lines.every((l) => l.points.isEmpty)) {
                return const NoteCard(title: 'No isolates for these filters in this period.');
              }
              final sentence = trendSentence(lines);
              return ColumnGap(
                [
                  TrendChart(
                    lines: lines,
                    band: lines.length == 1,
                    height: compact ? 160 : 220,
                    labels: compact ? 2 : 3,
                  ),
                  if (sentence.isNotEmpty) Text(sentence, style: AmrText.body(compact ? 14 : 15)),
                ],
                gap: AmrSpace.x12,
                crossAxisAlignment: CrossAxisAlignment.stretch,
              );
            },
          ),
        ],
        gap: AmrSpace.x16,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.filters});

  final ResearchFilters filters;

  @override
  Widget build(BuildContext context) => QueryView<ResearchQuery, ResearchTable>(
    query: ResearchQuery(filters),
    fetch: fetchResearchTable,
    loading: const SkeletonBlock(lines: 3, lineHeight: 28),
    builder: (context, t) => ResearchTableView(table: t),
  );
}

/// Phone: Save view and Export CSV stick to the bottom over a white fade.
class _StickyActions extends StatelessWidget {
  const _StickyActions({required this.onSave, required this.onExport});

  final VoidCallback onSave;
  final VoidCallback onExport;

  /// The two actions; [AppPage] puts them in the sticky white fade.
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AmrColors.white, borderRadius: AmrRadius.pill),
          child: AmrButton(
            label: 'Save view',
            size: AmrButtonSize.xl,
            expand: true,
            onPressed: onSave,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: AmrButton(
          label: 'Export CSV',
          size: AmrButtonSize.xl,
          expand: true,
          variant: AmrButtonVariant.primary,
          fontWeight: FontWeight.w400,
          onPressed: onExport,
        ),
      ),
    ],
  );
}

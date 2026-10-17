import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/actions.dart';
import '../../catalog/widgets/cross_ward_warning.dart';
import '../../catalog/widgets/spreading_counts.dart';
import '../../catalog/widgets/ward_status.dart';
import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import '../shell/app_page.dart';
import 'hygiene_cubit.dart';

/// Infection control · "What is spreading": every ward against a usual period, and the wards
/// that share patients with the most raised one. Care workers see their own wards first.
class HygienePage extends StatelessWidget {
  const HygienePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HygieneCubit(),
      child: const AppPage(
        body: _Body(),
        phoneBar: StickyAskBar(hint: 'Ask, e.g. MRSA in ICU?'),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HygieneCubit>().state;
    final user = context.select((SessionCubit c) => c.state.user);
    final phone = context.isCompact;
    final query = state.query;
    return PageBody(
      top: phone ? 12 : fluid(context, 24, 4, 56),
      gap: phone ? AmrSpace.x18 : AmrSpace.x32,
      children: [
        phone ? const _PhoneHeader() : const _Header(),
        if (user?.role == Role.careWorker && user!.wards.isNotEmpty)
          ColumnGap(
            [
              SectionHeader(
                title: 'Your wards',
                subtitle: 'Where to clean more this week.',
                size: phone ? 24 : 30,
              ),
              WardStatus(
                query: SpreadingQuery(window: query.window, wards: user.wards),
              ),
            ],
            gap: AmrSpace.x16,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          ),
        if (phone)
          QueryView<SpreadingQuery, Spreading>(
            query: query,
            fetch: (repo, q) => repo.spreading(q),
            loading: const AmrCard(tone: AmrCardTone.alert, child: SkeletonBlock(lines: 1)),
            builder: (context, data) =>
                _RaisedSummary(spreads: wardSpreads(data, only: state.phenotype)),
          ),
        phone ? const _PhoneFilters() : const _Filters(),
        QueryView<SpreadingQuery, Spreading>(
          query: query,
          fetch: (repo, q) => repo.spreading(q),
          builder: (context, data) {
            final spreads = wardSpreads(data, only: state.phenotype);
            final top = spreads.where((s) => s.status.raised).firstOrNull;
            final ward = state.focus ?? top?.ward ?? Ward.uro;
            final focusSpread = spreads.where((s) => s.ward == ward).firstOrNull;
            final cubit = context.read<HygieneCubit>();
            return ColumnGap(
              [
                if (phone)
                  SpreadingPhoneGrid(wards: spreads, onTapWard: cubit.focus)
                else
                  SpreadingWardGrid(wards: spreads, only: state.phenotype, onTapWard: cubit.focus),
                CrossWardWarning(
                  key: ValueKey(ward),
                  query: WardLinksQuery(ward: ward, window: query.window),
                  phenotype: focusSpread?.status.raised == true
                      ? focusSpread!.top?.phenotype
                      : null,
                ),
              ],
              gap: phone ? AmrSpace.x18 : AmrSpace.x32,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            );
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 24,
      runSpacing: 24,
      children: [
        ColumnGap([
          const Breadcrumb(['Home', 'Whole hospital']),
          Text('What is spreading', style: AmrText.display(context, max: 80)),
        ], gap: AmrSpace.x18),
        SizedBox(
          width: 460,
          child: AskField(
            hint: 'Ask, e.g. where is MRSA this month?',
            onSubmit: context.read<CatalogActions>().ask,
          ),
        ),
      ],
    );
  }
}

class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader();

  @override
  Widget build(BuildContext context) => ColumnGap([
    Text('Home ✦ Whole hospital', style: AmrText.body(13)),
    Text('What is spreading', style: AmrText.sora(44, em: -0.04, height: 1)),
  ], gap: AmrSpace.x18);
}

String _windowNote(TimeWindow w) => w == TimeWindow.d365
    ? 'Last 12 months compared with a usual year'
    : 'Last 4 weeks compared with a usual 4 weeks';

class _Filters extends StatelessWidget {
  const _Filters();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HygieneCubit>().state;
    final cubit = context.read<HygieneCubit>();
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('Show', style: AmrText.body(15)),
              ),
              AmrButton.toggle(
                label: 'All resistant types',
                selected: state.phenotype == null,
                onPressed: () => cubit.showType(null),
              ),
              for (final p in Phenotype.values)
                AmrButton.toggle(
                  label: p.code,
                  selected: state.phenotype == p,
                  onPressed: () => cubit.showType(p),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Pressable(
          onTap: cubit.toggleYear,
          pressScale: 1,
          builder: (_, s) => Text(
            _windowNote(state.window),
            style: AmrText.body(
              15,
            ).copyWith(decoration: s.hovered ? TextDecoration.underline : null),
          ),
        ),
      ],
    );
  }
}

/// Phone: one scrolling row of chips, "12 months" switches the period.
class _PhoneFilters extends StatelessWidget {
  const _PhoneFilters();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HygieneCubit>().state;
    final cubit = context.read<HygieneCubit>();
    Widget chip(String label, bool selected, VoidCallback onTap) => AmrButton.toggle(
      label: label,
      selected: selected,
      size: AmrButtonSize.md,
      fontSize: 15,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      onPressed: onTap,
    );
    // Bleeds to the screen edges so chips scroll under the gutter, as in the design.
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: 44,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: context.gutter),
          child: Row(
            children: [
              for (final c in [
                chip('All types', state.phenotype == null, () => cubit.showType(null)),
                for (final p in Phenotype.values)
                  chip(p.code, state.phenotype == p, () => cubit.showType(p)),
                chip('12 months', state.window == TimeWindow.d365, cubit.toggleYear),
              ]) ...[c, const SizedBox(width: 8)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone: "2 wards above usual · Urology and Geriatrics, both ESBL. No VRE or CPE."
class _RaisedSummary extends StatelessWidget {
  const _RaisedSummary({required this.spreads});

  final List<WardSpread> spreads;

  @override
  Widget build(BuildContext context) {
    final raised = [
      for (final s in spreads)
        if (s.status.raised) s,
    ];
    return AmrCard(
      tone: raised.isEmpty ? AmrCardTone.subtle : AmrCardTone.alert,
      radius: AmrRadius.bubble,
      padding: const EdgeInsets.all(AmrSpace.x20),
      child: Row(
        children: [
          Text('${raised.length}', style: AmrText.sora(72, em: -0.05, height: 0.9)),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  raised.length == 1 ? 'ward above usual' : 'wards above usual',
                  style: AmrText.body(17, weight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(raisedSentence(spreads), style: AmrText.body(14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Urology and Geriatrics, both ESBL. No VRE or CPE in this period."
String raisedSentence(List<WardSpread> spreads) {
  String join(List<String> xs) =>
      xs.length <= 1 ? xs.join() : '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';
  final raised = [
    for (final s in spreads)
      if (s.status.raised) s,
  ];
  final types = {for (final s in raised) ?s.top?.phenotype};
  final found = {
    for (final s in spreads)
      for (final r in s.rows)
        if (r.count > 0) r.phenotype,
  };
  final missing = [
    for (final p in Phenotype.values)
      if (!found.contains(p)) p.code,
  ];
  final parts = <String>[];
  if (raised.isEmpty) {
    parts.add('Every ward is as usual.');
  } else {
    final names = join([for (final s in raised) s.ward.label]);
    final kind = types.length == 1
        ? '${raised.length == 1
              ? ''
              : raised.length == 2
              ? 'both '
              : 'all '}${types.first.code}'
        : join([for (final t in types) t.code]);
    parts.add('$names, $kind.');
  }
  if (missing.isNotEmpty) parts.add('No ${join(missing)} in this period.');
  return parts.join(' ');
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/actions.dart';
import '../../catalog/widgets/cross_ward_warning.dart';
import '../../catalog/widgets/spreading_counts.dart';
import '../../catalog/widgets/ward_status.dart';
import '../../session/session_cubit.dart';
import '../../core/models/alerts.dart';
import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../dashboard/dashboard_cubit.dart';
import '../chat/ask_context.dart';
import '../chat/widgets/ask_launcher.dart';
import '../shell/app_page.dart';
import '../shell/top_bar.dart';

/// Infection control · "What is spreading", the visual version: the one ward that matters, a
/// sparkline per ward, a ward detail with weekly bars, and where its patients go next.
/// Same numbers as the list view (`/v1/spreading`, `/v1/spreading/series`, `/v1/ward-links`).
class HygieneVisualPage extends StatelessWidget {
  const HygieneVisualPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => _VisualCubit(),
    child: AppPage(
      body: const _Body(),
      phoneBar: StickyAskBar(
        about: AskContext.spreading(context.select((SessionCubit c) => c.state.user?.role)),
      ),
    ),
  );
}

class _VisualState {
  const _VisualState({this.phenotype, this.focus});

  /// Only this resistant type in the tiles; null is "All types".
  final Phenotype? phenotype;
  final Ward? focus;
}

class _VisualCubit extends Cubit<_VisualState> {
  _VisualCubit() : super(const _VisualState());

  void showType(Phenotype? p) => emit(_VisualState(phenotype: p, focus: state.focus));

  void focus(Ward w) => emit(_VisualState(phenotype: state.phenotype, focus: w));
}

// Colours that only this page uses, from the design canvas.
const _barMuted = Color(0xFFCFCEDB);
const _barStrong = Color(0xFF9F9DB5);
const _lineMuted = Color(0xFFA3A2B8);
const _critical = Color(0xFFB8003F);

/// Bacteria segments: the bar charts' colours, largest share first.
const _orgColors = [AmrColors.magenta, _barStrong, _barMuted];

/// The "usual" level on every chart: navy and dashed, drawn over the bars.
const _usualColor = AmrColors.ink;

const _weeksInTile = 8;

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<_VisualCubit>().state;
    final phone = context.isCompact;
    final user = context.select((SessionCubit c) => c.state.user);
    return PageBody(
      top: phone ? 12 : fluid(context, 24, 4, 56),
      gap: phone ? AmrSpace.x24 : AmrSpace.x28,
      children: [
        const _Header(),
        if (user?.role == Role.careWorker && user!.wards.isNotEmpty)
          ColumnGap(
            [
              SectionHeader(
                title: 'Your wards',
                subtitle: 'Where to clean more this week.',
                size: phone ? 24 : 30,
              ),
              WardStatus(query: SpreadingQuery(wards: user.wards)),
            ],
            gap: AmrSpace.x16,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          ),
        QueryView<SpreadingQuery, Spreading>(
          query: const SpreadingQuery(),
          fetch: (repo, q) => repo.spreading(q),
          builder: (context, spreading) => QueryView<SpreadingSeriesQuery, SpreadingSeries>(
            query: const SpreadingSeriesQuery(),
            fetch: (repo, q) => repo.spreadingSeries(q),
            builder: (context, series) => _Content(
              state: state,
              spreads: wardSpreads(spreading, only: state.phenotype),
              allSpreads: wardSpreads(spreading),
              series: series,
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final phone = context.isCompact;
    final title = ColumnGap([
      Breadcrumb(['Home', 'Whole hospital'], onTapFirst: () => goHome(context)),
      Text(
        'What is spreading',
        style: phone
            ? AmrText.sora(44, em: -0.04, height: 1)
            : AmrText.sora(fluidHW(context, 40, 5, 8, 68), em: -0.035, height: 1.02),
      ),
    ], gap: AmrSpace.x16);
    if (phone) return title;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 24,
      runSpacing: 20,
      children: [
        title,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AskLauncher(
            hint: 'Ask anything, e.g. where is MRSA this month?',
            size: AskFieldSize.large,
            about: AskContext.spreading(context.select((SessionCubit c) => c.state.user?.role)),
          ),
        ),
      ],
    );
  }
}

// Numbers ---------------------------------------------------------------------

/// A ward's weekly counts for one resistant type, or all four added up when [p] is null.
class _Counts {
  const _Counts(this.weekly, this.normalWeekly);

  factory _Counts.of(SpreadingSeries s, Ward w, Phenotype? p) {
    final rows = [
      for (final r in s.rows)
        if (r.ward == w && (p == null || r.phenotype == p)) r,
    ];
    return _Counts([
      for (var i = 0; i < s.weekStarts.length; i++)
        rows.fold(0, (a, r) => a + (r.weekly.elementAtOrNull(i) ?? 0)),
    ], rows.fold(0.0, (a, r) => a + r.normalWeekly));
  }

  final List<int> weekly;

  /// Typical count per week.
  final double normalWeekly;

  int _sum(int from, int to) {
    final end = math.max(0, weekly.length + to);
    final start = math.max(0, weekly.length + from);
    return weekly.sublist(start, end).fold(0, (a, b) => a + b);
  }

  /// The last four weeks.
  int get now => _sum(-4, 0);

  /// The four weeks before those.
  int get before => _sum(-8, -4);

  /// Typical count for four weeks.
  double get usual => normalWeekly * 4;
}

/// "3×", or "New" when the ward has none usually, or "Usual".
String _ratioLabel(int now, double usual, {required bool raised}) {
  if (!raised) return 'Usual';
  if (usual <= 0) return 'New';
  final r = (now / usual * 10).round() / 10;
  return '${r == r.roundToDouble() ? r.round() : r}×';
}

Color _tagBg(SpreadStatus s) => switch (s) {
  SpreadStatus.high => AmrColors.magenta,
  SpreadStatus.bit => AmrColors.blush,
  SpreadStatus.usual => AmrColors.lavenderSoft,
};

Color _tagFg(SpreadStatus s) => s == SpreadStatus.high ? AmrColors.white : AmrColors.ink;

SpreadStatus _statusOf(SpreadingRow? r) => r == null ? SpreadStatus.usual : spreadStatus(r);

class _Content extends StatelessWidget {
  const _Content({
    required this.state,
    required this.spreads,
    required this.allSpreads,
    required this.series,
  });

  final _VisualState state;
  final List<WardSpread> spreads;

  /// Every type, whatever the tiles show: the hero's "Also watch" looks across all of them.
  final List<WardSpread> allSpreads;
  final SpreadingSeries series;

  @override
  Widget build(BuildContext context) {
    final phone = context.isCompact;
    final p = state.phenotype;
    final top = spreads.where((s) => s.status.raised).firstOrNull;
    final ward = state.focus ?? top?.ward ?? Ward.uro;
    final focus = spreads.where((s) => s.ward == ward).firstOrNull;
    return ColumnGap(
      [
        _Hero(spread: top, phenotype: p, all: allSpreads, series: series),
        _WardTiles(spreads: spreads, series: series, phenotype: p, selected: ward),
        _WardDetail(
          key: ValueKey((ward, p)),
          ward: ward,
          phenotype: p,
          series: series,
          spread: focus,
        ),
        _FlowSection(key: ValueKey(ward), ward: ward, raised: focus),
      ],
      gap: phone ? AmrSpace.x24 : AmrSpace.x28,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );
  }
}

// Hero ------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({
    required this.spread,
    required this.phenotype,
    required this.all,
    required this.series,
  });

  final WardSpread? spread;
  final Phenotype? phenotype;
  final List<WardSpread> all;
  final SpreadingSeries series;

  /// The most notable raised ward and type other than the hero's own, new ones first.
  ({SpreadingRow row, bool isNew})? _watch(SpreadingRow hero) {
    final rows = [
      for (final w in all)
        for (final r in w.rows)
          if (spreadStatus(r).raised && !(r.ward == hero.ward && r.phenotype == hero.phenotype)) r,
    ];
    if (rows.isEmpty) return null;
    bool isNew(SpreadingRow r) => r.normal < 0.5;
    rows.sort((a, b) {
      final n = (isNew(b) ? 1 : 0).compareTo(isNew(a) ? 1 : 0);
      return n != 0 ? n : (b.count - b.normal).compareTo(a.count - a.normal);
    });
    return (row: rows.first, isNew: isNew(rows.first));
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isCompact;
    final s = spread;
    if (s == null) {
      return AmrCard(
        tone: AmrCardTone.subtle,
        radius: AmrRadius.panel,
        padding: EdgeInsets.all(fluid(context, 24, 3, 40)),
        child: Text(
          'No ward is above usual for ${phenotype?.code ?? 'any resistant type'} '
          'in the last 4 weeks.',
          style: AmrText.sora(phone ? 24 : 30, em: -0.03, height: 1.2),
        ),
      );
    }
    final row = s.top!;
    final c = _Counts.of(series, s.ward, row.phenotype);
    final mix = series.mix(s.ward);
    final organism = mix == null || mix.organisms.isEmpty
        ? null
        : (mix.organisms.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    final big = _ratioLabel(c.now, c.usual, raised: true);
    final watch = _watch(row);
    final left = ColumnGap([
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: AmrColors.magenta, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text('Most critical right now · ${s.ward.label}', style: AmrText.label(14)),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(big, style: AmrText.sora(phone ? 88 : 120, em: -0.05, height: 1)),
          const SizedBox(width: 18),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                big == 'New'
                    ? 'patients with ${row.phenotype.code},\nusually none'
                    : 'the usual number of\npatients with ${row.phenotype.code}',
                style: AmrText.body(20, height: 1.3),
              ),
            ),
          ),
        ],
      ),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${c.now} ${c.now == 1 ? 'patient' : 'patients'}',
              style: AmrText.label(16),
            ),
            TextSpan(
              text:
                  ' in the last 4 weeks'
                  '${organism == null ? '' : ' · mostly ${organism.short}'}',
            ),
          ],
        ),
        style: AmrText.body(16),
      ),
      if (watch != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(color: AmrColors.white, borderRadius: AmrRadius.pill),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Also watch  ',
                  style: AmrText.label(14).copyWith(color: AmrColors.magenta),
                ),
                TextSpan(
                  text: watch.isNew
                      ? '${watch.row.count} new ${watch.row.phenotype.code} '
                            '${watch.row.count == 1 ? 'patient' : 'patients'} '
                            'on ${watch.row.ward.label}'
                      : '${watch.row.count} ${watch.row.phenotype.code} patients on '
                            '${watch.row.ward.label}, usually ${usualLabel(watch.row.normal)}',
                ),
              ],
            ),
            style: AmrText.body(14),
          ),
        ),
    ], gap: AmrSpace.x14);
    final chart = _BarChart(
      values: [for (final v in c.weekly) v.toDouble()],
      usual: c.normalWeekly,
      height: 180,
      raisedFrom: c.weekly.length - 4,
      raisedColor: AmrColors.magenta,
      baseColor: _barMuted,
      usualLabel: 'usual/week',
      rightWidth: 96,
      band: true,
      semantics:
          '${s.ward.label} patients with ${row.phenotype.code} per week, last '
          '${c.weekly.length} weeks',
    );
    return AmrCard(
      tone: AmrCardTone.alert,
      radius: AmrRadius.panel,
      padding: EdgeInsets.all(fluid(context, 24, 3, 40)),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 800
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 32),
                  Expanded(child: chart),
                ],
              )
            : ColumnGap(
                [left, chart],
                gap: AmrSpace.x24,
                crossAxisAlignment: CrossAxisAlignment.stretch,
              ),
      ),
    );
  }
}

/// Weekly bars on a navy baseline with a scale on the left, light grid lines, and the dashed
/// "usual" level drawn over the bars with its label to the right. The weeks from [raisedFrom]
/// use [raisedColor]; with [band], they also sit on a pink band labelled "Last 4 weeks".
class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.values,
    required this.usual,
    required this.height,
    required this.raisedFrom,
    required this.raisedColor,
    required this.baseColor,
    required this.usualLabel,
    required this.rightWidth,
    required this.semantics,
    this.gap = 8,
    this.band = false,
  });

  final List<double> values;

  /// Typical count per week.
  final double usual;
  final double height;
  final int raisedFrom;
  final Color raisedColor;
  final Color baseColor;
  final String usualLabel;
  final double rightWidth;
  final String semantics;

  final double gap;
  final bool band;

  @override
  Widget build(BuildContext context) {
    // The scale follows the data: one step per patient while the counts are small
    // (0, 1, 2, 3, 4), bigger steps only once there would be more than six ticks.
    final peak = values.fold<double>(usual, (m, v) => math.max(m, v));
    final need = math.max(1, peak.ceil());
    final step = need <= 6 ? 1 : (need / 5).ceil();
    final top = (need / step).ceil() * step;
    final max = top.toDouble();
    final ticks = [for (var t = 0; t <= top; t += step) t];
    final h = height;
    double at(double v) => v / max * h;
    final pad = band ? 26.0 : 0.0;
    return Semantics(
      label: semantics,
      child: Padding(
        padding: EdgeInsets.only(top: pad),
        child: SizedBox(
          height: h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 18,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final t in ticks)
                      Positioned(
                        right: 0,
                        bottom: at(t.toDouble()) - 7,
                        child: Text('$t', style: AmrText.body(12, height: 14 / 12)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    final share = values.isEmpty ? 0.0 : math.min(1.0, 4 / values.length);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final t in ticks.where((t) => t > 0))
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: at(t.toDouble()),
                            child: Container(
                              height: 1,
                              color: AmrColors.ink.withValues(alpha: band ? 0.12 : 0.10),
                            ),
                          ),
                        if (band) ...[
                          Positioned(
                            top: -26,
                            bottom: 0,
                            right: -4,
                            width: w * share + 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AmrColors.magenta.withValues(alpha: 0.10),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                              ),
                            ),
                          ),
                          Positioned(
                            top: -22,
                            right: 0,
                            width: w * share,
                            child: Text(
                              'Last 4 weeks',
                              textAlign: TextAlign.center,
                              style: AmrText.label(12).copyWith(color: _critical),
                            ),
                          ),
                          Positioned(
                            top: -22,
                            left: 0,
                            width: w * (1 - share),
                            child: Text(
                              '${values.length - 4} weeks before',
                              textAlign: TextAlign.center,
                              style: AmrText.label(12),
                            ),
                          ),
                        ],
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 0; i < values.length; i++) ...[
                                if (i > 0) SizedBox(width: gap),
                                Expanded(
                                  child: Container(
                                    // A week with none has no bar: the scale starts at 0.
                                    height: values[i] <= 0 ? 0 : math.max(2, at(values[i])),
                                    decoration: BoxDecoration(
                                      color: i >= raisedFrom ? raisedColor : baseColor,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6),
                                        bottom: Radius.circular(2),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // The baseline sits on 0, where the bars start and the "0" is labelled.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: -0.75,
                          child: Container(height: 1.5, color: AmrColors.ink),
                        ),
                        Positioned(
                          left: 0,
                          right: -14,
                          bottom: at(usual),
                          child: CustomPaint(
                            size: const Size(double.infinity, 2.5),
                            painter: _DashedLine(width: 2.5),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(
                width: rightWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 18,
                      bottom: at(usual) - 8,
                      child: Text(
                        usualLabel,
                        style: AmrText.label(
                          band ? 13 : 12,
                        ).copyWith(height: band ? 16 / 13 : 1.25),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedLine extends CustomPainter {
  _DashedLine({this.width = 2});

  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _usualColor
      ..strokeWidth = width;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 5, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => old.width != width;
}

// Ward tiles ------------------------------------------------------------------

class _WardTiles extends StatelessWidget {
  const _WardTiles({
    required this.spreads,
    required this.series,
    required this.phenotype,
    required this.selected,
  });

  final List<WardSpread> spreads;
  final SpreadingSeries series;
  final Phenotype? phenotype;
  final Ward selected;

  @override
  Widget build(BuildContext context) {
    final phone = context.isCompact;
    final cubit = context.read<_VisualCubit>();
    final what = phenotype == null
        ? 'Patients with any resistant type per week'
        : 'Patients with ${phenotype!.code} per week';
    return ColumnGap(
      [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 10,
          children: [
            Text('All wards', style: AmrText.sora(phone ? 24 : 28, em: -0.02)),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AmrButton.toggle(
                  label: 'All types',
                  selected: phenotype == null,
                  size: AmrButtonSize.md,
                  fontSize: 14,
                  onPressed: () => cubit.showType(null),
                ),
                for (final p in Phenotype.values)
                  AmrButton.toggle(
                    label: p.code,
                    selected: phenotype == p,
                    size: AmrButtonSize.md,
                    fontSize: 14,
                    onPressed: () => cubit.showType(p),
                  ),
              ],
            ),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _LegendItem(label: '$what, $_weeksInTile weeks', dashed: false),
                const _LegendItem(label: 'Usual', dashed: true),
              ],
            ),
          ],
        ),
        AutoGrid(
          minItemWidth: 240,
          gap: AmrSpace.x12,
          children: [
            // Always the same order, so a tile does not move when the numbers change.
            for (final w in [...spreads]..sort((a, b) => a.ward.index.compareTo(b.ward.index)))
              _WardTile(
                spread: w,
                counts: _Counts.of(series, w.ward, phenotype),
                selected: w.ward == selected,
                onTap: () => cubit.focus(w.ward),
              ),
          ],
        ),
      ],
      gap: AmrSpace.x14,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.dashed});

  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 18,
        child: dashed
            ? CustomPaint(size: const Size(18, 2.5), painter: _DashedLine(width: 2.5))
            : Container(height: 2.5, color: AmrColors.magenta),
      ),
      const SizedBox(width: 6),
      Text(label, style: AmrText.body(13)),
    ],
  );
}

class _WardTile extends StatelessWidget {
  const _WardTile({
    required this.spread,
    required this.counts,
    required this.selected,
    required this.onTap,
  });

  final WardSpread spread;
  final _Counts counts;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = spread.status;
    final raised = status.raised;
    final last = _smooth(counts.weekly).skip(math.max(0, counts.weekly.length - _weeksInTile));
    final diff = counts.now - counts.before;
    final trend = diff > 0
        ? '↑ up from ${counts.before} before'
        : diff < 0
        ? '↓ down from ${counts.before} before'
        : '→ same as before';
    return Pressable(
      onTap: onTap,
      pressScale: 0.99,
      builder: (_, s) => AnimatedContainer(
        duration: AmrMotion.base,
        curve: AmrMotion.curve,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: status.background,
          borderRadius: AmrRadius.card,
          border: Border.all(color: selected ? AmrColors.ink : Colors.transparent, width: 2),
          boxShadow: s.hovered ? AmrShadows.md : status.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    spread.ward.label,
                    style: AmrText.body(16, weight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _tagBg(status), borderRadius: AmrRadius.pill),
                  child: Text(
                    _ratioLabel(counts.now, counts.usual, raised: raised),
                    style: AmrText.label(13).copyWith(color: _tagFg(status)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('${counts.now}', style: AmrText.sora(44, em: -0.03, height: 1)),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('patients in 4 weeks', style: AmrText.body(13, height: 1.3)),
                      Text(
                        trend,
                        style: AmrText.label(13).copyWith(
                          height: 1.3,
                          color: diff > 0 && raised ? _critical : AmrColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: CustomPaint(
                painter: _SparkPainter(
                  values: last.toList(),
                  usual: counts.normalWeekly,
                  color: raised ? AmrColors.magenta : _lineMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trailing 3-week average, so one busy week does not read as a spike on a small ward.
List<double> _smooth(List<int> weekly) => [
  for (var i = 0; i < weekly.length; i++)
    weekly.sublist(math.max(0, i - 2), i + 1).fold(0, (a, b) => a + b) /
        (i - math.max(0, i - 2) + 1),
];

/// The last weeks as a line on a 160 x 48 grid, with a dashed usual level, as in the design.
class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.usual, required this.color});

  final List<double> values;
  final double usual;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final max = values.fold<double>(math.max(3.5, usual), (m, v) => math.max(m, v.toDouble()));
    double y(double v) => size.height * (44 - v / max * 40) / 48;
    final u = Paint()
      ..color = _usualColor
      ..strokeWidth = 2;
    final uy = y(usual);
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, uy), Offset(math.min(x + 5, size.width), uy), u);
    }
    // Quadratic curves between the midpoints of neighbouring points: smooth, never overshoots.
    final pts = [
      for (var i = 0; i < values.length; i++)
        Offset(values.length == 1 ? 0.0 : i * size.width / (values.length - 1), y(values[i])),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.usual != usual || old.color != color;
}

// Ward detail -----------------------------------------------------------------

class _WardDetail extends StatelessWidget {
  const _WardDetail({
    super.key,
    required this.ward,
    required this.phenotype,
    required this.series,
    required this.spread,
  });

  final Ward ward;
  final Phenotype? phenotype;
  final SpreadingSeries series;
  final WardSpread? spread;

  Future<void> _pin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context.read<DashboardCubit>().pin(
      WidgetPlacement(
        widget: 'SpreadingCounts',
        params: {if (phenotype != null) 'phenotype': phenotype!.code},
      ),
    );
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? 'Pinned to your home' : 'Could not pin it, try again')),
    );
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final buffer = StringBuffer(
      'week_start,${[for (final p in Phenotype.values) p.code].join(',')}\n',
    );
    for (var i = 0; i < series.weekStarts.length; i++) {
      final cells = [
        for (final p in Phenotype.values) series.row(ward, p)?.weekly.elementAtOrNull(i) ?? 0,
      ];
      buffer.writeln('${formatDate(series.weekStarts[i])},${cells.join(',')}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    messenger.showSnackBar(const SnackBar(content: Text('Weekly counts copied as CSV')));
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isCompact;
    final actions = context.read<CatalogActions>();
    final c = _Counts.of(series, ward, phenotype);
    final weekly = c.weekly;
    final label = phenotype?.code ?? 'resistant';
    final mix = series.mix(ward);
    final types = {for (final p in Phenotype.values) p: _Counts.of(series, ward, p)};
    final found = types.values.fold(0, (a, b) => a + b.now);
    final short = ward == Ward.ed ? 'the ED' : ward.short;

    final header = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 16,
      children: [
        ColumnGap([
          Text('Ward detail · last 4 weeks', style: AmrText.label(14)),
          Text(ward.label, style: AmrText.sora(fluid(context, 30, 3, 42), em: -0.03)),
          Text(
            '${mix?.cultures ?? 0} cultures tested · $found resistant finds',
            style: AmrText.body(14),
          ),
        ], gap: AmrSpace.x6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AmrButton(
              label: 'Ask about $short',
              size: AmrButtonSize.md,
              fontSize: 14,
              onPressed: () => actions.ask(
                'Tell me about ${phenotype?.code ?? 'resistant bacteria'} on ${ward.label}',
              ),
            ),
            AmrButton(
              label: 'Export',
              size: AmrButtonSize.md,
              fontSize: 14,
              onPressed: () => _export(context),
            ),
            AmrButton(
              label: 'Pin to my home',
              size: AmrButtonSize.md,
              fontSize: 14,
              variant: AmrButtonVariant.primary,
              onPressed: () => _pin(context),
            ),
          ],
        ),
      ],
    );

    final chart = ColumnGap(
      [
        ColumnGap([
          Text('Patients with a new $label finding, per week', style: AmrText.label(15)),
          Text(
            'Each bar is one week. Read the number of patients from the scale on the left.',
            style: AmrText.body(13),
          ),
        ], gap: AmrSpace.x4),
        Text('Patients', style: AmrText.label(12)),
        _BarChart(
          values: [for (final v in weekly) v.toDouble()],
          usual: c.normalWeekly,
          height: 170,
          raisedFrom: weekly.length - 4,
          raisedColor: AmrColors.magenta,
          baseColor: _barMuted,
          usualLabel: 'usual/week',
          rightWidth: 96,
          gap: 6,
          semantics:
              '${ward.label} patients with a new $label finding per week: ${weekly.join(', ')}',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 0, 104, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Week of ${_shortDate(series.weekStarts.firstOrNull)}', style: AmrText.body(12)),
              Text('Week of ${_shortDate(series.weekStarts.lastOrNull)}', style: AmrText.body(12)),
            ],
          ),
        ),
      ],
      gap: AmrSpace.x10,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );

    final orgs = (mix?.organisms.entries.toList() ?? [])
      ..sort((a, b) => b.value.compareTo(a.value));
    final orgTotal = orgs.fold(0, (a, e) => a + e.value);
    final side = ColumnGap(
      [
        ColumnGap(
          [
            Text('By resistant type', style: AmrText.body(14, weight: FontWeight.w500)),
            for (final p in [?phenotype, ...Phenotype.values.where((x) => x != phenotype)])
              _TypeRow(
                phenotype: p,
                counts: types[p]!,
                max: types.values.fold<double>(
                  4,
                  (m, t) => math.max(m, math.max(t.now.toDouble(), t.usual)),
                ),
                row: spread?.rows.where((r) => r.phenotype == p).firstOrNull,
              ),
          ],
          gap: AmrSpace.x8,
          crossAxisAlignment: CrossAxisAlignment.stretch,
        ),
        ColumnGap(
          [
            Text('Which bacteria', style: AmrText.body(14, weight: FontWeight.w500)),
            if (orgTotal == 0)
              Text('No resistant finds on this ward in the last 4 weeks.', style: AmrText.body(13))
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 18,
                  child: Row(
                    children: [
                      for (var i = 0; i < orgs.length; i++)
                        Expanded(
                          flex: orgs[i].value,
                          child: ColoredBox(
                            color: _orgColors[math.min(i, 2)],
                            child: const SizedBox.expand(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < orgs.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _orgColors[math.min(i, 2)],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('${orgs[i].key.short} ${orgs[i].value}', style: AmrText.body(13)),
                      ],
                    ),
                ],
              ),
            ],
          ],
          gap: AmrSpace.x8,
          crossAxisAlignment: CrossAxisAlignment.stretch,
        ),
      ],
      gap: AmrSpace.x22,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );

    return AmrCard(
      tone: AmrCardTone.raised,
      radius: AmrRadius.panel,
      padding: EdgeInsets.all(fluid(context, 24, 3, 40)),
      child: ColumnGap(
        [
          header,
          LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 860 && !phone
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: chart),
                      const SizedBox(width: 32),
                      Expanded(child: side),
                    ],
                  )
                : ColumnGap(
                    [chart, side],
                    gap: AmrSpace.x24,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                  ),
          ),
        ],
        gap: AmrSpace.x24,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

String _shortDate(DateTime? d) => d == null ? '' : '${d.day}.${d.month}.';

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.phenotype,
    required this.counts,
    required this.max,
    required this.row,
  });

  final Phenotype phenotype;
  final _Counts counts;
  final double max;
  final SpreadingRow? row;

  @override
  Widget build(BuildContext context) {
    final isNew = counts.now > 0 && counts.usual <= 0;
    final status = _statusOf(row);
    final (label, bg, fg, bar) = isNew
        ? ('New', AmrColors.magenta, AmrColors.white, AmrColors.magenta)
        : status.raised
        ? ('Higher', AmrColors.blush, AmrColors.ink, AmrColors.magenta)
        : ('Usual', AmrColors.lavenderSoft, AmrColors.ink, AmrColors.ink);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AmrColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(phenotype.code, style: AmrText.label(14))),
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SizedBox(
                height: 12,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AmrColors.lavenderSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    Container(
                      width: box.maxWidth * counts.now / max,
                      decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(6)),
                    ),
                    Positioned(
                      left: box.maxWidth * math.min(counts.usual, max) / max - 1,
                      top: -3,
                      bottom: -3,
                      child: Container(width: 2, color: AmrColors.ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${counts.now}', style: AmrText.label(14)),
                  TextSpan(text: ' · usual ${usualLabel(counts.usual)}'),
                ],
              ),
              style: AmrText.body(14),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: AmrRadius.pill),
            child: Text(label, style: AmrText.label(12).copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

// Linked wards ----------------------------------------------------------------

class _FlowSection extends StatelessWidget {
  const _FlowSection({super.key, required this.ward, required this.raised});

  final Ward ward;
  final WardSpread? raised;

  @override
  Widget build(BuildContext context) => QueryView<WardLinksQuery, WardLinks>(
    query: WardLinksQuery(ward: ward),
    fetch: (repo, q) => repo.wardLinks(q),
    builder: (context, links) => BlocProvider(
      create: (_) => HeadsUpCubit(),
      child: _Flow(links: links, raised: raised),
    ),
  );
}

class _Flow extends StatefulWidget {
  const _Flow({required this.links, required this.raised});

  final WardLinks links;
  final WardSpread? raised;

  @override
  State<_Flow> createState() => _FlowState();
}

class _FlowState extends State<_Flow> {
  Ward? _to;
  String _search = '';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pick(Ward w) => setState(() {
    _to = w;
    _search = '';
    _controller.clear();
  });

  @override
  Widget build(BuildContext context) {
    final phone = context.isCompact;
    final from = widget.links.ward;
    final top = widget.links.links.take(3).toList();
    final rest = widget.links.links.skip(3).toList();
    final topRow = widget.raised?.top;
    final shown = topRow != null && widget.raised!.status.raised ? topRow : null;
    final cubit = context.read<HeadsUpCubit>();
    final matches = _search.trim().isEmpty
        ? const <Ward>[]
        : [
            for (final w in Ward.values)
              if (w != from &&
                  (w.label.toLowerCase().contains(_search.trim().toLowerCase()) ||
                      w.code.toLowerCase().contains(_search.trim().toLowerCase())))
                w,
          ];
    final text = ColumnGap([
      Text('Early warning', style: AmrText.label(14)),
      Text(
        'Where ${from.label} patients go next',
        style: AmrText.sora(fluid(context, 28, 3, 38), em: -0.03, height: 1.1),
      ),
      Text(
        'The thicker the line, the more patients were sampled on both wards within 30 days. '
        'Totals only.',
        style: AmrText.body(14),
      ),
    ], gap: AmrSpace.x10);
    final flow = _FlowDiagram(from: from, shown: shown, links: top, selected: _to, onPick: _pick);
    return AmrCard(
      tone: AmrCardTone.accent,
      radius: AmrRadius.panel,
      padding: EdgeInsets.all(fluid(context, 24, 3, 40)),
      child: ColumnGap(
        [
          LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 860 && !phone
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: text),
                      const SizedBox(width: 24),
                      Expanded(child: flow),
                    ],
                  )
                : ColumnGap(
                    [text, flow],
                    gap: AmrSpace.x24,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            decoration: BoxDecoration(color: AmrColors.white, borderRadius: AmrRadius.card),
            child: ColumnGap(
              [
                ColumnGap([
                  Text('Patient going somewhere less common?', style: AmrText.label(16)),
                  Text(
                    'Warn any ward. They get the totals and what to watch for, '
                    'never patient details.',
                    style: AmrText.body(14),
                  ),
                ], gap: AmrSpace.x4),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 280, maxWidth: 520),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: AmrColors.lavenderSoft,
                          borderRadius: AmrRadius.pill,
                          border: Border.all(color: AmrColors.periwinkle),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, size: 18, color: AmrColors.ink),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                onChanged: (v) => setState(() => _search = v),
                                style: AmrText.body(15),
                                decoration: InputDecoration.collapsed(
                                  hintText: 'Find a ward, e.g. Surgery or Health centre North',
                                  hintStyle: AmrText.body(
                                    15,
                                  ).copyWith(color: AmrColors.ink.withValues(alpha: 0.6)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_to != null)
                      Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                        decoration: const BoxDecoration(
                          color: AmrColors.ink,
                          borderRadius: AmrRadius.pill,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _to!.label,
                              style: AmrText.body(14).copyWith(color: AmrColors.white),
                            ),
                            const SizedBox(width: 8),
                            Pressable(
                              onTap: () => setState(() => _to = null),
                              builder: (_, _) => Container(
                                width: 26,
                                height: 26,
                                decoration: const BoxDecoration(
                                  color: Color(0x33FFFFFF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, size: 14, color: AmrColors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (matches.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final w in matches) _LinkChip(label: w.label, onTap: () => _pick(w)),
                    ],
                  ),
                if (rest.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          'Other wards sharing patients with ${from.label}:',
                          style: AmrText.body(13),
                        ),
                      ),
                      for (final l in rest)
                        _LinkChip(
                          label: '+ ${l.ward.label} · ${l.sharedPatients30d}',
                          onTap: () => _pick(l.ward),
                        ),
                    ],
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _HeadsUpButton(
                      enabled: _to != null,
                      onTap: () => cubit.draft(
                        _to!,
                        headsUpMessage(from, organism: null, phenotype: shown?.phenotype),
                      ),
                    ),
                  ],
                ),
                BlocBuilder<HeadsUpCubit, HeadsUpState>(
                  builder: (context, s) => AnimatedSize(
                    duration: AmrMotion.base,
                    curve: AmrMotion.curve,
                    alignment: Alignment.topCenter,
                    child: switch (s.step) {
                      HeadsUpStep.idle => const SizedBox(width: double.infinity),
                      HeadsUpStep.sent => ActionPill(
                        message:
                            'Heads-up sent to the ${s.to!.label} at '
                            '${s.sentAt!.hour.toString().padLeft(2, '0')}:'
                            '${s.sentAt!.minute.toString().padLeft(2, '0')}',
                        actionLabel: 'Undo',
                        onAction: cubit.undo,
                      ),
                      _ => HeadsUpDraft(state: s),
                    },
                  ),
                ),
              ],
              gap: AmrSpace.x12,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            ),
          ),
        ],
        gap: AmrSpace.x24,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

class _HeadsUpButton extends StatelessWidget {
  const _HeadsUpButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: enabled ? onTap : null,
    builder: (_, s) => Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: const BoxDecoration(color: AmrColors.magenta, borderRadius: AmrRadius.pill),
        child: Center(
          widthFactor: 1,
          child: Text('Send heads-up', style: AmrText.label(15).copyWith(color: AmrColors.white)),
        ),
      ),
    ),
  );
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    builder: (_, s) => Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: s.hovered ? AmrColors.lavenderSoft : AmrColors.white,
        borderRadius: AmrRadius.pill,
        border: Border.all(color: AmrColors.lavender),
      ),
      child: Center(widthFactor: 1, child: Text(label, style: AmrText.body(13))),
    ),
  );
}

/// The ward as a circle with up to three curves to the wards it shares the most patients with.
/// Drawn on the design's 600 x 260 grid and scaled to the width.
class _FlowDiagram extends StatelessWidget {
  const _FlowDiagram({
    required this.from,
    required this.shown,
    required this.links,
    required this.selected,
    required this.onPick,
  });

  final Ward from;
  final SpreadingRow? shown;
  final List<WardLink> links;
  final Ward? selected;
  final ValueChanged<Ward> onPick;

  static const _ys = [40.0, 130.0, 220.0];

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return Text('No ward shares many patients with ${from.label}.', style: AmrText.body(15));
    }
    final maxShared = links.fold<int>(1, (m, l) => math.max(m, l.sharedPatients30d));
    // Fewer than three links sit in the middle rows so the curves stay symmetric.
    final rows = links.length == 3
        ? _ys
        : links.length == 2
        ? [_ys[0] + 45, _ys[2] - 45]
        : [_ys[1]];
    return AspectRatio(
      aspectRatio: 600 / 260,
      child: LayoutBuilder(
        builder: (context, box) {
          final k = box.maxWidth / 600;
          double width(int n) => 8 + 22 * n / maxShared;
          final warn = shown != null;
          return Semantics(
            label:
                '${from.label} shares patients with ${[for (final l in links) '${l.sharedPatients30d} with ${l.ward.label}'].join(', ')}',
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FlowPainter(
                      rows: rows,
                      widths: [for (final l in links) width(l.sharedPatients30d)],
                      warm: [for (final l in links) l.warning != null || l.ward == selected],
                      raised: warn,
                    ),
                  ),
                ),
                Positioned(
                  left: 6 * k,
                  top: (130 - 58) * k,
                  width: 116 * k,
                  height: 116 * k,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: warn ? AmrColors.magenta : AmrColors.ink,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            from.short,
                            textAlign: TextAlign.center,
                            style: AmrText.sora(
                              17 * k,
                              weight: FontWeight.w400,
                              em: 0,
                            ).copyWith(color: AmrColors.white),
                          ),
                          if (warn)
                            Text(
                              '${shown!.phenotype.code} up',
                              style: AmrText.body(13 * k).copyWith(color: AmrColors.white),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < links.length; i++)
                  Positioned(
                    left: 340 * k,
                    top: (rows[i] - 28) * k,
                    width: 250 * k,
                    height: 56 * k,
                    child: Pressable(
                      onTap: () => onPick(links[i].ward),
                      pressScale: 0.99,
                      builder: (_, s) => Container(
                        padding: EdgeInsets.symmetric(horizontal: 22 * k),
                        decoration: BoxDecoration(
                          color: links[i].warning != null ? AmrColors.blush : AmrColors.white,
                          borderRadius: AmrRadius.pill,
                          border: links[i].ward == selected
                              ? Border.all(color: AmrColors.ink, width: 2)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    links[i].ward.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: AmrText.body(15 * k, weight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${links[i].sharedPatients30d} patients shared',
                                    style: AmrText.body(13 * k),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Warn ›',
                              style: AmrText.label(13 * k).copyWith(
                                color: links[i].warning != null ? AmrColors.magenta : AmrColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.rows,
    required this.widths,
    required this.warm,
    required this.raised,
  });

  final List<double> rows;
  final List<double> widths;
  final List<bool> warm;
  final bool raised;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 600;
    for (var i = 0; i < rows.length; i++) {
      final y = rows[i] * k;
      final path = Path()
        ..moveTo(110 * k, 130 * k)
        ..cubicTo(240 * k, 130 * k, 240 * k, y, 370 * k, y);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = widths[i] * k
          ..color = warm[i] && raised
              ? AmrColors.magenta
              : AmrColors.ink.withValues(alpha: i == 0 ? 0.85 : 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.rows != rows || old.widths != widths || old.warm != warm || old.raised != raised;
}

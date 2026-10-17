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
  const _VisualState({this.phenotype = Phenotype.esbl, this.focus});

  final Phenotype phenotype;
  final Ward? focus;
}

class _VisualCubit extends Cubit<_VisualState> {
  _VisualCubit() : super(const _VisualState());

  void showType(Phenotype p) => emit(_VisualState(phenotype: p, focus: state.focus));

  void focus(Ward w) => emit(_VisualState(phenotype: state.phenotype, focus: w));
}

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
        _Header(state: state),
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
              series: series,
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final _VisualState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<_VisualCubit>();
    final phone = context.isCompact;
    final title = ColumnGap([
      Breadcrumb(['Home', 'Whole hospital'], onTapFirst: () => goHome(context)),
      Text(
        'What is spreading',
        style: phone
            ? AmrText.sora(44, em: -0.04, height: 1)
            : AmrText.sora(fluidHW(context, 40, 5, 8, 68), em: -0.035, height: 1.02),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in Phenotype.values)
            AmrButton.toggle(
              label: p.code,
              selected: state.phenotype == p,
              size: AmrButtonSize.md,
              fontSize: 15,
              onPressed: () => cubit.showType(p),
            ),
        ],
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

/// Count of the last four weeks of a ward and type, and the usual for the same four weeks.
class _Counts {
  const _Counts(this.now, this.usual, this.row);

  final int now;
  final double usual;
  final SpreadingSeriesRow? row;

  factory _Counts.of(SpreadingSeries s, Ward w, Phenotype p) {
    final r = s.row(w, p);
    final now = r == null
        ? 0
        : r.weekly.skip(math.max(0, r.weekly.length - 4)).fold(0, (a, b) => a + b);
    return _Counts(now, (r?.normalWeekly ?? 0) * 4, r);
  }

  double get ratio => usual > 0 ? now / usual : 0;
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
  const _Content({required this.state, required this.spreads, required this.series});

  final _VisualState state;
  final List<WardSpread> spreads;
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
        _Hero(spread: top, phenotype: p, series: series),
        _WardTiles(spreads: spreads, series: series, phenotype: p, selected: ward),
        _WardDetail(
          key: ValueKey((ward, p)),
          ward: ward,
          phenotype: p,
          series: series,
          spread: focus,
          allSpreads: spreads,
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
  const _Hero({required this.spread, required this.phenotype, required this.series});

  final WardSpread? spread;
  final Phenotype phenotype;
  final SpreadingSeries series;

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
          'No ward is above usual for ${phenotype.code} in the last 4 weeks.',
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
    final weekly = c.row?.weekly ?? const <int>[];
    final big = _ratioLabel(c.now, c.usual, raised: true);
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
          Text('Needs action · ${s.ward.label}', style: AmrText.label(14)),
        ],
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(big, style: AmrText.sora(phone ? 88 : 120, em: -0.05, height: 0.9)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              big == 'New'
                  ? 'patients with ${row.phenotype.code},\nusually none'
                  : 'the usual number of\npatients with ${row.phenotype.code}',
              style: AmrText.body(18, height: 1.35),
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
                  ' in the last 4 weeks · usually ${usualLabel(c.usual)}'
                  '${organism == null ? '' : ' · mostly ${organism.short}'}',
            ),
          ],
        ),
        style: AmrText.body(16),
      ),
    ], gap: AmrSpace.x14);
    final chart = ColumnGap(
      [
        _WeekBars(
          values: weekly,
          usual: c.row?.normalWeekly ?? 0,
          height: 180,
          raisedFrom: weekly.length - 4,
          raisedColor: AmrColors.magenta,
          baseColor: AmrColors.ink,
          usualLabel: 'usual',
          semantics:
              '${s.ward.label} ${row.phenotype.code} cases per week, last ${weekly.length} weeks',
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Patients per week · ${weekly.length} weeks ago', style: AmrText.body(12)),
            Text('Last 4 weeks', style: AmrText.label(12)),
          ],
        ),
      ],
      gap: AmrSpace.x10,
      crossAxisAlignment: CrossAxisAlignment.stretch,
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

/// Bars per week on a navy baseline with a dashed "usual" level. The last weeks, from
/// [raisedFrom], use [raisedColor]. [showValues] puts the count on top of each bar.
class _WeekBars extends StatelessWidget {
  const _WeekBars({
    required this.values,
    required this.usual,
    required this.height,
    required this.raisedFrom,
    required this.raisedColor,
    required this.baseColor,
    required this.usualLabel,
    required this.semantics,
    this.showValues = false,
    this.gap = 8,
  });

  final List<int> values;

  /// Typical count per week.
  final double usual;
  final double height;
  final int raisedFrom;
  final Color raisedColor;
  final Color baseColor;
  final String usualLabel;
  final String semantics;
  final bool showValues;
  final double gap;
  static const minMax = 3.5;
  static const fill = 0.85;

  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(math.max(minMax, usual), (m, v) => math.max(m, v.toDouble()));
    final usualBottom = usual / max * fill;
    return Semantics(
      label: semantics,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, box) {
            final h = box.maxHeight;
            return Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AmrColors.ink, width: 1.5)),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: usualBottom * h,
                    child: CustomPaint(
                      size: const Size(double.infinity, 1.5),
                      painter: _DashedLine(),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: usualBottom * h + 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      color: showValues ? AmrColors.white : null,
                      child: Text(usualLabel, style: AmrText.body(showValues ? 11 : 12)),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < values.length; i++) ...[
                        if (i > 0) SizedBox(width: gap),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (showValues)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text('${values[i]}', style: AmrText.label(13)),
                                ),
                              Container(
                                height: math.max(
                                  showValues ? 2 : 3,
                                  values[i] / max * fill * (showValues ? h - 22 : h),
                                ),
                                decoration: BoxDecoration(
                                  color: i >= raisedFrom ? raisedColor : baseColor,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6),
                                    bottom: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashedLine extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AmrColors.ink.withValues(alpha: 0.55)
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 4, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLine old) => false;
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
  final Phenotype phenotype;
  final Ward selected;

  @override
  Widget build(BuildContext context) {
    final phone = context.isCompact;
    final cubit = context.read<_VisualCubit>();
    final legend = Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendItem(label: 'Patients with ${phenotype.code} per week', dashed: false),
        const _LegendItem(label: 'Usual', dashed: true),
      ],
    );
    return ColumnGap(
      [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 16,
          runSpacing: 8,
          children: [
            ColumnGap([
              Text('All wards', style: AmrText.sora(phone ? 24 : 28, em: -0.02)),
              Text('Tap a ward to see its data.', style: AmrText.body(14)),
            ], gap: AmrSpace.x4),
            legend,
          ],
        ),
        AutoGrid(
          minItemWidth: 240,
          gap: AmrSpace.x12,
          children: [
            for (final w in spreads)
              _WardTile(
                spread: w,
                counts: _Counts.of(series, w.ward, phenotype),
                counts3: [
                  for (final o in Phenotype.values)
                    if (o != phenotype) (o, _Counts.of(series, w.ward, o)),
                ],
                phenotype: phenotype,
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
            ? CustomPaint(size: const Size(18, 1.5), painter: _DashedLine())
            : Container(height: 2.5, color: AmrColors.ink),
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
    required this.counts3,
    required this.phenotype,
    required this.selected,
    required this.onTap,
  });

  final WardSpread spread;
  final _Counts counts;
  final List<(Phenotype, _Counts)> counts3;
  final Phenotype phenotype;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = spread.status;
    final weekly = counts.row?.weekly ?? const <int>[];
    final last = weekly.skip(math.max(0, weekly.length - _weeksInTile)).toList();
    final raised = status.raised;
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${counts.now}', style: AmrText.sora(44, em: -0.03, height: 1)),
                    const SizedBox(height: 6),
                    Text('patients · usual ${usualLabel(counts.usual)}', style: AmrText.body(12)),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: CustomPaint(
                      painter: _SparkPainter(
                        values: last,
                        usual: counts.row?.normalWeekly ?? 0,
                        color: raised ? AmrColors.magenta : AmrColors.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x261D204E))),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < counts3.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: _TypeChip(phenotype: counts3[i].$1, counts: counts3[i].$2),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.phenotype, required this.counts});

  final Phenotype phenotype;
  final _Counts counts;

  @override
  Widget build(BuildContext context) {
    final isNew = counts.now > 0 && counts.usual <= 0;
    final higher = counts.now >= 2 && counts.now > counts.usual * 1.4;
    final (bg, fg) = isNew
        ? (AmrColors.magenta, AmrColors.white)
        : higher
        ? (AmrColors.blush, AmrColors.ink)
        : (const Color(0xB3FFFFFF), AmrColors.ink);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(phenotype.code, style: AmrText.body(12).copyWith(color: fg)),
          const SizedBox(width: 4),
          Text('${counts.now}', style: AmrText.label(12).copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// The last weeks as a line on a 160 x 48 grid, with a dashed usual level, as in the design.
class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.usual, required this.color});

  final List<int> values;
  final double usual;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final max = values.fold<double>(math.max(3.5, usual), (m, v) => math.max(m, v.toDouble()));
    double y(double v) => size.height * (44 - v / max * 40) / 48;
    final u = Paint()
      ..color = AmrColors.ink.withValues(alpha: 0.6)
      ..strokeWidth = 1.2;
    final uy = y(usual);
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, uy), Offset(math.min(x + 4, size.width), uy), u);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : i * size.width / (values.length - 1);
      i == 0 ? path.moveTo(x, y(values[i].toDouble())) : path.lineTo(x, y(values[i].toDouble()));
    }
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
    required this.allSpreads,
  });

  final Ward ward;
  final Phenotype phenotype;
  final SpreadingSeries series;
  final WardSpread? spread;
  final List<WardSpread> allSpreads;

  Future<void> _pin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context.read<DashboardCubit>().pin(
      WidgetPlacement(widget: 'SpreadingCounts', params: {'phenotype': phenotype.code}),
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
    final weekly = c.row?.weekly ?? const <int>[];
    final mix = series.mix(ward);
    final types = {for (final p in Phenotype.values) p: _Counts.of(series, ward, p)};
    final found = types.values.fold(0, (a, b) => a + b.now);
    final raised = _statusOf(
      spread?.rows.where((r) => r.phenotype == phenotype).firstOrNull,
    ).raised;
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
              onPressed: () => actions.ask('Tell me about ${phenotype.code} on ${ward.label}'),
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
          Text('Patients with a new ${phenotype.code} finding, per week', style: AmrText.label(15)),
          Text(
            'Each bar is one week. The number on top is how many patients.',
            style: AmrText.body(13),
          ),
        ], gap: AmrSpace.x4),
        Text('Patients', style: AmrText.label(12)),
        _WeekBars(
          values: weekly,
          usual: c.row?.normalWeekly ?? 0,
          height: 170,
          raisedFrom: weekly.length - 4,
          raisedColor: raised ? AmrColors.magenta : AmrColors.violet,
          baseColor: AmrColors.lavender,
          usualLabel: 'usual ${_usualWeek(c.row?.normalWeekly ?? 0)} a week',
          semantics:
              '${ward.label} patients with a new ${phenotype.code} finding per week: ${weekly.join(', ')}',
          showValues: true,
          gap: 6,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Week of ${_shortDate(series.weekStarts.firstOrNull)}', style: AmrText.body(12)),
            Text('Week of ${_shortDate(series.weekStarts.lastOrNull)}', style: AmrText.body(12)),
          ],
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
            for (final p in [phenotype, ...Phenotype.values.where((x) => x != phenotype)])
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
                            color: AmrColors.series[math.min(i, 2)],
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
                            color: AmrColors.series[math.min(i, 2)],
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

String _usualWeek(double perWeek) => perWeek <= 0
    ? '0'
    : perWeek < 1
    ? 'under 1'
    : '${(perWeek * 10).round() / 10}';

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
                    'Warn any ward or care home. They get the totals and what to watch for, '
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
                                  hintText: 'Find any ward, e.g. Cardiology or a care home',
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
        ..cubicTo(240 * k, 130 * k, 240 * k, y, 340 * k, y);
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

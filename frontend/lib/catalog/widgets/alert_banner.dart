import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/format.dart';
import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../actions.dart';
import '../catalog.dart';

final alertBannerEntry = CatalogEntry(
  name: 'AlertBanner',
  title: 'Alerts on my ward',
  description: 'The most important active alert on a ward, opening the alert.',
  builder: (context, params, slot) =>
      AlertBanner(query: AlertsQuery.fromJson({'status': 'active', ...params}), slot: slot),
);

/// Pink banner with the ward's top active alert; a calm note when there is none.
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, required this.query, this.slot = WidgetSlot.page});

  final AlertsQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<AlertsQuery, Alerts>(
    query: query,
    fetch: (repo, q) => repo.alerts(q),
    loading: const AmrCard(tone: AmrCardTone.alert, child: SkeletonBlock(lines: 2)),
    builder: (context, data) {
      final alerts = [...data.alerts]..sort((a, b) => b.severity.index.compareTo(a.severity.index));
      final ward = query.ward;
      if (alerts.isEmpty) {
        // In a chat answer an empty banner is noise; elsewhere it reassures.
        if (slot == WidgetSlot.chat) return const SizedBox.shrink();
        return AmrCard(
          tone: AmrCardTone.subtle,
          child: ColumnGap([
            DotLabel(ward == null ? 'All wards' : 'On ${ward.label}', color: AmrColors.periwinkle),
            Text('No active alerts right now', style: AmrText.title(26)),
          ]),
        );
      }
      return AlertBannerView(alert: alerts.first, slot: slot);
    },
  );
}

class AlertBannerView extends StatelessWidget {
  const AlertBannerView({super.key, required this.alert, this.slot = WidgetSlot.page});

  final Alert alert;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) {
    if (slot == WidgetSlot.chat) return _chat(context);
    if (slot == WidgetSlot.card) return _home(context);
    final style = AmrText.title(context.isShort ? 20 : 24);
    return AmrCard(
      tone: AmrCardTone.alert,
      padding: const EdgeInsets.all(AmrSpace.x28),
      onTap: () => context.read<CatalogActions>().openAlert(alert.alertId),
      child: ColumnGap([
        DotLabel('Active alert ${alert.onWhere}'),
        // One short line, as in the design: "E. coli with ESBL: 9 cases in 4 weeks, usually
        // about 3". The full sentence is on the alert page.
        switch (alert.type) {
          _ when alert.title.isEmpty => Text(alert.summary, style: style),
          AlertType.missingData => Text(alert.summary, style: style),
          AlertType.sentinel => Text(
            '${alert.title}: ${patients(alert.nCases)}, every one is reported',
            style: style,
          ),
          _ => QueryView<AlertDetailQuery, AlertDetail>(
            query: AlertDetailQuery(alertId: alert.alertId),
            fetch: (repo, q) => repo.alertDetail(q),
            loading: Text('${alert.title} is rising', style: style),
            errorMessage: '',
            builder: (context, d) {
              final (cases, usual) = _lastFourWeeks(d.epiCurve);
              final usually = usual < 1 ? 'usually under 1' : 'usually about ${usual.round()}';
              return Text(
                '${alert.title}: $cases ${cases == 1 ? 'case' : 'cases'} in 4 weeks, $usually',
                style: style,
              );
            },
          ),
        },
        Text(
          'Open the alert',
          style: AmrText.body(15).copyWith(decoration: TextDecoration.underline),
        ),
      ], gap: AmrSpace.x10),
    );
  }

  /// Home: "● On your ward now" with the link on the right, the title, then how far above the
  /// usual it is with the weekly bars.
  Widget _home(BuildContext context) {
    final title = alert.title.isEmpty
        ? alert.summary
        : switch (alert.type) {
            AlertType.sentinel => '${alert.title} found ${alert.onWhere}',
            AlertType.missingData => alert.summary,
            _ => '${alert.title} is rising ${alert.onWhere}',
          };
    return AmrCard(
      tone: AmrCardTone.alert,
      padding: const EdgeInsets.all(AmrSpace.x24),
      onTap: () => context.read<CatalogActions>().openAlert(alert.alertId),
      child: ColumnGap(
        [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              const DotLabel('On your ward now'),
              Text(
                'What it means for your patients',
                style: AmrText.body(14).copyWith(decoration: TextDecoration.underline),
              ),
            ],
          ),
          Text(title, style: AmrText.title(24)),
          if (alert.type != AlertType.missingData)
            QueryView<AlertDetailQuery, AlertDetail>(
              query: AlertDetailQuery(alertId: alert.alertId),
              fetch: (repo, q) => repo.alertDetail(q),
              loading: const SizedBox(height: 54),
              errorMessage: '',
              builder: (context, d) => _AlertMetric(alert: alert, weeks: d.epiCurve),
            ),
        ],
        gap: AmrSpace.x12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }

  /// Chat: "● Active alert", one line of title, and the link (no link on a phone).
  Widget _chat(BuildContext context) {
    final compact = context.isCompact;
    return AmrCard(
      tone: AmrCardTone.alert,
      padding: EdgeInsets.all(compact ? 16 : 22),
      onTap: () => context.read<CatalogActions>().openAlert(alert.alertId),
      child: ColumnGap(
        [
          Row(
            children: [
              StatusDot(size: compact ? 8 : 9),
              const SizedBox(width: 8),
              Text('Active alert', style: AmrText.label(compact ? 12 : 13)),
            ],
          ),
          Text(
            alert.title.isEmpty ? alert.summary : '${alert.title} rising ${alert.onWhere}',
            style: AmrText.body(compact ? 15 : 16, weight: FontWeight.w500),
          ),
          if (!compact)
            Text(
              'Open the alert',
              style: AmrText.body(14).copyWith(decoration: TextDecoration.underline),
            ),
        ],
        gap: compact ? 4 : 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

/// "3× the usual · 9 patients in 4 weeks · usually 3" beside the last 8 weeks as bars: weeks
/// above the usual in magenta, the usual as a dashed line. A single-isolate (sentinel) alert
/// has no usual, so it shows the count instead.
class _AlertMetric extends StatelessWidget {
  const _AlertMetric({required this.alert, required this.weeks});

  final Alert alert;
  final List<EpiPoint> weeks;

  @override
  Widget build(BuildContext context) {
    final (cases, usual) = _lastFourWeeks(weeks);
    final ratio = usual >= 0.5 ? cases / usual : null;
    final (String big, List<String> lines) = alert.type == AlertType.sentinel || ratio == null
        ? (
            '${alert.nCases}',
            [
              alert.nCases == 1 ? 'patient' : 'patients',
              if (alert.type == AlertType.sentinel) 'every one is reported',
              'since ${dayShort(alert.firstSeen)}',
            ],
          )
        : (
            ratio >= 2 ? '${ratio.round()}×' : '${ratio.toStringAsFixed(1)}×',
            [
              'the usual',
              '${patients(cases)} in 4 weeks',
              usual < 1 ? 'usually under 1' : 'usually ${usual.round()}',
            ],
          );
    final figure = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(big, style: AmrText.sora(48, em: -0.04, height: 1)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, l) in lines.indexed)
              Text(l, style: AmrText.body(13, weight: i == 0 ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ],
    );
    final recent = weeks.length > 8 ? weeks.sublist(weeks.length - 8) : weeks;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        figure,
        const SizedBox(width: 24),
        if (recent.isNotEmpty)
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260, minWidth: 120),
                child: _WeekBars(weeks: recent, ward: alert.where),
              ),
            ),
          ),
      ],
    );
  }
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.weeks, required this.ward});

  final List<EpiPoint> weeks;
  final String ward;

  @override
  Widget build(BuildContext context) {
    final top = weeks.fold<double>(1, (m, w) => [m, w.cases.toDouble(), w.expected].reduce(max));
    final usual = weeks.fold<double>(0, (n, w) => n + w.expected) / weeks.length;
    return Semantics(
      label: 'Patients per week on $ward, last ${weeks.length} weeks',
      child: SizedBox(
        height: 54,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AmrColors.ink, width: 1.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (i, w) in weeks.indexed) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Expanded(
                        child: FractionallySizedBox(
                          heightFactor: max(w.cases / top, 0.04),
                          alignment: Alignment.bottomCenter,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: w.cases > w.expected
                                  ? AmrColors.magenta
                                  : AmrColors.ink.withValues(alpha: 0.35),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                                bottom: Radius.circular(1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // The usual level (none to draw when it is zero, as for a single isolate).
            if (usual >= 0.05)
              Positioned(
                left: 0,
                right: 0,
                bottom: 54 * usual / top,
                child: const CustomPaint(size: Size(double.infinity, 1.5), painter: _Dashes()),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dashes extends CustomPainter {
  const _Dashes();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AmrColors.ink.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(min(x + 4, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => false;
}

/// Cases in the last 4 weeks and how many would be usual, from the weekly counts.
(int, double) _lastFourWeeks(List<EpiPoint> weeks) {
  final last4 = weeks.length >= 4 ? weeks.sublist(weeks.length - 4) : weeks;
  return (
    last4.fold<int>(0, (n, w) => n + w.cases),
    last4.fold<double>(0, (n, w) => n + w.expected),
  );
}

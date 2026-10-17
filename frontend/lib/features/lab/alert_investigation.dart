import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../catalog/widgets/alert_card.dart';
import '../../catalog/widgets/case_list.dart';
import '../../catalog/widgets/epi_curve.dart';
import '../../catalog/widgets/sampling_volume.dart';
import '../../core/format.dart';
import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import 'lab_cubit.dart';

/// One alert, investigated: what it is, the curve, why the verdict, and what to do next.
/// [compact] is the phone screen (stacked, without its own card and actions bar).
class AlertInvestigation extends StatelessWidget {
  const AlertInvestigation({super.key, required this.alertId, this.compact = false});

  final String alertId;
  final bool compact;

  @override
  Widget build(BuildContext context) => QueryView<AlertDetailQuery, AlertDetail>(
    query: AlertDetailQuery(alertId: alertId),
    fetch: (repo, q) => repo.alertDetail(q),
    loading: compact
        ? const SkeletonBlock(lines: 8)
        : const AmrCard(child: SkeletonBlock(lines: 8)),
    builder: (context, d) => _Investigation(detail: d, compact: compact),
  );
}

/// "Is it just more testing?": the volume reading and the verdict's reason.
String _testingText(AlertDetail d) {
  final (buckets, monthly) = volumeBuckets(d.volume);
  final reading = d.volume.isEmpty ? '' : '${volumeReading(buckets, monthly: monthly)} ';
  return '$reading${d.verdictReason}';
}

/// "Compared with the hospital": the alert ward's rate against the next highest ward.
String _comparisonText(AlertDetail d) {
  final a = d.alert;
  final rates = d.wardComparison.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
  if (rates.isEmpty) return 'No other wards to compare with yet.';
  final what = a.phenotype != null ? '${a.phenotype!.code} share' : 'Case rate';
  final own = d.wardComparison[a.ward?.code];
  final next = rates.where((e) => e.key != a.ward?.code).firstOrNull;
  String name(String code) => byCodeOrNull(Ward.values, code)?.label ?? code;
  if (own == null) {
    return '$what is highest on ${name(rates.first.key)}: ${pct(rates.first.value)}.';
  }
  if (next == null) return '$what ${a.onWhere}: ${pct(own)}.';
  // "Next highest" only when it is lower; otherwise the other ward is the highest.
  final rank = next.value > own ? 'Highest' : 'Next highest';
  return '$what ${a.onWhere}: ${pct(own)}. $rank, ${name(next.key)}: ${pct(next.value)}.';
}

/// The highest ward other than the alert's own, for "Compare with Surgery".
Ward? _compareWard(AlertDetail d) {
  final rates = d.wardComparison.entries.where((e) => e.key != d.alert.ward?.code).toList()
    ..sort((x, y) => y.value.compareTo(x.value));
  return rates.isEmpty ? null : byCodeOrNull(Ward.values, rates.first.key);
}

/// "9 cases in the last 4 weeks, usually about 3." plus the summary and grouped drugs.
String _paragraph(AlertDetail d) {
  final a = d.alert;
  final drugs = a.drugs.map((x) => x.label).toList();
  final grouped = drugs.length < 2
      ? ''
      : ' ${drugs.sublist(0, drugs.length - 1).join(', ')} and ${drugs.last} are affected, '
            'so they are grouped into this one alert.';
  return '${a.summary}$grouped';
}

class _Investigation extends StatefulWidget {
  const _Investigation({required this.detail, required this.compact});

  final AlertDetail detail;
  final bool compact;

  @override
  State<_Investigation> createState() => _InvestigationState();
}

class _InvestigationState extends State<_Investigation> {
  bool _isolates = false;
  bool _compare = false;

  @override
  void didUpdateWidget(_Investigation old) {
    super.didUpdateWidget(old);
    if (old.detail.alert.alertId != widget.detail.alert.alertId) {
      _isolates = false;
      _compare = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final a = d.alert;
    final compact = widget.compact;
    final reviewed = context.select((LabCubit c) => c.state.reviewed.contains(a.alertId));
    final cmp = _compareWard(d);

    final header = compact
        ? ColumnGap([
            Text(alertMeta(a, longDate: true), style: AmrText.body(13)),
            Text(
              '${alertHeadline(a)} ${a.onWhere}',
              style: AmrText.sora(32, em: -0.03, height: 1.1),
            ),
            VerdictTag(alert: a, size: VerdictTagSize.large),
          ], gap: AmrSpace.x16)
        : Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.start,
            spacing: 12,
            runSpacing: 12,
            children: [
              ColumnGap([
                Text(alertMeta(a, longDate: true), style: AmrText.body(14)),
                Text(
                  '${alertHeadline(a)} ${a.onWhere}',
                  style: AmrText.sora(fluid(context, 28, 3, 40), em: -0.03, height: 1.1),
                ),
              ], gap: AmrSpace.x8),
              VerdictTag(alert: a, size: VerdictTagSize.xlarge),
            ],
          );

    final reasons = [
      _Reason(title: 'Is it just more testing?', body: _testingText(d), compact: compact),
      _Reason(title: 'Compared with the hospital', body: _comparisonText(d), compact: compact),
      // A hospital-wide alert has no ward to trace patient moves from.
      if (a.ward != null) _LinkedWardsReason(ward: a.ward!, compact: compact),
    ];

    final actions = [
      AmrButton(
        label: _isolates ? 'Hide the isolates' : 'Show the isolates',
        expand: compact,
        onPressed: () => setState(() => _isolates = !_isolates),
      ),
      AmrButton(
        label: cmp == null ? 'Compare wards' : 'Compare with ${cmp.label}',
        expand: compact,
        onPressed: () => setState(() => _compare = !_compare),
      ),
      AmrButton(
        label: 'Warn linked wards',
        expand: compact,
        onPressed: () => context.go('/hygiene'),
      ),
    ];

    final body = ColumnGap(
      [
        header,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(_paragraph(d), style: AmrText.body(compact ? 15 : 16, height: 1.5)),
        ),
        EpiCurveView(detail: d, compact: compact),
        if (compact && d.volume.isNotEmpty)
          SamplingVolumeView(points: d.volume, compact: true, showReading: false),
        if (compact)
          ColumnGap(reasons, gap: AmrSpace.x12, crossAxisAlignment: CrossAxisAlignment.stretch)
        else
          AutoGrid(minItemWidth: 240, gap: 12, children: reasons),
        _Reveal(
          open: _compare,
          child: _WardComparison(detail: d),
        ),
        _Reveal(
          open: _isolates,
          child: CaseListView(cases: d.cases, alertId: a.alertId),
        ),
        if (compact)
          ColumnGap(actions, gap: AmrSpace.x8, crossAxisAlignment: CrossAxisAlignment.stretch)
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ...actions,
              ReviewButton(alertId: a.alertId, reviewed: reviewed),
            ],
          ),
      ],
      gap: compact ? AmrSpace.x16 : AmrSpace.x20,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );

    if (compact) return body;
    return AmrCard(padding: EdgeInsets.all(fluid(context, 24, 3, 36)), child: body);
  }
}

/// "Mark as reviewed", or the done pill with an undo once it is.
class ReviewButton extends StatelessWidget {
  const ReviewButton({
    super.key,
    required this.alertId,
    required this.reviewed,
    this.large = false,
  });

  final String alertId;
  final bool reviewed;

  /// The phone's sticky 56px full-width button.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LabCubit>();
    return AnimatedSwitcher(
      duration: AmrMotion.base,
      child: reviewed
          ? ActionPill(
              key: const ValueKey('done'),
              message: 'Marked as reviewed',
              actionLabel: 'Undo',
              onAction: () => cubit.toggleReviewed(alertId),
            )
          : AmrButton(
              key: const ValueKey('todo'),
              label: 'Mark as reviewed',
              variant: AmrButtonVariant.primary,
              size: large ? AmrButtonSize.xxl : AmrButtonSize.lg,
              expand: large,
              onPressed: () => cubit.toggleReviewed(alertId),
            ),
    );
  }
}

/// Fades and grows a section in or out.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: AmrMotion.base,
    curve: AmrMotion.curve,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: AmrMotion.base,
      child: open ? child : const SizedBox(width: double.infinity),
    ),
  );
}

class _Reason extends StatelessWidget {
  const _Reason({required this.title, required this.body, this.compact = false});

  final String title;
  final String body;
  final bool compact;

  @override
  Widget build(BuildContext context) => AmrCard(
    tone: AmrCardTone.accent,
    padding: EdgeInsets.all(compact ? 18 : 20),
    child: ColumnGap([
      Text(title, style: AmrText.body(compact ? 13 : 14, weight: FontWeight.w500)),
      Text(body, style: AmrText.body(15, height: 1.45)),
    ], gap: AmrSpace.x6),
  );
}

/// "Linked wards": the two wards that share the most patients with the alert's ward.
class _LinkedWardsReason extends StatelessWidget {
  const _LinkedWardsReason({required this.ward, this.compact = false});

  final Ward ward;
  final bool compact;

  @override
  Widget build(BuildContext context) => QueryView<WardLinksQuery, WardLinks>(
    query: WardLinksQuery(ward: ward),
    fetch: (repo, q) => repo.wardLinks(q),
    loading: _Reason(title: 'Linked wards', body: '…', compact: compact),
    builder: (context, data) {
      final top =
          ([...data.links]..sort((x, y) => y.sharedPatients30d.compareTo(x.sharedPatients30d)))
              .take(2)
              .map((l) => l.ward.label)
              .toList();
      final body = top.isEmpty
          ? 'No wards share many patients with ${ward.label}.'
          : '${top.join(' and ')} ${top.length == 1 ? 'shares' : 'share'} many patients with '
                '${ward.label}.';
      return _Reason(title: 'Linked wards', body: body, compact: compact);
    },
  );
}

/// The case rate on each ward, the alert's ward in pink.
class _WardComparison extends StatelessWidget {
  const _WardComparison({required this.detail});

  final AlertDetail detail;

  @override
  Widget build(BuildContext context) {
    final a = detail.alert;
    final rates = detail.wardComparison.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    final top = rates.isEmpty ? 1.0 : rates.first.value;
    return AmrCard(
      tone: AmrCardTone.subtle,
      padding: const EdgeInsets.all(20),
      child: ColumnGap(
        [
          Text(
            '${a.phenotype != null ? '${a.phenotype!.code} share' : 'Case rate'} by ward',
            style: AmrText.body(15, weight: FontWeight.w500),
          ),
          if (rates.isEmpty) Text('No other wards to compare with yet.', style: AmrText.body(14)),
          for (final e in rates)
            Row(
              children: [
                SizedBox(
                  width: context.isCompact ? 120 : 190,
                  child: Text(
                    byCodeOrNull(Ward.values, e.key)?.label ?? e.key,
                    overflow: TextOverflow.ellipsis,
                    style: AmrText.body(15),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShareBar(
                    value: top <= 0 ? 0 : e.value / top,
                    color: e.key == a.ward?.code ? AmrColors.magenta : AmrColors.ink,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 44,
                  child: Text(
                    pct(e.value),
                    textAlign: TextAlign.right,
                    style: AmrText.body(15, weight: FontWeight.w500),
                  ),
                ),
              ],
            ),
        ],
        gap: AmrSpace.x12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

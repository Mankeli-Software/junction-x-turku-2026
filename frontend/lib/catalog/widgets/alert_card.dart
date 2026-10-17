import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../actions.dart';
import '../catalog.dart';

final alertCardEntry = CatalogEntry(
  name: 'AlertCard',
  title: 'Alert',
  description: 'One grouped alert per ward, organism and type, with a plain verdict.',
  builder: (context, params, slot) =>
      AlertCard(query: AlertDetailQuery.fromJson(params), slot: slot),
);

// Wording and colors -----------------------------------------------------------

/// "Cluster", "Single rare find", "Slow trend", "Missing data".
String alertKind(Alert a) => a.type.label;

/// "E. coli with ESBL", or "E. coli resistance to trimethoprim" for a trend without a
/// phenotype, or the summary when there is neither.
String alertHeadline(Alert a) {
  if (a.phenotype != null) return a.title;
  if (a.organism != null && a.drugs.isNotEmpty) {
    final drugs = a.drugs.map((d) => d.label.toLowerCase()).join(', ');
    return '${a.organism!.short} resistance to $drugs';
  }
  if (a.organism != null) return a.organism!.short;
  return a.summary;
}

/// The dot in the inbox: pink for a likely real cluster or find, navy for a slow trend,
/// amber when it may be more testing, lavender when there are too few cases.
Color alertDot(Alert a) => switch (a.verdict) {
  Verdict.tooFewCases => AmrColors.periwinkle,
  Verdict.samplingArtefact => AmrColors.amber,
  Verdict.likelyReal => a.type == AlertType.trend ? AmrColors.ink : AmrColors.magenta,
};

Color verdictColor(Alert a) => switch (a.verdict) {
  Verdict.tooFewCases => AmrColors.lavenderPale,
  Verdict.samplingArtefact => AmrColors.amberSoft,
  Verdict.likelyReal => a.type == AlertType.trend ? AmrColors.lavenderPale : AmrColors.blush,
};

/// Cases in the last (up to) four weeks of the curve and what is usual for them.
(int cases, double expected) recentCases(AlertDetail d, {int weeks = 4}) {
  final tail = d.epiCurve.length <= weeks
      ? d.epiCurve
      : d.epiCurve.sublist(d.epiCurve.length - weeks);
  return (tail.fold<int>(0, (s, p) => s + p.cases), tail.fold<double>(0, (s, p) => s + p.expected));
}

/// "9 cases in 4 weeks, usually about 3".
String caseLine(AlertDetail d) {
  if (d.epiCurve.isEmpty) return d.alert.nCases == 1 ? '1 case' : '${d.alert.nCases} cases';
  final weeks = d.epiCurve.length < 4 ? d.epiCurve.length : 4;
  final (cases, expected) = recentCases(d);
  final usual = expected < 1 ? 'under 1' : 'about ${expected.round()}';
  final n = cases == 1 ? '1 case' : '$cases cases';
  return '$n in $weeks ${weeks == 1 ? 'week' : 'weeks'}, usually $usual';
}

/// "Cluster ✦ Urology ✦ since 9 Jun".
String alertMeta(Alert a, {bool longDate = false}) =>
    '${alertKind(a)} $sparkle ${a.where} $sparkle since '
    '${longDate ? day(a.firstSeen) : dayShort(a.firstSeen)}';

// Views ------------------------------------------------------------------------

enum VerdictTagSize {
  /// 11px: phone inbox.
  small(11, EdgeInsets.symmetric(horizontal: 10, vertical: 3)),

  /// 12px: inbox rows.
  medium(12, EdgeInsets.symmetric(horizontal: 10, vertical: 3)),

  /// 13px: cards and the phone alert.
  large(13, EdgeInsets.symmetric(horizontal: 14, vertical: 6)),

  /// 14px: the investigation header.
  xlarge(14, EdgeInsets.symmetric(horizontal: 16, vertical: 8));

  const VerdictTagSize(this.fontSize, this.padding);

  final double fontSize;
  final EdgeInsets padding;
}

/// "Likely real", "Too few cases yet", "Maybe more testing".
class VerdictTag extends StatelessWidget {
  const VerdictTag({super.key, required this.alert, this.size = VerdictTagSize.medium, this.label});

  final Alert alert;
  final VerdictTagSize size;

  /// Overrides the verdict text ("Reviewed").
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
    padding: size.padding,
    decoration: BoxDecoration(color: verdictColor(alert), borderRadius: AmrRadius.pill),
    child: Text(label ?? alert.verdict.label, style: AmrText.label(size.fontSize)),
  );
}

/// Connected `AlertCard`: loads the alert detail for "N cases in 4 weeks, usually about M".
class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.query, this.slot = WidgetSlot.page});

  final AlertDetailQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<AlertDetailQuery, AlertDetail>(
    query: query,
    fetch: (repo, q) => repo.alertDetail(q),
    loading: const AmrCard(tone: AmrCardTone.quiet, child: SkeletonBlock(lines: 1)),
    builder: (context, d) => AlertCardView(detail: d, slot: slot),
  );
}

/// One-row alert card: meta, "E. coli with ESBL · 9 cases in 4 weeks, usually about 3",
/// verdict tag. Opens the alert.
class AlertCardView extends StatelessWidget {
  const AlertCardView({super.key, required this.detail, this.slot = WidgetSlot.page});

  final AlertDetail detail;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) {
    final a = detail.alert;
    final chat = slot == WidgetSlot.chat;
    final title = '${alertHeadline(a)} · ${caseLine(detail)}';
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(alertMeta(a), style: AmrText.body(13)),
        const SizedBox(height: 4),
        Text(
          title,
          style: chat ? AmrText.title(26, height: 1.25) : AmrText.body(18, weight: FontWeight.w500),
        ),
      ],
    );
    final tag = VerdictTag(alert: a, size: chat ? VerdictTagSize.xlarge : VerdictTagSize.large);
    return AmrCard(
      tone: AmrCardTone.quiet,
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: chat ? 22 : 20),
      onTap: () => context.read<CatalogActions>().openAlert(a.alertId),
      child: context.isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 12), tag],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 12),
                tag,
              ],
            ),
    );
  }
}

/// A row in the alert inbox: dot, "Cluster ✦ Urology", title, verdict tag. The selected row
/// gets the soft lavender fill; on a phone a chevron shows it opens a screen.
class AlertInboxRow extends StatelessWidget {
  const AlertInboxRow({
    super.key,
    required this.alert,
    this.selected = false,
    this.reviewed = false,
    this.compact = false,
    this.onTap,
  });

  final Alert alert;
  final bool selected;
  final bool reviewed;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressScale: 0.99,
      builder: (_, s) => AnimatedContainer(
        duration: AmrMotion.base,
        curve: AmrMotion.curve,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 16)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: selected
              ? AmrColors.lavenderSoft
              : (s.hovered
                    ? AmrColors.lavenderSoft.withValues(alpha: 0.5)
                    : const Color(0x00FFFFFF)),
          border: const Border(top: BorderSide(color: AmrColors.ink)),
          borderRadius: selected
              ? const BorderRadius.vertical(bottom: Radius.circular(12))
              : BorderRadius.zero,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: StatusDot(color: reviewed ? AmrColors.line : alertDot(alert)),
            ),
            SizedBox(width: compact ? 12 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${alertKind(alert)} $sparkle ${alert.where}',
                    style: AmrText.body(compact ? 12 : 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alertHeadline(alert),
                    style: AmrText.body(compact ? 16 : 17, weight: FontWeight.w500, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  VerdictTag(
                    alert: alert,
                    size: compact ? VerdictTagSize.small : VerdictTagSize.medium,
                    label: reviewed ? 'Reviewed' : null,
                  ),
                ],
              ),
            ),
            if (compact) ...[
              const SizedBox(width: 12),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Icon(LucideIcons.chevronRight, size: 20, color: AmrColors.ink),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

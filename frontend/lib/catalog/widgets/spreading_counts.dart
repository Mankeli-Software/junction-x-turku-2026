import 'package:flutter/material.dart';

import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final spreadingCountsEntry = CatalogEntry(
  name: 'SpreadingCounts',
  title: 'Spreading by ward',
  description: 'MRSA, ESBL, VRE and CPE per ward, now compared with a usual period.',
  builder: (context, params, slot) => SpreadingCounts(
    query: SpreadingQuery.fromJson(params),
    phenotype: byCodeOrNull(Phenotype.values, params['phenotype']),
    slot: slot,
  ),
);

/// Connected spreading widget: loads `/v1/spreading` and shows every ward for the [slot].
class SpreadingCounts extends StatelessWidget {
  const SpreadingCounts({
    super.key,
    required this.query,
    this.phenotype,
    this.slot = WidgetSlot.page,
  });

  final SpreadingQuery query;

  /// Only this resistant type; null shows all of them.
  final Phenotype? phenotype;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<SpreadingQuery, Spreading>(
    query: query,
    fetch: (repo, q) => repo.spreading(q),
    builder: (context, data) {
      final wards = wardSpreads(
        data,
        only: phenotype,
        wards: query.wards.isEmpty ? null : query.wards,
      );
      return switch (slot) {
        WidgetSlot.page =>
          context.isCompact ? SpreadingPhoneGrid(wards: wards) : SpreadingWardGrid(wards: wards),
        WidgetSlot.chat => SpreadingCompactGrid(wards: wards),
        WidgetSlot.card => SpreadingCompactGrid(wards: wards, limit: 4, minTileWidth: 150),
      };
    },
  );
}

// View model ------------------------------------------------------------------

enum SpreadStatus {
  high('Higher than usual'),
  bit('A bit higher'),
  usual('Usual');

  const SpreadStatus(this.label);

  final String label;

  Color get background => switch (this) {
    SpreadStatus.high => AmrColors.blush,
    SpreadStatus.bit => AmrColors.lavenderSoft,
    SpreadStatus.usual => AmrColors.white,
  };

  Color get tag => switch (this) {
    SpreadStatus.high => AmrColors.white,
    SpreadStatus.bit => AmrColors.blush,
    SpreadStatus.usual => AmrColors.lavenderSoft,
  };

  List<BoxShadow>? get shadow => this == SpreadStatus.usual ? AmrShadows.sm : null;

  bool get raised => this != SpreadStatus.usual;
}

/// The one rule for "how unusual is this count":
/// - higher than usual: at least 3 more cases than usual and at least double the usual count;
/// - a bit higher: the backend flags it above normal, or at least 2 more cases than usual;
/// - usual: everything else.
SpreadStatus spreadStatus(SpreadingRow r) {
  final excess = r.count - r.normal;
  if (excess >= 3 && r.count >= 2 * r.normal) return SpreadStatus.high;
  if (r.aboveNormal || excess >= 2) return SpreadStatus.bit;
  return SpreadStatus.usual;
}

/// "3", "under 1", "0": the typical count as people say it.
String usualLabel(double normal) {
  if (normal <= 0) return '0';
  if (normal < 1) return 'under 1';
  return '${normal.round()}';
}

/// One ward with its resistant types, most unusual first.
class WardSpread {
  WardSpread(this.ward, List<SpreadingRow> rows)
    : rows = [...rows]..sort(_byConcern),
      status = rows.isEmpty
          ? SpreadStatus.usual
          : rows.map(spreadStatus).reduce((a, b) => a.index <= b.index ? a : b);

  final Ward ward;
  final List<SpreadingRow> rows;
  final SpreadStatus status;

  /// The most unusual row, if any.
  SpreadingRow? get top => rows.firstOrNull;

  double get excess => top == null ? 0 : top!.count - top!.normal;

  static int _byConcern(SpreadingRow a, SpreadingRow b) {
    final s = spreadStatus(a).index.compareTo(spreadStatus(b).index);
    if (s != 0) return s;
    return (b.count - b.normal).compareTo(a.count - a.normal);
  }
}

/// Every ward (or [wards]), wards without rows reading as usual; most raised first.
List<WardSpread> wardSpreads(Spreading data, {Phenotype? only, Iterable<Ward>? wards}) {
  final list = [
    for (final w in wards ?? Ward.values)
      WardSpread(w, [
        for (final r in data.rows)
          if (r.ward == w && (only == null || r.phenotype == only)) r,
      ]),
  ];
  list.sort((a, b) {
    final s = a.status.index.compareTo(b.status.index);
    if (s != 0) return s;
    final e = b.excess.compareTo(a.excess);
    return e != 0 ? e : a.ward.index.compareTo(b.ward.index);
  });
  return list;
}

/// "Intensive care" fits a phone tile; "Emergency department" becomes "Emergency dept.".
String wardTileName(Ward w) => w.label.length <= 15 ? w.label : w.short;

// Views -----------------------------------------------------------------------

/// Hygiene page: one big tile per ward with a line per resistant type.
class SpreadingWardGrid extends StatelessWidget {
  const SpreadingWardGrid({super.key, required this.wards, this.onTapWard, this.only});

  final List<WardSpread> wards;
  final ValueChanged<Ward>? onTapWard;

  /// The selected filter, so a ward with nothing shows "ESBL 0" rather than nothing.
  final Phenotype? only;

  @override
  Widget build(BuildContext context) {
    return AutoGrid(
      minItemWidth: 280,
      gap: AmrSpace.x16,
      children: [
        for (final w in wards)
          _WardTile(
            spread: w,
            only: only,
            onTap: onTapWard == null ? null : () => onTapWard!(w.ward),
          ),
      ],
    );
  }
}

class _WardTile extends StatelessWidget {
  const _WardTile({required this.spread, this.only, this.onTap});

  final WardSpread spread;
  final Phenotype? only;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = spread.status;
    final lines = spread.rows.isEmpty
        ? [(only?.code ?? 'Resistant types', 0, '0')]
        : [for (final r in spread.rows) (r.phenotype.code, r.count, usualLabel(r.normal))];
    return StatusCard(
      status: s,
      padding: const EdgeInsets.all(AmrSpace.x24),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 122),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Wrap, not Row: a long name next to "Higher than usual" moves the tag to the
            // next line instead of breaking the name mid-word.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spread.ward.label, style: AmrText.sora(22, weight: FontWeight.w400)),
                    const SizedBox(height: 2),
                    Text(spread.ward.code, style: AmrText.body(13)),
                  ],
                ),
                _StatusTag(
                  status: s,
                  fontSize: 13,
                  padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: ColumnGap(
                [
                  for (final (type, now, usual) in lines)
                    Container(
                      padding: const EdgeInsets.only(top: 6),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0x401D204E))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(type, style: AmrText.body(15, weight: FontWeight.w500)),
                          ),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$now',
                                  style: AmrText.body(15, weight: FontWeight.w600),
                                ),
                                TextSpan(text: ' now · usually $usual'),
                              ],
                            ),
                            style: AmrText.body(15),
                          ),
                        ],
                      ),
                    ),
                ],
                gap: AmrSpace.x6,
                crossAxisAlignment: CrossAxisAlignment.stretch,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chat and pinned cards: smaller tiles with the ward's most unusual type.
class SpreadingCompactGrid extends StatelessWidget {
  const SpreadingCompactGrid({
    super.key,
    required this.wards,
    this.limit = 4,
    this.minTileWidth = 200,
  });

  final List<WardSpread> wards;
  final int limit;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return AutoGrid(
      minItemWidth: minTileWidth,
      gap: AmrSpace.x10,
      children: [
        for (final w in wards.take(limit))
          StatusCard(
            status: w.status,
            radius: 14,
            padding: const EdgeInsets.all(AmrSpace.x18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(w.ward.label, style: AmrText.body(17, weight: FontWeight.w500)),
                const SizedBox(height: 8),
                _NowLine(row: w.top, size: 14),
                const SizedBox(height: 8),
                _StatusTag(status: w.status),
              ],
            ),
          ),
      ],
    );
  }
}

/// Phone: two columns, a big Sora count per ward, most raised first.
class SpreadingPhoneGrid extends StatelessWidget {
  const SpreadingPhoneGrid({super.key, required this.wards, this.onTapWard});

  final List<WardSpread> wards;
  final ValueChanged<Ward>? onTapWard;

  @override
  Widget build(BuildContext context) {
    return AutoGrid(
      minItemWidth: 140,
      gap: AmrSpace.x8,
      children: [
        for (final w in wards)
          StatusCard(
            status: w.status,
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: onTapWard == null ? null : () => onTapWard!(w.ward),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  wardTileName(w.ward),
                  style: AmrText.body(14, weight: FontWeight.w600, height: 1.25),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${w.top?.count ?? 0}', style: AmrText.sora(32, em: -0.04, height: 1)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${w.top?.phenotype.code ?? 'None'} · usually '
                        '${usualLabel(w.top?.normal ?? 0)}',
                        style: AmrText.body(12, weight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _StatusTag(
                  status: w.status,
                  fontSize: 11,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "**9** ESBL now · usually 3".
class _NowLine extends StatelessWidget {
  const _NowLine({required this.row, this.size = 14});

  final SpreadingRow? row;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = row;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${r?.count ?? 0}',
            style: AmrText.body(size, weight: FontWeight.w600),
          ),
          TextSpan(
            text: r == null
                ? ' resistant now · usually 0'
                : ' ${r.phenotype.code} now · usually ${usualLabel(r.normal)}',
          ),
        ],
      ),
      style: AmrText.body(size),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({
    required this.status,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
  });

  final SpreadStatus status;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: status.tag, borderRadius: AmrRadius.pill),
    child: Text(status.label, style: AmrText.label(fontSize)),
  );
}

/// A card filled by its [status]: blush when higher than usual, lavender when a bit higher,
/// white with the small shadow when usual.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.status,
    required this.child,
    this.padding = const EdgeInsets.all(AmrSpace.x22),
    this.radius = 16,
    this.onTap,
  });

  final SpreadStatus status;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  Widget _box({required bool hovered}) => AnimatedContainer(
    duration: AmrMotion.base,
    curve: AmrMotion.curve,
    padding: padding,
    decoration: BoxDecoration(
      color: status.background,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: hovered ? AmrShadows.md : status.shadow,
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return _box(hovered: false);
    return Pressable(
      onTap: onTap,
      pressScale: 0.99,
      builder: (_, s) => _box(hovered: s.hovered),
    );
  }
}

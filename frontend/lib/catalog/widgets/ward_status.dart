import 'package:flutter/material.dart';

import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../catalog.dart';
import 'spreading_counts.dart';

final wardStatusEntry = CatalogEntry(
  name: 'WardStatus',
  title: 'Is my ward OK?',
  description: 'Plain status per ward for care workers: as usual, or what to clean more for.',
  builder: (context, params, slot) =>
      WardStatus(query: SpreadingQuery.fromJson(params), slot: slot),
);

/// Care-worker view: one card per ward in [SpreadingQuery.wards] ("mine"), plus a note for
/// a raised ward elsewhere. Loads every ward so it can spot raised ones outside the list.
class WardStatus extends StatelessWidget {
  const WardStatus({super.key, required this.query, this.slot = WidgetSlot.page});

  final SpreadingQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<SpreadingQuery, Spreading>(
    query: SpreadingQuery(window: query.window),
    fetch: (repo, q) => repo.spreading(q),
    builder: (context, data) => WardStatusView(
      spreads: wardSpreads(data),
      mine: query.wards,
      compact: context.isCompact || slot == WidgetSlot.card,
    ),
  );
}

/// One plain sentence per ward: what to do differently, if anything.
class WardStatusView extends StatelessWidget {
  const WardStatusView({
    super.key,
    required this.spreads,
    required this.mine,
    this.compact = false,
    this.elsewhere = 1,
  });

  /// Every ward, most raised first ([wardSpreads]).
  final List<WardSpread> spreads;
  final List<Ward> mine;

  /// Phone: usual wards merge into one card ("Intensive care and Surgery").
  final bool compact;

  /// How many raised wards outside [mine] to mention.
  final int elsewhere;

  @override
  Widget build(BuildContext context) {
    final own = [
      for (final s in spreads)
        if (mine.contains(s.ward)) s,
    ];
    final usual = [
      for (final s in own)
        if (!s.status.raised) s,
    ];
    final raised = [
      for (final s in own)
        if (s.status.raised) s,
    ];
    final other = [
      for (final s in spreads)
        if (!mine.contains(s.ward) && s.status.raised) s,
    ].take(elsewhere);

    final cards = <Widget>[
      for (final s in raised)
        _StatusNote(title: s.ward.label, body: _raisedAdvice(s, here: true), raised: true),
      if (compact && usual.isNotEmpty)
        _StatusNote(title: _join(usual.map((s) => s.ward.label)), body: _usualAdvice)
      else
        for (final s in usual) _StatusNote(title: s.ward.label, body: _usualAdvice),
      for (final s in other)
        _StatusNote(
          title: 'If you also work on ${s.ward.label}',
          body: _raisedAdvice(s, here: false),
          raised: true,
        ),
    ];
    if (compact) {
      return ColumnGap(cards, gap: AmrSpace.x8, crossAxisAlignment: CrossAxisAlignment.stretch);
    }
    return AutoGrid(minItemWidth: 280, gap: AmrSpace.x12, children: cards);
  }
}

const _usualAdvice = 'As usual. Keep your normal routine.';

String _raisedAdvice(WardSpread s, {required bool here}) {
  final type = s.top?.phenotype.code ?? 'resistant bacteria';
  return 'More $type than usual${here ? '' : ' there'}. Follow its $type cleaning guideline.';
}

String _join(Iterable<String> names) {
  final list = names.toList();
  if (list.length <= 1) return list.join();
  return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
}

class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.title, required this.body, this.raised = false});

  final String title;
  final String body;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final phone = context.isCompact;
    return StatusCard(
      status: raised ? SpreadStatus.high : SpreadStatus.usual,
      radius: phone ? 14 : 16,
      padding: EdgeInsets.all(phone ? AmrSpace.x16 : AmrSpace.x22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AmrText.body(phone ? 16 : 17, weight: FontWeight.w500)),
          SizedBox(height: phone ? 4 : 8),
          Text(body, style: AmrText.body(phone ? 14 : 15)),
        ],
      ),
    );
  }
}

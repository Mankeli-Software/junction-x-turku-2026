import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models/data.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final organismMixEntry = CatalogEntry(
  name: 'OrganismMix',
  title: 'What is causing it',
  description: 'Which bacteria are causing this infection now; the weights behind coverage.',
  builder: (context, params, slot) =>
      OrganismMixWidget(query: OrganismMixQuery.fromJson(params), slot: slot),
);

class OrganismMixWidget extends StatelessWidget {
  const OrganismMixWidget({super.key, required this.query, this.slot = WidgetSlot.page});

  final OrganismMixQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<OrganismMixQuery, OrganismMix>(
    query: query,
    fetch: (repo, q) => repo.organisms(q),
    builder: (context, mix) => OrganismMixView(mix: mix, slot: slot),
  );
}

/// "What is usually causing it": the top organisms as share bars, the rest as "Other".
class OrganismMixView extends StatelessWidget {
  const OrganismMixView({super.key, required this.mix, this.slot = WidgetSlot.page, this.top = 4});

  final OrganismMix mix;
  final WidgetSlot slot;
  final int top;

  @override
  Widget build(BuildContext context) {
    if (slot == WidgetSlot.chat) return OrganismMixStrip(mix: mix);
    final shown = mix.organisms.take(top).toList();
    final other = mix.organisms.skip(top).fold<double>(0, (a, o) => a + o.share);
    final rows = [
      for (final o in shown) (o.organism.code, o.share, true),
      if (other > 0.005) ('Other', other, false),
    ];
    final subtitle = [
      if (mix.specimen != null) '${mix.specimen!.label} cultures',
      mix.ward?.label ?? 'Whole hospital',
      windowLabel(mix.window),
    ].join(' · ');
    final compact = context.isCompact || slot != WidgetSlot.page;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slot != WidgetSlot.card) ...[
          Text('What is usually causing it', style: AmrText.title(26)),
          const SizedBox(height: 14),
        ],
        Text(subtitle, style: AmrText.body(14)),
        const SizedBox(height: 14),
        if (rows.isEmpty) Text('No isolates in this period.', style: AmrText.body(15)),
        for (final (name, share, italic) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                SizedBox(
                  width: compact ? 150 : 190,
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: AmrText.inter(15, style: italic ? FontStyle.italic : null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShareBar(
                    value: share,
                    track: slot == WidgetSlot.card ? AmrColors.lavenderSoft : AmrColors.white,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 44,
                  child: Text(
                    pct(share),
                    textAlign: TextAlign.right,
                    style: AmrText.body(15, weight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        if (mix.note != null) Text(mix.note!, style: AmrText.body(13, height: 1.45)),
      ],
    );
    if (slot == WidgetSlot.card) return body;
    return AmrCard(tone: AmrCardTone.subtle, child: body);
  }
}

/// Chat version: one stacked bar and a line of names, e.g. "E. coli 57% · Klebsiella 11% ·
/// other 16% · last 4 weeks".
class OrganismMixStrip extends StatelessWidget {
  const OrganismMixStrip({super.key, required this.mix, this.top = 4});

  final OrganismMix mix;
  final int top;

  static String _infection(OrganismMix m) => switch (m.specimen) {
    Specimen.urine => 'urinary infections',
    Specimen.blood => 'bloodstream infections',
    Specimen.wound => 'wound infections',
    null => 'infections',
  };

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final shown = mix.organisms.take(top).toList();
    final other = mix.organisms.skip(top).fold<double>(0, (a, o) => a + o.share);
    final colors = AmrColors.series;
    final small = AmrText.body(compact ? 12 : 14);
    final italic = AmrText.inter(compact ? 12 : 14, style: FontStyle.italic);
    return AmrCard(
      tone: AmrCardTone.subtle,
      padding: EdgeInsets.all(compact ? 16 : 24),
      child: ColumnGap(
        [
          if (compact)
            Text('What is causing it', style: AmrText.body(14, weight: FontWeight.w500))
          else
            Text(
              'What is causing ${_infection(mix)} on ${mix.ward?.label ?? 'the whole hospital'}',
              style: AmrText.title(22, em: 0),
            ),
          StackedBar(
            height: compact ? 14 : 20,
            radius: compact ? 5 : 8,
            segments: [
              for (var i = 0; i < shown.length; i++) (shown[i].share, colors[i]),
              if (other > 0) (other, colors.last),
            ],
          ),
          Text.rich(
            TextSpan(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) TextSpan(text: ' · ', style: small),
                  TextSpan(text: shown[i].organism.short, style: italic),
                  TextSpan(text: ' ${pct(shown[i].share)}', style: small),
                ],
                if (other > 0) TextSpan(text: ' · other ${pct(other)}', style: small),
                if (!compact) TextSpan(text: ' · ${windowLabel(mix.window)}', style: small),
              ],
            ),
          ),
          if (mix.note != null) Text(mix.note!, style: AmrText.body(12, height: 1.45)),
        ],
        gap: compact ? 8 : 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

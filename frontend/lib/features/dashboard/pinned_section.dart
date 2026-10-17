import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../catalog/actions.dart';
import '../../catalog/catalog.dart';
import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import 'dashboard_cubit.dart';

/// "UTI · Urology · woman 75+" from a placement's params.
String placementTitle(Json params) {
  final p = PatientProfile.fromJson(params);
  final infection = switch (p.infectionType) {
    InfectionType.uti => 'UTI',
    final InfectionType t => t.label,
    null => p.specimen?.label,
  };
  final who = [?p.sex?.inSentence, ?p.ageBand?.short].join(' ');
  final parts = [?infection, p.ward?.label ?? 'Whole hospital', if (who.isNotEmpty) who];
  return parts.join(' · ');
}

/// "Pinned for you": the user's saved catalog widgets plus the "Add a widget" card.
class PinnedSection extends StatelessWidget {
  const PinnedSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        final cards = <Widget>[
          if (state.loading && state.dashboard == null)
            for (var i = 0; i < 2; i++)
              const AmrCard(padding: EdgeInsets.all(24), child: SkeletonBlock(lines: 3)),
          for (final p in state.layout)
            if (p.widget != 'ContextChips') _PinnedCard(placement: p),
          const _AddWidgetCard(),
        ];
        return ColumnGap(
          [
            SectionHeader(
              title: 'Pinned for you',
              subtitle: 'Always showing the latest data.',
              trailing: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  const AmrButton(label: 'Edit layout'),
                  AmrButton(
                    label: '+ Add widget',
                    variant: AmrButtonVariant.primary,
                    onPressed: () => _pinFirstMissing(context),
                  ),
                ],
              ),
            ),
            if (state.error != null && state.dashboard == null)
              InlineError(
                message: 'Could not load your pinned views.',
                onRetry: context.read<DashboardCubit>().load,
              ),
            AutoGrid(minItemWidth: 380, children: cards),
          ],
          gap: AmrSpace.x20,
          crossAxisAlignment: CrossAxisAlignment.stretch,
        );
      },
    );
  }

  void _pinFirstMissing(BuildContext context) {
    final pinned = context.read<DashboardCubit>().state.layout.map((p) => p.widget).toSet();
    final entry = context
        .read<WidgetCatalog>()
        .entries
        .where((e) => e.name != 'ContextChips' && !pinned.contains(e.name))
        .firstOrNull;
    if (entry != null) _pin(context, entry);
  }
}

void _pin(BuildContext context, CatalogEntry entry) {
  final ward = context.read<SessionCubit>().state.user?.ward;
  context.read<DashboardCubit>().pin(
    WidgetPlacement(widget: entry.name, params: {'ward': ?ward?.code}),
  );
}

class _PinnedCard extends StatelessWidget {
  const _PinnedCard({required this.placement});

  final WidgetPlacement placement;

  @override
  Widget build(BuildContext context) {
    final entry = context.read<WidgetCatalog>()[placement.widget];
    final profile = PatientProfile.fromJson(placement.params);
    final opensAnswer = placement.widget == 'CoverageRanking' || placement.widget == 'OrganismMix';
    return AmrCard(
      padding: const EdgeInsets.all(AmrSpace.x24),
      // spaceBetween, not Spacer: the link sits at the bottom of a stretched card (CSS
      // margin-top: auto) and the card still measures in an unbounded first pass.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry?.title ?? placement.widget, style: AmrText.label(12)),
                        const SizedBox(height: 4),
                        Text(placementTitle(placement.params), style: AmrText.title(22, em: 0)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CardMenu(placement: placement),
                ],
              ),
              const SizedBox(height: 14),
              CatalogWidget(placement, slot: WidgetSlot.card),
            ],
          ),
          if (opensAnswer)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AmrLink(
                  'Open full answer',
                  onTap: () => context.read<CatalogActions>().openAnswer(profile),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.placement});

  final WidgetPlacement placement;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AmrColors.white),
        surfaceTintColor: WidgetStatePropertyAll(AmrColors.white),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AmrRadius.card)),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(LucideIcons.pinOff, size: 18, color: AmrColors.ink),
          onPressed: () => context.read<DashboardCubit>().unpin(placement),
          child: Text('Remove from home', style: AmrText.body(15)),
        ),
      ],
      builder: (context, controller, _) => AmrIconButton(
        icon: LucideIcons.ellipsis,
        size: 40,
        variant: AmrIconButtonVariant.soft,
        tooltip: 'Widget options',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _AddWidgetCard extends StatelessWidget {
  const _AddWidgetCard();

  @override
  Widget build(BuildContext context) {
    final entries = context.read<WidgetCatalog>().entries.where((e) => e.name != 'ContextChips');
    return AmrCard(
      tone: AmrCardTone.dashed,
      padding: const EdgeInsets.all(AmrSpace.x24),
      child: ColumnGap([
        Text('Add a widget', style: AmrText.title(24, em: 0)),
        Text('Describe what you want to see', style: AmrText.body(14, weight: FontWeight.w500)),
        AskField(
          hint: 'e.g. MRSA on my ward this year',
          style: AskFieldStyle.flat,
          onSubmit: context.read<CatalogActions>().ask,
        ),
        Text('Or pick from the catalog', style: AmrText.body(14, weight: FontWeight.w500)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in entries)
              AmrButton(
                label: '+ ${e.title ?? e.name}',
                size: AmrButtonSize.sm,
                variant: AmrButtonVariant.outline,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                onPressed: () => _pin(context, e),
              ),
          ],
        ),
      ], crossAxisAlignment: CrossAxisAlignment.stretch),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import 'research_cubit.dart';
import 'research_data.dart';

class FilterOption {
  const FilterOption(this.label, this.next, {this.selected = false});

  final String label;
  final ResearchFilters next;
  final bool selected;
}

/// One row of the filters panel: its label, the current value and the choices.
class FilterField {
  const FilterField(this.label, this.value, this.chip, this.options);

  final String label;
  final String value;

  /// Short form for the phone's chip summary.
  final String chip;
  final List<FilterOption> options;
}

final _monYear = DateFormat('MMM y');

List<FilterField> filterFields(ResearchFilters f, DateTime asOf) {
  FilterOption opt(String label, ResearchFilters next, bool selected) =>
      FilterOption(label, next, selected: selected);
  final start = f.period.start(asOf);
  return [
    FilterField(
      'Time period',
      '${day(start)} – ${day(asOf)}',
      '${_monYear.format(start)} – '
          '${_monYear.format(asOf)}',
      [for (final p in ResearchPeriod.values) opt(p.label, f.copyWith(period: p), p == f.period)],
    ),
    FilterField('Ward', f.ward?.label ?? 'All wards', f.ward?.short ?? 'All wards', [
      opt('All wards', f.copyWith(ward: () => null), f.ward == null),
      for (final w in Ward.values) opt(w.label, f.copyWith(ward: () => w), w == f.ward),
    ]),
    FilterField('Sample', f.specimen?.label ?? 'All samples', f.specimen?.label ?? 'All samples', [
      opt('All samples', f.copyWith(specimen: () => null), f.specimen == null),
      for (final s in Specimen.values) opt(s.label, f.copyWith(specimen: () => s), s == f.specimen),
    ]),
    FilterField('Organism', f.organism.code, f.organism.short, [
      for (final o in Organism.values) opt(o.code, f.copyWith(organism: o), o == f.organism),
    ]),
    FilterField('Antibiotic', f.drug.label, f.drug.label, [
      for (final d in Drug.values) opt(d.label, f.copyWith(drug: d), d == f.drug),
    ]),
    FilterField(
      'Split by',
      f.split.label,
      f.split == SplitBy.none ? 'No split' : 'Split by ${f.split.label.toLowerCase()}',
      [
        for (final s in SplitBy.values)
          opt(
            s.label,
            // A split replaces the filter it splits on.
            f.copyWith(
              split: s,
              ageBand: s == SplitBy.age ? () => null : null,
              onset: s == SplitBy.onset ? () => null : null,
            ),
            s == f.split,
          ),
      ],
    ),
    FilterField(
      'Age',
      f.split == SplitBy.age ? 'By age group' : (f.ageBand?.label ?? 'All ages'),
      f.ageBand?.short ?? 'All ages',
      [
        opt('All ages', f.copyWith(ageBand: () => null), f.ageBand == null),
        for (final a in AgeBand.values)
          opt(
            a.label,
            f.copyWith(ageBand: () => a, split: f.split == SplitBy.age ? SplitBy.none : null),
            a == f.ageBand,
          ),
      ],
    ),
    FilterField(
      'Onset',
      f.split == SplitBy.onset ? 'By onset' : (f.onset?.label ?? 'Home and hospital'),
      f.onset?.label ?? 'Home and hospital',
      [
        opt('Home and hospital', f.copyWith(onset: () => null), f.onset == null),
        for (final o in Onset.values)
          opt(
            o.label,
            f.copyWith(onset: () => o, split: f.split == SplitBy.onset ? SplitBy.none : null),
            o == f.onset,
          ),
      ],
    ),
  ];
}

const _note = 'First isolate per patient in each period. Numbers under 30 are hidden.';

/// Desktop: the lavender filters panel with one select per filter.
class FiltersPanel extends StatelessWidget {
  const FiltersPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.select((ResearchCubit c) => c.state.filters);
    final asOf = context.select((SessionCubit c) => c.state.asOf);
    return AmrCard(
      tone: AmrCardTone.accent,
      child: ColumnGap(
        [
          Text('Filters', style: AmrText.body(18, weight: FontWeight.w500)),
          for (final field in filterFields(f, asOf)) _LabelledSelect(field: field),
          Text(_note, style: AmrText.body(13, height: 1.45)),
        ],
        gap: AmrSpace.x16,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

class _LabelledSelect extends StatelessWidget {
  const _LabelledSelect({required this.field});

  final FilterField field;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(field.label, style: AmrText.body(14, weight: FontWeight.w500)),
      const SizedBox(height: 6),
      FilterSelect(field: field),
    ],
  );
}

/// White pill select; tapping opens the choices.
class FilterSelect extends StatelessWidget {
  const FilterSelect({super.key, required this.field});

  final FilterField field;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ResearchCubit>();
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AmrColors.white),
        surfaceTintColor: WidgetStatePropertyAll(AmrColors.white),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AmrRadius.card)),
        maximumSize: WidgetStatePropertyAll(Size(360, 420)),
      ),
      menuChildren: [
        for (final o in field.options)
          MenuItemButton(
            onPressed: () => cubit.setFilters(o.next),
            trailingIcon: o.selected
                ? const Icon(LucideIcons.check, size: 16, color: AmrColors.ink)
                : null,
            child: Text(
              o.label,
              style: AmrText.body(15, weight: o.selected ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
      ],
      builder: (context, controller, _) => Pressable(
        pressScale: 0.99,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        builder: (_, s) => AnimatedContainer(
          duration: AmrMotion.fast,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: s.hovered ? AmrColors.lavenderSoft : AmrColors.white,
            borderRadius: AmrRadius.pill,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(field.value, style: AmrText.body(15), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              const Icon(LucideIcons.chevronDown, size: 18, color: AmrColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone: the filters as a chip summary, with Change opening every filter in a bottom sheet.
class FiltersSummary extends StatelessWidget {
  const FiltersSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final f = context.select((ResearchCubit c) => c.state.filters);
    final asOf = context.select((SessionCubit c) => c.state.asOf);
    return AmrCard(
      tone: AmrCardTone.accent,
      padding: const EdgeInsets.all(AmrSpace.x18),
      child: ColumnGap(
        [
          Row(
            children: [
              Expanded(
                child: Text('Filters', style: AmrText.body(16, weight: FontWeight.w500)),
              ),
              AmrButton(
                label: 'Change',
                variant: AmrButtonVariant.primary,
                size: AmrButtonSize.sm,
                onPressed: () => showFiltersSheet(context),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final field in filterFields(f, asOf))
                Container(
                  constraints: const BoxConstraints(minHeight: 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const BoxDecoration(
                    color: AmrColors.white,
                    borderRadius: AmrRadius.pill,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 8),
                      Text(field.chip, style: AmrText.body(13)),
                      const SizedBox(height: 8),
                    ],
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

void showFiltersSheet(BuildContext context) {
  final cubit = context.read<ResearchCubit>();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scroll) => BlocBuilder<ResearchCubit, ResearchState>(
          builder: (context, state) {
            final asOf = context.select((SessionCubit c) => c.state.asOf);
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                Text('Filters', style: AmrText.title(26)),
                const SizedBox(height: 16),
                for (final field in filterFields(state.filters, asOf)) ...[
                  Text(field.label, style: AmrText.body(14, weight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: AmrColors.lavender,
                      borderRadius: AmrRadius.pill,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: FilterSelect(field: field),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(_note, style: AmrText.body(13, height: 1.45)),
                const SizedBox(height: 18),
                AmrButton(
                  label: 'Show results',
                  variant: AmrButtonVariant.primary,
                  size: AmrButtonSize.xl,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

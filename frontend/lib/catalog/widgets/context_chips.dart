import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/models/common.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import '../actions.dart';
import '../catalog.dart';

/// "Woman, 75+, on Urology, with a urinary tract infection that started in hospital".
String patientSentence(PatientProfile p) {
  final parts = <String>[
    if (p.sex != null) p.sex!.label,
    if (p.ageBand != null) p.ageBand!.short,
    if (p.ward != null) 'on ${p.ward!.label}',
  ];
  var s = parts.join(', ');
  if (p.infectionType != null) {
    s += '${s.isEmpty ? 'With' : ', with'} ${p.infectionType!.inSentence}';
    if (p.onset != null) s += ' that started ${p.onset!.inSentence}';
  } else if (p.specimen != null) {
    s += '${s.isEmpty ? '' : ', '}${p.specimen!.label.toLowerCase()} cultures';
  }
  return s.isEmpty ? 'Any patient' : s;
}

final contextChipsEntry = CatalogEntry(
  name: 'ContextChips',
  title: 'Selected patient',
  description: 'What was understood about the patient, with Edit and New patient.',
  builder: (context, params, slot) {
    final profile = PatientProfile.fromJson(params);
    return switch (slot) {
      WidgetSlot.card => Text(patientSentence(profile), style: AmrText.body(15, height: 1.45)),
      WidgetSlot.chat => SelectedPatientChips(profile: profile),
      WidgetSlot.page => SelectedPatientCard(profile: profile),
    };
  },
);

/// The "Selected patient" panel at the top of an answer.
class SelectedPatientCard extends StatelessWidget {
  const SelectedPatientCard({super.key, required this.profile});

  final PatientProfile profile;

  @override
  Widget build(BuildContext context) {
    final actions = context.read<CatalogActions>();
    final compact = context.isCompact;
    final text = Row(
      children: [
        Container(
          width: compact ? 48 : 64,
          height: compact ? 48 : 64,
          decoration: const BoxDecoration(color: AmrColors.lavender, shape: BoxShape.circle),
          child: Icon(LucideIcons.userRound, size: compact ? 22 : 28, color: AmrColors.ink),
        ),
        SizedBox(width: compact ? 14 : 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Selected patient', style: AmrText.label(14)),
              const SizedBox(height: 6),
              Text(
                patientSentence(profile),
                style: AmrText.sora(fluid(context, 22, 2.2, 30), height: 1.25),
              ),
            ],
          ),
        ),
      ],
    );
    final edit = AmrButton(
      label: 'Edit details',
      size: AmrButtonSize.xl,
      leading: const Icon(LucideIcons.pencil),
      expand: compact,
      padding: compact ? const EdgeInsets.symmetric(horizontal: 12) : null,
      onPressed: () => actions.editPatient(profile),
    );
    final fresh = AmrButton(
      label: 'New patient',
      size: AmrButtonSize.xl,
      variant: AmrButtonVariant.primary,
      fontWeight: FontWeight.w500,
      leading: const Icon(LucideIcons.plus),
      expand: compact,
      padding: compact ? const EdgeInsets.symmetric(horizontal: 12) : null,
      onPressed: actions.newPatient,
    );
    return AmrCard(
      radius: AmrRadius.panel,
      shadow: AmrShadows.lg,
      padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 28, vertical: compact ? 20 : 24),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: edit),
                    const SizedBox(width: 10),
                    Expanded(child: fresh),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 32),
                edit,
                const SizedBox(width: 10),
                fresh,
              ],
            ),
    );
  }
}

/// Lets the surrounding answer (a chat turn) take patient changes made on its chips. Without
/// one, a change opens the answer page for the new patient.
class PatientEditScope extends InheritedWidget {
  const PatientEditScope({super.key, required this.onChanged, required super.child});

  final ValueChanged<PatientProfile> onChanged;

  static PatientEditScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PatientEditScope>();

  @override
  bool updateShouldNotify(PatientEditScope old) => old.onChanged != onChanged;
}

/// One editable word of the patient: its label and the choices behind it.
class _Field {
  const _Field(this.label, this.options);

  final String label;
  final List<(String, PatientProfile)> options;
}

List<_Field> _fields(PatientProfile p, {required bool short}) => [
  if (p.sex != null)
    _Field(p.sex!.label, [for (final v in Sex.values) (v.label, p.copyWith(sex: v))]),
  if (p.ageBand != null)
    _Field(p.ageBand!.short, [for (final v in AgeBand.values) (v.label, p.copyWith(ageBand: v))]),
  if (p.ward != null)
    _Field(p.ward!.label, [for (final v in Ward.values) (v.label, p.copyWith(ward: v))]),
  if (p.infectionType != null)
    _Field(
      short && p.infectionType == InfectionType.uti
          ? 'UTI'
          : p.infectionType == InfectionType.uti
          ? 'Urinary tract infection'
          : p.infectionType!.label,
      [for (final v in InfectionType.values) (v.label, p.copyWith(infectionType: v))],
    ),
  if (p.onset != null)
    _Field(
      short
          ? (p.onset == Onset.hospital ? 'Hospital onset' : 'Home onset')
          : 'Started ${p.onset!.inSentence}',
      [for (final v in Onset.values) (v.label, p.copyWith(onset: v))],
    ),
];

/// Chat version: "Selected patient · tap to change" and one chip per word. A chip opens its
/// choices; the numbers below update without asking the AI again.
class SelectedPatientChips extends StatelessWidget {
  const SelectedPatientChips({super.key, required this.profile});

  final PatientProfile profile;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final scope = PatientEditScope.maybeOf(context);
    void change(PatientProfile p) =>
        scope != null ? scope.onChanged(p) : context.read<CatalogActions>().openAnswer(p);
    return AmrCard(
      radius: BorderRadius.circular(compact ? 18 : 20),
      shadow: compact ? AmrShadows.input : AmrShadows.md,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22, vertical: compact ? 14 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Selected patient · tap to change', style: AmrText.label(compact ? 12 : 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in _fields(profile, short: compact))
                _ChipMenu(field: f, compact: compact, onPick: change),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipMenu extends StatelessWidget {
  const _ChipMenu({required this.field, required this.compact, required this.onPick});

  final _Field field;
  final bool compact;
  final ValueChanged<PatientProfile> onPick;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AmrColors.white),
        surfaceTintColor: WidgetStatePropertyAll(AmrColors.white),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AmrRadius.card)),
      ),
      menuChildren: [
        for (final (label, p) in field.options)
          MenuItemButton(
            onPressed: () => onPick(p),
            child: Text(label, style: AmrText.body(15)),
          ),
      ],
      builder: (context, controller, _) => Pressable(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        builder: (_, s) => AnimatedContainer(
          duration: AmrMotion.fast,
          height: compact ? 34 : 36,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
          decoration: BoxDecoration(
            color: s.hovered ? AmrColors.lavender : AmrColors.lavenderPale,
            borderRadius: AmrRadius.pill,
          ),
          child: Align(
            widthFactor: 1,
            child: Text(field.label, style: AmrText.body(compact ? 13 : 14)),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../catalog/actions.dart';
import '../../core/models/common.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import 'patient_form_cubit.dart';

class _Option {
  const _Option(this.value, this.title, this.token, {this.sub, this.icon});

  final Object value;
  final String title;

  /// How the choice reads inside the sentence.
  final String token;
  final String? sub;
  final IconData? icon;
}

List<_Option> _options(PatientField f, Ward? home) => switch (f) {
  PatientField.sex => [for (final s in Sex.values) _Option(s, s.label, s.inSentence)],
  PatientField.age => [for (final a in AgeBand.values) _Option(a, a.label, a.short)],
  PatientField.ward => [
    for (final w in [?home, ...Ward.values.where((w) => w != home)])
      _Option(w, w.label, w.label, sub: w == home ? 'Your ward' : null),
  ],
  PatientField.infection => [
    for (final t in InfectionType.values)
      _Option(
        t,
        t.label,
        t.inSentence,
        sub: t.specimen == null ? 'Not in this data yet' : 'From ${t.specimen!.code} cultures',
        icon: switch (t) {
          InfectionType.uti => LucideIcons.droplet,
          InfectionType.sepsis => LucideIcons.activity,
          InfectionType.wound => LucideIcons.bandage,
          InfectionType.pneumonia => LucideIcons.wind,
        },
      ),
  ],
  PatientField.onset => [
    for (final o in Onset.values) _Option(o, o.label, o.inSentence, sub: o.hint),
  ],
};

Object? _valueOf(PatientField f, PatientProfile p) => switch (f) {
  PatientField.sex => p.sex,
  PatientField.age => p.ageBand,
  PatientField.ward => p.ward,
  PatientField.infection => p.infectionType,
  PatientField.onset => p.onset,
};

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// The quick patient form: a tappable sentence, option tiles for the active word, keys 1–N.
class PatientForm extends StatelessWidget {
  const PatientForm({super.key, required this.homeWard});

  final Ward? homeWard;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientFormCubit, PatientFormState>(
      builder: (context, state) {
        final cubit = context.read<PatientFormCubit>();
        final options = _options(state.active, homeWard);
        final selected = _valueOf(state.active, state.profile);
        return Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is! KeyDownEvent) return KeyEventResult.ignored;
            final n = _digits.indexOf(e.logicalKey) + 1;
            if (n < 1 || n > options.length) return KeyEventResult.ignored;
            cubit.pick(options[n - 1].value);
            return KeyEventResult.handled;
          },
          child: AmrCard(
            radius: AmrRadius.panel,
            shadow: AmrShadows.lg,
            padding: EdgeInsets.all(fluid(context, 24, 3.5, 44)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Text(
                      'Or tap the words to change them',
                      style: AmrText.body(15, weight: FontWeight.w500),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Step ${state.step + 1} of 5', style: AmrText.body(14)),
                        StepDots(count: 5, current: state.step),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _Sentence(state: state, homeWard: homeWard),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.only(top: 24),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AmrColors.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Text(
                            state.active.question,
                            style: AmrText.body(17, weight: FontWeight.w500),
                          ),
                          if (!context.isCompact) _KeyHint(max: options.length),
                        ],
                      ),
                      const SizedBox(height: 14),
                      AnimatedSwitcher(
                        duration: AmrMotion.base,
                        switchInCurve: AmrMotion.curve,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.03),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          ),
                        ),
                        child: AutoGrid(
                          key: ValueKey(state.active),
                          minItemWidth: context.isCompact ? 140 : 200,
                          gap: 12,
                          children: [
                            for (var i = 0; i < options.length; i++)
                              _Tile(
                                option: options[i],
                                index: i + 1,
                                selected: options[i].value == selected,
                                onTap: () => cubit.pick(options[i].value),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // On a phone the button sticks to the bottom of the screen instead.
                    if (!context.isCompact)
                      AmrButton(
                        label: 'Show what works',
                        variant: AmrButtonVariant.primary,
                        size: AmrButtonSize.hero,
                        trailing: const Text('→'),
                        onPressed: () => context.read<CatalogActions>().openAnswer(state.profile),
                      ),
                    Text(
                      'Answers in under a second. Your ward and the usual choices are filled in '
                      'for you.',
                      style: AmrText.body(14),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Sentence extends StatelessWidget {
  const _Sentence({required this.state, required this.homeWard});

  final PatientFormState state;
  final Ward? homeWard;

  @override
  Widget build(BuildContext context) {
    final style = AmrText.sentence(context);
    final fields = PatientField.values;
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final f in fields) ...[
          Text(f.lead, style: style),
          _Token(
            label: _tokenFor(f) + (f == fields.last ? '.' : ''),
            active: f == state.active,
            style: style,
            onTap: () => context.read<PatientFormCubit>().focus(f),
          ),
        ],
      ],
    );
  }

  String _tokenFor(PatientField f) {
    final v = _valueOf(f, state.profile);
    return _options(f, homeWard).where((o) => o.value == v).firstOrNull?.token ?? '…';
  }
}

class _Token extends StatelessWidget {
  const _Token({
    required this.label,
    required this.active,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool active;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AmrColors.white : AmrColors.ink;
    return Pressable(
      onTap: onTap,
      builder: (_, s) => AnimatedContainer(
        duration: AmrMotion.base,
        curve: AmrMotion.curve,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.fromLTRB(24, 6, 20, 6),
        decoration: BoxDecoration(
          color: active ? AmrColors.ink : (s.hovered ? AmrColors.lavender : AmrColors.lavenderPale),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: AnimatedDefaultTextStyle(
                duration: AmrMotion.base,
                style: style.copyWith(fontWeight: FontWeight.w400, color: fg, height: 1.2),
                child: Text(label),
              ),
            ),
            const SizedBox(width: 10),
            Icon(LucideIcons.chevronDown, size: (style.fontSize ?? 30) * 0.6, color: fg),
          ],
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.max});

  final int max;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Press ', style: AmrText.body(13)),
      const Kbd('1'),
      Text(' – ', style: AmrText.body(13)),
      Kbd('$max'),
      Text(' to choose · it moves to the next word', style: AmrText.body(13)),
    ],
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.option,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final _Option option;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AmrColors.white : AmrColors.ink;
    return Pressable(
      onTap: onTap,
      builder: (_, s) => AnimatedContainer(
        duration: AmrMotion.base,
        curve: AmrMotion.curve,
        constraints: const BoxConstraints(minHeight: 112),
        padding: context.isCompact
            ? const EdgeInsets.all(16)
            : const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: selected ? AmrColors.ink : (s.hovered ? AmrColors.lavenderSoft : AmrColors.white),
          borderRadius: AmrRadius.card,
          border: Border.all(color: selected ? AmrColors.ink : AmrColors.lavender),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (option.icon != null) Icon(option.icon, size: 28, color: fg),
                const Spacer(),
                if (!context.isCompact)
                  Kbd(
                    '$index',
                    large: true,
                    color: selected ? AmrColors.white : AmrColors.lavenderPale,
                    textColor: AmrColors.ink,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.title,
                  style: AmrText.body(18, weight: FontWeight.w500).copyWith(color: fg),
                ),
                const SizedBox(height: 4),
                Text(
                  option.sub ?? ' ',
                  style: AmrText.body(13).copyWith(color: fg.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

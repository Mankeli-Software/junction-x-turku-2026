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

IconData _wardIcon(Ward w) => switch (w) {
  Ward.ed => LucideIcons.ambulance,
  Ward.medA || Ward.medB => LucideIcons.stethoscope,
  Ward.surg => LucideIcons.scissors,
  Ward.uro => LucideIcons.droplets,
  Ward.icu => LucideIcons.heartPulse,
  Ward.ger => LucideIcons.armchair,
  Ward.phcN || Ward.phcS => LucideIcons.housePlus,
};

IconData _ageIcon(AgeBand a) => switch (a) {
  AgeBand.a0_17 => LucideIcons.baby,
  AgeBand.a18_44 => LucideIcons.personStanding,
  AgeBand.a45_64 => LucideIcons.briefcase,
  AgeBand.a65_74 => LucideIcons.glasses,
  AgeBand.a75 => LucideIcons.armchair,
};

List<_Option> _options(PatientField f, Ward? home) => switch (f) {
  PatientField.sex => [
    for (final s in Sex.values)
      _Option(
        s,
        s.label,
        s.inSentence,
        icon: s == Sex.female ? LucideIcons.venus : LucideIcons.mars,
      ),
  ],
  PatientField.age => [
    for (final a in AgeBand.values) _Option(a, a.label, a.short, icon: _ageIcon(a)),
  ],
  PatientField.ward => [
    for (final w in [?home, ...Ward.values.where((w) => w != home)])
      _Option(w, w.label, w.label, sub: w == home ? 'Your ward' : null, icon: _wardIcon(w)),
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
    for (final o in Onset.values)
      _Option(
        o,
        o.label,
        o.inSentence,
        sub: o.hint,
        icon: o == Onset.community ? LucideIcons.house : LucideIcons.bedDouble,
      ),
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
/// After the last word it is "All set": the tiles fold away and "Show what works" (Enter)
/// appears at the end of the sentence.
class PatientForm extends StatelessWidget {
  const PatientForm({super.key, required this.homeWard});

  final Ward? homeWard;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PatientFormCubit, PatientFormState>(
      builder: (context, state) {
        final cubit = context.read<PatientFormCubit>();
        void submit() => context.read<CatalogActions>().openAnswer(state.profile);
        return Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is! KeyDownEvent) return KeyEventResult.ignored;
            final active = state.active;
            if (active == null) {
              if (e.logicalKey != LogicalKeyboardKey.enter &&
                  e.logicalKey != LogicalKeyboardKey.numpadEnter) {
                return KeyEventResult.ignored;
              }
              submit();
              return KeyEventResult.handled;
            }
            final options = _options(active, homeWard);
            final n = _digits.indexOf(e.logicalKey) + 1;
            if (n < 1 || n > options.length) return KeyEventResult.ignored;
            cubit.pick(options[n - 1].value);
            return KeyEventResult.handled;
          },
          child: AmrCard(
            radius: AmrRadius.panel,
            shadow: AmrShadows.lg,
            padding: EdgeInsets.all(context.vfit(fluid(context, 24, 3.5, 44), min: 22)),
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
                        Text(
                          state.done ? 'All set' : 'Step ${state.step + 1} of 5',
                          style: AmrText.body(14),
                        ),
                        StepDots(count: 5, current: state.done ? 4 : state.step),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: context.vfit(28, min: 16)),
                _Sentence(
                  state: state,
                  homeWard: homeWard,
                  trailing: state.done ? _ShowWhatWorks(onPressed: submit) : null,
                ),
                AnimatedSize(
                  duration: AmrMotion.slow,
                  curve: AmrMotion.curve,
                  alignment: Alignment.topCenter,
                  child: state.done
                      ? Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'All set. Tap a word if something is wrong, then show the answer.',
                                style: AmrText.body(13),
                              ),
                              AmrLink('Start over', fontSize: 13, onTap: cubit.startOver),
                            ],
                          ),
                        )
                      : _Choices(state: state, homeWard: homeWard),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The question and the option tiles for the active word.
class _Choices extends StatelessWidget {
  const _Choices({required this.state, required this.homeWard});

  final PatientFormState state;
  final Ward? homeWard;

  @override
  Widget build(BuildContext context) {
    final active = state.active!;
    final cubit = context.read<PatientFormCubit>();
    final options = _options(active, homeWard);
    final selected = _valueOf(active, state.profile);
    final dense = !context.isCompact && (context.isShort || options.length > 5);
    return Padding(
      padding: EdgeInsets.only(top: context.vfit(28, min: 16)),
      child: Container(
        padding: EdgeInsets.only(top: context.vfit(24, min: 14)),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AmrColors.line)),
        ),
        // The card eases to the new height (2 sexes, 9 wards) instead of jumping.
        child: AnimatedSize(
          duration: AmrMotion.slow,
          curve: AmrMotion.curve,
          alignment: Alignment.topCenter,
          // Fade-through: the old question and tiles leave in the first part, the new ones
          // arrive after, so the two sets never sit on top of each other.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 340),
            switchInCurve: const Interval(0.4, 1, curve: Curves.easeOutCubic),
            switchOutCurve: const Interval(0.55, 1, curve: Curves.easeInCubic),
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
            transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
            child: Column(
              key: ValueKey(active),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(active.question, style: AmrText.body(17, weight: FontWeight.w500)),
                    if (!context.isCompact) _KeyHint(max: options.length),
                  ],
                ),
                const SizedBox(height: 14),
                AutoGrid(
                  minItemWidth: context.isCompact ? 140 : 200,
                  gap: dense ? 10 : 12,
                  children: [
                    for (var i = 0; i < options.length; i++)
                      _StaggerIn(
                        // Starts once the old tiles have faded, then one tile after another.
                        delay: Duration(milliseconds: 120 + 30 * i),
                        child: _Tile(
                          option: options[i],
                          index: i + 1,
                          selected: options[i].value == selected,
                          dense: dense,
                          onTap: () => cubit.pick(options[i].value),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and lifts its child in after [delay], once.
class _StaggerIn extends StatefulWidget {
  const _StaggerIn({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  late final _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (context, child) => Opacity(
      opacity: _a.value,
      child: Transform.translate(offset: Offset(0, 10 * (1 - _a.value)), child: child),
    ),
    child: widget.child,
  );
}

/// The violet "Show what works [Enter ↵]" at the end of the sentence once all words are set.
class _ShowWhatWorks extends StatelessWidget {
  const _ShowWhatWorks({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AmrMotion.slow,
      curve: AmrMotion.curve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
      child: Pressable(
        onTap: onPressed,
        builder: (_, s) => AnimatedContainer(
          duration: AmrMotion.fast,
          constraints: BoxConstraints(minHeight: context.isShort ? 46 : 54),
          padding: EdgeInsets.only(left: 28, right: compact ? 28 : 12),
          decoration: BoxDecoration(
            color: s.hovered ? AmrColors.violetHover : AmrColors.violet,
            borderRadius: AmrRadius.pill,
            boxShadow: const [
              BoxShadow(color: Color(0x59635BF1), offset: Offset(0, 6), blurRadius: 18),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Show what works',
                style: AmrText.body(16, weight: FontWeight.w600).copyWith(color: AmrColors.white),
              ),
              if (!compact) ...[
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Enter ↵', style: AmrText.label(12).copyWith(color: AmrColors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Sentence extends StatelessWidget {
  const _Sentence({required this.state, required this.homeWard, this.trailing});

  final PatientFormState state;
  final Ward? homeWard;

  /// Placed after the last word ("Show what works" once all set).
  final Widget? trailing;

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
            confirmed: state.confirmed.contains(f),
            style: style,
            onTap: () => context.read<PatientFormCubit>().focus(f),
          ),
        ],
        ?trailing,
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
    this.confirmed = false,
  });

  final String label;
  final bool active;

  /// Chosen by the user (not just the pre-filled default): drawn a little bolder.
  final bool confirmed;
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
        constraints: BoxConstraints(minHeight: context.isShort ? 46 : 56),
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
                style: style.copyWith(
                  fontWeight: confirmed || active ? FontWeight.w500 : FontWeight.w400,
                  color: fg,
                  height: 1.2,
                ),
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
    this.dense = false,
  });

  final _Option option;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  /// One line per option (short windows, long lists like the 9 wards).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AmrColors.white : AmrColors.ink;
    if (dense) return _dense(context, fg);
    return Pressable(
      onTap: onTap,
      builder: (_, s) => AnimatedContainer(
        duration: AmrMotion.base,
        curve: AmrMotion.curve,
        constraints: BoxConstraints(minHeight: context.isShort ? 84 : 112),
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

  /// The compact tile: one row with the icon, the name and hint, and the number key.
  Widget _dense(BuildContext context, Color fg) => Pressable(
    onTap: onTap,
    builder: (_, s) => AnimatedContainer(
      duration: AmrMotion.base,
      curve: AmrMotion.curve,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: selected ? AmrColors.ink : (s.hovered ? AmrColors.lavenderSoft : AmrColors.white),
        borderRadius: AmrRadius.card,
        border: Border.all(color: selected ? AmrColors.ink : AmrColors.lavender),
      ),
      child: Row(
        children: [
          if (option.icon != null) ...[
            AnimatedContainer(
              duration: AmrMotion.base,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected ? const Color(0x26FFFFFF) : AmrColors.lavenderSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(option.icon, size: 20, color: fg),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  option.title,
                  style: AmrText.body(
                    16,
                    weight: FontWeight.w500,
                    height: 1.25,
                  ).copyWith(color: fg),
                ),
                if (option.sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    option.sub!,
                    style: AmrText.body(
                      13,
                      height: 1.3,
                    ).copyWith(color: fg.withValues(alpha: 0.85)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Kbd(
            '$index',
            large: true,
            color: selected ? AmrColors.white : AmrColors.lavenderPale,
            textColor: AmrColors.ink,
          ),
        ],
      ),
    ),
  );
}

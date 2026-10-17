import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../ds/ds.dart';
import '../../session/demo_users.dart';
import '../../session/session_cubit.dart';
import '../shell/app_page.dart';

/// Demo login: pick a predefined profile, no password.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  DemoUser _picked = demoUsers.first;

  void _continue() => context.read<SessionCubit>().signIn(_picked);

  @override
  Widget build(BuildContext context) {
    return AppPage(
      glowHeight: 560,
      topBarTrailing: context.isCompact ? const SizedBox.shrink() : const _PocPill(),
      body: PageBody(
        top: fluid(context, 40, 7, 96),
        gap: AmrSpace.x40,
        children: [
          ColumnGap([
            Text('Sign in ✦ Demo', style: AmrText.body(15)),
            Text('Who is using it today?', style: AmrText.display(context)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Text(
                'Pick your profile. There is no password in this demo. Your profile sets your '
                'ward and what you see first, and you can switch from the top bar anytime.',
                style: AmrText.lede,
              ),
            ),
          ], gap: AmrSpace.x18),
          AutoGrid(
            minItemWidth: 340,
            children: [
              for (final g in UserGroup.values)
                _GroupCard(
                  group: g,
                  picked: _picked,
                  onPick: (u) => setState(() => _picked = u),
                  onConfirm: (u) {
                    setState(() => _picked = u);
                    _continue();
                  },
                ),
            ],
          ),
          Wrap(
            spacing: 28,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AmrButton(
                label: 'Continue as ${_picked.name}',
                variant: AmrButtonVariant.primary,
                size: AmrButtonSize.xxl,
                trailing: const Text('→'),
                onPressed: _continue,
              ),
              Text('Synthetic data only. Not for clinical decisions.', style: AmrText.body(14)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PocPill extends StatelessWidget {
  const _PocPill();

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AmrColors.white,
      borderRadius: AmrRadius.pill,
      boxShadow: AmrShadows.sm,
    ),
    child: Text('Proof of concept · synthetic data', style: AmrText.body(15)),
  );
}

IconData _groupIcon(UserGroup g) => switch (g) {
  UserGroup.clinicians => LucideIcons.stethoscope,
  UserGroup.prevention => LucideIcons.shieldCheck,
  UserGroup.labResearch => LucideIcons.flaskConical,
};

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.picked,
    required this.onPick,
    required this.onConfirm,
  });

  final UserGroup group;
  final DemoUser picked;
  final ValueChanged<DemoUser> onPick;
  final ValueChanged<DemoUser> onConfirm;

  @override
  Widget build(BuildContext context) {
    final users = demoUsers.where((u) => u.group == group);
    return AmrCard(
      tone: AmrCardTone.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Icon(_groupIcon(group), size: 40, color: AmrColors.ink),
          ),
          const SizedBox(height: 10),
          Text(group.label, style: AmrText.body(22, weight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(group.description, style: AmrText.body(15, height: 1.45)),
          const SizedBox(height: 18),
          for (final u in users) ...[
            _UserButton(
              user: u,
              selected: u == picked,
              onTap: () => onPick(u),
              onDoubleTap: () => onConfirm(u),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _UserButton extends StatelessWidget {
  const _UserButton({
    required this.user,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
  });

  final DemoUser user;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AmrColors.white : AmrColors.ink;
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Pressable(
        onTap: onTap,
        pressScale: 0.98,
        builder: (_, s) => AnimatedContainer(
          duration: AmrMotion.base,
          curve: AmrMotion.curve,
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.fromLTRB(20, 8, 10, 8),
          decoration: BoxDecoration(
            color: selected
                ? AmrColors.ink
                : (s.hovered ? AmrColors.lavenderSoft : AmrColors.white),
            borderRadius: AmrRadius.pill,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: AmrMotion.base,
                      style: AmrText.body(
                        16,
                        weight: FontWeight.w600,
                        height: 1.25,
                      ).copyWith(color: fg),
                      child: Text(user.name),
                    ),
                    AnimatedDefaultTextStyle(
                      duration: AmrMotion.base,
                      style: AmrText.body(
                        13,
                        height: 1.25,
                      ).copyWith(color: fg.withValues(alpha: 0.85)),
                      child: Text(user.title),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AmrAvatar(
                user.initials,
                size: 40,
                color: selected ? AmrColors.white : AmrColors.lavenderPale,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

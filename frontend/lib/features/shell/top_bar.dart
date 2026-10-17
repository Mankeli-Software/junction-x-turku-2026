import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import '../../session/demo_users.dart';
import '../../session/session_cubit.dart';
import 'replay_sheet.dart';

String taglineFor(Role? role) => switch (role) {
  Role.doctor => 'Know what works for your patient this week.',
  Role.hygiene || Role.careWorker => 'Know what is spreading, and where.',
  Role.lab => 'Spot real change early.',
  Role.researcher => 'Every filter, every period, ready to export.',
  null => 'Know what works for your patient this week.',
};

String replayLabel(SessionState s) =>
    s.isLive ? 'Data to ${day(s.asOf)}' : 'Replay · ${day(s.asOf)}';

/// Brand, tagline, replay date, user and switch user. On a phone: brand and avatar only; the
/// avatar opens a sheet with the rest.
class TopBar extends StatelessWidget {
  const TopBar({super.key, this.trailing, this.subtitle});

  /// Replaces the session controls (the login page shows a "Proof of concept" pill).
  final Widget? trailing;

  /// Replaces the role tagline next to the brand ("Home ✦ Ask").
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    final user = session.user;
    final compact = context.isCompact;
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('AMRight', style: AmrText.brand),
        if (!compact) ...[
          const SizedBox(width: 22),
          Flexible(child: Text(subtitle ?? taglineFor(user?.role), style: AmrText.body(15))),
        ],
      ],
    );
    final Widget controls;
    if (trailing != null) {
      controls = trailing!;
    } else if (user == null) {
      controls = const SizedBox.shrink();
    } else if (compact) {
      controls = Pressable(
        onTap: () => _showUserSheet(context),
        builder: (_, _) => AmrAvatar(user.initials, size: 44),
      );
    } else {
      controls = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          AmrButton(
            label: replayLabel(session),
            variant: AmrButtonVariant.surface,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(LucideIcons.clock),
            onPressed: () => showReplaySheet(context),
          ),
          AmrButton(
            label: '${user.name} · ${user.context}',
            variant: AmrButtonVariant.surface,
            padding: const EdgeInsets.only(left: 6, right: 20),
            leading: AmrAvatar(user.initials),
            onPressed: () => _showUserSheet(context),
          ),
          AmrButton(
            label: 'Switch user',
            variant: AmrButtonVariant.surface,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(LucideIcons.logOut),
            onPressed: () => context.read<SessionCubit>().signOut(),
          ),
        ],
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.gutter, vertical: 22),
      child: Row(
        children: [
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: brand),
          ),
          const SizedBox(width: 24),
          controls,
        ],
      ),
    );
  }
}

void _showUserSheet(BuildContext context) {
  final cubit = context.read<SessionCubit>();
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => BlocProvider.value(value: cubit, child: const _UserSheet()),
  );
}

/// The avatar menu: who you are, the replay date and switch user.
class _UserSheet extends StatelessWidget {
  const _UserSheet();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    final DemoUser? user = session.user;
    if (user == null) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AmrAvatar(user.initials, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name, style: AmrText.body(17, weight: FontWeight.w600)),
                      Text(user.title, style: AmrText.body(14)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SheetRow(
              label: 'Replay date',
              value: day(session.asOf),
              onTap: () {
                Navigator.of(context).pop();
                showReplaySheet(context);
              },
            ),
            const SizedBox(height: 10),
            _SheetRow(
              label: 'Component catalog',
              value: 'Every widget',
              onTap: () {
                Navigator.of(context).pop();
                GoRouter.of(context).go('/components');
              },
            ),
            const SizedBox(height: 20),
            AmrButton(
              label: 'Switch user',
              size: AmrButtonSize.xl,
              expand: true,
              leading: const Icon(LucideIcons.logOut),
              onPressed: () {
                Navigator.of(context).pop();
                context.read<SessionCubit>().signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    pressScale: 0.99,
    builder: (_, s) => AnimatedContainer(
      duration: AmrMotion.fast,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: s.hovered ? AmrColors.lavenderPale : AmrColors.lavenderSoft,
        borderRadius: AmrRadius.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AmrText.body(15, weight: FontWeight.w500)),
          ),
          Text(value, style: AmrText.body(15)),
          const SizedBox(width: 6),
          const Icon(LucideIcons.chevronRight, size: 18, color: AmrColors.ink),
        ],
      ),
    ),
  );
}

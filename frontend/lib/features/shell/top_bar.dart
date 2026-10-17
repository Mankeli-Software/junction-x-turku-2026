import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/router.dart';
import '../../core/format.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import 'replay_sheet.dart';

String taglineFor(Role? role) => switch (role) {
  Role.doctor => 'Know what works for your patient this week.',
  Role.hygiene || Role.careWorker => 'Know what is spreading, and where.',
  Role.lab => 'Spot real change early.',
  Role.researcher => 'Every filter, every period, ready to export.',
  null => 'Know what works for your patient this week.',
};

/// Goes to the signed-in user's home screen (the login page when nobody is signed in).
void goHome(BuildContext context) {
  final user = context.read<SessionCubit>().state.user;
  context.go(user == null ? Routes.login : Routes.homeFor(user.role));
}

String replayLabel(SessionState s) =>
    s.isLive ? 'Data to ${day(s.asOf)}' : 'Replay · ${day(s.asOf)}';

/// Brand, tagline, replay date, static user profile and switch user.
/// On a phone: brand and a static avatar only.
class TopBar extends StatelessWidget {
  const TopBar({super.key, this.trailing, this.subtitle, this.breadcrumb});

  /// Replaces the tagline with a breadcrumb whose first part can be tapped.
  final Widget? breadcrumb;

  /// Replaces the session controls.
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
        Pressable(
          onTap: () => goHome(context),
          pressScale: 1,
          builder: (_, _) => Text('AMRight', style: AmrText.brand),
        ),
        if (!compact) ...[
          const SizedBox(width: 22),
          Flexible(
            child: breadcrumb ?? Text(subtitle ?? taglineFor(user?.role), style: AmrText.body(15)),
          ),
        ],
      ],
    );
    final Widget controls;
    if (trailing != null) {
      controls = trailing!;
    } else if (user == null) {
      controls = const SizedBox.shrink();
    } else if (compact) {
      controls = AmrAvatar(user.initials, size: 44);
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
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(left: 6, right: 20),
            decoration: const BoxDecoration(
              color: AmrColors.white,
              borderRadius: AmrRadius.pill,
              boxShadow: AmrShadows.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AmrAvatar(user.initials),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '${user.name} · ${user.context}',
                    style: AmrText.inter(15, weight: FontWeight.w400, color: AmrColors.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
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
      padding: EdgeInsets.symmetric(
        horizontal: context.gutter,
        vertical: context.vfit(22, min: 12),
      ),
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

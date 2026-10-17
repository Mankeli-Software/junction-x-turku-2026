import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'pressable.dart';

/// "Action done" confirmation, 60px pill: "Pinned to your home [Undo]" (navy) or
/// "ecoli_tmp_by_sex.csv · 2 periods [Download]" ([dark] false: white with the small shadow).
class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.dark = true,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? AmrColors.white : AmrColors.ink;
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
      decoration: BoxDecoration(
        color: dark ? AmrColors.ink : AmrColors.white,
        borderRadius: AmrRadius.pill,
        boxShadow: dark ? null : AmrShadows.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: AmrText.body(15).copyWith(color: fg)),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 12),
            Pressable(
              onTap: onAction,
              builder: (_, s) => AnimatedContainer(
                duration: AmrMotion.fast,
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dark
                      ? (s.hovered ? const Color(0x1FFFFFFF) : const Color(0x00FFFFFF))
                      : (s.hovered ? AmrColors.inkHover : AmrColors.ink),
                  borderRadius: AmrRadius.pill,
                  border: dark ? Border.all(color: AmrColors.white) : null,
                ),
                child: Text(actionLabel!, style: AmrText.body(13).copyWith(color: AmrColors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

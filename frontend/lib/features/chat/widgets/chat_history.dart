import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/format.dart';
import '../../../ds/ds.dart';
import '../chat_cubit.dart';
import '../chat_models.dart';

/// "New chat" and the earlier conversations, newest first; tap one to reopen it. The side
/// panel on wide screens, the drawer elsewhere ([onPicked] closes the drawer).
class ChatHistory extends StatelessWidget {
  const ChatHistory({super.key, this.onPicked});

  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChatCubit>();
    final state = context.watch<ChatCubit>().state;
    final chats = state.chats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AmrButton(
          label: 'New chat',
          variant: AmrButtonVariant.primary,
          size: AmrButtonSize.md,
          expand: true,
          leading: const Icon(LucideIcons.plus),
          onPressed: state.entries.isEmpty
              ? null
              : () {
                  cubit.newChat();
                  onPicked?.call();
                },
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text('Recent chats', style: AmrText.label(13)),
        ),
        Expanded(
          child: chats.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Your chats appear here.',
                    style: AmrText.body(14).copyWith(color: AmrColors.inkHover),
                  ),
                )
              // The list scrolling must not frost the top bar.
              : NotificationListener<ScrollNotification>(
                  onNotification: (_) => true,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: chats.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, i) {
                      final c = chats[i];
                      return _ChatRow(
                        chat: c,
                        open: c.id == state.currentId,
                        onTap: () {
                          cubit.open(c.id);
                          onPicked?.call();
                        },
                        onDelete: () => cubit.delete(c.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// Title (the first question) and when it last changed; the delete button shows on hover.
class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.open,
    required this.onTap,
    required this.onDelete,
  });

  final Conversation chat;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    pressScale: 0.99,
    builder: (context, s) => AnimatedContainer(
      duration: AmrMotion.fast,
      padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
      decoration: BoxDecoration(
        color: open
            ? AmrColors.lavenderPale
            : s.hovered
            ? AmrColors.lavenderSoft
            : AmrColors.lavenderSoft.withValues(alpha: 0),
        borderRadius: AmrRadius.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chat.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AmrText.body(14, weight: open ? FontWeight.w600 : FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  _when(chat.updatedAt),
                  style: AmrText.body(12).copyWith(color: AmrColors.inkHover),
                ),
              ],
            ),
          ),
          // On hover, and always on the open chat (touch screens have no hover).
          IgnorePointer(
            ignoring: !(s.hovered || open),
            child: AnimatedOpacity(
              duration: AmrMotion.fast,
              opacity: s.hovered || open ? 1 : 0,
              child: AmrIconButton(
                icon: LucideIcons.trash2,
                size: 30,
                iconSize: 14,
                variant: AmrIconButtonVariant.soft,
                tooltip: 'Delete chat',
                onPressed: onDelete,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final _time = DateFormat('HH:mm');

/// "14:32" today, "Yesterday", then "9 Jun".
String _when(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  if (d == today) return _time.format(t);
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return dayShort(t);
}

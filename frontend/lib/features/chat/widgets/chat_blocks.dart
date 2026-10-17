import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../ds/ds.dart';

/// The question, right-aligned in navy (UserMessage).
class UserBubble extends StatelessWidget {
  const UserBubble(this.text, {super.key, this.short = false});

  final String text;

  /// A tapped choice: smaller padding and type.
  final bool short;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final r = compact ? 22.0 : 24.0;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? context.screenWidth * 0.85 : 620),
        child: Container(
          padding: short
              ? EdgeInsets.symmetric(horizontal: compact ? 16 : 20, vertical: compact ? 10 : 12)
              : EdgeInsets.symmetric(horizontal: compact ? 18 : 22, vertical: compact ? 14 : 16),
          decoration: BoxDecoration(
            color: AmrColors.ink,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(r),
              topRight: Radius.circular(r),
              bottomLeft: Radius.circular(r),
              bottomRight: const Radius.circular(6),
            ),
          ),
          child: Text(
            text,
            style: AmrText.body(
              short ? (compact ? 14 : 15) : (compact ? 16 : 17),
              height: 1.45,
            ).copyWith(color: AmrColors.white),
          ),
        ),
      ),
    );
  }
}

/// The ✦ avatar used for the assistant.
class AiMark extends StatelessWidget {
  const AiMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: AmrColors.lavender, shape: BoxShape.circle),
    child: Text(sparkle, style: AmrText.body(size * 0.45)),
  );
}

/// "✦ AMRight · Built from [coverage] [organism mix] · data to 30 Jun 2025": which tools
/// made the answer, so it is clear the numbers came from the data (AnswerHeader).
class AnswerHeader extends StatelessWidget {
  const AnswerHeader({super.key, this.builtFrom = const [], this.note, this.dataTo});

  final List<String> builtFrom;
  final String? note;
  final String? dataTo;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Wrap(
      spacing: compact ? 6 : 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AiMark(size: compact ? 32 : 40),
        Text('AMRight', style: AmrText.label(compact ? 14 : 15)),
        if (note != null)
          Text(note!, style: AmrText.body(compact ? 12 : 13))
        else if (builtFrom.isNotEmpty) ...[
          if (!compact) Text('Built from', style: AmrText.body(13)),
          for (final t in builtFrom)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 3 : 4,
              ),
              decoration: const BoxDecoration(
                color: AmrColors.lavenderSoft,
                borderRadius: AmrRadius.pill,
              ),
              child: Text(t, style: AmrText.body(compact ? 11 : 12)),
            ),
          if (dataTo != null && !compact) Text('· data to $dataTo', style: AmrText.body(12)),
        ],
      ],
    );
  }
}

/// "Building your answer · checking coverage on Urology…" with placeholder lines.
class BuildingCard extends StatelessWidget {
  const BuildingCard({super.key, this.status, this.onStop});

  final String? status;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return AmrCard(
      tone: AmrCardTone.quiet,
      padding: const EdgeInsets.all(AmrSpace.x24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Building your answer${status == null ? '…' : ' · ${status!}'}',
                  style: AmrText.body(14, weight: FontWeight.w500),
                ),
              ),
              if (onStop != null)
                AmrButton(label: 'Stop', size: AmrButtonSize.sm, fontSize: 13, onPressed: onStop),
            ],
          ),
          const SizedBox(height: 10),
          const FractionallySizedBox(widthFactor: 0.70, child: Skeleton(height: 18, radius: 9)),
          const SizedBox(height: 10),
          const FractionallySizedBox(widthFactor: 0.92, child: Skeleton(height: 18, radius: 9)),
          const SizedBox(height: 10),
          const FractionallySizedBox(widthFactor: 0.54, child: Skeleton(height: 18, radius: 9)),
        ],
      ),
    );
  }
}

/// A question back with tappable answers (ClarifyingQuestion). Every option looks the same
/// until one is tapped, so nothing seems chosen in advance; then the choice stays highlighted.
class ClarifyCard extends StatelessWidget {
  const ClarifyCard({
    super.key,
    required this.question,
    required this.options,
    this.chosen,
    this.onChoose,
  });

  final String question;
  final List<String> options;
  final String? chosen;
  final ValueChanged<String>? onChoose;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final buttons = [
      for (var i = 0; i < options.length; i++)
        AmrButton(
          label: options[i],
          size: AmrButtonSize.lg,
          variant: chosen == options[i] ? AmrButtonVariant.primary : AmrButtonVariant.soft,
          expand: compact,
          fontWeight: FontWeight.w400,
          onPressed: chosen == null && onChoose != null ? () => onChoose!(options[i]) : null,
        ),
    ];
    return AmrCard(
      tone: AmrCardTone.subtle,
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(question, style: AmrText.sora(compact ? 21 : 24, em: -0.015, height: 1.25)),
          const SizedBox(height: 14),
          if (compact)
            ColumnGap(buttons, gap: 8, crossAxisAlignment: CrossAxisAlignment.stretch)
          else
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ],
      ),
    );
  }
}

/// Under every answer: follow-ups that work without the AI, the main action, and feedback.
class AnswerActionsBar extends StatelessWidget {
  const AnswerActionsBar({super.key, required this.actions, this.onFeedback});

  /// (label, primary, icon, onTap).
  final List<(String, bool, IconData?, VoidCallback)> actions;
  final ValueChanged<bool>? onFeedback;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: compact ? 6 : 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (label, primary, icon, onTap) in actions)
          AmrButton(
            label: label,
            size: compact ? AmrButtonSize.sm : AmrButtonSize.md,
            fontSize: compact ? 13 : 14,
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
            variant: primary ? AmrButtonVariant.primary : AmrButtonVariant.outline,
            fontWeight: FontWeight.w400,
            leading: icon == null ? null : Icon(icon, size: 16),
            onPressed: onTap,
          ),
        if (onFeedback != null && !compact) ...[
          AmrIconButton(
            icon: LucideIcons.thumbsUp,
            variant: AmrIconButtonVariant.soft,
            tooltip: 'Helpful',
            onPressed: () => onFeedback!(true),
          ),
          AmrIconButton(
            icon: LucideIcons.thumbsDown,
            variant: AmrIconButtonVariant.soft,
            tooltip: 'Not helpful',
            onPressed: () => onFeedback!(false),
          ),
        ],
      ],
    );
  }
}

/// The ask box with suggestions above it (Composer). Suggestions come from the role, the ward
/// and the last answer, without the AI.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.onSend,
    this.suggestions = const [],
    this.hint = 'Ask anything about resistance on your wards…',
    this.enabled = true,
  });

  final ValueChanged<String> onSend;
  final List<String> suggestions;
  final String hint;
  final bool enabled;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = (text ?? _controller.text).trim();
    if (t.isEmpty || !widget.enabled) return;
    widget.onSend(t);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final field = compact ? 44.0 : 52.0;
    final chips = [
      for (final s in widget.suggestions)
        AmrButton(
          label: s,
          size: AmrButtonSize.sm,
          fontSize: compact ? 13 : 14,
          variant: AmrButtonVariant.outline,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
          onPressed: widget.enabled ? () => _send(s) : null,
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chips.isNotEmpty) ...[
          if (compact)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) => Center(child: chips[i]),
              ),
            )
          else
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          SizedBox(height: compact ? 8 : 10),
        ],
        Opacity(
          opacity: widget.enabled ? 1 : 0.6,
          child: Container(
            padding: compact
                ? const EdgeInsets.fromLTRB(18, 6, 6, 6)
                : const EdgeInsets.fromLTRB(26, 8, 8, 8),
            decoration: BoxDecoration(
              color: AmrColors.white,
              borderRadius: AmrRadius.pill,
              boxShadow: [
                BoxShadow(
                  color: Color(compact ? 0x241D204E : 0x1F1D204E),
                  offset: const Offset(0, 4),
                  blurRadius: compact ? 20 : 24,
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: field,
                    child: Center(
                      // Never disabled: on the web a disabled field's input turns read-only and
                      // stays read-only once enabled again, so nothing could be typed after an
                      // answer. While an answer builds, typing works and sending waits.
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        onSubmitted: (_) {
                          _send();
                          _focus.requestFocus();
                        },
                        style: AmrText.body(compact ? 16 : 17),
                        decoration: InputDecoration.collapsed(
                          hintText: widget.hint,
                          hintStyle: AmrText.body(
                            compact ? 16 : 17,
                          ).copyWith(color: AmrColors.inkHover),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!compact) ...[
                  AmrIconButton(
                    icon: LucideIcons.mic,
                    size: field,
                    iconSize: 20,
                    variant: AmrIconButtonVariant.soft,
                    tooltip: 'Speak',
                    onPressed: widget.enabled ? () {} : null,
                  ),
                  const SizedBox(width: 8),
                ],
                AmrIconButton(
                  icon: LucideIcons.arrowRight,
                  size: field,
                  iconSize: 20,
                  tooltip: 'Send',
                  onPressed: widget.enabled ? _send : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "AI unavailable · everything still works without it" with the way to the quick form.
class AiUnavailablePanel extends StatelessWidget {
  const AiUnavailablePanel({super.key, required this.onQuickForm, this.onRetry});

  final VoidCallback onQuickForm;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AmrCard(
      tone: AmrCardTone.subtle,
      radius: AmrRadius.bubble,
      child: ColumnGap(
        [
          const DotLabel(
            'AI unavailable · everything still works without it',
            color: AmrColors.periwinkle,
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
            decoration: const BoxDecoration(color: AmrColors.white, borderRadius: AmrRadius.pill),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  'AI answers are paused right now. The numbers and the quick form work as usual.',
                  style: AmrText.body(15),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (onRetry != null)
                      AmrButton(label: 'Try again', size: AmrButtonSize.md, onPressed: onRetry),
                    AmrButton(
                      label: 'Use the quick form',
                      size: AmrButtonSize.md,
                      fontSize: 14,
                      variant: AmrButtonVariant.primary,
                      onPressed: onQuickForm,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        gap: 16,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

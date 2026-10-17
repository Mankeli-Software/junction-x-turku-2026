import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../tokens.dart';
import '../typography.dart';
import 'buttons.dart';
import 'surfaces.dart';

/// A softly pulsing placeholder block.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 8});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Color.lerp(AmrColors.lavenderSoft, AmrColors.lavenderPale, _c.value),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    ),
  );
}

/// A few skeleton lines, the default loading state for a widget.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({super.key, this.lines = 4, this.lineHeight = 18});

  final int lines;
  final double lineHeight;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Skeleton(height: 24, width: 220),
      for (var i = 0; i < lines; i++) ...[
        const SizedBox(height: 14),
        FractionallySizedBox(
          widthFactor: 1 - (i % 3) * 0.15,
          child: Skeleton(height: lineHeight),
        ),
      ],
    ],
  );
}

/// Calm inline error with a retry.
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AmrCard(
    tone: AmrCardTone.subtle,
    padding: const EdgeInsets.all(AmrSpace.x20),
    child: Row(
      children: [
        const Icon(LucideIcons.cloudOff, size: 20, color: AmrColors.ink),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: AmrText.body(15))),
        if (onRetry != null)
          AmrButton(label: 'Try again', size: AmrButtonSize.sm, onPressed: onRetry),
      ],
    ),
  );
}

/// "Not in this data" / small-sample style note: a dot, a title and a sentence.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.title,
    this.body,
    this.dot = AmrColors.lavender,
    this.tone = AmrCardTone.subtle,
    this.actions = const [],
  });

  final String title;
  final String? body;
  final Color dot;
  final AmrCardTone tone;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AmrCard(
    tone: tone,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: StatusDot(color: dot, size: 12),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: AmrText.title(21, em: -0.01, height: 1.25))),
          ],
        ),
        if (body != null) ...[
          const SizedBox(height: 12),
          Text(body!, style: AmrText.body(14, height: 1.5)),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: actions),
        ],
      ],
    ),
  );
}

import 'package:flutter/material.dart';

import '../../ds/ds.dart';

/// "In short": the only free text the AI writes, from the numbers on the page. Without
/// [text] (no agent yet, or it is unavailable) it shows a quiet placeholder.
class InShortCard extends StatelessWidget {
  const InShortCard({super.key, this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final placeholder = text == null;
    return AmrCard(
      tone: AmrCardTone.subtle,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const AmrTag('In short', color: AmrColors.white),
              Text('Written by AI from the numbers on this page', style: AmrText.body(12)),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Text(
              text ?? 'A short summary appears here once the chat is connected.',
              style: AmrText.sora(
                22,
                em: -0.01,
                height: 1.35,
              ).copyWith(color: placeholder ? AmrColors.inkHover : AmrColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

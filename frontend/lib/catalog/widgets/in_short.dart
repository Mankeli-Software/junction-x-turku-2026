import 'package:flutter/material.dart';

import '../../core/models/data.dart';
import '../../core/query/query_view.dart';
import '../../core/repository.dart';
import '../../ds/ds.dart';

/// "In short": the only free text the AI writes, from the numbers on the page. Without
/// [text] (AI answers are off, or no line passed the number check) it shows a quiet
/// placeholder; while [loading] it says the line is being written.
class InShortCard extends StatelessWidget {
  const InShortCard({super.key, this.text, this.loading = false});

  final String? text;
  final bool loading;

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
              text ??
                  (loading
                      ? 'Writing a short summary from these numbers…'
                      : 'No short summary this time. Every number on this page is from the lab data.'),
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

/// A results page's "In short": the AI's line from the page's own numbers, loaded with [fetch]
/// (`GET /v1/agent/in-short…`). While it is written the card says so; when AI answers are off it
/// keeps the placeholder.
class AiInShort<Q extends AsOfQuery<Q>> extends StatelessWidget {
  const AiInShort({super.key, required this.query, required this.fetch});

  final Q query;
  final Future<InShort> Function(AmrRepository repo, Q query) fetch;

  @override
  Widget build(BuildContext context) => QueryView<Q, InShort>(
    query: query,
    fetch: fetch,
    loading: const InShortCard(loading: true),
    error: (_, _) => const InShortCard(),
    updatingLabel: false, // one line of text: the bar is enough
    builder: (_, s) => InShortCard(text: s.text),
  );
}

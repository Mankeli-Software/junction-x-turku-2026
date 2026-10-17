import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../catalog/actions.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import '../shell/top_bar.dart';
import 'chat_cubit.dart';
import 'chat_models.dart';
import 'widgets/chat_answer.dart';
import 'widgets/chat_blocks.dart';

/// What people ask, by role (Chat-overview): the composer's suggestions before the first answer.
List<String> roleQuestions(Role? role) => switch (role) {
  Role.doctor || null => [
    'What works for a UTI on my ward?',
    'What is causing UTIs now?',
    'Is trimethoprim still OK?',
  ],
  Role.hygiene => [
    'What is spreading this week?',
    'Which wards should we warn?',
    'MRSA in ICU this month?',
  ],
  Role.careWorker => ['Where should I clean more?', 'Is my ward OK?', 'What is ESBL?'],
  Role.lab => ['Is the Urology alert real?', 'Show the isolates', 'Compare Urology with Surgery'],
  Role.researcher => [
    'ICU MRSA trend in 2026',
    'E. coli trimethoprim trend by sex',
    'What do S, I and R mean?',
  ],
};

/// The chat: the conversation in a 1040px column, the composer stuck to the bottom.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.question});

  /// Sent once on open (`/chat?q=…`, from any "Ask" field in the app).
  final String? question;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    if (q != null && q.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ChatCubit>().send(q);
        context.replace('/chat'); // a reload must not ask again
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: AmrMotion.slow,
      curve: AmrMotion.curve,
    );
  });

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final role = context.select((SessionCubit c) => c.state.user?.role);
    final cubit = context.read<ChatCubit>();
    return Scaffold(
      body: BlocConsumer<ChatCubit, ChatState>(
        listenWhen: (a, b) =>
            a.entries.length != b.entries.length ||
            a.lastAnswer?.parts.length != b.lastAnswer?.parts.length ||
            a.lastAnswer?.streaming != b.lastAnswer?.streaming,
        listener: (_, _) => _toBottom(),
        builder: (context, state) {
          final empty = state.entries.isEmpty;
          final suggestions = state.lastAnswer?.suggestions.isNotEmpty ?? false
              ? state.lastAnswer!.suggestions
              : roleQuestions(role);
          return Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: AmrBackground(
                    glowHeight: 520,
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const TopBar(subtitle: 'Home ✦ Ask'),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1040),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  fluid(context, 16, 4, 48),
                                  compact ? 8 : 24,
                                  fluid(context, 16, 4, 48),
                                  compact ? 200 : 220,
                                ),
                                child: empty
                                    ? const _Welcome()
                                    : ColumnGap(
                                        [
                                          for (final e in state.entries)
                                            switch (e) {
                                              UserEntry() => UserBubble(e.text, short: e.short),
                                              AnswerEntry() => ChatAnswer(
                                                key: ValueKey(e.id),
                                                entry: e,
                                              ),
                                            },
                                        ],
                                        gap: compact ? 18 : 28,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00FFFFFF), AmrColors.white],
                      stops: [0, 0.3],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1040),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            fluid(context, 16, 4, 48),
                            24,
                            fluid(context, 16, 4, 48),
                            compact ? 26 : 32,
                          ),
                          child: state.aiUnavailable
                              ? AiUnavailablePanel(
                                  onQuickForm: context.read<CatalogActions>().newPatient,
                                )
                              : Composer(
                                  suggestions: state.busy ? const [] : suggestions,
                                  hint: empty
                                      ? 'Ask anything about resistance on your wards…'
                                      : 'Ask a follow-up…',
                                  enabled: !state.busy,
                                  onSend: cubit.send,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Before the first question: what the chat does and what people in this role ask.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return ColumnGap(
      [
        Text(
          'Ask anything. The AI arranges the answer, the lab data writes the numbers.',
          style: AmrText.sora(fluid(context, 34, 4.4, 56), em: -0.035, height: 1.06),
        ),
        Text(
          'Every answer is built from the same verified widgets the app uses. The AI picks which '
          'widget to show and for whom. It never types a number itself.',
          style: AmrText.body(compact ? 16 : 18, height: 1.55),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (n, t) in const [
              ('1', 'You ask'),
              ('2', 'AI reads your role, ward and date'),
              ('3', 'Verified widgets, numbers from the lab data'),
              ('4', 'Pin it, change a chip or ask more'),
            ])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: const BoxDecoration(
                  color: AmrColors.lavenderSoft,
                  borderRadius: AmrRadius.pill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(n, style: AmrText.sora(20, height: 1)),
                    const SizedBox(width: 10),
                    Text(t, style: AmrText.body(14)),
                  ],
                ),
              ),
          ],
        ),
      ],
      gap: compact ? 16 : 22,
      crossAxisAlignment: CrossAxisAlignment.start,
    );
  }
}

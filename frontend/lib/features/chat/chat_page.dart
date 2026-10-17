import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../catalog/actions.dart';
import '../../core/models/common.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import '../shell/sticky_top_bar.dart';
import '../shell/top_bar.dart';
import 'chat_cubit.dart';
import 'chat_models.dart';
import 'widgets/chat_answer.dart';
import 'widgets/chat_blocks.dart';
import 'widgets/chat_history.dart';

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

/// The chat: the conversation in a 1040px column, the composer stuck to the bottom, and the
/// history (a side panel on wide screens, a drawer elsewhere).
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.question, this.patient});

  /// Sent once on open (`/chat?q=…`, from any "Ask" field in the app).
  final String? question;

  /// The patient [question] was asked about (`&ward=…&infection_type=…`), from an answer page.
  final PatientProfile? patient;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();
  late final CatalogActions _actions = _InChatActions(
    context.read<CatalogActions>(),
    context.read<ChatCubit>(),
  );

  @override
  void initState() {
    super.initState();
    _askFromUrl();
  }

  @override
  void didUpdateWidget(ChatPage old) {
    super.didUpdateWidget(old);
    if (widget.question != old.question) _askFromUrl(); // `/chat?q=…` while already here
  }

  /// A question from outside the chat (`/chat?q=…`) always starts a new conversation.
  void _askFromUrl() {
    final q = widget.question;
    if (q == null || q.trim().isEmpty) return;
    final patient = widget.patient;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatCubit>()
        ..newChat()
        ..send(q, patient: patient);
      context.replace('/chat'); // a reload must not ask again
    });
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
    final wide = context.screenWidth >= 1200;
    final role = context.select((SessionCubit c) => c.state.user?.role);
    final cubit = context.read<ChatCubit>();
    final side = fluid(context, 16, 4, 48);
    return RepositoryProvider<CatalogActions>.value(
      value: _actions,
      child: Scaffold(
        key: _scaffold,
        drawer: wide
            ? null
            : Drawer(
                width: 320,
                backgroundColor: AmrColors.white,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: ChatHistory(onPicked: () => _scaffold.currentState?.closeDrawer()),
                  ),
                ),
              ),
        body: AmrBackground(
          glowHeight: 520,
          child: BlocConsumer<ChatCubit, ChatState>(
            listenWhen: (a, b) =>
                a.currentId != b.currentId ||
                a.entries.length != b.entries.length ||
                a.lastAnswer?.parts.length != b.lastAnswer?.parts.length ||
                a.lastAnswer?.streaming != b.lastAnswer?.streaming,
            listener: (_, _) => _toBottom(),
            builder: (context, state) {
              final empty = state.entries.isEmpty;
              final suggestions = state.lastAnswer?.suggestions.isNotEmpty ?? false
                  ? state.lastAnswer!.suggestions
                  : roleQuestions(role);
              Widget conversation(Widget topBar) => Stack(
                children: [
                  Positioned.fill(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            topBar,
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1040),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    side,
                                    compact ? 8 : 24,
                                    side,
                                    compact ? 200 : 220,
                                  ),
                                  child: ColumnGap(
                                    [
                                      if (!wide)
                                        _ChatBar(
                                          canStartNew: !empty,
                                          hasHistory: state.chats.isNotEmpty,
                                          onHistory: () => _scaffold.currentState?.openDrawer(),
                                          onNew: cubit.newChat,
                                        ),
                                      if (empty)
                                        const _Welcome()
                                      else
                                        for (final e in state.entries)
                                          switch (e) {
                                            UserEntry() => UserBubble(e.text, short: e.short),
                                            AnswerEntry() => ChatAnswer(
                                              key: ValueKey('${state.currentId}-${e.id}'),
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
                              padding: EdgeInsets.fromLTRB(side, 24, side, compact ? 26 : 32),
                              child: state.aiUnavailable
                                  ? AiUnavailablePanel(
                                      onQuickForm: context.read<CatalogActions>().newPatient,
                                    )
                                  : Composer(
                                      key: ValueKey(state.currentId),
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
              return StickyTopBar(
                bar: TopBar(
                  breadcrumb: Breadcrumb(const ['Home', 'Ask'], onTapFirst: () => goHome(context)),
                ),
                // Wide: the bar spans both columns and the conversation scrolls below it.
                page: (context, topBar) => wide
                    ? SafeArea(
                        bottom: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            topBar,
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    width: 300 + context.gutter,
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(context.gutter - 12, 24, 0, 0),
                                      child: const ChatHistory(),
                                    ),
                                  ),
                                  Expanded(child: conversation(const SizedBox.shrink())),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : conversation(topBar),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Narrow screens: "Chats" opens the history drawer, "New chat" starts over.
class _ChatBar extends StatelessWidget {
  const _ChatBar({
    required this.canStartNew,
    required this.hasHistory,
    required this.onHistory,
    required this.onNew,
  });

  final bool canStartNew;
  final bool hasHistory;
  final VoidCallback onHistory;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (hasHistory)
        AmrButton(
          label: 'Chats',
          size: AmrButtonSize.sm,
          variant: AmrButtonVariant.surface,
          leading: const Icon(LucideIcons.history, size: 16),
          onPressed: onHistory,
        ),
      const Spacer(),
      if (canStartNew)
        AmrButton(
          label: 'New chat',
          size: AmrButtonSize.sm,
          variant: AmrButtonVariant.primary,
          leading: const Icon(LucideIcons.plus, size: 16),
          onPressed: onNew,
        ),
    ],
  );
}

/// Inside the chat an "ask" continues the conversation; everywhere else it starts a new one.
class _InChatActions implements CatalogActions {
  _InChatActions(this._app, this._chat);

  final CatalogActions _app;
  final ChatCubit _chat;

  @override
  void ask(String question, {PatientProfile? patient}) => _chat.send(question, patient: patient);

  @override
  void openAnswer(PatientProfile profile) => _app.openAnswer(profile);

  @override
  void editPatient(PatientProfile profile) => _app.editPatient(profile);

  @override
  void newPatient() => _app.newPatient();

  @override
  void openAlert(String alertId) => _app.openAlert(alertId);
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

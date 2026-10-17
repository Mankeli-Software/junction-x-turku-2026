import 'dart:math' as math;

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

  /// The latest question and its answer: a new answer is read from here down, so this is what
  /// scrolls to the top (under the bar), never the bottom of a half-built answer.
  final _lastTurn = GlobalKey();

  /// The state on screen when a new one arrives (the listener only gets the new one).
  late ChatState _shown = context.read<ChatCubit>().state;

  /// The pinned top bar; on narrow screens the conversation scrolls under it.
  final _bar = GlobalKey();
  late final CatalogActions _actions = _InChatActions(
    context.read<CatalogActions>(),
    context.read<ChatCubit>(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showLastTurn());
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

  /// Space kept between the top of the view and the latest question.
  static const _turnTopGap = 16.0;

  /// The latest turn's content, without the space that makes the turn a screen tall.
  final _lastTurnContent = GlobalKey();

  /// A laid-out height; never call it while building.
  double _height(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box.size.height : 0;
  }

  /// How much of the conversation the pinned bar covers: all of it on narrow screens, where
  /// the conversation scrolls under the bar, none when wide. Read after layout.
  double get _barOver => _wide ? 0 : _height(_bar);
  bool _wide = false;

  /// [_barOver] as of the last frame, for building.
  double _barHeight = 0;

  void _measureBar() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final h = _barOver;
    if (mounted && h != _barHeight) setState(() => _barHeight = h);
  });

  /// Where the latest question sits just under the bar: the turn is the scroll view's center,
  /// so that is a fixed offset, whatever loads above it later. Read after layout.
  double get _turnTop => -(_barOver + _turnTopGap);

  /// A new question becomes the latest turn: keep the view where it was for one frame, then
  /// bring the question to the top, so its answer streams in below it, where the reader is.
  /// Opening a conversation shows its latest question at once.
  void _onTurn(ChatState before, ChatState after) {
    final sameChat = before.currentId == after.currentId && before.entries.isNotEmpty;
    // In the old layout the new question starts right under the old latest turn.
    final shift = _height(_lastTurnContent) + (context.isCompact ? 18 : 28);
    final from = _scroll.hasClients ? _scroll.offset : 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!sameChat) return _showLastTurn();
      if (!mounted || !_scroll.hasClients || after.entries.isEmpty) return;
      final p = _scroll.position;
      _scroll.jumpTo((from - shift).clamp(p.minScrollExtent, p.maxScrollExtent));
      _scroll.animateTo(
        _turnTop.clamp(p.minScrollExtent, p.maxScrollExtent),
        duration: AmrMotion.slow,
        curve: AmrMotion.curve,
      );
    });
  }

  /// The latest question at the top, at once (a conversation opened or the page loaded).
  void _showLastTurn() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    _scroll.jumpTo(_turnTop.clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    _measureBar();
    final compact = context.isCompact;
    final wide = _wide = context.screenWidth >= 1200;
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
            // Only a new question moves the view; parts streaming in never do.
            listenWhen: (a, b) {
              _shown = a;
              return a.currentId != b.currentId || a.entries.length < b.entries.length;
            },
            listener: (_, b) => _onTurn(_shown, b),
            builder: (context, state) {
              final empty = state.entries.isEmpty;
              final lastQuestion = state.entries.lastIndexWhere((e) => e is UserEntry);
              final gap = compact ? 18.0 : 28.0;
              final bottomSpace = compact ? 200.0 : 220.0; // room above the composer
              Widget conversation(Widget topBar) => Stack(
                children: [
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, viewport) {
                        Widget column(List<Widget> children, {double top = 0, double bottom = 0}) =>
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 1040),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(side, top, side, bottom),
                                  child: ColumnGap(
                                    children,
                                    gap: gap,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                  ),
                                ),
                              ),
                            );
                        final split = math.max(0, lastQuestion);
                        // The latest turn is the scroll view's center: offset 0 is its question,
                        // and what comes before grows upward, so earlier answers that are still
                        // loading never push it down. It is at least a screen tall, so its
                        // question can sit at the top while the answer builds below.
                        return CustomScrollView(
                          controller: _scroll,
                          center: empty ? null : _lastTurn,
                          slivers: [
                            SliverToBoxAdapter(
                              child: SafeArea(
                                bottom: false,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    topBar,
                                    column(
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
                                          for (final e in state.entries.take(split))
                                            _entry(e, state.currentId),
                                      ],
                                      top: compact ? 8 : 24,
                                      bottom: empty ? 0 : gap,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (!empty)
                              SliverToBoxAdapter(
                                key: _lastTurn,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: math.max(
                                      0,
                                      viewport.maxHeight - _barHeight - _turnTopGap - bottomSpace,
                                    ),
                                  ),
                                  child: KeyedSubtree(
                                    key: _lastTurnContent,
                                    child: column([
                                      for (final e in state.entries.skip(split))
                                        _entry(e, state.currentId),
                                    ]),
                                  ),
                                ),
                              ),
                            SliverToBoxAdapter(child: SizedBox(height: bottomSpace)),
                          ],
                        );
                      },
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
                                      onRetry: cubit.retry,
                                    )
                                  : Composer(
                                      key: ValueKey(state.currentId),
                                      // Only before the first question: once the chat has
                                      // started, the follow-ups sit under each answer.
                                      suggestions: empty ? roleQuestions(role) : const [],
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
                barKey: _bar,
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

Widget _entry(ChatEntry e, String conversation) => switch (e) {
  UserEntry() => UserBubble(e.text, short: e.short),
  AnswerEntry() => ChatAnswer(key: ValueKey('$conversation-${e.id}'), entry: e),
};

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

  @override
  void openResearch([Json params = const {}]) => _app.openResearch(params);

  @override
  void openInfectionControl() => _app.openInfectionControl();

  @override
  void openLab() => _app.openLab();
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

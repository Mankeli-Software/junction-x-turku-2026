import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../catalog/catalog.dart';
import '../../core/models/dashboard.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import '../chat/ask_context.dart';
import '../chat/widgets/chat_blocks.dart';
import 'dashboard_cubit.dart';
import 'widget_agent.dart';
import 'widget_settings.dart';

/// One step of the "Add a widget" conversation.
sealed class BuilderTurn extends Equatable {
  const BuilderTurn();
}

class AskedTurn extends BuilderTurn {
  const AskedTurn(this.text, {this.short = false});

  final String text;

  /// A tapped choice rather than a typed request: drawn smaller.
  final bool short;

  @override
  List<Object?> get props => [text, short];
}

class ProposalTurn extends BuilderTurn {
  const ProposalTurn(this.placement, {this.why, this.passed = false});

  final WidgetPlacement placement;
  final String? why;

  /// The user asked for something else: the buttons go away.
  final bool passed;

  ProposalTurn pass() => ProposalTurn(placement, why: why, passed: true);

  @override
  List<Object?> get props => [placement, why, passed];
}

class QuestionTurn extends BuilderTurn {
  const QuestionTurn(this.question, this.options, {this.chosen});

  final String question;
  final List<String> options;
  final String? chosen;

  @override
  List<Object?> get props => [question, options, chosen];
}

class NoteTurn extends BuilderTurn {
  const NoteTurn(this.text);

  final String text;

  @override
  List<Object?> get props => [text];
}

class WidgetBuilderState extends Equatable {
  const WidgetBuilderState({
    this.turns = const [],
    this.busy = false,
    this.status,
    this.unavailable = false,
  });

  final List<BuilderTurn> turns;
  final bool busy;
  final String? status;

  /// No AI (no key, no backend): the dialog offers the catalog instead.
  final bool unavailable;

  WidgetBuilderState copyWith({
    List<BuilderTurn>? turns,
    bool? busy,
    String? Function()? status,
    bool? unavailable,
  }) => WidgetBuilderState(
    turns: turns ?? this.turns,
    busy: busy ?? this.busy,
    status: status != null ? status() : this.status,
    unavailable: unavailable ?? this.unavailable,
  );

  @override
  List<Object?> get props => [turns, busy, status, unavailable];
}

/// The "Add a widget" conversation: the user says what to keep an eye on, the widget agent
/// suggests one widget at a time (or asks one question), and the user adds it, asks for
/// something else or changes it in words. Nothing is pinned without the user's tap.
class WidgetBuilderCubit extends Cubit<WidgetBuilderState> {
  WidgetBuilderCubit(this._agent, this._session, this._dashboard)
    : super(const WidgetBuilderState());

  final WidgetAgent _agent;
  final SessionCubit _session;
  final DashboardCubit _dashboard;
  StreamSubscription<WidgetAgentEvent>? _sub;

  /// How many earlier turns go with a message (the backend takes at most 24).
  static const maxHistory = 12;

  Future<void> send(String text, {bool short = false}) {
    final user = _session.state.user;
    final message = text.trim();
    if (user == null || message.isEmpty || state.busy) return Future.value();
    final ctx = WidgetAgentContext(
      user: user,
      asOf: _session.state.asOf,
      layout: _dashboard.state.layout,
      history: _history(),
    );
    emit(
      state.copyWith(
        turns: [
          for (final t in state.turns) t is ProposalTurn ? t.pass() : t,
          AskedTurn(message, short: short),
        ],
        busy: true,
        status: () => null,
      ),
    );
    final done = Completer<void>();
    _sub = _agent
        .suggest(message, ctx)
        .listen(
          _apply,
          onError: (Object _) => _apply(const WidgetAgentUnavailable()),
          onDone: () {
            if (!isClosed) emit(state.copyWith(busy: false, status: () => null));
            done.complete();
          },
        );
    return done.future;
  }

  /// A tapped answer to the agent's question.
  Future<void> choose(QuestionTurn turn, String option) {
    emit(
      state.copyWith(
        turns: [
          for (final t in state.turns)
            t == turn ? QuestionTurn(turn.question, turn.options, chosen: option) : t,
        ],
      ),
    );
    return send(option, short: true);
  }

  Future<void> somethingElse() => send('Show me something else', short: true);

  /// Pins [p]; a failed save is said in the conversation and the dialog stays open.
  Future<bool> add(WidgetPlacement p) async {
    final ok = await _dashboard.pin(p);
    if (!ok && !isClosed) {
      emit(
        state.copyWith(
          turns: [...state.turns, const NoteTurn('Could not save it to your home. Try again.')],
        ),
      );
    }
    return ok;
  }

  void stop() {
    _sub?.cancel();
    emit(state.copyWith(busy: false, status: () => null));
  }

  void _apply(WidgetAgentEvent e) {
    if (isClosed) return;
    switch (e) {
      case WidgetAgentStatus(:final text):
        emit(state.copyWith(status: () => text));
      case WidgetProposal(:final placement, :final why):
        emit(
          state.copyWith(
            turns: [
              ...state.turns,
              ProposalTurn(placement, why: why),
            ],
          ),
        );
      case WidgetAgentQuestion(:final question, :final options):
        emit(state.copyWith(turns: [...state.turns, QuestionTurn(question, options)]));
      case WidgetAgentError(:final message):
        emit(state.copyWith(turns: [...state.turns, NoteTurn(message)]));
      case WidgetAgentUnavailable():
        _sub?.cancel();
        emit(state.copyWith(busy: false, status: () => null, unavailable: true));
    }
  }

  /// The conversation for the agent, oldest first: what was asked, what was suggested or asked
  /// back.
  List<(String, String)> _history() {
    final turns = [
      for (final t in state.turns)
        ?switch (t) {
          AskedTurn(:final text) => ('user', text),
          ProposalTurn(:final placement, :final why) => (
            'assistant',
            'Proposed ${placement.widget} ${jsonEncode(placement.params)}'
                '${why == null ? '' : ': $why'}',
          ),
          QuestionTurn(:final question, :final options) => (
            'assistant',
            'Asked: $question (${options.join(' / ')})',
          ),
          NoteTurn() => null,
        },
    ];
    return [
      for (final (role, text) in turns.skip(math.max(0, turns.length - maxHistory)))
        (role, text.length > 1500 ? text.substring(0, 1500) : text),
    ];
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

/// Opens "Add a widget"; with [message] the agent starts on it at once. Returns the placement
/// that was added, or null.
Future<WidgetPlacement?> showWidgetBuilder(BuildContext context, {String? message}) {
  final agent = context.read<WidgetAgent>();
  final session = context.read<SessionCubit>();
  final dashboard = context.read<DashboardCubit>();
  return showAmrDialog<WidgetPlacement>(
    context,
    maxWidth: 880,
    child: BlocProvider(
      create: (_) {
        final cubit = WidgetBuilderCubit(agent, session, dashboard);
        if (message != null && message.trim().isNotEmpty) unawaited(cubit.send(message));
        return cubit;
      },
      child: const _BuilderPanel(),
    ),
  );
}

class _BuilderPanel extends StatefulWidget {
  const _BuilderPanel();

  @override
  State<_BuilderPanel> createState() => _BuilderPanelState();
}

class _BuilderPanelState extends State<_BuilderPanel> {
  final _scroll = ScrollController();
  final _text = TextEditingController();

  @override
  void dispose() {
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  void _send(String text) {
    _text.clear();
    context.read<WidgetBuilderCubit>().send(text);
  }

  Future<void> _add(WidgetPlacement p) async {
    final navigator = Navigator.of(context);
    if (await context.read<WidgetBuilderCubit>().add(p)) navigator.pop(p);
  }

  Future<void> _adjust(WidgetPlacement p) async {
    final navigator = Navigator.of(context);
    final cubit = context.read<WidgetBuilderCubit>();
    final next = await showWidgetSettings(context, p, adding: true);
    if (next != null && await cubit.add(next)) navigator.pop(next);
  }

  Future<void> _pick(String widget) async {
    final user = context.read<SessionCubit>().state.user;
    await _adjust(WidgetPlacement(widget: widget, params: defaultParams(widget, user)));
  }

  /// Keeps the newest turn in view as it arrives.
  void _follow() => WidgetsBinding.instance.addPostFrameCallback((_) {
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
    final side = compact ? 18.0 : 32.0;
    final ward = context.select((SessionCubit c) => c.state.user?.ward);
    return BlocConsumer<WidgetBuilderCubit, WidgetBuilderState>(
      listenWhen: (a, b) => a.turns.length != b.turns.length || a.busy != b.busy,
      listener: (_, _) => _follow(),
      builder: (context, state) {
        final cubit = context.read<WidgetBuilderCubit>();
        final empty = state.turns.isEmpty && !state.busy;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(side, compact ? 18 : 28, compact ? 12 : 20, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AiMark(size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ColumnGap([
                        Text('Add a widget', style: AmrText.label(12)),
                        Text(
                          'What do you want to keep an eye on?',
                          style: AmrText.title(compact ? 22 : 26, em: 0),
                        ),
                      ], gap: 4),
                    ),
                    AmrIconButton(
                      icon: LucideIcons.x,
                      size: 40,
                      variant: AmrIconButtonVariant.soft,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(side, 4, side, 12),
                  child: ColumnGap(
                    [
                      if (empty && !state.unavailable)
                        Text(
                          'Say it in your own words. The AI suggests one widget at a time with '
                          'live data, and you decide whether it goes on your home page.',
                          style: AmrText.body(15, height: 1.5),
                        ),
                      for (final t in state.turns)
                        switch (t) {
                          AskedTurn(:final text, :final short) => UserBubble(text, short: short),
                          final ProposalTurn p => _ProposalCard(
                            turn: p,
                            onAdd: () => _add(p.placement),
                            onAdjust: () => _adjust(p.placement),
                            onElse: state.busy ? null : cubit.somethingElse,
                          ),
                          final QuestionTurn q => ClarifyCard(
                            question: q.question,
                            options: q.options,
                            chosen: q.chosen,
                            onChoose: state.busy ? null : (o) => cubit.choose(q, o),
                          ),
                          NoteTurn(:final text) => NoteCard(title: text),
                        },
                      if (state.busy)
                        BuildingCard(
                          status: state.status ?? 'Choosing a widget',
                          onStop: cubit.stop,
                        ),
                      if (state.unavailable)
                        NoteCard(
                          title: 'AI suggestions are off right now',
                          body: 'Pick a widget from the catalog below and set it up yourself.',
                        ),
                      if (empty || state.unavailable) _Catalog(onPick: _pick),
                    ],
                    gap: AmrSpace.x16,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                  ),
                ),
              ),
              if (!state.unavailable)
                Container(
                  padding: EdgeInsets.fromLTRB(side, 12, side, compact ? 16 : 24),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AmrColors.line)),
                  ),
                  child: ColumnGap(
                    [
                      if (empty)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in AskContext.dashboard(ward: ward).suggestions)
                              AmrButton(
                                label: s,
                                size: AmrButtonSize.sm,
                                variant: AmrButtonVariant.soft,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                onPressed: () => _send(s),
                              ),
                          ],
                        ),
                      AskField(
                        hint: state.turns.any((t) => t is ProposalTurn)
                            ? 'Change it, e.g. "the whole hospital" or "last 12 months"'
                            : 'e.g. MRSA on my ward this year',
                        style: AskFieldStyle.outlined,
                        accent: true,
                        enabled: !state.busy,
                        controller: _text,
                        onSubmit: _send,
                      ),
                    ],
                    gap: AmrSpace.x12,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The agent's suggestion: what it is, why, a live preview, and the user's decision.
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.turn,
    required this.onAdd,
    required this.onAdjust,
    required this.onElse,
  });

  final ProposalTurn turn;
  final VoidCallback onAdd;
  final VoidCallback onAdjust;
  final VoidCallback? onElse;

  @override
  Widget build(BuildContext context) {
    final p = turn.placement;
    final entry = context.read<WidgetCatalog>()[p.widget];
    final compact = context.isCompact;
    final summary = placementSummary(p);
    return Opacity(
      opacity: turn.passed ? 0.55 : 1,
      child: AmrCard(
        padding: EdgeInsets.all(compact ? 18 : 24),
        child: ColumnGap(
          [
            Text('Suggested widget', style: AmrText.label(12)),
            ColumnGap([
              Text(entry?.title ?? p.widget, style: AmrText.title(compact ? 21 : 24, em: 0)),
              if (summary.isNotEmpty)
                Text(summary, style: AmrText.body(14, weight: FontWeight.w500)),
            ], gap: 2),
            if (turn.why case final why?) Text(why, style: AmrText.body(15, height: 1.5)),
            AmrCard(
              tone: AmrCardTone.subtle,
              padding: const EdgeInsets.all(AmrSpace.x20),
              child: CatalogWidget(p, slot: WidgetSlot.card),
            ),
            if (!turn.passed) ...[
              Text(
                'Add this to your home page?',
                style: AmrText.sora(compact ? 19 : 21, em: -0.01),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AmrButton(
                    label: 'Add to my home',
                    variant: AmrButtonVariant.primary,
                    leading: const Icon(LucideIcons.pin, size: 16),
                    onPressed: onAdd,
                  ),
                  AmrButton(
                    label: 'Adjust settings',
                    variant: AmrButtonVariant.outline,
                    leading: const Icon(LucideIcons.slidersHorizontal, size: 16),
                    onPressed: onAdjust,
                  ),
                  AmrButton(
                    label: 'Something else',
                    variant: AmrButtonVariant.outline,
                    onPressed: onElse,
                  ),
                ],
              ),
            ],
          ],
          gap: AmrSpace.x12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
        ),
      ),
    );
  }
}

/// Every widget that can go on a home page; picking one opens its settings.
class _Catalog extends StatelessWidget {
  const _Catalog({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<WidgetCatalog>();
    return ColumnGap(
      [
        Text('Or pick from the catalog', style: AmrText.body(14, weight: FontWeight.w500)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in pinnable)
              if (catalog[name] case final e?)
                Tooltip(
                  message: e.description,
                  child: AmrButton(
                    label: '+ ${e.title ?? e.name}',
                    size: AmrButtonSize.sm,
                    variant: AmrButtonVariant.outline,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    onPressed: () => onPick(e.name),
                  ),
                ),
          ],
        ),
      ],
      gap: AmrSpace.x10,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../catalog/actions.dart';
import '../../../catalog/catalog.dart';
import '../../../catalog/widgets/context_chips.dart';
import '../../../catalog/widgets/in_short.dart';
import '../../../core/format.dart';
import '../../../core/models/common.dart';
import '../../../core/models/dashboard.dart';
import '../../../ds/ds.dart';
import '../../../session/session_cubit.dart';
import '../../dashboard/dashboard_cubit.dart';
import '../chat_cubit.dart';
import '../chat_models.dart';
import 'chat_blocks.dart';

/// Widgets that sit two to a row on a wide screen (the epidemic curve beside the volume).
const _halfWidth = {'EpiCurve', 'SamplingVolume'};

/// One assistant turn: header, the building state, its parts as they stream in, and actions.
class ChatAnswer extends StatefulWidget {
  const ChatAnswer({super.key, required this.entry});

  final AnswerEntry entry;

  @override
  State<ChatAnswer> createState() => _ChatAnswerState();
}

class _ChatAnswerState extends State<ChatAnswer> {
  WidgetPlacement? _pinned;

  Future<void> _pin(WidgetPlacement p) async {
    final ok = await context.read<DashboardCubit>().pin(p);
    if (mounted && ok) setState(() => _pinned = p);
  }

  void _undoPin() {
    final p = _pinned;
    if (p == null) return;
    context.read<DashboardCubit>().unpin(p);
    setState(() => _pinned = null);
  }

  void _run(ChatAction a) {
    final actions = context.read<CatalogActions>();
    switch (a.kind) {
      case ChatActionKind.ask:
        context.read<ChatCubit>().send(a.label);
      case ChatActionKind.openAnswer:
        actions.openAnswer(a.payload! as PatientProfile);
      case ChatActionKind.pin:
        _pin(a.payload! as WidgetPlacement);
      case ChatActionKind.newPatient:
        actions.newPatient();
      case ChatActionKind.navigate:
        context.go(a.payload! as String);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final cubit = context.read<ChatCubit>();
    final asOf = context.select((SessionCubit c) => c.state.asOf);
    final compact = context.isCompact;
    final parts = _rows(e.parts, compact);
    return PatientEditScope(
      onChanged: (p) => cubit.changePatient(e.id, p),
      child: ColumnGap(
        [
          AnswerHeader(builtFrom: e.builtFrom, note: e.note, dataTo: day(asOf)),
          if (e.streaming && e.parts.isEmpty) BuildingCard(status: e.status, onStop: cubit.stop),
          for (final row in parts) _Appear(child: row),
          if (e.streaming && e.parts.isNotEmpty)
            Text(e.status ?? 'Building…', style: AmrText.body(13, weight: FontWeight.w500)),
          if (!e.streaming && e.actions.isNotEmpty)
            _Appear(
              child: _pinned != null
                  ? ActionPill(
                      message: 'Pinned to your home',
                      actionLabel: 'Undo',
                      onAction: _undoPin,
                    )
                  : AnswerActionsBar(
                      actions: [
                        for (final a in e.actions)
                          (
                            a.label,
                            a.primary,
                            a.kind == ChatActionKind.pin ? LucideIcons.pin : null,
                            () => _run(a),
                          ),
                      ],
                      onFeedback: (_) {},
                    ),
            ),
        ],
        gap: compact ? 12 : 16,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }

  List<Widget> _rows(List<AnswerPart> parts, bool compact) {
    final rows = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      final next = i + 1 < parts.length ? parts[i + 1] : null;
      if (!compact && _isHalf(p) && next != null && _isHalf(next)) {
        rows.add(FlexSplit(basis: const [300, 300], children: [_part(p), _part(next)]));
        i++;
      } else {
        rows.add(_part(p));
      }
    }
    return rows;
  }

  bool _isHalf(AnswerPart p) => p is WidgetPart && _halfWidth.contains(p.placement.widget);

  Widget _part(AnswerPart p) => switch (p) {
    WidgetPart(:final placement) => CatalogWidget(placement, slot: WidgetSlot.chat),
    InShortPart(:final text) => InShortCard(text: text),
    ClarifyPart() => ClarifyCard(
      question: p.question,
      options: p.options,
      chosen: p.chosen,
      onChoose: (o) => context.read<ChatCubit>().choose(widget.entry.id, p, o),
    ),
  };
}

/// Parts fade and rise in as they stream.
class _Appear extends StatelessWidget {
  const _Appear({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: AmrMotion.slow,
    curve: AmrMotion.curve,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
    ),
    child: child,
  );
}

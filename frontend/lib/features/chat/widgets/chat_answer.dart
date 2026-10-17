import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:genui/genui.dart' as genui;
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../catalog/actions.dart';
import '../../../catalog/widgets/context_chips.dart';
import '../../../core/format.dart';
import '../../../core/models/common.dart';
import '../../../core/models/dashboard.dart';
import '../../../ds/ds.dart';
import '../../../session/session_cubit.dart';
import '../../dashboard/dashboard_cubit.dart';
import '../answer_catalog.dart';
import '../chat_cubit.dart';
import '../chat_models.dart';
import 'chat_blocks.dart';

/// One assistant turn: header, the building state, the answer's A2UI surface as its parts
/// stream in (rendered by genui from the chat catalog), and actions.
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
    final hasParts = e.parts.isNotEmpty;
    final surfaceId = e.surfaceId;
    return PatientEditScope(
      onChanged: (p) => cubit.changePatient(e.id, p),
      child: ColumnGap(
        [
          AnswerHeader(builtFrom: e.builtFrom, note: e.note, dataTo: day(asOf)),
          if (e.streaming && !hasParts) BuildingCard(status: e.status, onStop: cubit.stop),
          if (surfaceId != null && hasParts)
            genui.Surface(
              key: ValueKey(surfaceId),
              surfaceContext: cubit.surfaces.contextFor(surfaceId),
              actionDelegate: _ChooseDelegate((component, option) {
                cubit.choose(e.id, component, option);
              }),
            ),
          if (e.error case final error?) NoteCard(title: error),
          if (e.streaming && hasParts)
            Text(e.status ?? 'Building…', style: AmrText.body(13, weight: FontWeight.w500)),
          if (!e.streaming && e.actions.isNotEmpty)
            AnswerAppear(
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
}

/// A tapped answer on a clarifying question goes to the chat, not back to the AI as an event.
class _ChooseDelegate implements genui.ActionDelegate {
  const _ChooseDelegate(this.onChoose);

  final void Function(String componentId, String option) onChoose;

  @override
  bool handleEvent(
    BuildContext context,
    genui.UiEvent event,
    genui.SurfaceContext genUiContext,
    Widget Function(genui.SurfaceDefinition, genui.Catalog, String, genui.DataContext) buildWidget,
  ) {
    if (!event.isUserAction) return false;
    final action = genui.UserActionEvent.fromMap(event.toMap());
    if (action.name != AnswerComponents.choose) return false;
    final option = action.context['option'];
    if (option is String) onChoose(action.sourceComponentId, option);
    return true;
  }
}

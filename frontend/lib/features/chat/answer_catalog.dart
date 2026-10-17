import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';
import '../../ds/ds.dart';
import 'widgets/chat_blocks.dart';
import '../../catalog/catalog.dart';
import '../../catalog/widgets/in_short.dart';

/// The A2UI catalog the chat agent builds answers from. Same id as backend/app/agent/a2ui.py.
const amrCatalogId = 'https://amright.app/a2ui/v0_9/catalog.json';

/// The A2UI component names besides the widget catalog: the answer's root and its two pieces of
/// AI text.
abstract final class AnswerComponents {
  static const root = 'Answer';
  static const rootId = 'root';
  static const inShort = 'InShort';
  static const clarify = 'Clarify';

  /// The user action a [clarify] component dispatches; `context.option` is the tapped answer.
  static const choose = 'choose';
}

/// Widgets that sit two to a row on a wide screen (the epidemic curve beside the volume).
const _halfWidth = {'EpiCurve', 'SamplingVolume'};

/// The genui [Catalog] for chat answers: every [WidgetCatalog] entry as a [CatalogItem] whose
/// A2UI properties are its query params, plus the answer layout, "In short" and the clarifying
/// question.
///
/// Schemas stay open (`additionalProperties`): the backend validates every param against
/// backend/app/widgets/catalog.py before it sends a component, and a widget shows a quiet
/// placeholder for anything it cannot use.
Catalog buildGenUiCatalog(WidgetCatalog widgets) => Catalog([
  for (final e in widgets.entries)
    CatalogItem(
      name: e.name,
      dataSchema: S.object(description: e.description),
      widgetBuilder: (ctx) => widgets.build(
        ctx.buildContext,
        WidgetPlacement(widget: ctx.type, params: _props(ctx.data)),
        slot: WidgetSlot.chat,
      ),
    ),
  CatalogItem(
    name: AnswerComponents.root,
    dataSchema: S.object(
      description: 'One chat answer: its parts in order.',
      properties: {'children': S.list(items: S.string())},
      required: ['children'],
    ),
    widgetBuilder: (ctx) {
      final data = _props(ctx.data);
      final ids = (data['children'] as List? ?? const []).cast<String>();
      return _AnswerLayout(
        ids: ids,
        types: [for (final id in ids) ctx.getComponent(id)?.type],
        part: ctx.buildChild,
      );
    },
  ),
  CatalogItem(
    name: AnswerComponents.inShort,
    dataSchema: S.object(
      description: 'The one line of AI text; without text the placeholder shows.',
      properties: {'text': S.string()},
    ),
    widgetBuilder: (ctx) => InShortCard(text: _props(ctx.data)['text'] as String?),
  ),
  CatalogItem(
    name: AnswerComponents.clarify,
    dataSchema: S.object(
      description: 'A question back with 2 to 4 tappable answers, the likeliest first.',
      properties: {
        'question': S.string(),
        'options': S.list(items: S.string()),
        'chosen': S.string(),
      },
      required: ['question', 'options'],
    ),
    widgetBuilder: (ctx) {
      final data = _props(ctx.data);
      return ClarifyCard(
        question: data['question'] as String? ?? '',
        options: (data['options'] as List? ?? const []).cast<String>(),
        chosen: data['chosen'] as String?,
        onChoose: (option) => ctx.dispatchEvent(
          UserActionEvent(
            name: AnswerComponents.choose,
            sourceComponentId: ctx.id,
            context: {'option': option},
          ),
        ),
      );
    },
  ),
], catalogId: amrCatalogId);

Json _props(Object data) => data is Map ? data.cast<String, Object?>() : const {};

/// The answer's parts one under the other, two half-width widgets side by side on a wide
/// screen; each part fades and rises in as it arrives.
class _AnswerLayout extends StatelessWidget {
  const _AnswerLayout({required this.ids, required this.types, required this.part});

  final List<String> ids;
  final List<String?> types;
  final Widget Function(String id) part;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final rows = <Widget>[];
    for (var i = 0; i < ids.length; i++) {
      final pair =
          !compact &&
          i + 1 < ids.length &&
          _halfWidth.contains(types[i]) &&
          _halfWidth.contains(types[i + 1]);
      rows.add(
        AnswerAppear(
          key: ValueKey(ids[i]),
          child: pair
              ? FlexSplit(basis: const [300, 300], children: [part(ids[i]), part(ids[i + 1])])
              : part(ids[i]),
        ),
      );
      if (pair) i++;
    }
    return ColumnGap(rows, gap: compact ? 12 : 16, crossAxisAlignment: CrossAxisAlignment.stretch);
  }
}

/// A part fades and rises in as it arrives.
class AnswerAppear extends StatelessWidget {
  const AnswerAppear({super.key, required this.child});

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

import 'dart:math' as math;

import '../../../core/models/common.dart';
import '../answer_catalog.dart';
import '../chat_models.dart';
import 'chat_agent.dart';

/// Builds one answer's A2UI messages part by part, the same way backend/app/agent/a2ui.py does:
/// createSurface before the first part, then one updateComponents per part that also sends the
/// root `Answer` with the new list of children.
class AnswerSurface {
  AnswerSurface([String? id]) : id = id ?? 'answer-${_random()}';

  final String id;
  final _children = <String>[];
  bool _created = false;

  static String _random() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 30).toRadixString(36)}';

  /// The events that put [part] on the screen.
  List<AgentSurface> add(AnswerPart part) {
    final cid = 'p${_children.length + 1}';
    _children.add(cid);
    final (type, props) = part.component;
    final first = !_created;
    _created = true;
    return [
      if (first) AgentSurface(createMessage(id)),
      AgentSurface(
        updateMessage(id, [
          {...props, 'id': cid, 'component': type},
          rootComponent(_children),
        ]),
      ),
    ];
  }

  static Json createMessage(String surfaceId) => {
    'version': 'v0.9',
    'createSurface': {'surfaceId': surfaceId, 'catalogId': amrCatalogId},
  };

  static Json updateMessage(String surfaceId, List<Json> components) => {
    'version': 'v0.9',
    'updateComponents': {'surfaceId': surfaceId, 'components': components},
  };

  static Json rootComponent(List<String> children) => {
    'id': AnswerComponents.rootId,
    'component': AnswerComponents.root,
    'children': [...children],
  };
}

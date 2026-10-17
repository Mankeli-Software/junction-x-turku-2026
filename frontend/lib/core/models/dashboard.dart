import 'package:equatable/equatable.dart';

import 'common.dart';
import 'vocab.dart';

/// One catalog widget on a dashboard, chat answer or page: a name and its params.
/// This is the unit the AI places; it never carries numbers.
class WidgetPlacement extends Equatable {
  const WidgetPlacement({required this.widget, this.params = const {}});

  factory WidgetPlacement.fromJson(Json j) =>
      WidgetPlacement(widget: j['widget']! as String, params: (j['params'] as Json?) ?? const {});

  final String widget;
  final Json params;

  Json toJson() => {'widget': widget, 'params': params};

  @override
  List<Object?> get props => [widget, params];
}

class Dashboard extends Equatable {
  const Dashboard({required this.userId, required this.role, required this.layout});

  factory Dashboard.fromJson(Json j) => Dashboard(
    userId: j['user_id']! as String,
    role: byCode(Role.values, j['role']! as String),
    layout: jsonList(j['layout']).map(WidgetPlacement.fromJson).toList(),
  );

  final String userId;
  final Role role;
  final List<WidgetPlacement> layout;

  Dashboard copyWith({List<WidgetPlacement>? layout}) =>
      Dashboard(userId: userId, role: role, layout: layout ?? this.layout);

  Json toJson() => {
    'user_id': userId,
    'role': role.code,
    'layout': [for (final w in layout) w.toJson()],
  };

  @override
  List<Object?> get props => [userId, role, layout];
}

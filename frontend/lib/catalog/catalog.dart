import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/models/common.dart';
import '../core/models/dashboard.dart';
import '../ds/ds.dart';

/// Where a catalog widget is placed. Widgets change density per slot, never their numbers.
enum WidgetSlot {
  /// Full width on a page (the answer page, Explore).
  page,

  /// A pinned card on the home dashboard: the short version.
  card,

  /// Inside a chat answer.
  chat,
}

typedef CatalogBuilder = Widget Function(BuildContext context, Json params, WidgetSlot slot);

/// One widget the AI (or a saved dashboard) can place by [name] with JSON [params].
///
/// Params are query settings only (ward, specimen, organism, drug, window, as_of …); the
/// widget fetches its own numbers. The params' JSON Schema is served by the backend at
/// `GET /v1/widgets` (backend/app/widgets/catalog.py), the single source of truth that a GenUI
/// `CatalogItem` will be built from: `CatalogItem(name: e.name, dataSchema: <schema from
/// /v1/widgets>, widgetBuilder: (ctx) => e.builder(ctx.buildContext, ctx.data, WidgetSlot.chat))`.
class CatalogEntry {
  const CatalogEntry({
    required this.name,
    required this.description,
    required this.builder,
    this.title,
  });

  final String name;
  final String description;
  final CatalogBuilder builder;

  /// Short human name for the "Add widget" picker.
  final String? title;
}

class WidgetCatalog {
  WidgetCatalog(List<CatalogEntry> entries) : _entries = {for (final e in entries) e.name: e};

  final Map<String, CatalogEntry> _entries;

  Iterable<CatalogEntry> get entries => _entries.values;
  CatalogEntry? operator [](String name) => _entries[name];

  /// Builds a placement; an unknown name or bad params show a quiet placeholder, never a crash.
  Widget build(BuildContext context, WidgetPlacement p, {WidgetSlot slot = WidgetSlot.page}) {
    final entry = _entries[p.widget];
    if (entry == null) return _Unavailable('“${p.widget}” is not in the catalog yet.');
    try {
      return entry.builder(context, p.params, slot);
    } on Object catch (e) {
      return _Unavailable('Could not show ${entry.title ?? entry.name}: $e');
    }
  }
}

/// Builds a [WidgetPlacement] from the catalog in scope.
class CatalogWidget extends StatelessWidget {
  const CatalogWidget(this.placement, {super.key, this.slot = WidgetSlot.page});

  final WidgetPlacement placement;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) =>
      context.read<WidgetCatalog>().build(context, placement, slot: slot);
}

class _Unavailable extends StatelessWidget {
  const _Unavailable(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => NoteCard(title: message);
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../catalog/actions.dart';
import '../../catalog/catalog.dart';
import '../../core/models/dashboard.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import 'dashboard_cubit.dart';
import 'widget_builder.dart';
import 'widget_settings.dart';

/// "Pinned for you": the user's saved catalog widgets, each with its settings and a link to the
/// page it comes from, plus the "Add a widget" card. A new user gets the default for their role
/// and ward (backend `default_layout`).
class PinnedSection extends StatefulWidget {
  const PinnedSection({super.key});

  @override
  State<PinnedSection> createState() => _PinnedSectionState();
}

class _PinnedSectionState extends State<PinnedSection> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardState>(
      builder: (context, state) {
        final cubit = context.read<DashboardCubit>();
        final layout = state.layout.where((p) => p.widget != 'ContextChips').toList();
        final cards = <Widget>[
          if (state.loading && state.dashboard == null)
            for (var i = 0; i < 2; i++)
              const AmrCard(padding: EdgeInsets.all(24), child: SkeletonBlock(lines: 3)),
          for (final (i, p) in layout.indexed)
            _PinnedCard(
              key: ValueKey(p),
              placement: p,
              editing: _editing,
              isNew: state.added == p,
              onEarlier: i == 0 ? null : () => _move(layout, i, i - 1),
              onLater: i == layout.length - 1 ? null : () => _move(layout, i, i + 1),
            ),
          if (!_editing) const _AddWidgetCard(),
        ];
        return ColumnGap(
          [
            SectionHeader(
              title: 'Pinned for you',
              subtitle: _editing
                  ? 'Move, change or remove your widgets.'
                  : 'Always showing the latest data.',
              trailing: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_editing)
                    AmrButton(
                      label: 'Reset to default',
                      leading: const Icon(LucideIcons.rotateCcw, size: 16),
                      onPressed: state.loading ? null : () => _reset(context),
                    ),
                  AmrButton(
                    label: _editing ? 'Done' : 'Edit layout',
                    variant: _editing ? AmrButtonVariant.primary : AmrButtonVariant.outline,
                    onPressed: () => setState(() => _editing = !_editing),
                  ),
                  if (!_editing)
                    AmrButton(
                      label: '+ Add widget',
                      variant: AmrButtonVariant.primary,
                      onPressed: () => openWidgetBuilder(context),
                    ),
                ],
              ),
            ),
            if (state.error != null && state.dashboard == null)
              InlineError(message: 'Could not load your pinned views.', onRetry: cubit.load),
            if (state.error != null && state.dashboard != null)
              InlineError(message: 'Could not save that change, try again.'),
            AutoGrid(minItemWidth: 380, children: cards),
          ],
          gap: AmrSpace.x20,
          crossAxisAlignment: CrossAxisAlignment.stretch,
        );
      },
    );
  }

  /// Moves within the visible cards; the hidden patient chips keep their place.
  void _move(List<WidgetPlacement> visible, int from, int to) {
    final cubit = context.read<DashboardCubit>();
    final all = cubit.state.layout;
    cubit.move(all.indexOf(visible[from]), all.indexOf(visible[to]));
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await context.read<DashboardCubit>().reset();
    if (ok && mounted) setState(() => _editing = false);
  }
}

/// Opens "Add a widget" and says so when something was added, with an undo.
Future<void> openWidgetBuilder(BuildContext context, {String? message}) async {
  final messenger = ScaffoldMessenger.of(context);
  final dashboard = context.read<DashboardCubit>();
  final added = await showWidgetBuilder(context, message: message);
  if (added != null) _confirm(messenger, dashboard, added);
}

/// A catalog widget with its first settings, set up in the settings dialog, then pinned.
Future<void> _addFromCatalog(BuildContext context, String widget) async {
  final messenger = ScaffoldMessenger.of(context);
  final dashboard = context.read<DashboardCubit>();
  final user = context.read<SessionCubit>().state.user;
  final next = await showWidgetSettings(
    context,
    WidgetPlacement(widget: widget, params: defaultParams(widget, user)),
    adding: true,
  );
  if (next != null && await dashboard.pin(next)) _confirm(messenger, dashboard, next);
}

void _confirm(ScaffoldMessengerState messenger, DashboardCubit dashboard, WidgetPlacement p) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Added to your home'),
        // A SnackBar with an action stays until tapped unless told otherwise.
        persist: false,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: 'Undo', onPressed: () => dashboard.unpin(p)),
      ),
    );
}

class _PinnedCard extends StatelessWidget {
  const _PinnedCard({
    super.key,
    required this.placement,
    required this.editing,
    required this.isNew,
    this.onEarlier,
    this.onLater,
  });

  final WidgetPlacement placement;
  final bool editing;
  final bool isNew;
  final VoidCallback? onEarlier;
  final VoidCallback? onLater;

  Future<void> _edit(BuildContext context) async {
    final dashboard = context.read<DashboardCubit>();
    final next = await showWidgetSettings(context, placement);
    if (next != null) await dashboard.replace(placement, next);
  }

  @override
  Widget build(BuildContext context) {
    final entry = context.read<WidgetCatalog>()[placement.widget];
    final link = placementLink(placement);
    final summary = placementSummary(placement);
    final dashboard = context.read<DashboardCubit>();
    final tools = editing
        ? Wrap(
            spacing: 6,
            children: [
              AmrIconButton(
                icon: LucideIcons.arrowLeft,
                size: 36,
                variant: AmrIconButtonVariant.soft,
                tooltip: 'Move earlier',
                onPressed: onEarlier,
              ),
              AmrIconButton(
                icon: LucideIcons.arrowRight,
                size: 36,
                variant: AmrIconButtonVariant.soft,
                tooltip: 'Move later',
                onPressed: onLater,
              ),
              AmrIconButton(
                icon: LucideIcons.trash2,
                size: 36,
                variant: AmrIconButtonVariant.soft,
                tooltip: 'Remove from home',
                onPressed: () => dashboard.unpin(placement),
              ),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AmrIconButton(
                icon: LucideIcons.slidersHorizontal,
                size: 40,
                variant: AmrIconButtonVariant.soft,
                tooltip: 'Edit settings',
                onPressed: () => _edit(context),
              ),
              const SizedBox(width: 6),
              _CardMenu(
                placement: placement,
                onEdit: () => _edit(context),
                onEarlier: onEarlier,
                onLater: onLater,
              ),
            ],
          );
    return AnimatedContainer(
      duration: AmrMotion.slow,
      decoration: BoxDecoration(
        borderRadius: AmrRadius.card,
        border: Border.all(color: editing ? AmrColors.periwinkle : Colors.transparent, width: 1.5),
      ),
      child: AmrCard(
        padding: const EdgeInsets.all(AmrSpace.x24),
        // spaceBetween, not Spacer: the link sits at the bottom of a stretched card (CSS
        // margin-top: auto) and the card still measures in an unbounded first pass.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  entry?.title ?? placement.widget,
                                  style: AmrText.label(12),
                                ),
                              ),
                              if (isNew) ...[const SizedBox(width: 8), const _NewTag()],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            summary.isEmpty ? (entry?.title ?? placement.widget) : summary,
                            style: AmrText.title(22, em: 0),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    tools,
                  ],
                ),
                const SizedBox(height: 14),
                IgnorePointer(
                  ignoring: editing,
                  child: CatalogWidget(placement, slot: WidgetSlot.card),
                ),
              ],
            ),
            if (link != null && !editing)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AmrLink(link.$1, onTap: () => link.$2(context.read<CatalogActions>())),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NewTag extends StatelessWidget {
  const _NewTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: const BoxDecoration(color: AmrColors.lavenderPale, borderRadius: AmrRadius.pill),
    child: Text('Just added', style: AmrText.body(12, weight: FontWeight.w500)),
  );
}

class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.placement, required this.onEdit, this.onEarlier, this.onLater});

  final WidgetPlacement placement;
  final VoidCallback onEdit;
  final VoidCallback? onEarlier;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, VoidCallback? onPressed) => MenuItemButton(
      leadingIcon: Icon(icon, size: 18, color: AmrColors.ink),
      onPressed: onPressed,
      child: Text(label, style: AmrText.body(15)),
    );
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AmrColors.white),
        surfaceTintColor: WidgetStatePropertyAll(AmrColors.white),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AmrRadius.card)),
      ),
      menuChildren: [
        item(LucideIcons.slidersHorizontal, 'Edit settings', onEdit),
        item(LucideIcons.arrowLeft, 'Move earlier', onEarlier),
        item(LucideIcons.arrowRight, 'Move later', onLater),
        item(
          LucideIcons.pinOff,
          'Remove from home',
          () => context.read<DashboardCubit>().unpin(placement),
        ),
      ],
      builder: (context, controller, _) => AmrIconButton(
        icon: LucideIcons.ellipsis,
        size: 40,
        variant: AmrIconButtonVariant.soft,
        tooltip: 'Widget options',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// "Add a widget": say what you want (the AI suggests one and asks before adding it), or pick
/// from the catalog and set it up yourself.
class _AddWidgetCard extends StatefulWidget {
  const _AddWidgetCard();

  @override
  State<_AddWidgetCard> createState() => _AddWidgetCardState();
}

class _AddWidgetCardState extends State<_AddWidgetCard> {
  static const _shown = 6;
  final _text = TextEditingController();
  bool _all = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _ask(String text) {
    _text.clear();
    openWidgetBuilder(context, message: text);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<WidgetCatalog>();
    final entries = [for (final name in pinnable) ?catalog[name]];
    final more = entries.length - _shown;
    return AmrCard(
      tone: AmrCardTone.dashed,
      padding: const EdgeInsets.all(AmrSpace.x24),
      child: ColumnGap([
        Text('Add a widget', style: AmrText.title(24, em: 0)),
        Text(
          'Describe what you want to see; the AI suggests one and asks before adding it.',
          style: AmrText.body(14, weight: FontWeight.w500),
        ),
        AskField(
          hint: 'e.g. MRSA on my ward this year',
          style: AskFieldStyle.flat,
          accent: true,
          controller: _text,
          onSubmit: _ask,
        ),
        Text('Or pick from the catalog', style: AmrText.body(14, weight: FontWeight.w500)),
        AnimatedSize(
          duration: AmrMotion.base,
          curve: AmrMotion.curve,
          alignment: Alignment.topCenter,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _all ? entries : entries.take(_shown))
                AmrButton(
                  label: '+ ${e.title ?? e.name}',
                  size: AmrButtonSize.sm,
                  variant: AmrButtonVariant.outline,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  onPressed: () => _addFromCatalog(context, e.name),
                ),
            ],
          ),
        ),
        if (more > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              onTap: () => setState(() => _all = !_all),
              pressScale: 1,
              builder: (_, _) => Text(
                _all ? 'Show fewer' : 'Browse the whole catalog ($more more)',
                style: AmrText.body(14).copyWith(decoration: TextDecoration.underline),
              ),
            ),
          ),
      ], crossAxisAlignment: CrossAxisAlignment.stretch),
    );
  }
}

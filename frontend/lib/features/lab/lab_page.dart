import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../shell/top_bar.dart';

import '../../catalog/actions.dart';
import '../../catalog/widgets/alert_card.dart';
import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../shell/app_page.dart';
import 'alert_investigation.dart';
import 'lab_cubit.dart';

/// Lab · alert inbox and investigation.
///
/// Desktop: the inbox on the left, the selected alert on the right (selection stays on the
/// page). Phone: `/lab` is the inbox, `/lab/alerts/:id` the alert with a back button.
class LabPage extends StatelessWidget {
  const LabPage({super.key, this.alertId});

  final String? alertId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => LabCubit(selected: alertId),
    child: context.isCompact
        ? (alertId == null ? const _PhoneInbox() : _PhoneAlert(alertId: alertId!))
        : const _DesktopLab(),
  );
}

/// Open alerts (not resolved), most severe first.
List<Alert> _open(Alerts data) =>
    data.alerts.where((a) => a.status != AlertStatus.resolved).toList()
      ..sort((x, y) => y.severity.index.compareTo(x.severity.index));

String _needALook(int n) => switch (n) {
  0 => 'No alerts need a look',
  1 => '1 alert needs a look',
  _ => '$n alerts need a look',
};

class _AlertsData extends StatelessWidget {
  const _AlertsData({required this.builder});

  final Widget Function(BuildContext context, List<Alert> open) builder;

  @override
  Widget build(BuildContext context) => QueryView<AlertsQuery, Alerts>(
    query: const AlertsQuery(),
    fetch: (repo, q) => repo.alerts(q),
    builder: (context, data) => builder(context, _open(data)),
  );
}

// Desktop ----------------------------------------------------------------------

class _DesktopLab extends StatelessWidget {
  const _DesktopLab();

  @override
  Widget build(BuildContext context) {
    return AppPage(
      body: PageBody(
        top: fluid(context, 24, 4, 48),
        children: [
          _AlertsData(
            builder: (context, open) => BlocBuilder<LabCubit, LabState>(
              builder: (context, s) {
                final cubit = context.read<LabCubit>();
                final shown = open.where(s.filter.matches).toList();
                final selected =
                    shown.where((a) => a.alertId == s.selected).firstOrNull ?? shown.firstOrNull;
                final todo = open.where((a) => !s.reviewed.contains(a.alertId)).length;
                final inbox = _Inbox(
                  alerts: shown,
                  selectedId: selected?.alertId,
                  reviewed: s.reviewed,
                  onTap: (a) => cubit.select(a.alertId),
                );
                final detail = selected == null
                    ? const NoteCard(title: 'Nothing to investigate here.')
                    : AlertInvestigation(alertId: selected.alertId);
                return ColumnGap(
                  [
                    ColumnGap([
                      Breadcrumb(['Home', 'Alerts'], onTapFirst: () => goHome(context)),
                      Text(_needALook(todo), style: AmrText.display(context, max: 80)),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final f in AlertFilter.values)
                            AmrButton.toggle(
                              label: f.label,
                              selected: s.filter == f,
                              onPressed: () => cubit.setFilter(f),
                            ),
                        ],
                      ),
                    ], gap: AmrSpace.x18),
                    LayoutBuilder(
                      builder: (context, box) {
                        if (box.maxWidth < 360 + 24 + 620) {
                          return ColumnGap(
                            [inbox, detail],
                            gap: AmrSpace.x24,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 360, child: inbox),
                            const SizedBox(width: 24),
                            Expanded(child: detail),
                          ],
                        );
                      },
                    ),
                  ],
                  gap: AmrSpace.x28,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Inbox extends StatelessWidget {
  const _Inbox({
    required this.alerts,
    required this.selectedId,
    required this.reviewed,
    required this.onTap,
    this.compact = false,
  });

  final List<Alert> alerts;
  final String? selectedId;
  final Set<String> reviewed;
  final ValueChanged<Alert> onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: const BoxDecoration(
          border: Border.symmetric(horizontal: BorderSide(color: AmrColors.ink)),
        ),
        child: Text('No alerts of this kind right now.', style: AmrText.body(15)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in alerts)
          AlertInboxRow(
            alert: a,
            selected: !compact && a.alertId == selectedId,
            reviewed: reviewed.contains(a.alertId),
            compact: compact,
            onTap: () => onTap(a),
          ),
        const Divider(height: 1, thickness: 1, color: AmrColors.ink),
      ],
    );
  }
}

// Phone ------------------------------------------------------------------------

/// Page with a sticky bottom bar fading in from white (the composer, "Mark as reviewed").
class _StickyBottomPage extends StatelessWidget {
  const _StickyBottomPage({required this.body, required this.bottom});

  final Widget body;
  final Widget bottom;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      AppPage(
        body: Padding(padding: const EdgeInsets.only(bottom: 96), child: body),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00FFFFFF), AmrColors.white],
                stops: [0, 0.35],
              ),
            ),
            child: SafeArea(top: false, child: bottom),
          ),
        ),
      ),
    ],
  );
}

class _PhoneInbox extends StatelessWidget {
  const _PhoneInbox();

  @override
  Widget build(BuildContext context) {
    return _StickyBottomPage(
      bottom: AskField(
        hint: 'Ask, e.g. is this alert real?',
        onSubmit: context.read<CatalogActions>().ask,
      ),
      body: PageBody(
        top: 12,
        bottom: 16,
        gap: AmrSpace.x16,
        children: [
          _AlertsData(
            builder: (context, open) => BlocBuilder<LabCubit, LabState>(
              builder: (context, s) {
                final cubit = context.read<LabCubit>();
                final shown = open.where(s.filter.matches).toList();
                return ColumnGap(
                  [
                    Text('Home $sparkle Alerts', style: AmrText.body(13)),
                    Text(
                      _needALook(open.where((a) => !s.reviewed.contains(a.alertId)).length),
                      style: AmrText.sora(40, em: -0.035, height: 1.02),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(
                        children: [
                          for (final f in AlertFilter.values)
                            if (f.shortLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: AmrButton.toggle(
                                  label: f.shortLabel!,
                                  selected: s.filter == f,
                                  size: AmrButtonSize.sm,
                                  fontSize: 14,
                                  onPressed: () => cubit.setFilter(f),
                                ),
                              ),
                        ],
                      ),
                    ),
                    _Inbox(
                      alerts: shown,
                      selectedId: null,
                      reviewed: s.reviewed,
                      compact: true,
                      onTap: (a) => context.go('/lab/alerts/${a.alertId}'),
                    ),
                  ],
                  gap: AmrSpace.x16,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneAlert extends StatelessWidget {
  const _PhoneAlert({required this.alertId});

  final String alertId;

  @override
  Widget build(BuildContext context) {
    final reviewed = context.select((LabCubit c) => c.state.reviewed.contains(alertId));
    return _StickyBottomPage(
      bottom: ReviewButton(alertId: alertId, reviewed: reviewed, large: true),
      body: PageBody(
        top: 0,
        bottom: 16,
        gap: AmrSpace.x16,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              onTap: () => context.go('/lab'),
              builder: (_, s) => AnimatedContainer(
                duration: AmrMotion.fast,
                height: 44,
                padding: const EdgeInsets.only(left: 12, right: 18),
                decoration: BoxDecoration(
                  color: s.hovered ? AmrColors.lavenderSoft : AmrColors.white,
                  borderRadius: AmrRadius.pill,
                  boxShadow: AmrShadows.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.arrowLeft, size: 20, color: AmrColors.ink),
                    const SizedBox(width: 8),
                    Text('Alerts', style: AmrText.body(15)),
                  ],
                ),
              ),
            ),
          ),
          AlertInvestigation(alertId: alertId, compact: true),
        ],
      ),
    );
  }
}

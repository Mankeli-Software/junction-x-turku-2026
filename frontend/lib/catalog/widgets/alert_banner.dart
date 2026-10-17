import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../actions.dart';
import '../catalog.dart';

final alertBannerEntry = CatalogEntry(
  name: 'AlertBanner',
  title: 'Alerts on my ward',
  description: 'The most important active alert on a ward, opening the alert.',
  builder: (context, params, slot) =>
      AlertBanner(query: AlertsQuery.fromJson({'status': 'active', ...params}), slot: slot),
);

/// Pink banner with the ward's top active alert; a calm note when there is none.
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, required this.query, this.slot = WidgetSlot.page});

  final AlertsQuery query;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<AlertsQuery, Alerts>(
    query: query,
    fetch: (repo, q) => repo.alerts(q),
    loading: const AmrCard(tone: AmrCardTone.alert, child: SkeletonBlock(lines: 2)),
    builder: (context, data) {
      final alerts = [...data.alerts]..sort((a, b) => b.severity.index.compareTo(a.severity.index));
      final ward = query.ward;
      if (alerts.isEmpty) {
        // In a chat answer an empty banner is noise; elsewhere it reassures.
        if (slot == WidgetSlot.chat) return const SizedBox.shrink();
        return AmrCard(
          tone: AmrCardTone.subtle,
          child: ColumnGap([
            DotLabel(ward == null ? 'All wards' : 'On ${ward.label}', color: AmrColors.periwinkle),
            Text('No active alerts right now', style: AmrText.title(26)),
          ]),
        );
      }
      return AlertBannerView(alert: alerts.first, slot: slot);
    },
  );
}

class AlertBannerView extends StatelessWidget {
  const AlertBannerView({super.key, required this.alert, this.slot = WidgetSlot.page});

  final Alert alert;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) {
    if (slot == WidgetSlot.chat) return _chat(context);
    final home = slot == WidgetSlot.card;
    final title = alert.title.isEmpty
        ? alert.summary
        : switch (alert.type) {
            AlertType.sentinel => '${alert.title} found ${alert.onWhere}',
            AlertType.missingData => alert.summary,
            _ => '${alert.title} is rising ${alert.onWhere}',
          };
    return AmrCard(
      tone: AmrCardTone.alert,
      onTap: () => context.read<CatalogActions>().openAlert(alert.alertId),
      child: ColumnGap([
        DotLabel(home ? 'On your ward now' : 'Active alert ${alert.onWhere}'),
        Text(
          home ? title : alert.summary,
          style: AmrText.title(home ? 26 : (context.isShort ? 20 : 24)),
        ),
        Text(
          home ? 'See what it means for your patients' : 'Open the alert',
          style: AmrText.body(15).copyWith(decoration: TextDecoration.underline),
        ),
      ], gap: home ? AmrSpace.x14 : AmrSpace.x10),
    );
  }

  /// Chat: "● Active alert", one line of title, and the link (no link on a phone).
  Widget _chat(BuildContext context) {
    final compact = context.isCompact;
    return AmrCard(
      tone: AmrCardTone.alert,
      padding: EdgeInsets.all(compact ? 16 : 22),
      onTap: () => context.read<CatalogActions>().openAlert(alert.alertId),
      child: ColumnGap(
        [
          Row(
            children: [
              StatusDot(size: compact ? 8 : 9),
              const SizedBox(width: 8),
              Text('Active alert', style: AmrText.label(compact ? 12 : 13)),
            ],
          ),
          Text(
            alert.title.isEmpty ? alert.summary : '${alert.title} rising ${alert.onWhere}',
            style: AmrText.body(compact ? 15 : 16, weight: FontWeight.w500),
          ),
          if (!compact)
            Text(
              'Open the alert',
              style: AmrText.body(14).copyWith(decoration: TextDecoration.underline),
            ),
        ],
        gap: compact ? 4 : 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

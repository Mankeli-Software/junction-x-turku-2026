import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../catalog/actions.dart';
import '../../catalog/catalog.dart';
import '../../core/models/alerts.dart';
import '../../core/models/common.dart';
import '../../core/models/dashboard.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../../session/demo_users.dart';

/// Widgets that make sense on a home page; the patient chips and the fixed notices do not.
/// Same list as `PINNABLE` in backend/app/widgets/catalog.py.
const pinnable = [
  'CoverageRanking',
  'OrganismMix',
  'WindowCompare',
  'AlertBanner',
  'ResistanceTrend',
  'SpreadingCounts',
  'CrossWardWarning',
  'WardStatus',
  'SamplingVolume',
  'AlertCard',
  'EpiCurve',
  'CaseList',
];

/// Widgets that follow one alert and need its id.
const _alertWidgets = {'AlertCard', 'EpiCurve', 'CaseList'};

/// Good first settings for a widget picked from the catalog: the user's own ward, a urinary
/// infection, E. coli and trimethoprim. Pinned params carry no `as_of`: they follow the replay.
Json defaultParams(String widget, DemoUser? user) {
  final ward = user?.ward;
  final wards = user?.wards.isNotEmpty ?? false ? user!.wards : [?ward];
  return switch (widget) {
    'CoverageRanking' || 'OrganismMix' => {'ward': ?ward?.code, 'infection_type': 'uti'},
    'WindowCompare' || 'ResistanceTrend' => {
      'ward': ?ward?.code,
      'specimen': Specimen.urine.code,
      'organism': Organism.eColi.code,
      'drug': Drug.tmp.code,
    },
    'AlertBanner' || 'SamplingVolume' => {'ward': ?ward?.code},
    'CrossWardWarning' => {'ward': (ward ?? Ward.uro).code},
    'WardStatus' => {
      'wards': [
        for (final w in wards.isEmpty ? [Ward.uro] : wards) w.code,
      ],
    },
    _ => {},
  };
}

/// One editable input of a widget: a param key, its label and the choices.
class SettingField {
  const SettingField(
    this.key,
    this.label,
    this.options, {
    this.none,
    this.list = false,
    this.fallback,
  });

  final String key;
  final String label;

  /// (wire code, label).
  final List<(String, String)> options;

  /// The label of "not set" (e.g. "Whole hospital"); null when a value is required.
  final String? none;

  /// Stored as a one-item list (`wards`).
  final bool list;

  /// What the backend uses when the key is missing (`window` is 28d).
  final String? fallback;

  String? valueIn(Json params) {
    final v = params[key];
    if (list) return v is List && v.isNotEmpty ? '${v.first}' : null;
    if (v is bool) return v ? 'true' : null;
    return v is String ? v : fallback;
  }

  Json write(Json params, String? code) {
    final next = {...params}..remove(key);
    if (code == null) return next;
    if (list) return next..[key] = [code];
    if (key == 'oral_only') return next..[key] = true;
    return next..[key] = code;
  }

  String labelIn(Json params) {
    final code = valueIn(params);
    return options.where((o) => o.$1 == code).firstOrNull?.$2 ?? none ?? code ?? '';
  }
}

List<(String, String)> _coded<T extends Coded>(List<T> values, String Function(T) label) => [
  for (final v in values) (v.code, label(v)),
];

final _ward = SettingField(
  'ward',
  'Ward',
  _coded(Ward.values, (w) => w.label),
  none: 'Whole hospital',
);
final _wardRequired = SettingField('ward', 'Ward', _coded(Ward.values, (w) => w.label));
final _wards = SettingField(
  'wards',
  'Ward',
  _coded(Ward.values, (w) => w.label),
  none: 'All wards',
  list: true,
);
final _infection = SettingField(
  'infection_type',
  'Infection',
  _coded(InfectionType.values.where((t) => t.inData).toList(), (t) => t.label),
  none: 'Any sample',
);
final _specimen = SettingField(
  'specimen',
  'Sample',
  _coded(Specimen.values, (s) => s.label),
  none: 'All samples',
);
final _sex = SettingField('sex', 'Sex', _coded(Sex.values, (s) => s.label), none: 'Women and men');
final _age = SettingField(
  'age_band',
  'Age',
  _coded(AgeBand.values, (a) => a.label),
  none: 'All ages',
);
final _onset = SettingField(
  'onset',
  'Onset',
  _coded(Onset.values, (o) => o.label),
  none: 'Home and hospital',
);
final _window = SettingField(
  'window',
  'Period',
  _coded([TimeWindow.d28, TimeWindow.d365], (w) => w.label),
  fallback: TimeWindow.d28.code,
);
final _organism = SettingField('organism', 'Organism', _coded(Organism.values, (o) => o.code));
final _drug = SettingField('drug', 'Antibiotic', _coded(Drug.values, (d) => d.label));
final _phenotype = SettingField(
  'phenotype',
  'Resistant type',
  _coded(Phenotype.values, (p) => p.code),
  none: 'All types',
);
const _oral = SettingField('oral_only', 'Antibiotics', [('true', 'Oral only')], none: 'All');

/// The inputs a user can change on each widget. Alert widgets pick their alert separately.
List<SettingField> settingsFor(String widget) => switch (widget) {
  'CoverageRanking' => [_ward, _infection, _sex, _age, _onset, _window, _oral],
  'OrganismMix' => [_ward, _infection, _sex, _age, _onset, _window],
  'WindowCompare' => [_ward, _specimen, _organism, _drug],
  'ResistanceTrend' => [_ward, _specimen, _organism, _drug, _age, _onset],
  'AlertBanner' => [_ward],
  'SpreadingCounts' => [_wards, _phenotype, _window],
  'WardStatus' => [_wards, _window],
  'CrossWardWarning' => [_wardRequired, _phenotype],
  'SamplingVolume' => [_ward, _specimen, _window],
  _ => const [],
};

/// "E. coli · Trimethoprim · Urology": what a pinned card is set to, in a few words.
String placementSummary(WidgetPlacement p) {
  final params = p.params;
  String? label(SettingField f) => f.valueIn(params) == null ? null : f.labelIn(params);
  final infection = byCodeOrNull(InfectionType.values, params['infection_type']);
  final parts = switch (p.widget) {
    'CoverageRanking' || 'OrganismMix' => [
      infection == InfectionType.uti ? 'UTI' : infection?.label ?? label(_specimen),
      _ward.labelIn(params),
      label(_sex),
      byCodeOrNull(AgeBand.values, params['age_band'])?.short,
      label(_onset),
      if (params['oral_only'] == true) 'Oral only',
    ],
    'WindowCompare' || 'ResistanceTrend' => [
      byCodeOrNull(Organism.values, params['organism'])?.short,
      byCodeOrNull(Drug.values, params['drug'])?.label,
      _ward.labelIn(params),
    ],
    'SpreadingCounts' || 'WardStatus' => [_wards.labelIn(params), label(_phenotype)],
    'AlertCard' || 'EpiCurve' || 'CaseList' => ['One alert'],
    'CrossWardWarning' => ['From ${_wardRequired.labelIn(params)}', label(_phenotype)],
    _ => [_ward.labelIn(params)],
  };
  return [
    ...parts,
    if (params['window'] == TimeWindow.d365.code) TimeWindow.d365.label,
  ].nonNulls.where((s) => s.isNotEmpty).join(' · ');
}

/// Where a pinned card leads: the full page its numbers come from.
(String, void Function(CatalogActions))? placementLink(WidgetPlacement p) {
  final params = p.params;
  return switch (p.widget) {
    'CoverageRanking' ||
    'OrganismMix' => ('Open full answer', (a) => a.openAnswer(PatientProfile.fromJson(params))),
    'ResistanceTrend' || 'WindowCompare' => ('Open in Research', (a) => a.openResearch(params)),
    'AlertBanner' || 'SamplingVolume' => ('Open the lab inbox', (a) => a.openLab()),
    'AlertCard' || 'EpiCurve' || 'CaseList' when params['alert_id'] is String => (
      'Open the alert',
      (a) => a.openAlert(params['alert_id']! as String),
    ),
    'SpreadingCounts' ||
    'WardStatus' ||
    'CrossWardWarning' => ('Open infection control', (a) => a.openInfectionControl()),
    _ => null,
  };
}

/// The settings dialog: every input of the widget beside a live preview. With [adding] the
/// main button adds it to the home page; otherwise it saves the change. Returns the new
/// placement, or null on cancel.
Future<WidgetPlacement?> showWidgetSettings(
  BuildContext context,
  WidgetPlacement placement, {
  bool adding = false,
}) => showAmrDialog<WidgetPlacement>(
  context,
  maxWidth: 1040,
  child: WidgetSettingsPanel(placement: placement, adding: adding),
);

/// A centred white panel over a dimmed page, like the replay dialog; full width on a phone.
Future<T?> showAmrDialog<T>(BuildContext context, {required Widget child, double maxWidth = 720}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0x331D204E),
      transitionDuration: AmrMotion.base,
      pageBuilder: (context, _, _) {
        final compact = context.isCompact;
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 24),
                child: Material(
                  color: AmrColors.white,
                  borderRadius: AmrRadius.panel,
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, a, _, child) {
        final curved = CurvedAnimation(parent: a, curve: AmrMotion.curve);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(curved), child: child),
        );
      },
    );

class WidgetSettingsPanel extends StatefulWidget {
  const WidgetSettingsPanel({super.key, required this.placement, this.adding = false});

  final WidgetPlacement placement;
  final bool adding;

  @override
  State<WidgetSettingsPanel> createState() => _WidgetSettingsPanelState();
}

class _WidgetSettingsPanelState extends State<WidgetSettingsPanel> {
  late Json _params = {
    for (final e in widget.placement.params.entries)
      if (e.key != 'as_of') e.key: e.value,
  };

  WidgetPlacement get _draft => WidgetPlacement(widget: widget.placement.widget, params: _params);

  bool get _ready => !_alertWidgets.contains(_draft.widget) || _params['alert_id'] is String;

  @override
  Widget build(BuildContext context) {
    final entry = context.read<WidgetCatalog>()[_draft.widget];
    final compact = context.isCompact;
    final fields = settingsFor(_draft.widget);
    final inputs = ColumnGap(
      [
        if (_alertWidgets.contains(_draft.widget))
          _AlertPicker(
            selected: _params['alert_id'] as String?,
            onChanged: (id) => setState(() => _params = {..._params, 'alert_id': id}),
          ),
        for (final f in fields)
          _LabelledPick(
            field: f,
            params: _params,
            onChanged: (code) => setState(() => _params = f.write(_params, code)),
          ),
        if (fields.isEmpty && !_alertWidgets.contains(_draft.widget))
          Text('This widget has nothing to set.', style: AmrText.body(14)),
      ],
      gap: AmrSpace.x14,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );
    final preview = ColumnGap(
      [
        Text('Preview · live data', style: AmrText.label(12)),
        AmrCard(
          tone: AmrCardTone.subtle,
          padding: const EdgeInsets.all(AmrSpace.x20),
          child: _ready
              ? CatalogWidget(_draft, key: ValueKey(_params.toString()), slot: WidgetSlot.card)
              : Text('Pick an alert to see it here.', style: AmrText.body(14)),
        ),
      ],
      gap: AmrSpace.x8,
      crossAxisAlignment: CrossAxisAlignment.stretch,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DialogHeader(
            eyebrow: widget.adding ? 'Add to your home' : 'Widget settings',
            title: entry?.title ?? _draft.widget,
            subtitle: entry?.description,
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(compact ? 18 : 32, 4, compact ? 18 : 32, 8),
              child: compact
                  ? ColumnGap([inputs, preview], gap: AmrSpace.x20)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 300, child: inputs),
                        const SizedBox(width: AmrSpace.x28),
                        Expanded(child: preview),
                      ],
                    ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 18 : 32,
              12,
              compact ? 18 : 32,
              compact ? 18 : 24,
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 10,
              children: [
                AmrButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                AmrButton(
                  label: widget.adding ? 'Add to my home' : 'Save',
                  variant: AmrButtonVariant.primary,
                  leading: widget.adding ? const Icon(LucideIcons.pin, size: 16) : null,
                  onPressed: _ready ? () => Navigator.of(context).pop(_draft) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dialog's title row with a close button.
class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.eyebrow, required this.title, this.subtitle});

  final String eyebrow;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 18 : 32, compact ? 18 : 28, compact ? 12 : 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ColumnGap([
              Text(eyebrow, style: AmrText.label(12)),
              Text(title, style: AmrText.title(compact ? 24 : 28, em: 0)),
              if (subtitle != null) Text(subtitle!, style: AmrText.body(14)),
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
    );
  }
}

class _LabelledPick extends StatelessWidget {
  const _LabelledPick({required this.field, required this.params, required this.onChanged});

  final SettingField field;
  final Json params;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = field.valueIn(params);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(field.label, style: AmrText.body(14, weight: FontWeight.w500)),
        const SizedBox(height: 6),
        PillSelect(
          value: field.labelIn(params),
          options: [
            if (field.none != null) (null, field.none!),
            for (final (code, label) in field.options) (code, label),
          ],
          selected: current,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// The active alerts at the replay date, to follow one.
class _AlertPicker extends StatelessWidget {
  const _AlertPicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => QueryView<AlertsQuery, Alerts>(
    query: const AlertsQuery(status: AlertStatus.active),
    fetch: (repo, q) => repo.alerts(q),
    loading: const SkeletonBlock(lines: 1),
    builder: (context, data) {
      String label(Alert a) => [
        a.type.label,
        a.phenotype?.code ?? a.organism?.short,
        a.ward?.short ?? 'Whole hospital',
      ].nonNulls.join(' · ');
      final current = data.alerts.where((a) => a.alertId == selected).firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Alert', style: AmrText.body(14, weight: FontWeight.w500)),
          const SizedBox(height: 6),
          if (data.alerts.isEmpty)
            Text('No active alerts at this date.', style: AmrText.body(14))
          else
            PillSelect(
              value: current == null ? (selected ?? 'Choose an alert') : label(current),
              options: [for (final a in data.alerts) (a.alertId, label(a))],
              selected: selected,
              onChanged: onChanged,
            ),
        ],
      );
    },
  );
}

/// A white-on-lavender pill that opens its choices in a menu, like Explore's filters.
class PillSelect extends StatelessWidget {
  const PillSelect({
    super.key,
    required this.value,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String value;

  /// (code, label); a null code is "not set".
  final List<(String?, String)> options;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AmrColors.white),
        surfaceTintColor: WidgetStatePropertyAll(AmrColors.white),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AmrRadius.card)),
        maximumSize: WidgetStatePropertyAll(Size(360, 420)),
      ),
      menuChildren: [
        for (final (code, label) in options)
          MenuItemButton(
            onPressed: () => onChanged(code),
            trailingIcon: code == selected
                ? const Icon(LucideIcons.check, size: 16, color: AmrColors.ink)
                : null,
            child: Text(
              label,
              style: AmrText.body(15, weight: code == selected ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
      ],
      builder: (context, controller, _) => Pressable(
        pressScale: 0.99,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        builder: (_, s) => AnimatedContainer(
          duration: AmrMotion.fast,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: s.hovered ? AmrColors.lavenderPale : AmrColors.lavenderSoft,
            borderRadius: AmrRadius.pill,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(value, style: AmrText.body(15), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              const Icon(LucideIcons.chevronDown, size: 18, color: AmrColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}

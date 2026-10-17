import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../core/models/alerts.dart';
import '../../core/models/vocab.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final crossWardWarningEntry = CatalogEntry(
  name: 'CrossWardWarning',
  title: 'Warn linked wards',
  description: 'Wards that share many patients with a ward that has an alert, with a heads-up.',
  builder: (context, params, slot) => CrossWardWarning(
    query: WardLinksQuery.fromJson(params),
    organism: byCodeOrNull(Organism.values, params['organism']),
    phenotype: byCodeOrNull(Phenotype.values, params['phenotype']),
    only: [
      for (final w in params['to'] as List? ?? const [])
        // A heads-up goes to the other wards, never to the ward it is about.
        if (byCodeOrNull(Ward.values, w) case final ward? when ward.code != params['ward']) ward,
    ],
    slot: slot,
  ),
);

/// Connected linked-wards panel: loads `/v1/ward-links` and offers a heads-up per ward.
class CrossWardWarning extends StatelessWidget {
  const CrossWardWarning({
    super.key,
    required this.query,
    this.organism,
    this.phenotype,
    this.only = const [],
    this.slot = WidgetSlot.page,
  });

  final WardLinksQuery query;

  /// What is raised on [WardLinksQuery.ward]; it goes into the heads-up text.
  final Organism? organism;
  final Phenotype? phenotype;

  /// The wards the user asked to warn (`to`): only they get a heads-up button.
  final List<Ward> only;
  final WidgetSlot slot;

  @override
  Widget build(BuildContext context) => QueryView<WardLinksQuery, WardLinks>(
    query: query,
    fetch: (repo, q) => repo.wardLinks(q),
    builder: (context, data) => LinkedWardsPanel(
      links: data,
      organism: organism,
      phenotype: phenotype,
      only: only,
      slot: slot,
    ),
  );
}

// Heads-up state --------------------------------------------------------------

/// Sends a heads-up; there is no backend call yet, so the default only waits a moment.
typedef HeadsUpSender = Future<void> Function(Ward to, String message);

Future<void> _pretendToSend(Ward to, String message) =>
    Future<void>.delayed(const Duration(milliseconds: 250));

enum HeadsUpStep { idle, draft, editing, sending, sent }

class HeadsUpState extends Equatable {
  const HeadsUpState({this.step = HeadsUpStep.idle, this.to, this.message = '', this.sentAt});

  final HeadsUpStep step;
  final Ward? to;
  final String message;
  final DateTime? sentAt;

  @override
  List<Object?> get props => [step, to, message, sentAt];
}

/// One heads-up at a time: draft → (edit) → send → sent, with cancel and undo.
class HeadsUpCubit extends Cubit<HeadsUpState> {
  HeadsUpCubit({HeadsUpSender? send}) : _send = send ?? _pretendToSend, super(const HeadsUpState());

  final HeadsUpSender _send;

  void draft(Ward to, String message) =>
      emit(HeadsUpState(step: HeadsUpStep.draft, to: to, message: message));

  void edit() =>
      emit(HeadsUpState(step: HeadsUpStep.editing, to: state.to, message: state.message));

  void changeText(String text) => emit(HeadsUpState(step: state.step, to: state.to, message: text));

  void cancel() => emit(const HeadsUpState());

  Future<void> send() async {
    final to = state.to;
    if (to == null) return;
    emit(HeadsUpState(step: HeadsUpStep.sending, to: to, message: state.message));
    await _send(to, state.message);
    if (!isClosed) {
      emit(
        HeadsUpState(
          step: HeadsUpStep.sent,
          to: to,
          message: state.message,
          sentAt: DateTime.now(),
        ),
      );
    }
  }

  /// Takes the heads-up back: no backend yet, so this only clears the confirmation.
  void undo() => emit(const HeadsUpState());
}

/// The heads-up text, built from aggregates only: no patient details.
String headsUpMessage(Ward from, {Organism? organism, Phenotype? phenotype}) {
  final what = switch ((organism, phenotype)) {
    (final Organism o, final Phenotype p) => '${o.short} with ${p.code}',
    (null, final Phenotype p) => p.code,
    (final Organism o, null) => 'Resistant ${o.short}',
    _ => 'Resistant bacteria',
  };
  final consider = phenotype == null ? 'resistance' : phenotype.code;
  return '$what has risen on ${from.label} over the last 4 weeks. Your ward shares many '
      'patients with ${from.label}. Consider $consider when choosing antibiotics and follow '
      'contact precautions for transfers. No patient details are included.';
}

/// "Shares 291 patients in 30 days · ESBL is also higher here".
String linkNote(WardLink l) => [
  'Shares ${l.sharedPatients30d} patients in 30 days',
  if (l.phenotype != null) '${l.phenotype!.code} is also higher here',
].join(' · ');

// Views -----------------------------------------------------------------------

/// The lavender "warn the linked wards" panel, plus the draft and the sent confirmation.
class LinkedWardsPanel extends StatelessWidget {
  const LinkedWardsPanel({
    super.key,
    required this.links,
    this.organism,
    this.phenotype,
    this.only = const [],
    this.slot = WidgetSlot.page,
    this.sender,
  });

  final WardLinks links;
  final Organism? organism;
  final Phenotype? phenotype;

  /// When set, a heads-up for just these wards instead of every linked ward.
  final List<Ward> only;
  final WidgetSlot slot;
  final HeadsUpSender? sender;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HeadsUpCubit(send: sender),
      child: BlocBuilder<HeadsUpCubit, HeadsUpState>(
        builder: (context, s) {
          final cubit = context.read<HeadsUpCubit>();
          void open(Ward to) =>
              cubit.draft(to, headsUpMessage(links.ward, organism: organism, phenotype: phenotype));
          final panel = switch (slot) {
            _ when only.isNotEmpty => _TargetedPanel(
              links: links,
              to: only,
              onHeadsUp: open,
              compact: context.isCompact || slot == WidgetSlot.card,
            ),
            WidgetSlot.page =>
              context.isCompact
                  ? _PhonePanel(links: links, onHeadsUp: open)
                  : _PagePanel(links: links, onHeadsUp: open),
            _ => _ChatPanel(links: links, onHeadsUp: open, compact: slot == WidgetSlot.card),
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              panel,
              AnimatedSize(
                duration: AmrMotion.base,
                curve: AmrMotion.curve,
                alignment: Alignment.topCenter,
                child: switch (s.step) {
                  HeadsUpStep.idle => const SizedBox(width: double.infinity),
                  HeadsUpStep.sent => Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: ActionPill(
                      message: context.isCompact
                          ? 'Heads-up sent at ${DateFormat.Hm().format(s.sentAt!)}'
                          : 'Heads-up sent to the ${s.to!.label} at '
                                '${DateFormat.Hm().format(s.sentAt!)}',
                      actionLabel: 'Undo',
                      onAction: cubit.undo,
                    ),
                  ),
                  _ => Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: HeadsUpDraft(state: s),
                  ),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Hygiene page: "Early warning for linked wards" with a grid of white pill rows.
class _PagePanel extends StatelessWidget {
  const _PagePanel({required this.links, required this.onHeadsUp});

  final WardLinks links;
  final ValueChanged<Ward> onHeadsUp;

  @override
  Widget build(BuildContext context) {
    return AmrCard(
      tone: AmrCardTone.accent,
      padding: EdgeInsets.all(fluid(context, 24, 3, 40)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Early warning for linked wards', style: AmrText.body(15, weight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            'Patients move from ${links.ward.label} to these wards',
            style: AmrText.sora(fluid(context, 28, 3, 40), em: -0.03, height: 1.1),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Text(
              'Counts of shared patients in the last 30 days. Only totals are shared between '
              'wards, never patient details.',
              style: AmrText.body(15),
            ),
          ),
          const SizedBox(height: 16),
          if (links.links.isEmpty)
            Text('No wards share many patients with ${links.ward.label}.', style: AmrText.body(15))
          else
            AutoGrid(
              minItemWidth: 300,
              gap: AmrSpace.x12,
              children: [
                for (final l in links.links)
                  _LinkRow(
                    title: l.ward.label,
                    note: linkNote(l),
                    action: 'Send heads-up',
                    onTap: () => onHeadsUp(l.ward),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Phone: stacked pill rows with a short "Heads-up" button.
class _PhonePanel extends StatelessWidget {
  const _PhonePanel({required this.links, required this.onHeadsUp});

  final WardLinks links;
  final ValueChanged<Ward> onHeadsUp;

  @override
  Widget build(BuildContext context) {
    return AmrCard(
      tone: AmrCardTone.accent,
      radius: AmrRadius.bubble,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: ColumnGap(
        [
          Text('Early warning for linked wards', style: AmrText.body(13, weight: FontWeight.w500)),
          Text(
            'Patients move from ${links.ward.label} to these wards',
            style: AmrText.sora(28, em: -0.025, height: 1.1),
          ),
          Text('Only totals are shared, never patient details.', style: AmrText.body(13)),
          for (final l in links.links)
            _LinkRow(
              title: l.ward.label,
              note: linkNote(l),
              action: 'Heads-up',
              compact: true,
              onTap: () => onHeadsUp(l.ward),
            ),
        ],
        gap: AmrSpace.x12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

/// The user named whom to warn: "Give Geriatrics a heads-up" with one button per named ward
/// (usually one), so there is nothing to look for. The button opens the same draft to check.
class _TargetedPanel extends StatelessWidget {
  const _TargetedPanel({
    required this.links,
    required this.to,
    required this.onHeadsUp,
    this.compact = false,
  });

  final WardLinks links;
  final List<Ward> to;
  final ValueChanged<Ward> onHeadsUp;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final names = to.map((w) => w.label).toList();
    final who = names.length == 1
        ? names.single
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    String why(Ward w) {
      final link = links.links.where((l) => l.ward == w).firstOrNull;
      final from = links.ward.label;
      return [
        if (link == null)
          'About resistant bacteria on $from.'
        else
          'Shares ${link.sharedPatients30d} patients with $from in 30 days.',
        if (link?.phenotype case final p?) '${p.code} is also higher on ${w.label}.',
        'Only totals are shared.',
      ].join(' ');
    }

    return AmrCard(
      tone: AmrCardTone.accent,
      padding: EdgeInsets.all(compact ? AmrSpace.x18 : AmrSpace.x24),
      child: ColumnGap(
        [
          Text('Give $who a heads-up', style: AmrText.title(compact ? 20 : 22, em: 0)),
          for (final w in to)
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Text(why(w), style: AmrText.body(14)),
                ),
                AmrButton(
                  label: 'Send heads-up to ${w.label}',
                  variant: AmrButtonVariant.primary,
                  size: AmrButtonSize.md,
                  expand: compact,
                  onPressed: () => onHeadsUp(w),
                ),
              ],
            ),
        ],
        gap: compact ? AmrSpace.x10 : AmrSpace.x14,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

/// Chat: "Warn the wards linked to Urology" with inline pills.
class _ChatPanel extends StatelessWidget {
  const _ChatPanel({required this.links, required this.onHeadsUp, this.compact = false});

  final WardLinks links;
  final ValueChanged<Ward> onHeadsUp;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final phone = context.isCompact || compact;
    return AmrCard(
      tone: AmrCardTone.accent,
      padding: EdgeInsets.all(phone ? AmrSpace.x18 : AmrSpace.x24),
      child: ColumnGap(
        [
          Text(
            'Warn the wards linked to ${links.ward.label}',
            style: AmrText.title(phone ? 20 : 22, em: 0),
          ),
          if (!phone)
            Text(
              'These wards share the most patients with ${links.ward.label}. '
              'Only totals are shared.',
              style: AmrText.body(14),
            ),
          if (phone)
            for (final l in links.links)
              _InlineLink(
                ward: l.ward,
                label: l.ward.short,
                action: 'Heads-up',
                expand: true,
                onTap: onHeadsUp,
              )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in links.links)
                  _InlineLink(
                    ward: l.ward,
                    label: l.ward.label,
                    action: 'Send heads-up',
                    onTap: onHeadsUp,
                  ),
              ],
            ),
        ],
        gap: phone ? AmrSpace.x10 : AmrSpace.x12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.title,
    required this.note,
    required this.action,
    required this.onTap,
    this.compact = false,
  });

  final String title;
  final String note;
  final String action;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 22,
        compact ? 8 : 14,
        compact ? 8 : 14,
        compact ? 8 : 14,
      ),
      decoration: const BoxDecoration(color: AmrColors.white, borderRadius: AmrRadius.pill),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AmrText.body(compact ? 15 : 16, weight: FontWeight.w600, height: 1.3),
                ),
                Text(note, style: AmrText.body(compact ? 12 : 13, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AmrButton(
            label: action,
            size: AmrButtonSize.md,
            fontSize: compact ? 13 : 14,
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 18),
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

/// "Emergency department [Send heads-up]" as one white pill.
class _InlineLink extends StatelessWidget {
  const _InlineLink({
    required this.ward,
    required this.label,
    required this.action,
    required this.onTap,
    this.expand = false,
  });

  final Ward ward;
  final String label;
  final String action;
  final ValueChanged<Ward> onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = AmrButton(
      label: action,
      size: AmrButtonSize.sm,
      fontSize: 13,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      onPressed: () => onTap(ward),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: EdgeInsets.fromLTRB(expand ? 16 : 18, 6, 8, 6),
      decoration: const BoxDecoration(color: AmrColors.white, borderRadius: AmrRadius.pill),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (expand)
            Expanded(child: Text(label, style: AmrText.body(14)))
          else
            Text(label, style: AmrText.body(15)),
          const SizedBox(width: 10),
          button,
        ],
      ),
    );
  }
}

/// "Check before sending": the recipient, the text, Send / Edit text / Cancel.
class HeadsUpDraft extends StatelessWidget {
  const HeadsUpDraft({super.key, required this.state});

  final HeadsUpState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HeadsUpCubit>();
    final phone = context.isCompact;
    final editing = state.step == HeadsUpStep.editing;
    final sending = state.step == HeadsUpStep.sending;
    final textStyle = AmrText.body(phone ? 14 : 15, height: 1.5);
    final send = AmrButton(
      label: sending ? 'Sending…' : 'Send',
      variant: AmrButtonVariant.primary,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      expand: phone,
      onPressed: sending || state.message.trim().isEmpty ? null : cubit.send,
    );
    final edit = AmrButton(
      label: editing ? 'Done editing' : 'Edit text',
      size: phone ? AmrButtonSize.md : AmrButtonSize.lg,
      fontSize: phone ? 14 : 15,
      expand: phone,
      onPressed: sending
          ? null
          : (editing ? () => cubit.draft(state.to!, state.message) : cubit.edit),
    );
    final cancel = phone
        ? AmrButton(
            label: 'Cancel',
            size: AmrButtonSize.md,
            fontSize: 14,
            expand: true,
            onPressed: sending ? null : cubit.cancel,
          )
        : SizedBox(
            height: 48,
            child: Center(
              child: AmrLink('Cancel', fontSize: 15, onTap: sending ? null : cubit.cancel),
            ),
          );
    return AmrCard(
      tone: AmrCardTone.quiet,
      padding: EdgeInsets.all(phone ? AmrSpace.x16 : AmrSpace.x24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Check before sending', style: AmrText.body(13)),
          const SizedBox(height: 6),
          Text('To: ${state.to!.label}, nurse in charge', style: AmrText.label(phone ? 12 : 13)),
          SizedBox(height: phone ? 12 : 14),
          Container(
            padding: EdgeInsets.all(phone ? 14 : 18),
            decoration: const BoxDecoration(
              color: AmrColors.lavenderSoft,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            child: editing
                ? _MessageEditor(text: state.message, style: textStyle, onChanged: cubit.changeText)
                : Text(state.message, style: textStyle),
          ),
          SizedBox(height: phone ? 12 : 14),
          if (phone) ...[
            send,
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: edit),
                const SizedBox(width: 8),
                Expanded(child: cancel),
              ],
            ),
          ] else
            Wrap(spacing: 8, runSpacing: 8, children: [send, edit, cancel]),
        ],
      ),
    );
  }
}

class _MessageEditor extends StatefulWidget {
  const _MessageEditor({required this.text, required this.style, required this.onChanged});

  final String text;
  final TextStyle style;
  final ValueChanged<String> onChanged;

  @override
  State<_MessageEditor> createState() => _MessageEditorState();
}

class _MessageEditorState extends State<_MessageEditor> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    autofocus: true,
    maxLines: null,
    style: widget.style,
    onChanged: widget.onChanged,
    decoration: const InputDecoration.collapsed(hintText: 'Write the heads-up'),
  );
}

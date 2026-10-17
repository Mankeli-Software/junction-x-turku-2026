import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../shell/top_bar.dart';

import '../../catalog/actions.dart';
import '../../catalog/catalog.dart';
import '../../catalog/widgets/alert_banner.dart';
import '../../core/models/alerts.dart';
import '../../core/models/common.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import '../chat/ask_context.dart';
import '../chat/widgets/ask_launcher.dart';
import '../dashboard/pinned_section.dart';
import '../shell/app_page.dart';
import 'patient_form.dart';
import 'patient_form_cubit.dart';

/// Doctor · 1: "Who is your patient?" — free text, the quick form, ward alerts and pins.
class DoctorHomePage extends StatelessWidget {
  const DoctorHomePage({super.key, this.initial});

  /// Pre-fills the form ("Edit details" from an answer).
  final PatientProfile? initial;

  @override
  Widget build(BuildContext context) {
    final user = context.select((SessionCubit c) => c.state.user);
    final ward = user?.ward;
    return BlocProvider(
      create: (_) => PatientFormCubit(initial: initial),
      child: AppPage(
        body: PageBody(
          top: fluid(context, 32, 5, 72),
          gap: AmrSpace.x36,
          children: [
            _Header(ward: ward),
            PatientForm(homeWard: ward),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AutoGrid(
                minItemWidth: 360,
                children: [
                  AlertBanner(
                    query: AlertsQuery(ward: ward, status: AlertStatus.active),
                    slot: WidgetSlot.card,
                  ),
                  _AskCard(ward: ward),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.only(top: 20), child: PinnedSection()),
          ],
        ),
      ),
    );
  }
}

/// "Ask AMRight": the AI's own card, with its ask field and a row of questions. The first two
/// open an answer straight away (no AI needed), the rest go to the chat.
class _AskCard extends StatelessWidget {
  const _AskCard({required this.ward});

  final Ward? ward;

  @override
  Widget build(BuildContext context) {
    final actions = context.read<CatalogActions>();
    final presets = <(String, VoidCallback)>[
      (
        'UTI, hospital onset, 75+',
        () => actions.openAnswer(
          PatientProfile(
            ward: ward,
            infectionType: InfectionType.uti,
            onset: Onset.hospital,
            ageBand: AgeBand.a75,
          ),
        ),
      ),
      (
        'Sepsis after surgery',
        () => actions.openAnswer(
          const PatientProfile(
            ward: Ward.surg,
            infectionType: InfectionType.sepsis,
            onset: Onset.hospital,
          ),
        ),
      ),
      for (final q in const [
        'What is causing UTIs now?',
        'Is trimethoprim still OK?',
        'Mecillinam or nitrofurantoin?',
      ])
        (q, () => actions.ask(q)),
    ];
    final chips = [
      for (final (label, onTap) in presets)
        AmrButton(
          label: label,
          size: AmrButtonSize.sm,
          variant: AmrButtonVariant.soft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          onPressed: onTap,
        ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AmrSpace.x24),
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        borderRadius: AmrRadius.card,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AmrColors.lavender, Color(0xFFE4D9F7), AmrColors.glowPink],
          stops: [0, 0.6, 1],
        ),
      ),
      child: ColumnGap(
        [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AmrSpace.x24),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: AmrColors.violet, shape: BoxShape.circle),
                  child: const Icon(LucideIcons.sparkles, size: 18, color: AmrColors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ask AMRight', style: AmrText.body(16, weight: FontWeight.w600)),
                      Text('AI answers with verified data from your lab', style: AmrText.body(13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AmrSpace.x24),
            child: AskLauncher(
              hint: 'Ask anything about resistance on your ward',
              style: AskFieldStyle.flat,
              accent: true,
              about: AskContext.patientForm(ward: ward),
            ),
          ),
          // One row to the card's edges, as in the design; swipe it, drag it with a mouse,
          // or scroll it with a trackpad.
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(dragDevices: {...PointerDeviceKind.values}, scrollbars: false),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AmrSpace.x24),
              child: Row(
                children: [
                  for (final (i, chip) in chips.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    chip,
                  ],
                ],
              ),
            ),
          ),
        ],
        gap: AmrSpace.x12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      ),
    );
  }
}

/// "Home ✦ Urology", "Who is your patient?" and, under it, the field that opens the AI
/// composer. Short windows get the medium field so the form still fits without scrolling.
class _Header extends StatelessWidget {
  const _Header({required this.ward});

  final Ward? ward;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ColumnGap(
          [
            Breadcrumb(['Home', ward?.label ?? 'All wards'], onTapFirst: () => goHome(context)),
            Text('Who is your patient?', style: AmrText.display(context)),
            AskLauncher(
              hint: 'e.g. woman over 75, urinary infection, on the ward for 3 days',
              size: context.isShort ? AskFieldSize.medium : AskFieldSize.large,
              about: AskContext.patientForm(ward: ward),
            ),
          ],
          gap: context.vfit(22, min: 12),
          crossAxisAlignment: CrossAxisAlignment.stretch,
        ),
      ),
    );
  }
}

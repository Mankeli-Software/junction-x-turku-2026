import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
                  _WardQuestions(ward: ward),
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

/// "People on your ward often ask": presets that open an answer without the AI.
class _WardQuestions extends StatelessWidget {
  const _WardQuestions({required this.ward});

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
      ('What is causing UTIs now?', () => actions.ask('What is causing UTIs now?')),
      ('Is trimethoprim still OK?', () => actions.ask('Is trimethoprim still OK?')),
    ];
    return AmrCard(
      tone: AmrCardTone.accent,
      child: ColumnGap([
        Text(
          ward == null ? 'People often ask' : 'People on your ward often ask',
          style: AmrText.label(14),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, onTap) in presets)
              AmrButton(
                label: label,
                variant: AmrButtonVariant.soft,
                size: AmrButtonSize.md,
                onPressed: onTap,
              ),
          ],
        ),
      ]),
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

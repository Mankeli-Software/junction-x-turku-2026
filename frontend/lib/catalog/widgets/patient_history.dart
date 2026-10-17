import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models/patient.dart';
import '../../core/query/query_view.dart';
import '../../ds/ds.dart';
import '../catalog.dart';

final patientHistoryEntry = CatalogEntry(
  name: 'PatientHistory',
  title: 'Earlier findings',
  description:
      'Earlier findings for one patient, only when a lab sample or patient ID is given. Facts '
      'only; does not change the ranking.',
  builder: (context, params, slot) => QueryView<PatientHistoryQuery, PatientHistory>(
    query: PatientHistoryQuery.fromJson(params),
    fetch: (repo, q) => repo.patientHistory(q),
    builder: (context, h) => PatientHistoryView(history: h),
  ),
);

/// "Earlier findings for this patient": month · organism · specimen · phenotype tag.
class PatientHistoryView extends StatelessWidget {
  const PatientHistoryView({super.key, required this.history});

  final PatientHistory history;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return AmrCard(
      tone: AmrCardTone.quiet,
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Earlier findings for this patient', style: AmrText.title(22, em: 0)),
          ),
          if (history.findings.isEmpty)
            Text('No earlier findings before this date.', style: AmrText.body(15)),
          for (final f in history.findings)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AmrColors.ink)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: compact ? 80 : 120,
                    child: Text(
                      '${month(f.sampleDate)} ${f.sampleDate.year}',
                      style: AmrText.body(15),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: f.organism.code,
                            style: AmrText.inter(15, style: FontStyle.italic),
                          ),
                          TextSpan(text: ' · ${f.specimen.code}', style: AmrText.body(15)),
                        ],
                      ),
                    ),
                  ),
                  if (f.phenotype != null) AmrTag(f.phenotype!.code, color: AmrColors.blush),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

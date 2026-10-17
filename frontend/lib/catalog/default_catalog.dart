import 'catalog.dart';
import 'widgets/alert_banner.dart';
import 'widgets/alert_card.dart';
import 'widgets/case_list.dart';
import 'widgets/context_chips.dart';
import 'widgets/coverage_ranking.dart';
import 'widgets/cross_ward_warning.dart';
import 'widgets/epi_curve.dart';
import 'widgets/guardrails.dart';
import 'widgets/organism_mix.dart';
import 'widgets/patient_history.dart';
import 'widgets/resistance_trend.dart';
import 'widgets/sampling_volume.dart';
import 'widgets/spreading_counts.dart';
import 'widgets/ward_status.dart';
import 'widgets/window_compare.dart';

/// Every widget the app, a saved dashboard or the AI can place. Names match
/// backend/app/widgets/catalog.py; add a widget there and here together.
WidgetCatalog buildCatalog() => WidgetCatalog([
  // For the patient in front of you
  contextChipsEntry,
  coverageRankingEntry,
  organismMixEntry,
  windowCompareEntry,
  alertBannerEntry,
  patientHistoryEntry,
  // Wards, the lab and research
  spreadingCountsEntry,
  crossWardWarningEntry,
  wardStatusEntry,
  alertCardEntry,
  epiCurveEntry,
  samplingVolumeEntry,
  caseListEntry,
  resistanceTrendEntry,
  // Limits and explanations
  notInThisDataEntry,
  outsideScopeEntry,
  explainEntry,
]);

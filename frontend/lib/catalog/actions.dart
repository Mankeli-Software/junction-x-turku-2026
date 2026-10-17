import '../core/models/common.dart';

/// What a catalog widget can ask the app to do. Widgets never import the router: the app
/// provides an implementation, and the chat can later map these to A2UI user actions.
abstract interface class CatalogActions {
  /// Open the answer page for a described patient.
  void openAnswer(PatientProfile profile);

  /// Back to the patient form, pre-filled.
  void editPatient(PatientProfile profile);

  /// An empty patient form.
  void newPatient();

  void openAlert(String alertId);

  /// Hand a question to the chat; with [patient], the chat answers about that patient
  /// (follow-ups from an answer page).
  void ask(String question, {PatientProfile? patient});

  /// Research Explore with these `ResistanceTrend` params as its filters.
  void openResearch([Json params = const {}]);

  /// Infection control: resistant bacteria on every ward.
  void openInfectionControl();

  /// The lab's alert inbox.
  void openLab();
}

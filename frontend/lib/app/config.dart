/// Build-time settings, passed with `--dart-define`.
abstract final class AppConfig {
  /// Backend base URL, e.g. `http://localhost:8000`.
  static const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8000');

  /// `--dart-define=FIXTURES=true` serves saved responses from assets/fixtures instead.
  static const useFixtures = bool.fromEnvironment('FIXTURES');
}

import 'models/alerts.dart';
import 'models/common.dart';
import 'models/dashboard.dart';
import 'models/data.dart';
import 'models/patient.dart';
import 'api/transport.dart';
import 'models/vocab.dart';

/// Typed access to every backend function (`GET /v1/functions`), one method per function.
///
/// GET responses are cached by path and query for the session: going back, switching tabs or
/// two widgets asking the same question cost one request. The data only changes with
/// `as_of`, which is part of every query.
class AmrRepository {
  AmrRepository(this._transport, {ApiTransport? pending})
    : _pending = pending ?? FixtureTransport();

  final ApiTransport _transport;

  /// Serves functions the backend does not have yet, from assets/fixtures.
  final ApiTransport _pending;
  final Map<String, Future<Object?>> _cache = {};

  Future<T> _get<T>(String path, Json query, T Function(Json) parse, {ApiTransport? via}) async {
    final key =
        '$path?${(query.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).join('&')}';
    final future = _cache[key] ??= (via ?? _transport).get(path, query);
    try {
      return parse((await future)! as Json);
    } catch (_) {
      _cache.remove(key); // never cache failures
      rethrow;
    }
  }

  void clearCache() => _cache.clear();

  // Data
  Future<OrganismMix> organisms(OrganismMixQuery q) =>
      _get('/v1/organisms', q.toQuery(), OrganismMix.fromJson);

  Future<Coverage> coverage(CoverageQuery q) =>
      _get('/v1/coverage', q.toQuery(), Coverage.fromJson);

  Future<Susceptibility> susceptibility(SusceptibilityQuery q) =>
      _get('/v1/susceptibility', q.toQuery(), Susceptibility.fromJson);

  Future<Series> series(SeriesQuery q) =>
      _get('/v1/susceptibility/series', q.toQuery(), Series.fromJson);

  // Alerts and surveillance
  Future<Alerts> alerts(AlertsQuery q) => _get('/v1/alerts', q.toQuery(), Alerts.fromJson);

  Future<AlertDetail> alertDetail(AlertDetailQuery q) =>
      _get('/v1/alerts/detail', q.toQuery(), AlertDetail.fromJson);

  Future<Volume> volume(VolumeQuery q) => _get('/v1/volume', q.toQuery(), Volume.fromJson);

  Future<Spreading> spreading(SpreadingQuery q) =>
      _get('/v1/spreading', q.toQuery(), Spreading.fromJson);

  Future<SpreadingSeries> spreadingSeries(SpreadingSeriesQuery q) =>
      _get('/v1/spreading/series', q.toQuery(), SpreadingSeries.fromJson);

  Future<WardLinks> wardLinks(WardLinksQuery q) =>
      _get('/v1/ward-links', q.toQuery(), WardLinks.fromJson);

  // Not in the backend yet: served from fixtures (see [_pending]).
  Future<PatientHistory> patientHistory(PatientHistoryQuery q) async => (await _get(
    '/v1/patient-history',
    q.toQuery(),
    PatientHistory.fromJson,
    via: _pending,
  )).upTo(q.asOf ?? dataEnd);

  // Dashboard: not cached, it is the user's own state.
  Future<Dashboard> dashboard(String userId) async =>
      Dashboard.fromJson((await _transport.get('/v1/dashboard', {'user_id': userId}))! as Json);

  Future<Dashboard> saveDashboard(Dashboard d) async =>
      Dashboard.fromJson((await _transport.put('/v1/dashboard', d.toJson()))! as Json);
}

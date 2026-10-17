import 'dart:convert';
import 'dart:io';

import 'package:amiright/core/models/alerts.dart';
import 'package:amiright/core/models/common.dart';
import 'package:amiright/core/models/dashboard.dart';
import 'package:amiright/core/models/data.dart';
import 'package:amiright/core/models/vocab.dart';
import 'package:flutter_test/flutter_test.dart';

/// assets/fixtures holds real backend responses; every model must parse them.
Json fixture(String name) =>
    jsonDecode(File('assets/fixtures/$name.json').readAsStringSync()) as Json;

void main() {
  test('every fixture parses into its model', () {
    final coverage = Coverage.fromJson(fixture('coverage'));
    expect(coverage.recent.options, isNotEmpty);
    expect(coverage.annual.window.window, '365d');

    expect(OrganismMix.fromJson(fixture('organisms')).organisms, isNotEmpty);
    expect(Susceptibility.fromJson(fixture('susceptibility')).recent.rows, isNotEmpty);
    expect(Series.fromJson(fixture('susceptibility_series')).series, isNotEmpty);
    final alerts = Alerts.fromJson(fixture('alerts')).alerts;
    expect(alerts, isNotEmpty);
    // A hospital-wide trend alert has no ward.
    expect(alerts.where((a) => a.type == AlertType.trend).first.ward, isNull);
    expect(AlertDetail.fromJson(fixture('alerts_detail')).epiCurve, isNotEmpty);
    expect(Spreading.fromJson(fixture('spreading')).rows, isNotEmpty);
    expect(WardLinks.fromJson(fixture('ward_links')).links, isNotEmpty);
    expect(Volume.fromJson(fixture('volume')).rows, isNotEmpty);
    expect(Dashboard.fromJson(fixture('dashboard')).layout, isNotEmpty);
  });

  test('queries encode codes, dates and lists as the backend expects', () {
    final q = CoverageQuery(
      profile: const PatientProfile(
        ward: Ward.uro,
        infectionType: InfectionType.uti,
        sex: Sex.female,
        ageBand: AgeBand.a75,
        onset: Onset.hospital,
      ),
      window: WindowSpec(asOf: DateTime.utc(2025, 6, 30)),
    );
    expect(q.toQuery(), {
      'as_of': '2025-06-30',
      'window': '28d',
      'ward': 'URO',
      'infection_type': 'uti',
      'sex': 'F',
      'age_band': '75+',
      'onset': 'hospital',
      'max_regimen_size': '2',
    });
    expect(const SpreadingQuery(wards: [Ward.icu, Ward.uro]).toQuery()['wards'], ['ICU', 'URO']);
  });

  test('AI params round-trip through the query models', () {
    final params = {'ward': 'ICU', 'infection_type': 'sepsis', 'window': '365d'};
    final q = CoverageQuery.fromJson(params);
    expect(q.profile.effectiveSpecimen, Specimen.blood);
    expect(q.window.window, TimeWindow.d365);
    expect(q.resolve(dataEnd).toQuery()['as_of'], '2026-09-27');
  });
}

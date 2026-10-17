import 'dart:convert';
import 'dart:io';

import 'package:amiright/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('renders the coverage fixture from the API', (tester) async {
    // test/coverage_fixture.json is a saved response of GET /v1/coverage.
    final body = File('test/coverage_fixture.json').readAsStringSync();
    final client = MockClient((_) async => http.Response(body, 200, headers: {'content-type': 'application/json'}));
    expect(jsonDecode(body), isA<Map>());

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CoverageRanking(query: const {'ward': 'URO'}, client: client))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Coverage URO'), findsOneWidget);
    expect(find.text('NIT'), findsOneWidget);
    expect(find.textContaining('Narrowest effective: NIT'), findsOneWidget);
  });
}

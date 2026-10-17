import 'dart:async';

import 'package:amiright/core/api/transport.dart';
import 'package:amiright/core/models/alerts.dart';
import 'package:amiright/core/models/vocab.dart';
import 'package:amiright/core/query/query_view.dart';
import 'package:amiright/core/repository.dart';
import 'package:amiright/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('new numbers loading over old ones say so, after a moment', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    final session = await SessionCubit.restore();
    final pending = <Completer<String>>[];
    Widget view(Ward ward) => MultiRepositoryProvider(
      providers: [RepositoryProvider(create: (_) => AmrRepository(FixtureTransport()))],
      child: BlocProvider.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            body: QueryView<AlertsQuery, String>(
              query: AlertsQuery(ward: ward),
              fetch: (_, q) => (pending..add(Completer())).last.future,
              builder: (_, text) => SizedBox(height: 200, child: Text(text)),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(view(Ward.uro));
    pending.last.complete('Urology numbers');
    await tester.pump();
    expect(find.text('Urology numbers'), findsOneWidget);
    expect(find.text('Updating…'), findsNothing);

    await tester.pumpWidget(view(Ward.icu)); // a filter changed: a new load starts
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Updating…'), findsNothing, reason: 'a quick answer must not flicker');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Updating…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Urology numbers'), findsOneWidget); // the old numbers stay, dimmed

    pending.last.complete('ICU numbers');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ICU numbers'), findsOneWidget);
    expect(find.text('Updating…'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}

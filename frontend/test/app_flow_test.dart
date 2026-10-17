import 'package:amiright/app/app.dart';
import 'package:amiright/core/api/transport.dart';
import 'package:amiright/session/session_cubit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('pick a user, describe the patient, see the answer', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = await SessionCubit.restore();
    await tester.pumpWidget(
      AmrApp(
        session: session,
        transport: FixtureTransport(latency: Duration.zero),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Who is using it today?'), findsOneWidget);

    await tester.tap(find.text('Continue as Aino Virtanen'));
    await tester.pumpAndSettle();
    expect(find.text('Who is your patient?'), findsOneWidget);
    expect(find.text('Step 4 of 5'), findsOneWidget);

    // Pick "Sepsis" with the keyboard: it moves on to the last word.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pumpAndSettle();
    expect(find.text('Step 5 of 5'), findsOneWidget);

    await tester.tap(find.text('Show what works'));
    await tester.pumpAndSettle();
    expect(find.text('Selected patient'), findsOneWidget);
    expect(find.text('All antibiotics'), findsOneWidget);
    expect(find.textContaining('not a prescription'), findsOneWidget);
  });
}

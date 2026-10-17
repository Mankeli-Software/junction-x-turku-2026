import 'package:amiright/app/app.dart';
import 'package:amiright/core/api/transport.dart';
import 'package:amiright/features/chat/widgets/chat_blocks.dart';
import 'package:amiright/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canned_agent.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [text] in the conversation itself (the history panel repeats a chat's first question).
Finder inBubble(String text) =>
    find.descendant(of: find.byType(UserBubble), matching: find.text(text));

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
        agent: CannedAgent.new,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Who is using it today?'), findsOneWidget);

    await tester.tap(find.text('Continue as Aino Virtanen'));
    await tester.pumpAndSettle();
    expect(find.text('Who is your patient?'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    // A new patient starts blank: each word shows its category, nothing is chosen.
    expect(find.text('sex'), findsOneWidget);
    expect(find.text('where'), findsOneWidget);
    // No answer button until every word is set.
    expect(find.text('Show what works'), findsNothing);

    // Five picks with the keyboard: woman, 75+, Urology, sepsis, in hospital.
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit2,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(find.text('All set'), findsOneWidget);
    expect(find.text('Show what works'), findsOneWidget);

    // Enter shows the answer.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Selected patient'), findsOneWidget);
    expect(find.text('All antibiotics'), findsOneWidget);
    expect(find.textContaining('not a prescription'), findsOneWidget);

    // "New patient" starts over: a fresh form on the first word, no answer button.
    await tester.tap(find.text('New patient'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('All set'), findsNothing);
  });

  testWidgets('not sure of the infection: the form hands over to the chat', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'flutter.session.user': 'aino'});
    final session = await SessionCubit.restore();
    await tester.pumpWidget(
      AmrApp(
        session: session,
        transport: FixtureTransport(latency: Duration.zero),
        agent: CannedAgent.new,
      ),
    );
    await tester.pumpAndSettle();

    // Woman, 75+, Urology, then "Not sure? Ask the AI" (key 5 on the infection step).
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit1,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(find.text('Not sure? Ask the AI'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await settle();
    expect(
      inBubble(
        "My patient is a woman aged 75+ on Urology. I'm not sure what kind of infection it is.",
      ),
      findsOneWidget,
    );
    expect(find.text('Which infection do you suspect?'), findsOneWidget);

    await tester.tap(find.text('Urinary tract (urine)'));
    await settle();
    await tester.tap(find.text('In hospital, day 3 or later').first);
    await settle();
    expect(find.text('Selected patient · tap to change'), findsOneWidget);
  });

  testWidgets('the ask field opens a composer: Esc keeps the draft, Enter asks', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'flutter.session.user': 'aino'});
    final session = await SessionCubit.restore();
    await tester.pumpWidget(
      AmrApp(
        session: session,
        transport: FixtureTransport(latency: Duration.zero),
        agent: CannedAgent.new,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.text('Ask the AI'), findsOneWidget);
    expect(find.text('Try asking'), findsOneWidget);

    // Esc puts the field back with what was typed; the form is untouched.
    await tester.enterText(find.byType(TextField).last, 'woman over 75 with a UTI');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Ask the AI'), findsNothing);
    expect(find.text('woman over 75 with a UTI'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);

    // Open again and send: the chat opens with the question.
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Ask the AI'), findsNothing);
    expect(inBubble('woman over 75 with a UTI'), findsOneWidget);
    expect(find.text('Who is your patient?'), findsNothing);
  });
}

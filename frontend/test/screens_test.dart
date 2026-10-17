import 'package:amiright/app/app.dart';
import 'package:amiright/core/api/transport.dart';
import 'package:amiright/session/session_cubit.dart';
import 'package:amiright/features/chat/widgets/ask_launcher.dart';
import 'package:amiright/features/chat/widgets/chat_blocks.dart';
import 'package:amiright/features/chat/widgets/chat_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the app on fixtures as [user] at [size] and opens [path].
Future<void> open(
  WidgetTester tester,
  String user,
  String path, {
  Size size = const Size(1440, 2400),
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  // The test font draws every glyph as a wide square, so text overflows that never happen with
  // Inter; layout is checked in the browser screenshots instead. Every other error still fails.
  final onError = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    onError?.call(d);
  };
  addTearDown(() => FlutterError.onError = onError);
  SharedPreferences.setMockInitialValues({'flutter.session.user': user});
  tester.view.physicalSize = size;
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
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(path);
  // Not pumpAndSettle: the gallery's "Building" sample animates forever.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  for (final size in const [Size(1440, 2400), Size(390, 2400)]) {
    final tag = size.width < 768 ? 'phone' : 'desktop';

    testWidgets('every role screen renders ($tag)', (tester) async {
      await open(tester, 'sanna', '/hygiene', size: size);
      expect(find.text('What is spreading'), findsWidgets);
      await open(tester, 'elina', '/lab', size: size);
      expect(find.textContaining('alert'), findsWidgets);
      await open(tester, 'elina', '/lab/alerts/trend-escherichia-coli-TMP', size: size);
      await open(tester, 'tomi', '/research', size: size);
      expect(find.text('Explore the data'), findsWidgets);
      await open(tester, 'jari', '/hygiene', size: size);
    });

    testWidgets('infection control visual version renders ($tag)', (tester) async {
      await open(tester, 'sanna', '/hygiene', size: size);
      expect(find.text('What is spreading'), findsWidgets);
      expect(find.text('All wards'), findsOneWidget);
      expect(find.textContaining('Ward detail'), findsOneWidget);
      expect(find.textContaining('Early warning'), findsOneWidget);
      await tester.tap(find.text('Geriatrics').first);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('Geriatrics'), findsWidgets);
    });

    testWidgets('component gallery builds every widget ($tag)', (tester) async {
      await open(tester, 'aino', '/components', size: size);
      expect(find.text('What the AI can place'), findsOneWidget);
      expect(find.textContaining('is not in the catalog'), findsNothing);
    });
  }

  testWidgets('chat: a patient question asks for the onset, then answers', (tester) async {
    await open(
      tester,
      'aino',
      '/chat?q=My 80-year-old female patient on Urology has a UTI. What works?',
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Did the infection start at home or in hospital?'), findsOneWidget);
    await tester.tap(find.text('In hospital, day 3 or later').first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Selected patient · tap to change'), findsOneWidget);
    expect(find.text('Pin to my home'), findsOneWidget);
  });

  testWidgets('chat: limits are answered calmly', (tester) async {
    await open(tester, 'aino', '/chat?q=What dose of piperacillin-tazobactam should I give?');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('I can’t suggest doses or prescribe.'), findsOneWidget);
  });

  testWidgets('ask fields open a composer that knows where it was opened', (tester) async {
    Future<void> openComposer() async {
      final field = find.descendant(
        of: find.byType(AskLauncher).first,
        matching: find.byType(TextField),
      );
      // Centred, so a long page does not park the field under the pinned top bar.
      await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(field);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    await open(tester, 'sanna', '/hygiene');
    await openComposer();
    expect(find.text('Ask about spreading'), findsOneWidget);
    expect(find.text('Which wards should we warn?'), findsOneWidget);

    // From an answer, the follow-up is answered for the same patient.
    await open(
      tester,
      'aino',
      '/doctor/answer?ward=URO&infection_type=uti&sex=F&age_band=75%2B&onset=hospital',
    );
    await openComposer();
    expect(find.text('Ask about this patient'), findsOneWidget);
    expect(find.text('What if she is allergic to penicillin?'), findsOneWidget);
    await tester.tap(find.text('Only oral options').last);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.textContaining('oral options only'), findsOneWidget);
  });

  testWidgets('chat: a question from outside starts a new chat; the old one is in the history', (
    tester,
  ) async {
    await open(tester, 'aino', '/chat?q=What is causing UTIs now?');
    await tester.pump(const Duration(seconds: 3));
    final bubble = find.byType(UserBubble);
    Finder asked(String q) => find.descendant(of: bubble, matching: find.text(q));
    expect(asked('What is causing UTIs now?'), findsOneWidget);

    GoRouter.of(
      tester.element(find.byType(Navigator).first),
    ).go('/chat?q=Is trimethoprim still OK?');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(asked('Is trimethoprim still OK?'), findsOneWidget);
    expect(asked('What is causing UTIs now?'), findsNothing);

    // The first chat waits in the history panel and opens again.
    await tester.tap(
      find.descendant(
        of: find.byType(ChatHistory),
        matching: find.text('What is causing UTIs now?'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(asked('What is causing UTIs now?'), findsOneWidget);
    expect(asked('Is trimethoprim still OK?'), findsNothing);

    // New chat: back to the welcome.
    await tester.tap(find.text('New chat'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(bubble, findsNothing);
    expect(find.text('Recent chats'), findsOneWidget);
  });
}

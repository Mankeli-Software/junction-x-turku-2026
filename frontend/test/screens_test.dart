import 'package:amiright/app/app.dart';
import 'package:amiright/core/api/transport.dart';
import 'package:amiright/session/session_cubit.dart';
import 'package:flutter/widgets.dart';
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
}

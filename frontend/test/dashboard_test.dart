import 'package:amiright/app/app.dart';
import 'package:amiright/core/api/transport.dart';
import 'package:amiright/core/models/dashboard.dart';
import 'package:amiright/features/dashboard/widget_agent.dart';
import 'package:amiright/features/dashboard/widget_settings.dart';
import 'package:amiright/features/research/research_cubit.dart';
import 'package:amiright/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canned_agent.dart';

/// Suggests a sampling-volume widget, then asks a question, in turn.
class _FakeWidgetAgent implements WidgetAgent {
  final messages = <String>[];
  final contexts = <WidgetAgentContext>[];

  @override
  Stream<WidgetAgentEvent> suggest(String message, WidgetAgentContext context) async* {
    messages.add(message);
    contexts.add(context);
    yield const WidgetAgentStatus('Checking how many cultures were sent…');
    yield const WidgetProposal(
      WidgetPlacement(widget: 'SamplingVolume', params: {'ward': 'URO'}),
      why: 'Shows whether a change on Urology is more testing or more cases.',
    );
  }
}

class _OffWidgetAgent implements WidgetAgent {
  @override
  Stream<WidgetAgentEvent> suggest(String message, WidgetAgentContext context) async* {
    yield const WidgetAgentUnavailable();
  }
}

Future<void> _open(WidgetTester tester, WidgetAgent agent, {String path = '/doctor'}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final onError = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    onError?.call(d);
  };
  addTearDown(() => FlutterError.onError = onError);
  SharedPreferences.setMockInitialValues({'flutter.session.user': 'aino'});
  tester.view.physicalSize = const Size(1440, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = await SessionCubit.restore();
  await tester.pumpWidget(
    AmrApp(
      session: session,
      transport: FixtureTransport(latency: Duration.zero),
      agent: CannedAgent.new,
      widgetAgent: agent,
    ),
  );
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(path);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('the default home links to the answer, Research, the lab and infection control', (
    tester,
  ) async {
    await _open(tester, _FakeWidgetAgent());
    expect(find.text('Pinned for you'), findsOneWidget);
    for (final link in const [
      'Open full answer',
      'Open in Research',
      'Open the lab inbox',
      'Open infection control',
    ]) {
      expect(find.text(link), findsOneWidget, reason: link);
    }

    await tester.ensureVisible(find.text('Open in Research'));
    await tester.tap(find.text('Open in Research'));
    await _settle(tester);
    final research = tester.element(find.text('Filters').first).read<ResearchCubit>();
    expect(research.state.filters.drug.code, 'TMP');
    expect(research.state.filters.ward?.code, 'URO');
  });

  testWidgets('the AI suggests a widget and adds it only when the user says so', (tester) async {
    final agent = _FakeWidgetAgent();
    await _open(tester, agent);
    expect(find.text('Testing volume'), findsNothing);

    final field = find.widgetWithText(TextField, 'e.g. MRSA on my ward this year');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Is Urology just testing more?');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);

    expect(agent.messages, ['Is Urology just testing more?']);
    expect(agent.contexts.single.layout, hasLength(4)); // the agent knows what is pinned
    expect(find.text('Add this to your home page?'), findsOneWidget);
    expect(find.textContaining('more testing or more cases'), findsOneWidget);

    await tester.tap(find.text('Something else'));
    await _settle(tester);
    expect(agent.messages.last, 'Show me something else');
    expect(agent.contexts.last.history.first, ('user', 'Is Urology just testing more?'));
    expect(agent.contexts.last.history[1].$2, startsWith('Proposed SamplingVolume'));

    await tester.tap(find.text('Add to my home'));
    await _settle(tester);
    expect(find.text('Add this to your home page?'), findsNothing); // the dialog closed
    expect(find.text('Just added'), findsOneWidget);
    expect(find.text('Added to your home'), findsOneWidget);
    // It has an Undo action, yet it still goes away by itself.
    await tester.pump(const Duration(seconds: 6));
    await _settle(tester);
    expect(find.text('Added to your home'), findsNothing);
  });

  testWidgets('a pinned widget\'s settings can be changed by hand', (tester) async {
    await _open(tester, _FakeWidgetAgent());
    expect(find.text('E. coli · Trimethoprim · Urology'), findsOneWidget);

    // The trend is the third card; its settings button opens the editor.
    await tester.tap(find.byTooltip('Edit settings').at(2));
    await _settle(tester);
    expect(find.text('Widget settings'), findsOneWidget);
    expect(find.text('Preview · live data'), findsOneWidget);

    await tester.tap(
      find.descendant(of: find.byType(PillSelect), matching: find.text('Trimethoprim')),
    );
    await _settle(tester);
    await tester.ensureVisible(find.text('Ciprofloxacin').last); // the menu scrolls
    await _settle(tester);
    await tester.tap(find.text('Ciprofloxacin').last);
    await _settle(tester);
    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(find.text('E. coli · Ciprofloxacin · Urology'), findsOneWidget);
    expect(find.text('E. coli · Trimethoprim · Urology'), findsNothing);
  });

  testWidgets('edit layout moves and removes cards', (tester) async {
    await _open(tester, _FakeWidgetAgent());
    await tester.tap(find.text('Edit layout'));
    await _settle(tester);
    expect(find.text('Reset to default'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove from home').first);
    await _settle(tester);
    expect(find.text('UTI · Urology'), findsNothing);
    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(find.text('Edit layout'), findsOneWidget);
  });

  testWidgets('without the AI the dialog offers the catalog', (tester) async {
    await _open(tester, _OffWidgetAgent());
    await tester.tap(find.text('+ Add widget'));
    await _settle(tester);
    await tester.tap(find.text('What works for a UTI on my ward?').last);
    await _settle(tester);
    expect(find.text('AI suggestions are off right now'), findsOneWidget);
    await tester.tap(find.text('+ Resistance trend').last);
    await _settle(tester);
    expect(find.text('Add to your home'), findsOneWidget);
    expect(find.text('Add to my home'), findsOneWidget);
  });
}

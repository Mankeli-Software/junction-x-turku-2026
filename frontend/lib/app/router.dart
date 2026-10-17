import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../catalog/actions.dart';
import '../core/models/common.dart';
import '../core/models/vocab.dart';
import '../features/doctor/doctor_answer_page.dart';
import '../features/doctor/doctor_home_page.dart';
import '../features/login/login_page.dart';
import '../features/chat/chat_page.dart';
import '../features/components/components_page.dart';
import '../features/hygiene/hygiene_page.dart';
import '../features/lab/lab_page.dart';
import '../features/research/research_page.dart';
import '../session/session_cubit.dart';

abstract final class Routes {
  static const login = '/login';
  static const doctor = '/doctor';
  static const answer = '/doctor/answer';
  static const hygiene = '/hygiene';
  static const lab = '/lab';
  static const research = '/research';
  static const chat = '/chat';
  static const components = '/components';

  static String alert(String id) => '$lab/alerts/$id';

  static String homeFor(Role role) => switch (role) {
    Role.doctor => doctor,
    Role.hygiene || Role.careWorker => hygiene,
    Role.lab => lab,
    Role.researcher => research,
  };
}

/// Fade-through: the page fades in while rising 8px.
CustomTransitionPage<void> _page(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 260),
  reverseTransitionDuration: const Duration(milliseconds: 180),
  transitionsBuilder: (context, a, _, child) {
    final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.008), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  },
);

/// The patient travels in the URL (`/doctor/answer?ward=URO&infection_type=uti…`), so an
/// answer can be linked, reloaded and opened by the chat.
PatientProfile _profileOf(GoRouterState s) => PatientProfile.fromJson(s.uri.queryParameters);

GoRouter buildRouter(SessionCubit session) {
  return GoRouter(
    initialLocation: Routes.login,
    refreshListenable: _SignInListenable(session),
    redirect: (context, state) {
      final user = session.state.user;
      final at = state.matchedLocation;
      if (user == null) return at == Routes.login ? null : Routes.login;
      if (at == Routes.login || at == '/') return Routes.homeFor(user.role);
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => Routes.login),
      GoRoute(path: Routes.login, pageBuilder: (_, s) => _page(s, const LoginPage())),
      GoRoute(
        path: Routes.doctor,
        pageBuilder: (_, s) =>
            _page(s, DoctorHomePage(initial: s.uri.queryParameters.isEmpty ? null : _profileOf(s))),
      ),
      // A sibling, not a child of /doctor: a child would keep the home page (and its filled-in
      // form) alive underneath, so "New patient" would come back to the old patient.
      GoRoute(
        path: Routes.answer,
        pageBuilder: (_, s) => _page(s, DoctorAnswerPage(profile: _profileOf(s))),
      ),
      GoRoute(path: Routes.hygiene, pageBuilder: (_, s) => _page(s, const HygienePage())),
      GoRoute(
        path: Routes.lab,
        pageBuilder: (_, s) => _page(s, const LabPage()),
        routes: [
          GoRoute(
            path: 'alerts/:id',
            pageBuilder: (_, s) => _page(s, LabPage(alertId: s.pathParameters['id'])),
          ),
        ],
      ),
      GoRoute(path: Routes.research, pageBuilder: (_, s) => _page(s, const ResearchPage())),
      GoRoute(
        path: Routes.chat,
        pageBuilder: (_, s) => _page(s, ChatPage(question: s.uri.queryParameters['q'])),
      ),
      GoRoute(path: Routes.components, pageBuilder: (_, s) => _page(s, const ComponentsPage())),
    ],
  );
}

/// Re-runs the redirect only when someone signs in or out, not on every replay-date change.
class _SignInListenable extends ChangeNotifier {
  _SignInListenable(SessionCubit session) {
    var signedIn = session.state.signedIn;
    _sub = session.stream.listen((s) {
      if (s.signedIn != signedIn) {
        signedIn = s.signedIn;
        notifyListeners();
      }
    });
  }

  late final StreamSubscription<SessionState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// [CatalogActions] backed by the router.
class RouterCatalogActions implements CatalogActions {
  RouterCatalogActions(this._router);

  final GoRouter _router;

  @override
  void openAnswer(PatientProfile profile) =>
      _router.go(Uri(path: Routes.answer, queryParameters: _params(profile)).toString());

  @override
  void editPatient(PatientProfile profile) =>
      _router.go(Uri(path: Routes.doctor, queryParameters: _params(profile)).toString());

  @override
  void newPatient() => _router.go(Routes.doctor);

  @override
  void openAlert(String alertId) => _router.go(Routes.alert(alertId));

  /// Every "Ask" field in the app hands its question to the chat.
  @override
  void ask(String question) =>
      _router.go(Uri(path: Routes.chat, queryParameters: {'q': question}).toString());

  Map<String, String> _params(PatientProfile p) => p.toQuery().cast<String, String>();
}

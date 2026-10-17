import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../catalog/actions.dart';
import '../catalog/catalog.dart';
import '../catalog/default_catalog.dart';
import '../core/api/transport.dart';
import '../core/repository.dart';
import '../ds/ds.dart';
import '../features/chat/agent/chat_agent.dart';
import '../features/chat/agent/remote_agent.dart';
import '../features/chat/answer_catalog.dart';
import '../features/chat/chat_cubit.dart';
import '../features/dashboard/dashboard_cubit.dart';
import '../session/session_cubit.dart';
import 'config.dart';
import 'router.dart';

/// Wires the app: repository, widget catalog, actions, session and the user's dashboard.
class AmrApp extends StatefulWidget {
  const AmrApp({super.key, required this.session, this.transport, this.agent});

  final SessionCubit session;

  /// Override for tests; defaults to HTTP, or fixtures with `--dart-define=FIXTURES=true`.
  final ApiTransport? transport;

  /// Override for tests; defaults to the Claude agent on the backend. With no backend (fixture
  /// mode) it cannot be reached, and the chat offers the quick patient form instead.
  final ChatAgent Function()? agent;

  @override
  State<AmrApp> createState() => _AmrAppState();
}

class _AmrAppState extends State<AmrApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final ApiTransport _transport =
      widget.transport ??
      (AppConfig.useFixtures ? FixtureTransport() : HttpTransport(AppConfig.apiBase));
  late final AmrRepository _repo = AmrRepository(_transport);
  late final GoRouter _router = buildRouter(widget.session);
  late final CatalogActions _actions = RouterCatalogActions(_router);
  final WidgetCatalog _catalog = buildCatalog();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: _repo),
        RepositoryProvider.value(value: _catalog),
        RepositoryProvider.value(value: _actions),
      ],
      child: BlocProvider.value(
        value: widget.session,
        child: MaterialApp.router(
          title: 'AMRight',
          debugShowCheckedModeBanner: false,
          theme: buildAmrTheme(),
          scaffoldMessengerKey: _messenger,
          routerConfig: _router,
          builder: (context, child) => _UserScope(
            newAgent: widget.agent ?? () => RemoteAgent(AppConfig.apiBase),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Gives every screen the signed-in user's dashboard and conversation, rebuilt per user.
///
/// The chat asks the Claude agent on the backend ([RemoteAgent], #12), whose answers are A2UI
/// that genui renders from the chat catalog.
class _UserScope extends StatelessWidget {
  const _UserScope({required this.newAgent, required this.child});

  final ChatAgent Function() newAgent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = context.select((SessionCubit c) => c.state.user);
    if (user == null) return child;
    return MultiBlocProvider(
      key: ValueKey(user.id),
      providers: [
        BlocProvider(
          create: (context) => DashboardCubit(context.read<AmrRepository>(), user)..load(),
        ),
        BlocProvider(
          create: (context) => ChatCubit(
            newAgent,
            context.read<SessionCubit>(),
            catalog: buildGenUiCatalog(context.read<WidgetCatalog>()),
          ),
        ),
      ],
      child: child,
    );
  }
}

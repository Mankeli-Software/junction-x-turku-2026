import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../ds/ds.dart';
import '../../session/session_cubit.dart';
import '../api/transport.dart';
import '../models/data.dart';
import '../repository.dart';
import 'query_cubit.dart';

/// Loads [query] through the repository and builds [builder] with the result.
///
/// The query is stamped with the session's replay date (unless it sets its own `as_of`) and
/// reloads when either changes. While reloading the previous result stays on screen, dimmed.
class QueryView<Q extends AsOfQuery<Q>, T> extends StatefulWidget {
  const QueryView({
    super.key,
    required this.query,
    required this.fetch,
    required this.builder,
    this.loading,
    this.errorMessage = 'Could not load this right now.',
    this.error,
  });

  final Q query;
  final Future<T> Function(AmrRepository repo, Q query) fetch;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loading;
  final String errorMessage;

  /// Replaces the inline error and its retry, for content that can go without (the AI's line).
  final Widget Function(BuildContext context, Object error)? error;

  @override
  State<QueryView<Q, T>> createState() => _QueryViewState<Q, T>();
}

class _QueryViewState<Q extends AsOfQuery<Q>, T> extends State<QueryView<Q, T>> {
  final _cubit = QueryCubit<T>();
  Q? _last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(QueryView<Q, T> old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  void _load({bool force = false}) {
    final q = widget.query.resolve(context.read<SessionCubit>().state.asOf);
    if (!force && q == _last) return;
    _last = q;
    final repo = context.read<AmrRepository>();
    _cubit.load(() => widget.fetch(repo, q));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SessionCubit, SessionState>(
      listenWhen: (a, b) => a.asOf != b.asOf,
      listener: (_, _) => _load(),
      child: BlocBuilder<QueryCubit<T>, QueryState<T>>(
        bloc: _cubit,
        builder: (context, s) {
          final Widget child;
          if (s.hasData) {
            child = AnimatedOpacity(
              key: const ValueKey('data'),
              opacity: s.loading ? 0.55 : 1,
              duration: AmrMotion.base,
              child: widget.builder(context, s.data as T),
            );
          } else if (s.error != null && widget.error != null) {
            child = KeyedSubtree(
              key: const ValueKey('error'),
              child: widget.error!(context, s.error!),
            );
          } else if (s.error != null) {
            final e = s.error;
            child = InlineError(
              key: const ValueKey('error'),
              message: e is ApiException && e.statusCode != null && e.statusCode! < 500
                  ? e.message
                  : widget.errorMessage,
              onRetry: () => _load(force: true),
            );
          } else {
            child = KeyedSubtree(
              key: const ValueKey('loading'),
              child: widget.loading ?? const SkeletonBlock(),
            );
          }
          return AnimatedSwitcher(
            duration: AmrMotion.base,
            switchInCurve: AmrMotion.curve,
            layoutBuilder: (current, previous) => Stack(
              // passthrough: the loaded widget fills its slot like a block element, so cards
              // stretch in rows and columns instead of shrink-wrapping their content.
              fit: StackFit.passthrough,
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: child,
          );
        },
      ),
    );
  }
}

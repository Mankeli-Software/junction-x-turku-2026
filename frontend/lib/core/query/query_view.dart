import 'dart:async';

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
    this.updatingLabel = true,
  });

  final Q query;
  final Future<T> Function(AmrRepository repo, Q query) fetch;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loading;
  final String errorMessage;

  /// Replaces the inline error and its retry, for content that can go without (the AI's line).
  final Widget Function(BuildContext context, Object error)? error;

  /// While new numbers load over old ones: the "Updating…" label as well as the bar. Off for a
  /// line of text the label would cover.
  final bool updatingLabel;

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
            // The same tree loading or not, so the content keeps its state between loads.
            child = Stack(
              key: const ValueKey('data'),
              fit: StackFit.passthrough,
              children: [
                AnimatedOpacity(
                  opacity: s.loading ? 0.55 : 1,
                  duration: AmrMotion.base,
                  child: widget.builder(context, s.data as T),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: _Updating(active: s.loading, label: widget.updatingLabel),
                  ),
                ),
              ],
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

/// Over content that is being replaced: a thin moving bar along the top and an "Updating…"
/// label, shown only when the load takes longer than [_delay], so remembered results that come
/// back at once do not flicker.
class _Updating extends StatefulWidget {
  const _Updating({required this.active, required this.label});

  final bool active;
  final bool label;

  @override
  State<_Updating> createState() => _UpdatingState();
}

class _UpdatingState extends State<_Updating> {
  static const _delay = Duration(milliseconds: 250);
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Updating old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    _timer?.cancel();
    if (!widget.active) {
      if (_shown) setState(() => _shown = false);
      return;
    }
    _timer = Timer(_delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: AmrMotion.base,
      // Not built until shown: an indeterminate bar animates every frame.
      child: !_shown
          ? const SizedBox.shrink()
          : Stack(
              children: [
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ClipRRect(
                    borderRadius: AmrRadius.pill,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: AmrColors.violet,
                      backgroundColor: AmrColors.lavenderPale,
                    ),
                  ),
                ),
                if (widget.label)
                  Positioned(
                    top: 10,
                    right: 0,
                    child: Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
                        decoration: const BoxDecoration(
                          color: AmrColors.white,
                          borderRadius: AmrRadius.pill,
                          boxShadow: AmrShadows.sm,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AmrColors.violet,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('Updating…', style: AmrText.body(13, weight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

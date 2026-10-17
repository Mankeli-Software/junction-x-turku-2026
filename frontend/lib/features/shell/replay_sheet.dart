import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/format.dart';
import '../../core/models/vocab.dart';
import '../../ds/ds.dart';
import '../../session/session_cubit.dart';

/// Weekly steps back from the end of the data.
final _weeks = dataEnd.difference(dataStart).inDays ~/ 7;

DateTime _dateAt(int step) => dataEnd.subtract(Duration(days: 7 * (_weeks - step)));

int _stepOf(DateTime d) => (_weeks - dataEnd.difference(d).inDays / 7).round().clamp(0, _weeks);

Future<void> showReplaySheet(BuildContext context) => showGeneralDialog(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: const Color(0x331D204E),
  transitionDuration: AmrMotion.base,
  pageBuilder: (_, _, _) => const _ReplayDialog(),
  transitionBuilder: (context, a, _, child) {
    final curved = CurvedAnimation(parent: a, curve: AmrMotion.curve);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
    );
  },
);

/// The replay slider: one week per step, from the first to the last day of the data. Every
/// number on every screen is computed as if today were the chosen date.
class _ReplayDialog extends StatefulWidget {
  const _ReplayDialog();

  @override
  State<_ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayDialogState extends State<_ReplayDialog> {
  late double _step = _stepOf(context.read<SessionCubit>().state.asOf).toDouble();

  void _commit() => context.read<SessionCubit>().setAsOf(_dateAt(_step.round()));

  @override
  Widget build(BuildContext context) {
    final date = _dateAt(_step.round());
    final live = _step.round() == _weeks;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: AmrColors.white,
            borderRadius: AmrRadius.panel,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: const BoxDecoration(
                borderRadius: AmrRadius.panel,
                boxShadow: AmrShadows.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Replay the data', style: AmrText.label(14)),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: AmrMotion.fast,
                    child: Text(
                      day(date),
                      key: ValueKey(date),
                      style: AmrText.sora(44, em: -0.035, height: 1.05),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    live
                        ? 'The latest data. Every number uses everything up to this day.'
                        : 'Every number is computed as if today were this day. '
                              'Nothing after it is used.',
                    style: AmrText.body(15, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                      showValueIndicator: ShowValueIndicator.never,
                    ),
                    child: Slider(
                      value: _step,
                      max: _weeks.toDouble(),
                      divisions: _weeks,
                      onChanged: (v) => setState(() => _step = v),
                      onChangeEnd: (_) => _commit(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(day(dataStart), style: AmrText.body(13)),
                        Text(day(dataEnd), style: AmrText.body(13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      AmrButton(
                        label: 'Latest data',
                        onPressed: live
                            ? null
                            : () {
                                setState(() => _step = _weeks.toDouble());
                                _commit();
                              },
                      ),
                      AmrButton(
                        label: 'Done',
                        variant: AmrButtonVariant.primary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../catalog/actions.dart';
import '../../../ds/ds.dart';
import '../ask_context.dart';

/// Every ask field in the app: tapping it opens a larger composer at the top of the page,
/// the field rising and growing while the page frosts over behind it. Enter (or a suggestion
/// from [about]) hands the question to the chat with [about]'s patient; Esc, a tap outside or
/// Cancel puts the field back, keeping what was typed.
class AskLauncher extends StatefulWidget {
  const AskLauncher({
    super.key,
    required this.hint,
    required this.about,
    this.size = AskFieldSize.medium,
    this.style = AskFieldStyle.elevated,
    this.accent = false,
  });

  final String hint;

  /// Where the field is: the composer's title, suggestions and the patient sent along.
  final AskContext about;
  final AskFieldSize size;
  final AskFieldStyle style;

  /// A violet send button, here and in the composer.
  final bool accent;

  @override
  State<AskLauncher> createState() => _AskLauncherState();
}

class _AskLauncherState extends State<AskLauncher> {
  final _controller = TextEditingController();
  final _key = GlobalKey();
  bool _open = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Where the inline field is now, so the composer leaves from and lands on it.
  Rect? _rect() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _ask(String question) =>
      context.read<CatalogActions>().ask(question, patient: widget.about.patient);

  Future<void> _expand() async {
    if (_open) return;
    final route = _ComposerRoute(
      text: _controller,
      source: _rect,
      hint: widget.hint,
      about: widget.about,
      accent: widget.accent,
      onSubmit: _ask,
    );
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    setState(() => _open = true);
    Navigator.of(context).push(route);
    await route.completed; // after the field has landed back in place
    if (!mounted) return;
    // The returning focus would select the kept draft; leave it as plain text instead.
    FocusManager.instance.primaryFocus?.unfocus();
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) => Opacity(
    // The composer stands in for the field while it is open.
    opacity: _open ? 0 : 1,
    child: AskField(
      key: _key,
      hint: widget.hint,
      size: widget.size,
      style: widget.style,
      accent: widget.accent,
      controller: _controller,
      onTap: _expand,
      onSubmit: _ask, // the send button with a kept draft asks it right away
    ),
  );
}

class _ComposerRoute extends PopupRoute<void> {
  _ComposerRoute({
    required this.text,
    required this.source,
    required this.hint,
    required this.about,
    required this.accent,
    required this.onSubmit,
  });

  final TextEditingController text;
  final Rect? Function() source;
  final String hint;
  final AskContext about;
  final bool accent;
  final ValueChanged<String> onSubmit;

  @override
  Color? get barrierColor => null; // the composer draws its own frosted backdrop

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Cancel';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 420);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> _) =>
      _Composer(route: this, animation: animation);
}

class _Composer extends StatefulWidget {
  const _Composer({required this.route, required this.animation});

  final _ComposerRoute route;
  final Animation<double> animation;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late final _t = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Where the field started; kept if the inline field goes away (e.g. on submit).
  Rect? _source;
  bool _sending = false;

  TextEditingController get _controller => widget.route.text;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_sending) return;
    Navigator.of(context).maybePop();
  }

  void _send([String? text]) {
    final t = (text ?? _controller.text).trim();
    if (t.isEmpty || _sending) return;
    if (text != null) _controller.text = text;
    setState(() => _sending = true);
    widget.route.onSubmit(t); // the chat page fades in over the composer
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final compact = context.isCompact;
    final side = compact ? 16.0 : context.gutter;
    final width = math.min(size.width - 2 * side, 880.0);
    final targetHeight = compact ? 64.0 : 80.0;
    final top = pad.top + (compact ? 64.0 : math.max(96.0, size.height * 0.16));
    final target = Rect.fromLTWH((size.width - width) / 2, top, width, targetHeight);

    return Material(
      type: MaterialType.transparency,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cancel},
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = _t.value;
            _source = widget.route.source() ?? _source;
            final from = _source ?? target.translate(0, 24);
            final rect = Rect.lerp(from, target, t)!;
            // Header and suggestions follow the field in, a beat behind it.
            final late = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _cancel,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10 * t, sigmaY: 10 * t),
                      child: ColoredBox(color: AmrColors.lavenderSoft.withValues(alpha: 0.8 * t)),
                    ),
                  ),
                ),
                Positioned(
                  left: target.left,
                  width: target.width,
                  bottom: size.height - target.top + (compact ? 14 : 20),
                  child: _Faded(
                    value: late,
                    child: _Header(about: widget.route.about, compact: compact, onCancel: _cancel),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: _Field(
                    controller: _controller,
                    hint: widget.route.hint,
                    t: t,
                    compact: compact,
                    enabled: !_sending,
                    accent: widget.route.accent,
                    onSend: _send,
                  ),
                ),
                Positioned(
                  left: target.left,
                  width: target.width,
                  top: target.bottom + (compact ? 16 : 22),
                  child: _Faded(
                    value: _sending ? 0 : late,
                    child: _Suggestions(
                      suggestions: widget.route.about.suggestions,
                      compact: compact,
                      onPick: _send,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fades in while rising 10px; ignores taps until it is visible.
class _Faded extends StatelessWidget {
  const _Faded({required this.value, required this.child});

  final double value;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: value < 0.5,
    child: Opacity(
      opacity: value,
      child: Transform.translate(offset: Offset(0, 10 * (1 - value)), child: child),
    ),
  );
}

/// "✦ Ask about this patient" and what the question is about on the left, Cancel on the right.
class _Header extends StatelessWidget {
  const _Header({required this.about, required this.compact, required this.onCancel});

  final AskContext about;
  final bool compact;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: compact ? 30 : 36,
        height: compact ? 30 : 36,
        decoration: const BoxDecoration(color: AmrColors.violet, shape: BoxShape.circle),
        child: Icon(LucideIcons.sparkles, size: compact ? 16 : 18, color: AmrColors.white),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(about.title, style: AmrText.title(compact ? 20 : 26)),
            if (about.subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                about.subtitle!,
                style: AmrText.body(compact ? 13 : 15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(width: 12),
      AmrButton(
        label: 'Cancel',
        size: AmrButtonSize.sm,
        variant: AmrButtonVariant.surface,
        leading: const Icon(LucideIcons.x, size: 16),
        onPressed: onCancel,
      ),
    ],
  );
}

/// The pill; text and send button grow with [t] from the inline size to the composer's.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.t,
    required this.compact,
    required this.enabled,
    required this.accent,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hint;
  final double t;
  final bool compact;
  final bool enabled;
  final bool accent;
  final ValueChanged<String?> onSend;

  @override
  Widget build(BuildContext context) {
    final style = AmrText.body(lerpDouble(compact ? 16 : 18, compact ? 18 : 22, t)!);
    final inset = lerpDouble(8, compact ? 8 : 10, t)!;
    return LayoutBuilder(
      builder: (context, box) {
        final button = box.maxHeight - 2 * inset;
        return Container(
          padding: EdgeInsets.fromLTRB(lerpDouble(28, compact ? 22 : 34, t)!, inset, inset, inset),
          decoration: BoxDecoration(
            color: AmrColors.white,
            borderRadius: AmrRadius.pill,
            border: Border.all(color: Color.lerp(AmrColors.white, AmrColors.lavender, t)!),
            boxShadow: [
              BoxShadow(
                color: AmrColors.ink.withValues(alpha: lerpDouble(0.10, 0.16, t)!),
                offset: Offset(0, lerpDouble(4, 14, t)!),
                blurRadius: lerpDouble(24, 48, t)!,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  enabled: enabled,
                  style: style,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(null),
                  decoration: InputDecoration.collapsed(
                    hintText: hint,
                    hintStyle: style.copyWith(color: AmrColors.inkHover),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AmrIconButton(
                icon: LucideIcons.arrowRight,
                size: button,
                iconSize: lerpDouble(22, 24, t)!,
                tooltip: 'Ask',
                variant: accent ? AmrIconButtonVariant.accent : AmrIconButtonVariant.primary,
                onPressed: enabled ? () => onSend(null) : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "Try asking" chips and the keyboard hints.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.suggestions, required this.compact, required this.onPick});

  final List<String> suggestions;
  final bool compact;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final hints = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Kbd('Enter'),
        const SizedBox(width: 6),
        Text('to ask', style: AmrText.body(13)),
        const SizedBox(width: 14),
        const Kbd('Esc'),
        const SizedBox(width: 6),
        Text('to cancel', style: AmrText.body(13)),
      ],
    );
    return ColumnGap(
      [
        if (suggestions.isNotEmpty) ...[
          Text('Try asking', style: AmrText.label(14)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in suggestions)
                AmrButton(
                  label: s,
                  size: AmrButtonSize.sm,
                  fontSize: compact ? 13 : 14,
                  variant: AmrButtonVariant.surface,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16),
                  onPressed: () => onPick(s),
                ),
            ],
          ),
        ],
        if (!compact) Padding(padding: const EdgeInsets.only(top: 6), child: hints),
      ],
      gap: 10,
      crossAxisAlignment: CrossAxisAlignment.start,
    );
  }
}

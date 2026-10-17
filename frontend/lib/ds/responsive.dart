import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'tokens.dart';
import 'typography.dart';

extension AmrResponsive on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// Phone layout: one column, compact top bar, sticky composer.
  bool get isCompact => screenWidth < AmrBreakpoints.compact;

  /// Page side gutter: clamp(16px, 4vw, 64px).
  double get gutter => fluid(this, 16, 4, 64);

  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// A laptop-height window (under 1000px tall): layouts tighten so the main content fits
  /// without scrolling. Tall windows keep the design's exact spacing.
  bool get isShort => screenHeight < 1000;

  /// Scales a vertical design spacing down on short windows: full size from 1000px tall,
  /// half size at 640px and below, never under [min].
  double vfit(double v, {double min = 0}) {
    final f = ((screenHeight - 640) / 360).clamp(0.5, 1.0);
    final out = v * f;
    return out < min ? min : out;
  }
}

/// CSS `grid-template-columns: repeat(auto-fit, minmax(min(minWidth, 100%), 1fr))`.
///
/// Items in a row share the row's height, like CSS grid's default stretch.
class AutoGrid extends StatelessWidget {
  const AutoGrid({
    super.key,
    required this.minItemWidth,
    required this.children,
    this.gap = AmrSpace.x20,
    this.rowGap,
    this.stretch = true,
  });

  final double minItemWidth;
  final double gap;
  final double? rowGap;
  final bool stretch;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final cols = math.max(1, ((width + gap) / (minItemWidth + gap)).floor());
        final count = math.min(cols, children.length);
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += count) {
          final slice = children.sublist(i, math.min(i + count, children.length));
          final cells = [
            for (var j = 0; j < count; j++) j < slice.length ? slice[j] : const SizedBox(),
          ];
          if (rows.isNotEmpty) rows.add(SizedBox(height: rowGap ?? gap));
          rows.add(EqualRow(gap: gap, stretch: stretch, children: cells));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}

/// CSS `display: flex; flex-wrap: wrap` with flex-basis per child: [FlexSplit] puts
/// children side by side when each gets at least its basis, otherwise stacks them.
class FlexSplit extends StatelessWidget {
  const FlexSplit({
    super.key,
    required this.children,
    required this.basis,
    this.flex,
    this.gap = AmrSpace.x20,
    this.stretch = true,
    this.growFromBasis = false,
  });

  final List<Widget> children;

  /// Minimum width of each child before the row wraps.
  final List<double> basis;

  /// Relative widths when side by side; defaults to equal.
  final List<int>? flex;
  final double gap;
  final bool stretch;

  /// CSS `flex: <flex> 1 <basis>`: each child starts at its [basis] and only the width left
  /// over is shared by [flex]. `flex: [999, 1]` keeps the second child at its basis, as for a
  /// fixed side column.
  final bool growFromBasis;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final need = basis.fold<double>(0, (a, b) => a + b) + gap * (children.length - 1);
        if (box.maxWidth < need) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return EqualRow(
          gap: gap,
          flex: flex,
          basis: growFromBasis ? basis : null,
          stretch: stretch,
          children: children,
        );
      },
    );
  }
}

/// A row whose children share the width by [flex] and, with [stretch], all take the height of
/// the tallest child (CSS grid/flex `align-items: stretch`).
///
/// Children are laid out first at their natural height, then again at the row's height. Unlike
/// `IntrinsicHeight` this measures real layout, so text wraps the same in both passes and
/// `LayoutBuilder` children work.
class EqualRow extends MultiChildRenderObjectWidget {
  const EqualRow({
    super.key,
    required super.children,
    this.gap = 0,
    this.flex,
    this.basis,
    this.stretch = true,
  });

  final double gap;
  final List<int>? flex;

  /// Starting widths; [flex] then shares only what is left (see [FlexSplit.growFromBasis]).
  final List<double>? basis;
  final bool stretch;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderEqualRow(gap, flex, stretch)..basis = basis;

  @override
  void updateRenderObject(BuildContext context, RenderEqualRow renderObject) {
    renderObject
      ..gap = gap
      ..flex = flex
      ..basis = basis
      ..stretch = stretch;
  }
}

class _EqualRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderEqualRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EqualRowParentData> {
  RenderEqualRow(this._gap, this._flex, this._stretch);

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  List<int>? _flex;
  set flex(List<int>? v) {
    _flex = v;
    markNeedsLayout();
  }

  List<double>? _basis;
  set basis(List<double>? v) {
    _basis = v;
    markNeedsLayout();
  }

  bool _stretch;
  set stretch(bool v) {
    if (v == _stretch) return;
    _stretch = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualRowParentData) child.parentData = _EqualRowParentData();
  }

  List<double> _widths(double width, int n) {
    final weights = [for (var i = 0; i < n; i++) (_flex?[i] ?? 1).toDouble()];
    final total = weights.fold<double>(0, (a, b) => a + b);
    final free = math.max(0.0, width - _gap * (n - 1));
    final basis = _basis;
    if (basis != null) {
      final extra = math.max(0.0, free - basis.take(n).fold<double>(0, (a, b) => a + b));
      return [for (var i = 0; i < n; i++) basis[i] + extra * weights[i] / total];
    }
    return [for (final w in weights) free * w / total];
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final kids = getChildrenAsList();
    final widths = _widths(constraints.maxWidth, kids.length);
    var height = 0.0;
    for (var i = 0; i < kids.length; i++) {
      height = math.max(
        height,
        kids[i].getDryLayout(BoxConstraints.tightFor(width: widths[i])).height,
      );
    }
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void performLayout() {
    final kids = getChildrenAsList();
    final width = constraints.maxWidth;
    final widths = _widths(width, kids.length);
    var height = 0.0;
    for (var i = 0; i < kids.length; i++) {
      kids[i].layout(BoxConstraints.tightFor(width: widths[i]), parentUsesSize: true);
      height = math.max(height, kids[i].size.height);
    }
    var x = 0.0;
    for (var i = 0; i < kids.length; i++) {
      if (_stretch && kids[i].size.height != height) {
        // A minimum, not a tight height: a tightly constrained child becomes a relayout
        // boundary and would later resize without telling this row.
        kids[i].layout(
          BoxConstraints(minWidth: widths[i], maxWidth: widths[i], minHeight: height),
          parentUsesSize: true,
        );
      }
      (kids[i].parentData! as _EqualRowParentData).offset = Offset(x, 0);
      x += widths[i] + _gap;
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A column of full-width children whose last child grows to the height the parent asks for,
/// like CSS `flex: 1` on the last item of a stretched grid cell (an [EqualRow] child). The
/// widget tree is the same however tall it is, so children keep their state.
class FillColumn extends MultiChildRenderObjectWidget {
  const FillColumn({super.key, required super.children, this.gap = 0});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderFillColumn(gap);

  @override
  void updateRenderObject(BuildContext context, RenderFillColumn renderObject) =>
      renderObject.gap = gap;
}

class _FillColumnParentData extends ContainerBoxParentData<RenderBox> {}

class RenderFillColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FillColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FillColumnParentData> {
  RenderFillColumn(this._gap);

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FillColumnParentData) child.parentData = _FillColumnParentData();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final kids = getChildrenAsList();
    final width = BoxConstraints.tightFor(width: constraints.maxWidth);
    var height = _gap * math.max(0, kids.length - 1);
    for (final k in kids) {
      height += k.getDryLayout(width).height;
    }
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void performLayout() {
    final kids = getChildrenAsList();
    final width = constraints.maxWidth;
    var height = _gap * math.max(0, kids.length - 1);
    for (final k in kids) {
      k.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      height += k.size.height;
    }
    final extra = constraints.minHeight - height;
    if (extra > 0 && kids.isNotEmpty) {
      final last = kids.last;
      last.layout(
        BoxConstraints(minWidth: width, maxWidth: width, minHeight: last.size.height + extra),
        parentUsesSize: true,
      );
    }
    var y = 0.0;
    for (final (i, k) in kids.indexed) {
      if (i > 0) y += _gap;
      (k.parentData! as _FillColumnParentData).offset = Offset(0, y);
      y += k.size.height;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

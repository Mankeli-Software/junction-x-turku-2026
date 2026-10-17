import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// CSS `clamp(min, vw, max)` against the viewport width.
double fluid(BuildContext context, double min, double vw, double max) =>
    (MediaQuery.sizeOf(context).width * vw / 100).clamp(min, max);

/// CSS `clamp(min, min(vw, vh), max)`: also capped by the viewport height, so big type shrinks
/// on short laptop screens and the page still fits without scrolling.
double fluidHW(BuildContext context, double min, double vw, double vh, double max) {
  final size = MediaQuery.sizeOf(context);
  final v = size.width * vw / 100;
  final h = size.height * vh / 100;
  return (v < h ? v : h).clamp(min, max);
}

/// Type styles from the design: Sora for display, Inter for everything else.
///
/// Letter spacing in the design is in em; [_em] converts it to logical px.
abstract final class AmrText {
  static const _tabular = [FontFeature.tabularFigures()];

  static double _em(double size, double em) => size * em;

  /// Sora, light by default. [em] is letter spacing in em.
  static TextStyle sora(
    double size, {
    FontWeight weight = FontWeight.w300,
    double em = -0.02,
    double? height,
    Color color = AmrColors.ink,
  }) => GoogleFonts.sora(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: _em(size, em),
    height: height,
    color: color,
    fontFeatures: _tabular,
  );

  /// Inter, regular by default.
  static TextStyle inter(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? height,
    Color color = AmrColors.ink,
    FontStyle? style,
  }) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color,
    fontStyle: style,
    fontFeatures: _tabular,
  );

  // Named roles -------------------------------------------------------------

  /// "AMRight" wordmark: Sora 700 22, +0.02em.
  static TextStyle get brand => sora(22, weight: FontWeight.w700, em: 0.02);

  /// Page h1, e.g. "Who is your patient?": clamp(44, 6vw, 84), lh 1.02, -0.035em.
  static TextStyle display(BuildContext c, {double max = 84}) =>
      sora(fluidHW(c, 44, 6, 8, max), em: -0.035, height: 1.02);

  /// Drug name in the answer hero: clamp(36, 4.4vw, 60), lh 1.05.
  static TextStyle headline(BuildContext c) =>
      sora(fluidHW(c, 34, 4.4, 5, 60), em: -0.035, height: 1.05);

  /// The big percentage: clamp(64, 7vw, 104), lh 0.95, -0.05em.
  static TextStyle metric(BuildContext c) =>
      sora(fluidHW(c, 56, 7, 8, 104), em: -0.05, height: 0.95);

  /// The tappable patient sentence: clamp(26, 2.8vw, 38), lh 1.3.
  static TextStyle sentence(BuildContext c) => sora(fluidHW(c, 26, 2.8, 4, 38), height: 1.3);

  /// Section and card titles (22, 24, 26, 30, 34 in the design).
  static TextStyle title(double size, {double em = -0.02, double height = 1.2}) =>
      sora(size, em: em, height: height);

  /// Lede under a page title: Inter 18, lh 1.55.
  static TextStyle get lede => inter(18, height: 1.55);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, double? height}) =>
      inter(size, weight: weight, height: height);

  /// Small bold labels ("On your ward now", "Selected patient").
  static TextStyle label(double size) => inter(size, weight: FontWeight.w600);
}

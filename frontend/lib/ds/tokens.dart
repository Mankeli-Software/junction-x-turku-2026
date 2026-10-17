import 'package:flutter/widgets.dart';

/// Colors, exactly as in the design canvas ("AM Right — designs").
abstract final class AmrColors {
  // Ink
  static const ink = Color(0xFF1D204E); // navy: text, primary buttons, S in S/I/R
  static const inkHover = Color(0xFF4A4E72);
  static const white = Color(0xFFFFFFFF);

  // Lavender surfaces
  static const lavender = Color(0xFFC6C4ED); // accent panels, avatars
  static const lavenderSoft = Color(0xFFF4F3FC); // subtle panels, selected rows
  static const lavenderPale = Color(0xFFECEBFA); // tags, unselected tokens
  static const line = Color(0xFFE7E6F3); // hairlines, empty step dots
  static const periwinkle = Color(0xFFA6A1F9); // I in S/I/R, quiet bars, dashed borders
  static const violet = Color(0xFF635BF1); // the "Show what works" call to action
  static const violetHover = Color(0xFF5149E3);
  static const mist = Color(0xFFE2E1F0); // "other" in stacked shares
  static const hairline = Color(0xFFF0EFF8); // row dividers inside white chat cards

  /// Categorical order for stacked shares (organism mix): largest share first.
  static const series = [ink, violet, periwinkle, lavender, mist];

  // Alert
  static const blush = Color(0xFFFDE3E9); // alert surfaces
  static const magenta = Color(0xFFEA0054); // R in S/I/R, alert dots
  static const danger = Color(0xFFB0003F); // "▼ 12 pts" text
  static const amber = Color(0xFFE0832B);
  static const amberSoft = Color(0xFFFBE7D5);

  // Page glow (radial gradients in the top corners)
  static const glowLavender = Color(0xFFD9D4FB);
  static const glowPink = Color(0xFFF8D2E6);

  // S / I / R
  static const susceptible = ink;
  static const increased = periwinkle;
  static const resistant = magenta;
}

/// The spacing steps the design uses (px).
abstract final class AmrSpace {
  static const double x4 = 4;
  static const double x6 = 6;
  static const double x8 = 8;
  static const double x10 = 10;
  static const double x12 = 12;
  static const double x14 = 14;
  static const double x16 = 16;
  static const double x18 = 18;
  static const double x20 = 20;
  static const double x22 = 22;
  static const double x24 = 24;
  static const double x28 = 28;
  static const double x32 = 32;
  static const double x36 = 36;
  static const double x40 = 40;
  static const double x44 = 44;
  static const double x64 = 64;
}

abstract final class AmrRadius {
  static const pill = BorderRadius.all(Radius.circular(999));
  static const card = BorderRadius.all(Radius.circular(16));
  static const panel = BorderRadius.all(Radius.circular(24));
  static const bubble = BorderRadius.all(Radius.circular(20));
  static const kbd = BorderRadius.all(Radius.circular(8));
  static const kbdSmall = BorderRadius.all(Radius.circular(6));
  static const swatch = BorderRadius.all(Radius.circular(4));
}

abstract final class AmrShadows {
  static const _c8 = Color(0x141D204E); // rgba(29,32,78,0.08)
  static const _c10 = Color(0x1A1D204E); // rgba(29,32,78,0.10)

  /// 0 2px 14px .08: top-bar pills, quiet cards.
  static const sm = [BoxShadow(color: _c8, offset: Offset(0, 2), blurRadius: 14)];

  /// 0 4px 20px .10: inline ask fields.
  static const input = [BoxShadow(color: _c10, offset: Offset(0, 4), blurRadius: 20)];

  /// 0 4px 24px .10: cards, the hero ask field.
  static const md = [BoxShadow(color: _c10, offset: Offset(0, 4), blurRadius: 24)];

  /// 0 6px 32px .10: the big panels (patient form, selected patient).
  static const lg = [BoxShadow(color: _c10, offset: Offset(0, 6), blurRadius: 32)];
}

abstract final class AmrBreakpoints {
  /// Below this everything stacks in one column and the top bar shrinks.
  static const double compact = 768;
  static const double maxContent = 1320;
}

abstract final class AmrMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
}

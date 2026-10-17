import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Material theme built from the tokens. Our own components style themselves; this keeps the
/// Material primitives we still use (text fields, sliders, dialogs, sheets) on brand.
ThemeData buildAmrTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
  // google_fonts' own TextTheme helpers target the standalone material_ui package, so apply
  // the family to Flutter's TextTheme directly.
  final text = base.textTheme.apply(
    fontFamily: GoogleFonts.inter().fontFamily,
    bodyColor: AmrColors.ink,
    displayColor: AmrColors.ink,
  );
  return base.copyWith(
    colorScheme: const ColorScheme.light(
      primary: AmrColors.ink,
      onPrimary: AmrColors.white,
      secondary: AmrColors.lavender,
      onSecondary: AmrColors.ink,
      tertiary: AmrColors.periwinkle,
      error: AmrColors.magenta,
      surface: AmrColors.white,
      onSurface: AmrColors.ink,
      outline: AmrColors.ink,
      outlineVariant: AmrColors.line,
    ),
    scaffoldBackgroundColor: AmrColors.white,
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AmrColors.ink,
      selectionColor: AmrColors.lavender.withValues(alpha: 0.6),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AmrColors.ink,
      inactiveTrackColor: AmrColors.lavenderPale,
      thumbColor: AmrColors.ink,
      overlayColor: Color(0x1F1D204E),
      trackHeight: 6,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AmrColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AmrRadius.panel),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AmrColors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AmrColors.lavender,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AmrColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AmrRadius.pill),
      contentTextStyle: GoogleFonts.inter(fontSize: 15, color: AmrColors.white),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(color: AmrColors.ink, borderRadius: AmrRadius.kbd),
      textStyle: GoogleFonts.inter(fontSize: 13, color: AmrColors.white),
    ),
  );
}

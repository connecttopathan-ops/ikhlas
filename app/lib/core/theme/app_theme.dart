import 'package:flutter/material.dart';

/// ============================================================
/// Ikhlas design tokens — from the approved Visual Spec (Turn 2)
/// Dark = 2a–2c emerald + gold. Light = 2d sage ivory (flat).
/// ============================================================

class DarkTokens {
  // The app now ships in the light 2d "sage ceremonial" palette. These
  // fields keep their names — screens use them semantically (`ivory` =
  // primary text, `gold` = accent) — but hold the light-theme values, so
  // all 16 screens flip to light without per-screen edits. The theme-aware
  // shared widgets read LightTokens directly (themeMode is light).
  static const bg = Color(0xFFEFF0E5); // sage-tinted ivory ground
  static const ivory = Color(0xFF17251B); // deep green ink (primary text)
  static Color muted([double o = .58]) => ivory.withOpacity(o);
  static const gold = Color(0xFFA8842B); // darkened gold for contrast on light
  static Color hairline([double o = .28]) =>
      const Color(0xFF947420).withOpacity(o);
  static const ctaBg = Color(0xFF152A1D); // deep green
  static const ctaText = Color(0xFFD9BC57); // champagne
  static Color ctaRing = const Color(0xFFC9A227).withOpacity(.4);
}

class LightTokens {
  static const bg = Color(0xFFEFF0E5); // sage-tinted ivory
  static const ink = Color(0xFF17251B);
  static Color muted([double o = .55]) => ink.withOpacity(o);
  static const goldArabic = Color(0xFFA8842B); // darkened for contrast
  static Color hairline = const Color(0xFF947420).withOpacity(.55);
  static const link = Color(0xFF8F711F);
  static const greenAccent = Color(0xFF2E5C41); // diamond bullets
  static const ctaBg = Color(0xFF152A1D); // deep green
  static const ctaText = Color(0xFFD9BC57); // champagne gold
  static Color ctaRing = const Color(0xFFC9A227).withOpacity(.4);
}

class AppRadius {
  static const double control = 10;
  static const double checkbox = 6;
}

class AppSpace {
  static const double screenMargin = 24;
  static const double hero = 64;
}

/// Type roles. Fraunces = display serif · Inter = UI · Amiri = Arabic.
/// All three are bundled as app assets (see pubspec) — no runtime fetch.
class AppType {
  static TextStyle fraunces(double size,
          {FontWeight weight = FontWeight.w400,
          Color? color,
          double height = 1.1,
          FontStyle style = FontStyle.normal}) =>
      TextStyle(
          fontFamily: 'Fraunces',
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color,
          fontStyle: style,
          letterSpacing: -0.2);

  static TextStyle inter(double size,
          {FontWeight weight = FontWeight.w400,
          Color? color,
          double height = 1.6,
          double letterSpacing = 0}) =>
      TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color,
          letterSpacing: letterSpacing);

  /// Eyebrow: Inter 600 11px, .15em tracking, uppercase.
  static TextStyle eyebrow(Color color) =>
      inter(11, weight: FontWeight.w600, color: color, letterSpacing: 11 * .15, height: 1.2);

  /// Amiri for Arabic (reverence-critical text).
  static TextStyle amiri(double size, {Color? color}) =>
      TextStyle(fontFamily: 'Amiri', fontSize: size, color: color, height: 1.6);
}

class AppTheme {
  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: DarkTokens.bg,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          surface: DarkTokens.bg,
          primary: DarkTokens.gold,
          onPrimary: DarkTokens.ctaText,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'Inter',
            bodyColor: DarkTokens.ivory,
            displayColor: DarkTokens.ivory),
      );

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: LightTokens.bg,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.light(
          surface: LightTokens.bg,
          primary: LightTokens.ctaBg,
          onPrimary: LightTokens.ctaText,
        ),
        textTheme: ThemeData.light().textTheme.apply(
            fontFamily: 'Inter',
            bodyColor: LightTokens.ink,
            displayColor: LightTokens.ink),
      );
}

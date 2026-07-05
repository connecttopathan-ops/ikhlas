import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Ikhlas brand tokens for the guardian portal — the same emerald + gold
/// world, but a calm, low-density, low-tech-friendly layout.
class T {
  static const bg = Color(0xFF0A120C);
  static const panel = Color(0xFF101B13);
  static const ivory = Color(0xFFEFEDDF);
  static const gold = Color(0xFFC9A227);
  static const ctaText = Color(0xFF0E1811);
  static Color muted = ivory.withOpacity(.6);
  static Color hairline = gold.withOpacity(.2);

  static TextStyle fraunces(double size,
          {FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.fraunces(
          fontSize: size, fontWeight: weight, color: color, height: 1.15);

  static TextStyle inter(double size,
          {FontWeight weight = FontWeight.w400,
          Color? color,
          double height = 1.55}) =>
      GoogleFonts.inter(
          fontSize: size, fontWeight: weight, color: color, height: height);
}

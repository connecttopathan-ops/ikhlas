import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Minimal token set for the internal dashboard — same palette family as
/// the app (emerald-black, ivory, gold) so the brand stays coherent, but
/// this is an internal tool, not part of the approved member-facing spec.
class T {
  static const bg = Color(0xFF0A120C);
  static const panel = Color(0xFF101B13);
  static const ivory = Color(0xFFEFEDDF);
  static const gold = Color(0xFFC9A227);
  static const ctaText = Color(0xFF0E1811);
  static Color muted = ivory.withOpacity(.55);
  static Color hairline = gold.withOpacity(.18);

  static const approve = Color(0xFF3E7A55);
  static const reject = Color(0xFF8A4B3B);

  static TextStyle fraunces(double size,
          {FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.fraunces(
          fontSize: size, fontWeight: weight, color: color, height: 1.15);

  static TextStyle inter(double size,
          {FontWeight weight = FontWeight.w400,
          Color? color,
          double height = 1.5}) =>
      GoogleFonts.inter(
          fontSize: size, fontWeight: weight, color: color, height: height);
}

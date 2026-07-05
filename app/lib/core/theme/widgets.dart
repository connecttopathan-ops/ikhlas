import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// ============================================================
/// Shared visual components — built to the Visual Spec:
/// gold CTA w/ inset ring · diamond bullets · hairlines ·
/// girih line-art painter · fractal-noise overlay
/// ============================================================

/// Primary CTA. Spec: solid gold #C9A227, text #0E1811, 56px, radius 10,
/// inset ring rgba(15,25,18,.3). Light theme: deep green bg, champagne text,
/// gold ring. Disabled = dimmed (reduced opacity), never grey-dead.
class PrimaryCta extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const PrimaryCta({super.key, required this.label, this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? DarkTokens.ctaBg : LightTokens.ctaBg;
    final fg = isDark ? DarkTokens.ctaText : LightTokens.ctaText;
    final ring = isDark ? DarkTokens.ctaRing : LightTokens.ctaRing;
    final enabled = onPressed != null && !loading;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.4,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: enabled ? onPressed : null,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: ring, width: 1),
              ),
              child: loading
                  ? SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                  : Text(label,
                      style: AppType.inter(15, weight: FontWeight.w600, color: fg, height: 1.2)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet link — "Already a member? Sign in" pattern.
class QuietLink extends StatelessWidget {
  final String prefix;
  final String linkText;
  final VoidCallback? onTap;
  const QuietLink({super.key, this.prefix = '', required this.linkText, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? DarkTokens.muted() : LightTokens.muted();
    final linkColor = isDark ? DarkTokens.gold : LightTokens.link;
    return GestureDetector(
      onTap: onTap,
      child: Text.rich(
        TextSpan(children: [
          if (prefix.isNotEmpty)
            TextSpan(text: '$prefix ', style: AppType.inter(13.5, color: mutedColor)),
          TextSpan(
              text: linkText,
              style: AppType.inter(13.5, weight: FontWeight.w500, color: linkColor)),
        ]),
      ),
    );
  }
}

/// 6px gold square rotated 45° (spec: diamond bullets).
class DiamondBullet extends StatelessWidget {
  final Color? color;
  final double size;
  const DiamondBullet({super.key, this.color, this.size = 6});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
          width: size, height: size,
          color: color ?? (isDark ? DarkTokens.gold : LightTokens.greenAccent)),
    );
  }
}

/// Hairline rule (gold at spec opacity), horizontal.
class Hairline extends StatelessWidget {
  final double? width;
  const Hairline({super.key, this.width});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
        width: width, height: 1,
        color: isDark ? DarkTokens.hairline() : LightTokens.hairline);
  }
}

/// ============================================================
/// Brand marks (approved logo spec — 14a dark / 14b light).
/// The signature detail is the gold lozenge (a square rotated 45°) used
/// as the dotless-ı tittle; it recurs in the wordmark and the app icon.
/// ============================================================

/// Colour set for the two logo themes.
class _LogoColors {
  final Color word, lozenge, caption, line;
  const _LogoColors(this.word, this.lozenge, this.caption, this.line);
  static const dark = _LogoColors( // 14a
      Color(0xFFEFEDDF), Color(0xFFD9BC57), Color(0xFFD9BC57), Color(0x73D9BC57));
  static const light = _LogoColors( // 14b
      Color(0xFF17251B), Color(0xFFA8842B), Color(0xFF8F711F), Color(0x80947420));
}

/// The full wordmark lockup: `ıkhlaas` (dotless ı + double-a) in Fraunces
/// with the lozenge tittle, and the Arabic `إخلاص` caption in Amiri flanked
/// by hairlines. `size` is the wordmark font-size (spec reference: 70).
class IkhlasLogo extends StatelessWidget {
  final double size;
  final bool? dark; // null → follow theme brightness
  const IkhlasLogo({super.key, this.size = 70, this.dark});

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? _LogoColors.dark : _LogoColors.light;
    final k = size / 70; // scale from the 70px reference

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wordmark with the lozenge tittle centred on the ı stem.
        Stack(clipBehavior: Clip.none, children: [
          Text('ıkhlaas',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: size,
                height: 1.0,
                letterSpacing: -0.018 * size,
                // Bundled Fraunces is 400/600; 400 is the nearest to the
                // spec's 390 (dark) / 410 (light).
                fontWeight: FontWeight.w400,
                color: c.word,
              )),
          Positioned(
            left: 2 * k,
            top: 21 * k,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(width: 11 * k, height: 11 * k, color: c.lozenge),
            ),
          ),
        ]),
        SizedBox(height: 1 * k),
        // Caption rule: line — إخلاص — line
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 20 * k, height: 1, color: c.line),
          SizedBox(width: 10 * k),
          Text('إخلاص',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontFamily: 'Amiri',
                  fontSize: 18 * k,
                  height: 1,
                  color: c.caption)),
          SizedBox(width: 10 * k),
          Container(width: 20 * k, height: 1, color: c.line),
        ]),
      ],
    );
  }
}

/// The ı-monogram — the dotless `ı` in Fraunces with the gold lozenge
/// tittle. The brand's compact icon element, used as a watermark and in
/// empty/resting states. (Named GirihMark for source compatibility with
/// existing call sites; `progress` is accepted but unused.)
class GirihMark extends StatelessWidget {
  final double size;
  final double opacity;
  final double progress;
  const GirihMark(
      {super.key, required this.size, this.opacity = 1, this.progress = 1});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? _LogoColors.dark : _LogoColors.light;
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          Text('ı',
              style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: size * 0.86,
                  height: 1,
                  color: c.word.withOpacity(isDark ? 1 : .9),
                  fontWeight: FontWeight.w400)),
          Positioned(
            top: size * 0.11,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                  width: size * 0.16, height: size * 0.16, color: c.lozenge),
            ),
          ),
        ]),
      ),
    );
  }
}

/// ============================================================
/// Noise overlay ~3–3.5% grain (approximates the spec's fractal-noise SVG).
/// Rendered as a single drawPoints batch, alpha folded into the point
/// colour (so no full-screen Opacity saveLayer), and cached by a
/// RepaintBoundary so it rasterises once and is reused as a texture.
/// ============================================================
class NoiseOverlay extends StatelessWidget {
  final double opacity;
  const NoiseOverlay({super.key, this.opacity = .032});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
              painter: _NoisePainter(opacity), size: Size.infinite),
        ),
      );
}

class _NoisePainter extends CustomPainter {
  final double opacity;
  _NoisePainter(this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7); // fixed seed → stable grain
    // ~1 grain per 900px² (was ~1 per 55px² = ~15× fewer points) with the
    // 3.2% alpha folded in, so the whole overlay is one cheap point batch.
    final count = (size.width * size.height / 900).round();
    final points = List<Offset>.generate(
        count,
        (_) => Offset(
            rnd.nextDouble() * size.width, rnd.nextDouble() * size.height));
    final paint = Paint()
      // Ink grain reads on the light sage ground (white would vanish).
      ..color = const Color(0xFF17251B).withValues(alpha: opacity)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) => old.opacity != opacity;
}

/// Scaffold wrapper: background + noise, spec screen margin.
class IkhlasScaffold extends StatelessWidget {
  final Widget child;
  final bool safeArea;
  const IkhlasScaffold({super.key, required this.child, this.safeArea = true});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          Positioned.fill(
              child: safeArea ? SafeArea(child: child) : child),
          const Positioned.fill(child: NoiseOverlay()),
        ]),
      );
}

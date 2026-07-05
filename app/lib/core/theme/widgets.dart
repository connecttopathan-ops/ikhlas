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
/// Girih line-art: concentric circles + rotated squares.
/// stroke #C9A227 @ 0.55w. `progress` (0→1) animates self-drawing.
/// ============================================================
class GirihMark extends StatelessWidget {
  final double size;
  final double opacity; // spec: 5–11% as background motif; ~100% as the splash mark
  final double progress;
  const GirihMark({super.key, required this.size, this.opacity = 1, this.progress = 1});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: opacity,
        child: CustomPaint(
            size: Size.square(size), painter: _GirihPainter(progress: progress)),
      );
}

class _GirihPainter extends CustomPainter {
  final double progress;
  _GirihPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = DarkTokens.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55;
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // Concentric circles (arc-draw with progress)
    for (final f in [1.0, 0.82, 0.58]) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * f * 0.96),
          -math.pi / 2, 2 * math.pi * progress.clamp(0, 1), false, paint);
    }
    // Two rotated squares (0° and 45°) — draw edges up to progress
    for (final rot in [0.0, math.pi / 4]) {
      final path = Path();
      for (int i = 0; i < 4; i++) {
        final a1 = rot + i * math.pi / 2 + math.pi / 4;
        final a2 = rot + (i + 1) * math.pi / 2 + math.pi / 4;
        final p1 = c + Offset(math.cos(a1), math.sin(a1)) * r * 0.7;
        final p2 = c + Offset(math.cos(a2), math.sin(a2)) * r * 0.7;
        if (i == 0) path.moveTo(p1.dx, p1.dy);
        path.lineTo(p2.dx, p2.dy);
      }
      final metrics = path.computeMetrics().toList();
      for (final m in metrics) {
        canvas.drawPath(m.extractPath(0, m.length * progress.clamp(0, 1)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GirihPainter old) => old.progress != progress;
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
      ..color = Colors.white.withValues(alpha: opacity)
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

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// Landing — glassmorphism. A single frosted surface fills the screen: the
/// couple illustration frosts softly behind the hero, and the differentiators
/// and how-it-works sit on glass panels. No floating outer card (that read as
/// a frame-within-a-frame), so the whole screen is one clean surface.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  static const _differentiators = [
    (Icons.verified_user_outlined, 'Aqidah-gated',
        'Screened on creed & practice.'),
    (Icons.how_to_reg_outlined, 'Application only',
        'Fewer than 4 in 10 accepted.'),
    (Icons.groups_outlined, 'Wali-first', 'Her guardian, from the start.'),
    (Icons.favorite_border, 'Deen-first matching',
        'On deen and intent, not looks.'),
  ];

  // (icon, label) — the caption line was dropped; the label under each disc
  // names the stage.
  static const _flow = [
    (Icons.description_outlined, 'Apply'),
    (Icons.badge_outlined, 'Verify'),
    (Icons.auto_awesome_outlined, 'Match'),
    (Icons.forum_outlined, 'Wali'),
    (Icons.favorite, 'Nikah'),
  ];

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  // Warm glass tone layered over the sage ground.
  static const _cream = Color(0xFFF7F5EC);
  static const _differentiators = LandingScreen._differentiators;
  static const _flow = LandingScreen._flow;

  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Widget _staged(double start, Widget child) =>
      _staggerIn(_intro, start, child);

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) _intro.value = 1;
    return Scaffold(
      body: Stack(children: [
        // Ground.
        const Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(color: LightTokens.bg))),
        // Couple illustration at the top, faded into the ground.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 380,
          child: IgnorePointer(
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, .62, .95],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: Image.asset('assets/brand/couple.png',
                  fit: BoxFit.cover, alignment: const Alignment(0, -.35)),
            ),
          ),
        ),
        // Full-screen frosted glass over the couple — light blur so the couple
        // stays recognisable through the hero, opaque toward the panels.
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _cream.withValues(alpha: .30),
                      _cream.withValues(alpha: .66),
                      _cream.withValues(alpha: .88),
                    ],
                    stops: const [0, .34, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Content.
        Positioned.fill(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(children: [
                _staged(0, _hero()),
                const SizedBox(height: 24),
                _staged(.30,
                    _glassPanel(child: const _DiffList(items: _differentiators))),
                const SizedBox(height: 16),
                _staged(
                    .42,
                    _glassPanel(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                        child: Column(children: [
                          _eyebrow('HOW IT WORKS'),
                          const SizedBox(height: 14),
                          const _HowItWorks(steps: _flow),
                        ]))),
                const SizedBox(height: 26),
                _staged(.56, _cta(context)),
                const SizedBox(height: 16),
                _staged(
                    .64,
                    Text(
                        'Membership by application · fewer than 4 in 10 accepted',
                        textAlign: TextAlign.center,
                        style: AppType.inter(11.5, color: LightTokens.muted(.6)))),
                const SizedBox(height: 8),
                _staged(
                    .70,
                    Center(
                      child: QuietLink(
                          prefix: 'Already have an account?',
                          linkText: 'Sign in',
                          onTap: () => context.go('/login')),
                    )),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _hero() => Column(children: [
        const SizedBox(height: 6),
        const Center(child: IkhlasLogo(size: 30)),
        const SizedBox(height: 24),
        Text('Where nikah begins with deen',
            textAlign: TextAlign.center,
            style: AppType.fraunces(32, color: LightTokens.ink, height: 1.12)),
        const SizedBox(height: 12),
        Text(
            'A screened, application-only pool for Muslims serious '
            'about marriage.',
            textAlign: TextAlign.center,
            style:
                AppType.inter(13.5, color: LightTokens.muted(.7), height: 1.5)),
      ]);

  Widget _glassPanel(
          {required Widget child,
          EdgeInsets padding = const EdgeInsets.fromLTRB(16, 18, 16, 16)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _cream.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: .55)),
          boxShadow: [
            BoxShadow(
                color: LightTokens.ctaBg.withValues(alpha: .10),
                blurRadius: 22,
                offset: const Offset(0, 10)),
          ],
        ),
        child: child,
      );

  Widget _cta(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: LightTokens.ctaBg,
            foregroundColor: LightTokens.ctaText,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30)),
          ),
          onPressed: () => context.go('/login'),
          child: Text('Begin my application',
              style: AppType.fraunces(17,
                  weight: FontWeight.w500, color: LightTokens.ctaText)),
        ),
      );

  static Widget _eyebrow(String s) => Text(s,
      textAlign: TextAlign.center,
      style: AppType.inter(11,
          weight: FontWeight.w700,
          color: LightTokens.goldArabic,
          letterSpacing: 11 * .17));
}

/// Fade-and-rise reveal for the one-time entrance choreography.
Widget _staggerIn(Animation<double> intro, double start, Widget child) {
  final a = CurvedAnimation(
      parent: intro,
      curve: Interval(start, (start + .40).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic));
  return FadeTransition(
    opacity: a,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(a),
      child: child,
    ),
  );
}

/// Differentiators — eyebrow + four rows, each a cream glass icon tile, the
/// claim and one clarifier, divided by hairlines.
class _DiffList extends StatelessWidget {
  final List<(IconData, String, String)> items;
  const _DiffList({required this.items});

  static const _tile = Color(0xFFE9E5D6);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _LandingScreenState._eyebrow('WHAT MAKES IKHLAAS DIFFERENT'),
      const SizedBox(height: 12),
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0)
          Padding(
            padding: const EdgeInsets.only(left: 59),
            child: Container(
                height: 1,
                color: const Color(0xFF787456).withValues(alpha: .18)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tile,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: .5)),
                boxShadow: [
                  BoxShadow(
                      color: LightTokens.ctaBg.withValues(alpha: .12),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Icon(items[i].$1, size: 20, color: LightTokens.goldArabic),
            ),
            const SizedBox(width: 15),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(items[i].$2,
                    style: AppType.inter(15,
                        weight: FontWeight.w700,
                        color: LightTokens.ink,
                        height: 1.2)),
                const SizedBox(height: 2),
                Text(items[i].$3,
                    style: AppType.inter(12.5,
                        color: LightTokens.muted(.7), height: 1.35)),
              ]),
            ),
          ]),
        ),
      ],
    ]);
  }
}

/// How it works — a continuous gold rail with glass step discs that fill to
/// emerald as they complete; the active stage auto-advances (looping).
class _HowItWorks extends StatefulWidget {
  final List<(IconData, String)> steps; // (icon, label)
  const _HowItWorks({required this.steps});
  @override
  State<_HowItWorks> createState() => _HowItWorksState();
}

class _HowItWorksState extends State<_HowItWorks> {
  int _active = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (!mounted) return;
      setState(() => _active = (_active + 1) % widget.steps.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.steps.length;
    return LayoutBuilder(builder: (context, c) {
      final slot = c.maxWidth / n;
      const disc = 40.0;
      final railInset = slot / 2;
      const railTop = disc / 2 - .75;
      return SizedBox(
        height: disc + 8 + 16,
        child: Stack(children: [
          Positioned(
            left: railInset,
            right: railInset,
            top: railTop,
            child: Container(
                height: 1.5, color: LightTokens.goldArabic.withValues(alpha: .35)),
          ),
          Positioned(
            left: railInset,
            top: railTop,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              width: slot * _active,
              height: 1.5,
              color: LightTokens.goldArabic,
            ),
          ),
          Row(children: [
            for (var i = 0; i < n; i++) Expanded(child: _node(i)),
          ]),
        ]),
      );
    });
  }

  Widget _node(int i) {
    final step = widget.steps[i];
    final done = i <= _active;
    final isActive = i == _active;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done
              ? LightTokens.ctaBg
              : const Color(0xFFF7F5EC).withValues(alpha: .55),
          border: Border.all(
            color: done
                ? LightTokens.ctaBg
                : LightTokens.goldArabic.withValues(alpha: .45),
            width: 1.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                      color: LightTokens.goldArabic.withValues(alpha: .30),
                      blurRadius: 0,
                      spreadRadius: 4),
                ]
              : (done
                  ? [
                      BoxShadow(
                          color: LightTokens.ctaBg.withValues(alpha: .35),
                          blurRadius: 12,
                          offset: const Offset(0, 6)),
                    ]
                  : null),
        ),
        child: Icon(step.$1,
            size: 18,
            color: done
                ? LightTokens.ctaText
                : LightTokens.goldArabic.withValues(alpha: .72)),
      ),
      const SizedBox(height: 8),
      Text(step.$2,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.inter(11,
              weight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: isActive ? LightTokens.ink : LightTokens.muted(.7))),
    ]);
  }
}

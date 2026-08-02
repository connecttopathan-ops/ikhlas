import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// Landing — 2d light "sage ceremonial". Hero → what makes Ikhlaas different
/// (compact 2×2 icon grid) → how it works (animated horizontal stepper) → CTAs.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  // Ikhlaas's OWN differentiators — each with a meaningful icon; copy kept to
  // one short line so the four sit in a tight 2×2 grid.
  static const _differentiators = [
    (Icons.verified_user_outlined, 'Aqidah-gated',
        'Screened on creed & practice.'),
    (Icons.how_to_reg_outlined, 'Application only',
        'Fewer than 4 in 10 accepted.'),
    (Icons.groups_outlined, 'Wali-first', 'Her guardian, from the start.'),
    (Icons.favorite_border, 'Deen-first matching',
        'On deen and intent, not looks.'),
  ];

  // (icon, label, body). Each stage carries its own line icon — reads far
  // more premium than a numbered pip. Glyphs chosen to stay legible inside a
  // 32px disc (the earlier handshake collapsed into a squiggle at this size).
  static const _flow = [
    (Icons.description_outlined, 'Apply', 'A short, honest application.'),
    (Icons.badge_outlined, 'Verify',
        'A selfie and government-ID confirm you are real.'),
    (Icons.auto_awesome_outlined, 'Match',
        'Curated daily matches, ranked deen-first.'),
    (Icons.forum_outlined, 'Wali',
        'On mutual interest, guardians are brought in.'),
    (Icons.favorite, 'Nikah', 'Proceed offline, in shaa Allah.'),
  ];

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.screenMargin, 24, AppSpace.screenMargin, 24),
          children: [
            // ---- Hero — the website's faceless-couple illustration washed
            // out behind the copy, fading into the sage ground below.
            Stack(alignment: Alignment.topCenter, children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0, .45, .96],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: Opacity(
                      opacity: .20,
                      child: Image.asset('assets/brand/couple.png',
                          fit: BoxFit.cover, alignment: Alignment.topCenter),
                    ),
                  ),
                ),
              ),
              Column(children: [
                const SizedBox(height: 2),
                const Center(child: IkhlasLogo(size: 30)),
                const SizedBox(height: 20),
                Text('Where nikah begins with deen',
                    textAlign: TextAlign.center,
                    style: AppType.fraunces(30,
                        color: LightTokens.ink, height: 1.14)),
                const SizedBox(height: 10),
                Text(
                    'A screened, application-only pool for Muslims serious '
                    'about marriage.',
                    textAlign: TextAlign.center,
                    style: AppType.inter(13.5,
                        color: LightTokens.muted(.7), height: 1.45)),

                // Ceremonial ornament — hairline · gold lozenge · hairline,
                // echoing the wordmark's diamond tittle.
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                      width: 26,
                      height: 1,
                      color: LightTokens.hairline.withValues(alpha: .6)),
                  const SizedBox(width: 8),
                  Transform.rotate(
                    angle: math.pi / 4,
                    child: Container(
                        width: 5, height: 5, color: LightTokens.goldArabic),
                  ),
                  const SizedBox(width: 8),
                  Container(
                      width: 26,
                      height: 1,
                      color: LightTokens.hairline.withValues(alpha: .6)),
                ]),
              ]),
            ]),

            // ---- What makes Ikhlaas different — fine editorial list ----
            const SizedBox(height: 24),
            _eyebrow('WHAT MAKES IKHLAAS DIFFERENT'),
            const SizedBox(height: 6),
            const _DiffList(items: _differentiators),

            // ---- How it works — animated horizontal stepper ----
            const SizedBox(height: 26),
            _eyebrow('HOW IT WORKS'),
            const SizedBox(height: 16),
            const _HowItWorks(steps: _flow),

            // ---- CTAs ----
            const SizedBox(height: 26),
            PrimaryCta(
                label: 'Begin my application',
                onPressed: () => context.go('/login')),
            const SizedBox(height: 12),
            Center(
              child: QuietLink(
                  prefix: 'Already have an account?',
                  linkText: 'Sign in',
                  onTap: () => context.go('/login')),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _eyebrow(String s) => Text(s,
      textAlign: TextAlign.center,
      style: AppType.inter(11,
          weight: FontWeight.w700,
          color: LightTokens.goldArabic,
          letterSpacing: 11 * .16));

}

/// The four differentiators as a fine editorial list — no boxes, no discs.
/// Each row: a gold line glyph, the claim, and one quiet clarifier, divided
/// by whisper-thin inset hairlines (the menu of a fine restaurant, not a
/// data table). Airy on the sage ground and structurally unmistakable from
/// the stepper's disc timeline.
class _DiffList extends StatelessWidget {
  final List<(IconData, String, String)> items;
  const _DiffList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0)
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Container(
                height: 1,
                color: LightTokens.hairline.withValues(alpha: .28)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 36,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(items[i].$1,
                    size: 20, color: LightTokens.goldArabic),
              ),
            ),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(items[i].$2,
                    style: AppType.inter(14,
                        weight: FontWeight.w600,
                        color: LightTokens.ink,
                        height: 1.25)),
                const SizedBox(height: 2),
                Text(items[i].$3,
                    style: AppType.inter(12.5,
                        color: LightTokens.muted(.68), height: 1.4)),
              ]),
            ),
          ]),
        ),
      ],
    ]);
  }
}

/// Animated horizontal "how it works" — five nodes on a timeline. The active
/// step auto-advances (looping), the connector fills as progress moves, and a
/// caption beneath cross-fades to the current step's description.
class _HowItWorks extends StatefulWidget {
  final List<(IconData, String, String)> steps; // (icon, label, body)
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
    return Column(children: [
      // Timeline — ONE continuous rail behind the nodes, with a gold segment
      // that fills to the active stage. A single rail (vs. per-gap fillers)
      // reads more premium and can never collapse on a narrow width.
      LayoutBuilder(builder: (context, c) {
        final slot = c.maxWidth / n; // each node centred in its own slot
        const disc = 32.0;
        final railInset = slot / 2; // ends meet the first/last disc centre
        const railTop = disc / 2 - 1; // 2px rail centred on the disc row
        return SizedBox(
          height: disc + 7 + 15, // disc + gap + label line
          child: Stack(children: [
            // Base rail — the full timeline.
            Positioned(
              left: railInset,
              right: railInset,
              top: railTop,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: LightTokens.hairline.withValues(alpha: .45),
                ),
              ),
            ),
            // Gold progress — grows one slot per completed stage.
            Positioned(
              left: railInset,
              top: railTop,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                width: slot * _active,
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: LightTokens.goldArabic,
                ),
              ),
            ),
            // The discs sit on top of the rail, one per equal slot.
            Row(children: [
              for (var i = 0; i < n; i++) Expanded(child: _node(i)),
            ]),
          ]),
        );
      }),
      const SizedBox(height: 14),
      // One Fraunces-italic line for the active stage (the bold label in the
      // timeline already names it — repeating the title read redundant).
      // Fixed height so the CTA below never shifts as captions change lines.
      SizedBox(
        height: 46,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, .12), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: Text(widget.steps[_active].$3,
                key: ValueKey(_active),
                textAlign: TextAlign.center,
                style: AppType.fraunces(14.5,
                    color: LightTokens.ink.withValues(alpha: .82),
                    style: FontStyle.italic,
                    height: 1.45)),
          ),
        ),
      ),
    ]);
  }

  Widget _node(int i) {
    final step = widget.steps[i];
    final done = i <= _active;
    final isActive = i == _active;
    return Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? LightTokens.ctaBg : LightTokens.bg,
            border: Border.all(
              color: isActive
                  ? LightTokens.goldArabic
                  : (done
                      ? LightTokens.ctaBg
                      : LightTokens.hairline.withValues(alpha: .6)),
              width: isActive ? 1.5 : 1,
            ),
            // Active stage gets a soft champagne halo — the premium cue that
            // replaces the numbered pip.
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: LightTokens.goldArabic.withValues(alpha: .28),
                      blurRadius: 9,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          // Upcoming stages stay in the gold family (muted), never grey —
          // ink-grey glyphs inside gold rings read muddy.
          child: Icon(step.$1,
              size: 17,
              color: done
                  ? LightTokens.ctaText
                  : LightTokens.goldArabic.withValues(alpha: .5)),
        ),
        const SizedBox(height: 7),
        Text(step.$2,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.inter(10.5,
                weight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? LightTokens.ink : LightTokens.muted(.7))),
    ]);
  }
}

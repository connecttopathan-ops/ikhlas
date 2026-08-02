import 'dart:async';

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

  // (icon, shortLabel, title, body). Each stage carries its own line icon —
  // reads far more premium than a numbered pip and shares the deep-green disc
  // language of the differentiator cards above, so the screen feels of a piece.
  static const _flow = [
    (Icons.description_outlined, 'Apply', 'Apply',
        'A short, honest application.'),
    (Icons.badge_outlined, 'Verify', 'Verify',
        'A selfie and government-ID confirm you are real.'),
    (Icons.auto_awesome_outlined, 'Match', 'Match',
        'Curated daily matches, ranked deen-first.'),
    (Icons.handshake_outlined, 'Wali', 'Contact wali',
        'On mutual interest, guardians are brought in.'),
    (Icons.favorite, 'Nikah', 'Nikah', 'Proceed offline, in shaa Allah.'),
  ];

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.screenMargin, 24, AppSpace.screenMargin, 24),
          children: [
            // ---- Hero ----
            const Center(child: IkhlasLogo(size: 30)),
            const SizedBox(height: 20),
            Text('Where nikah begins with deen',
                textAlign: TextAlign.center,
                style:
                    AppType.fraunces(30, color: LightTokens.ink, height: 1.14)),
            const SizedBox(height: 10),
            Text(
                'A screened, application-only pool for Muslims serious '
                'about marriage.',
                textAlign: TextAlign.center,
                style: AppType.inter(13.5,
                    color: LightTokens.muted(.7), height: 1.45)),

            // ---- What makes Ikhlaas different — 2×2 icon grid ----
            const SizedBox(height: 24),
            _eyebrow('WHAT MAKES IKHLAAS DIFFERENT'),
            const SizedBox(height: 12),
            _diffRow(_differentiators[0], _differentiators[1]),
            const SizedBox(height: 10),
            _diffRow(_differentiators[2], _differentiators[3]),

            // ---- How it works — animated horizontal stepper ----
            const SizedBox(height: 26),
            _eyebrow('HOW IT WORKS'),
            const SizedBox(height: 16),
            _HowItWorks(steps: _flow),

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

  static Widget _diffRow(
          (IconData, String, String) a, (IconData, String, String) b) =>
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _DiffCard(icon: a.$1, title: a.$2, body: a.$3)),
          const SizedBox(width: 10),
          Expanded(child: _DiffCard(icon: b.$1, title: b.$2, body: b.$3)),
        ]),
      );
}

/// Compact differentiator card — deep-green icon disc + title + one line.
class _DiffCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _DiffCard(
      {required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LightTokens.hairline.withValues(alpha: .5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: LightTokens.ctaBg),
          child: Icon(icon, size: 16, color: LightTokens.ctaText),
        ),
        const SizedBox(height: 9),
        Text(title,
            style: AppType.inter(13.5,
                weight: FontWeight.w600, color: LightTokens.ink, height: 1.2)),
        const SizedBox(height: 3),
        Text(body,
            style:
                AppType.inter(11.5, color: LightTokens.muted(.72), height: 1.35)),
      ]),
    );
  }
}

/// Animated horizontal "how it works" — five nodes on a timeline. The active
/// step auto-advances (looping), the connector fills as progress moves, and a
/// caption beneath cross-fades to the current step's description.
class _HowItWorks extends StatefulWidget {
  final List<(IconData, String, String, String)> steps; // icon,short,title,body
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
      const SizedBox(height: 16),
      // Active step's title + description, cross-fading as it advances.
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, .12), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: Column(
          key: ValueKey(_active),
          children: [
            Text(widget.steps[_active].$3,
                style: AppType.inter(15.5,
                    weight: FontWeight.w600, color: LightTokens.ink)),
            const SizedBox(height: 3),
            Text(widget.steps[_active].$4,
                textAlign: TextAlign.center,
                style: AppType.inter(13,
                    color: LightTokens.muted(.72), height: 1.4)),
          ],
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
          child: Icon(step.$1,
              size: 16,
              color: done ? LightTokens.ctaText : LightTokens.muted(.55)),
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

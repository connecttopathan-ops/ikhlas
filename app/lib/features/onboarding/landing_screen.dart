import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// Landing — 2d light "sage ceremonial". Hero → what makes Ikhlaas different
/// (our four, as a compact icon grid) → how it works (5-step flow) → CTAs.
/// Curved motifs only — no squares or diamonds.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  // Ikhlaas's OWN differentiators — deliberately not "no photos / no chat"
  // (those are a competitor's product decisions, not ours). Each carries a
  // meaningful icon; copy is kept short so the four sit in a 2×2 grid.
  static const _differentiators = [
    (Icons.verified_user_outlined, 'Aqidah-gated',
        'Screened on creed and practice from the start.'),
    (Icons.how_to_reg_outlined, 'Application only',
        'Fewer than 4 in 10 accepted — serious by design.'),
    (Icons.groups_outlined, 'Wali-first',
        'A sister’s guardian is involved from the start.'),
    (Icons.favorite_border, 'Deen-first matching',
        'Matched on deen and intent — not looks or income.'),
  ];

  static const _flow = [
    ('Apply', 'A short, honest application.'),
    ('Verify', 'A selfie and government-ID confirm you are real.'),
    ('Match', 'Curated daily matches, ranked deen-first.'),
    ('Contact wali', 'On mutual interest, guardians are brought in.'),
    ('Nikah', 'Proceed offline, in shaa Allah.'),
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
            const SizedBox(height: 26),
            _eyebrow('WHAT MAKES IKHLAAS DIFFERENT'),
            const SizedBox(height: 14),
            _diffRow(_differentiators[0], _differentiators[1]),
            const SizedBox(height: 12),
            _diffRow(_differentiators[2], _differentiators[3]),

            // ---- How it works ----
            const SizedBox(height: 26),
            _eyebrow('HOW IT WORKS'),
            const SizedBox(height: 14),
            for (var i = 0; i < _flow.length; i++)
              _FlowStep(
                index: i + 1,
                title: _flow[i].$1,
                body: _flow[i].$2,
                isLast: i == _flow.length - 1,
              ),

            // ---- CTAs ----
            const SizedBox(height: 24),
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

  // Two equal-height differentiator cards side by side.
  static Widget _diffRow(
          (IconData, String, String) a, (IconData, String, String) b) =>
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _DiffCard(icon: a.$1, title: a.$2, body: a.$3)),
          const SizedBox(width: 12),
          Expanded(child: _DiffCard(icon: b.$1, title: b.$2, body: b.$3)),
        ]),
      );
}

/// One differentiator — a deep-green icon disc (gold glyph, matching the
/// how-it-works step circles) over a title and a short line.
class _DiffCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _DiffCard(
      {required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LightTokens.hairline.withValues(alpha: .5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: LightTokens.ctaBg),
          child: Icon(icon, size: 19, color: LightTokens.ctaText),
        ),
        const SizedBox(height: 10),
        Text(title,
            style: AppType.inter(14.5,
                weight: FontWeight.w600, color: LightTokens.ink)),
        const SizedBox(height: 3),
        Text(body,
            style: AppType.inter(12, color: LightTokens.muted(.72), height: 1.4)),
      ]),
    );
  }
}

/// One numbered step in the how-it-works flow, joined by a soft connector.
class _FlowStep extends StatelessWidget {
  final int index;
  final String title;
  final String body;
  final bool isLast;
  const _FlowStep(
      {required this.index,
      required this.title,
      required this.body,
      required this.isLast});
  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: LightTokens.ctaBg,
            ),
            child: Text('$index',
                style: AppType.inter(12,
                    weight: FontWeight.w600, color: LightTokens.ctaText)),
          ),
          if (!isLast)
            Expanded(
              child: Container(
                width: 1.5,
                margin: const EdgeInsets.symmetric(vertical: 3),
                color: LightTokens.hairline,
              ),
            ),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14, top: 2),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppType.inter(14.5,
                          weight: FontWeight.w600, color: LightTokens.ink)),
                  const SizedBox(height: 1),
                  Text(body,
                      style: AppType.inter(12.5,
                          color: LightTokens.muted(.72), height: 1.4)),
                ]),
          ),
        ),
      ]),
    );
  }
}

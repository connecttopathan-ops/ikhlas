import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// Landing — 2d light "sage ceremonial". Hero → what makes Ikhlaas different
/// (our four, not a competitor's) → how it works (5-step flow) → CTAs.
/// Curved motifs only (lozenge / round bullets) — no squares or diamonds.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  // Ikhlaas's OWN differentiators — deliberately not "no photos / no chat"
  // (those are a competitor's product decisions, not ours).
  static const _differentiators = [
    (
      'Aqidah-gated',
      'A pool screened on creed and practice from the very start.',
    ),
    (
      'Application only',
      'Fewer than 4 in 10 are accepted — seriousness by design.',
    ),
    (
      'Wali-first',
      'The guardian is involved from the start for every sister.',
    ),
    (
      'Deen-first matching',
      'Matched on deen and intent — never appearance or income.',
    ),
  ];

  static const _flow = [
    ('Apply', 'A short, honest application.'),
    ('Verify', 'A selfie and a government-ID confirm you are real.'),
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
              AppSpace.screenMargin, 40, AppSpace.screenMargin, 28),
          children: [
            // ---- Hero ----
            const Center(child: IkhlasLogo(size: 34)),
            const SizedBox(height: 30),
            Text('Where nikah begins with deen',
                textAlign: TextAlign.center,
                style:
                    AppType.fraunces(36, color: LightTokens.ink, height: 1.14)),
            const SizedBox(height: 14),
            Text(
                'A screened, application-only pool for Muslims serious '
                'about marriage.',
                textAlign: TextAlign.center,
                style: AppType.inter(14.5,
                    color: LightTokens.muted(.7), height: 1.5)),

            // ---- What makes Ikhlaas different ----
            const SizedBox(height: 40),
            _eyebrow('WHAT MAKES IKHLAAS DIFFERENT'),
            const SizedBox(height: 16),
            for (final d in _differentiators) _DiffRow(title: d.$1, body: d.$2),

            // ---- How it works ----
            const SizedBox(height: 34),
            _eyebrow('HOW IT WORKS'),
            const SizedBox(height: 18),
            for (var i = 0; i < _flow.length; i++)
              _FlowStep(
                index: i + 1,
                title: _flow[i].$1,
                body: _flow[i].$2,
                isLast: i == _flow.length - 1,
              ),

            // ---- CTAs ----
            const SizedBox(height: 32),
            PrimaryCta(
                label: 'Begin my application',
                onPressed: () => context.go('/login')),
            const SizedBox(height: 16),
            Center(
              child: QuietLink(
                  prefix: 'Already have an account?',
                  linkText: 'Sign in',
                  onTap: () => context.go('/login')),
            ),
            const SizedBox(height: 12),
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

/// One differentiator — a curved lozenge motif + title + one line.
class _DiffRow extends StatelessWidget {
  final String title;
  final String body;
  const _DiffRow({required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: LozengeMark(size: 26, opacity: .9),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: AppType.inter(15,
                    weight: FontWeight.w600, color: LightTokens.ink)),
            const SizedBox(height: 3),
            Text(body,
                style: AppType.inter(13,
                    color: LightTokens.muted(.72), height: 1.5)),
          ]),
        ),
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
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LightTokens.ctaBg,
            ),
            child: Text('$index',
                style: AppType.inter(13,
                    weight: FontWeight.w600, color: LightTokens.ctaText)),
          ),
          if (!isLast)
            Expanded(
              child: Container(
                width: 1.5,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: LightTokens.hairline,
              ),
            ),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppType.inter(15,
                          weight: FontWeight.w600, color: LightTokens.ink)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: AppType.inter(13,
                          color: LightTokens.muted(.72), height: 1.5)),
                ]),
          ),
        ),
      ]),
    );
  }
}

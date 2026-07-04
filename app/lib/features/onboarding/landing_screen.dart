import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// Landing. Two compositions per the spec's Decision:
/// dark → 2b bottom-anchored editorial · light → 2d centered ceremonial (flat).
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const _LandingDark2b() : const _LandingLight2d();
  }
}

/// ---- 2b: dark, bottom-anchored editorial ----
class _LandingDark2b extends StatelessWidget {
  const _LandingDark2b();

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Stack(
        children: [
          // Girih 340px bleeding off top-right @ 11%
          const Positioned(
              top: -110, right: -110, child: GirihMark(size: 340, opacity: .11)),
          Padding(
            padding: const EdgeInsets.all(AppSpace.screenMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wordmark top-left, Fraunces 21, gold "i"
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: 'i',
                      style: AppType.fraunces(21, color: DarkTokens.gold)),
                  TextSpan(
                      text: 'khlas',
                      style: AppType.fraunces(21, color: DarkTokens.ivory)),
                ])),
                const Spacer(),
                Text('MEMBERSHIP BY APPLICATION',
                    style: AppType.eyebrow(DarkTokens.gold)),
                const SizedBox(height: 14),
                Text('Ikhlas is for Muslims serious about nikah.',
                    style: AppType.fraunces(39,
                        color: DarkTokens.ivory, height: 1.09)),
                const SizedBox(height: 12),
                Text('Membership is by application.',
                    style:
                        AppType.inter(15, color: DarkTokens.muted(.62), height: 1.6)),
                const SizedBox(height: 20),
                const Hairline(),
                const SizedBox(height: 16),
                Row(children: [
                  const DiamondBullet(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Every member is screened and verified.',
                        style: AppType.inter(13, color: DarkTokens.muted())),
                  ),
                ]),
                const SizedBox(height: 24),
                PrimaryCta(
                    label: 'Begin my application',
                    onPressed: () => context.go('/login')),
                const SizedBox(height: 16),
                Center(
                  child: QuietLink(
                      prefix: 'Already a member?',
                      linkText: 'Sign in',
                      onTap: () => context.go('/login')),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---- 2d: light, centered ceremonial, flat (no girih art) ----
class _LandingLight2d extends StatelessWidget {
  const _LandingLight2d();

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.screenMargin),
        child: Column(
          children: [
            const Spacer(flex: 2),
            Text('إخلاص', style: AppType.amiri(17, color: LightTokens.goldArabic)),
            const SizedBox(height: 10),
            Text('ikhlas', style: AppType.fraunces(27, color: LightTokens.ink)),
            const SizedBox(height: 18),
            const Hairline(width: 40),
            const SizedBox(height: 28),
            Text('Ikhlas is for Muslims serious about nikah.',
                textAlign: TextAlign.center,
                style:
                    AppType.fraunces(36, color: LightTokens.ink, height: 1.12)),
            const SizedBox(height: 12),
            Text('Membership is by application.',
                textAlign: TextAlign.center,
                style: AppType.inter(15, color: LightTokens.muted(.62))),
            const SizedBox(height: 22),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const DiamondBullet(),
              const SizedBox(width: 10),
              Text('Every member is screened and verified.',
                  style: AppType.inter(13, color: LightTokens.muted())),
            ]),
            const Spacer(flex: 3),
            PrimaryCta(
                label: 'Begin my application',
                onPressed: () => context.go('/login')),
            const SizedBox(height: 16),
            QuietLink(
                prefix: 'Already a member?',
                linkText: 'Sign in',
                onTap: () => context.go('/login')),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

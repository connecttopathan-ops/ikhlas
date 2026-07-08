import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// Landing — 2d light centered ceremonial composition (flat, no girih art).
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.screenMargin),
        child: Column(
          children: [
            const Spacer(flex: 2),
            const IkhlasLogo(size: 34),
            const SizedBox(height: 28),
            Text('Ikhlaas is for Muslims serious about nikah.',
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

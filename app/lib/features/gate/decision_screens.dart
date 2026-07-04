import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// Approved — the welcome moment. Profile builder is the Week-3/4
/// destination; until then this screen is the resting state.
class ApprovedScreen extends StatelessWidget {
  const ApprovedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.screenMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            const GirihMark(size: 96),
            const SizedBox(height: 44),
            Text('أَهْلًا وَسَهْلًا',
                style: AppType.amiri(16, color: DarkTokens.gold)),
            const SizedBox(height: 8),
            Text('Welcome to Ikhlas',
                textAlign: TextAlign.center,
                style: AppType.fraunces(30, color: DarkTokens.ivory)),
            const SizedBox(height: 16),
            Text(
              'Your application has been accepted, alhamdulillah. You are '
              'now part of a pool where every single member is serious '
              'about nikah.',
              textAlign: TextAlign.center,
              style:
                  AppType.inter(14, color: DarkTokens.muted(.62), height: 1.7),
            ),
            const Spacer(flex: 2),
            PrimaryCta(
              label: 'Build my profile',
              onPressed: () => context.go('/profile-builder'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Soft rejection — warm, dignified, leaves the door open (PRD §4.1:
/// "Rejection copy is warm and leaves a door open"). Never shame.
class SoftRejectedScreen extends StatelessWidget {
  const SoftRejectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.screenMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 2),
            const Center(child: GirihMark(size: 72, opacity: .8)),
            const SizedBox(height: 40),
            Center(
              child: Text('Not just yet',
                  style: AppType.fraunces(30, color: DarkTokens.ivory)),
            ),
            const SizedBox(height: 18),
            Text(
              'JazakAllah khair for your honesty — it is the quality we '
              'value most. Based on your answers, Ikhlas may not be the '
              'right place for you at this moment.\n\n'
              'That is not a judgement of you; it is a reflection of how '
              'strictly we guard the seriousness of the pool. When your '
              'circumstances change, we would be honoured to review a new '
              'application.',
              style:
                  AppType.inter(14, color: DarkTokens.muted(.62), height: 1.75),
            ),
            const SizedBox(height: 28),
            Row(children: [
              const DiamondBullet(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'May Allah grant you a righteous spouse and ease your path.',
                    style: AppType.inter(13.5,
                        color: DarkTokens.ivory, height: 1.6)),
              ),
            ]),
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for the Week-3/4 profile builder so the approved CTA
/// has a destination.
class ProfileBuilderPlaceholder extends StatelessWidget {
  const ProfileBuilderPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => IkhlasScaffold(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const GirihMark(size: 64, opacity: .8),
            const SizedBox(height: 20),
            Text('Profile builder — coming next',
                style: AppType.fraunces(22, color: DarkTokens.ivory)),
            const SizedBox(height: 8),
            Text('Photos, bio prompts, preferences and Wali setup land here.',
                style: AppType.inter(13, color: DarkTokens.muted())),
          ]),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../providers/application_provider.dart';

/// "Application under review" — the exclusivity moment, not a spinner
/// (ikhlas-tech-requirements.md §4, screen 8). Slow-breathing girih mark,
/// reverent copy. Router redirects away the instant `users.status` moves.
class ReviewWaitScreen extends ConsumerStatefulWidget {
  const ReviewWaitScreen({super.key});
  @override
  ConsumerState<ReviewWaitScreen> createState() => _ReviewWaitScreenState();
}

class _ReviewWaitScreenState extends ConsumerState<ReviewWaitScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
      vsync: this, duration: const Duration(seconds: 5))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the user-doc stream warm so the router notices the decision.
    ref.watch(userDocProvider);

    return IkhlasScaffold(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.screenMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            AnimatedBuilder(
              animation: _breath,
              builder: (_, __) => GirihMark(
                size: 96,
                opacity: .55 + .45 * _breath.value,
              ),
            ),
            const SizedBox(height: 44),
            Text('قَيْدُ الْمُرَاجَعَة',
                style: AppType.amiri(15, color: DarkTokens.gold)),
            const SizedBox(height: 8),
            Text('Under review',
                textAlign: TextAlign.center,
                style: AppType.fraunces(30, color: DarkTokens.ivory)),
            const SizedBox(height: 16),
            Text(
              'Your application is with our review team. Every member of '
              'Ikhlas passes through this gate — it is what keeps the pool '
              'serious.',
              textAlign: TextAlign.center,
              style: AppType.inter(14, color: DarkTokens.muted(.62), height: 1.7),
            ),
            const SizedBox(height: 28),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const DiamondBullet(),
              const SizedBox(width: 10),
              Text('Decisions typically within 24 hours',
                  style: AppType.inter(13, color: DarkTokens.ivory)),
            ]),
            const Spacer(flex: 3),
            Text(
              'You may close the app — we will notify you.',
              style: AppType.inter(12, color: DarkTokens.muted()),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

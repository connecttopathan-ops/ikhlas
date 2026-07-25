import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../data/notifications/push_service.dart';
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
  void initState() {
    super.initState();
    // "We will notify you" — ask for notification permission exactly here,
    // where the promise is being made.
    PushService.register(ref.read(applicationRepositoryProvider));
  }

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
            Text('Application under review',
                textAlign: TextAlign.center,
                style: AppType.fraunces(28, color: DarkTokens.ivory)),
            const SizedBox(height: 24),
            // One surface, sub-steps inside it. Photo + ID land instantly;
            // eligibility, sincerity and identity are the real 24h review —
            // decided together in a single moderator pass.
            _step(Icons.check_circle,
                'Selfie & ID received', 'instant', done: true),
            const SizedBox(height: 14),
            _step(Icons.hourglass_top,
                'Eligibility, sincerity & identity — reviewing', 'within 24h',
                done: false),
            const Spacer(flex: 3),
            Text(
              "We'll notify you the moment it's done. You may close the app.",
              textAlign: TextAlign.center,
              style: AppType.inter(12.5, color: DarkTokens.muted()),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _step(IconData icon, String label, String meta,
          {required bool done}) =>
      Row(children: [
        Icon(icon, size: 20,
            color: done ? DarkTokens.gold : DarkTokens.muted(.7)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: AppType.inter(14,
                  color: done ? DarkTokens.ivory : DarkTokens.muted(.9))),
        ),
        Text(meta,
            style: AppType.inter(12, color: DarkTokens.muted(.7))),
      ]);
}

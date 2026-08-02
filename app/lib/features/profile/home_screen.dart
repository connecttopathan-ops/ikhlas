import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../data/notifications/push_service.dart';
import '../../providers/application_provider.dart';
import '../matches/match_batch.dart';

/// Resting state for approved members. Daily matches land here in
/// Phase 2 — until then this is the quiet, complete home.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    PushService.register(ref.read(applicationRepositoryProvider));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(userStatusProvider);
    final paused = status == 'paused';

    return IkhlasScaffold(
      safeArea: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Frosted app bar spanning full width — blurs the aurora behind it.
          SafeArea(
            bottom: false,
            child: GlassBar(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(children: [
                Image.asset('assets/brand/wordmark.png',
                    height: 24, filterQuality: FilterQuality.medium),
                const Spacer(),
                IconButton(
                  onPressed: () => context.go('/conversations'),
                  icon: Icon(Icons.chat_bubble_outline,
                      size: 21, color: DarkTokens.muted(.7)),
                ),
                IconButton(
                  onPressed: () => context.go('/settings'),
                  icon: Icon(Icons.settings_outlined,
                      size: 22, color: DarkTokens.muted(.7)),
                ),
              ]),
            ),
          ),
          if (paused)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const GirihMark(size: 88, opacity: .45),
                  const SizedBox(height: 40),
                  Text('Your profile is paused',
                      style: AppType.fraunces(28, color: DarkTokens.ivory)),
                  const SizedBox(height: 14),
                  Text(
                    'Hidden from matching until you resume — take the '
                    'time you need.',
                    textAlign: TextAlign.center,
                    style: AppType.inter(14,
                        color: DarkTokens.muted(.62), height: 1.7),
                  ),
                ]),
              ),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.screenMargin, 14, AppSpace.screenMargin, 0),
                child: const MatchBatch(),
              ),
            ),
        ],
      ),
    );
  }
}

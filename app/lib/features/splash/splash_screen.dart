import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';

/// 2a — Splash. Centered rite composition on emerald.
/// Motion: girih line draws itself; wordmark + tagline rise/fade,
/// staggered 300–450ms. Light status bar.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _girih =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _stagger =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _girih.forward().whenComplete(() => _stagger.forward());
    // Hand off to landing after the rite completes.
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) context.go('/landing');
    });
  }

  @override
  void dispose() {
    _girih.dispose();
    _stagger.dispose();
    super.dispose();
  }

  Widget _rise(Animation<double> parent, double from, double to, Widget child) {
    final anim = CurvedAnimation(
        parent: parent, curve: Interval(from, to, curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - anim.value)), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _girih,
              builder: (_, __) => GirihMark(size: 96, progress: _girih.value),
            ),
            const SizedBox(height: 28),
            _rise(_stagger, 0.0, 0.5,
                Text('إخلاص', style: AppType.amiri(17, color: DarkTokens.gold))),
            const SizedBox(height: 8),
            _rise(_stagger, 0.15, 0.7,
                Text('ikhlas',
                    style: AppType.fraunces(34, color: DarkTokens.ivory))),
            const SizedBox(height: 12),
            _rise(_stagger, 0.35, 1.0,
                Text('Where nikah begins with deen',
                    style: AppType.fraunces(15,
                        color: DarkTokens.muted(.62), style: FontStyle.italic))),
          ],
        ),
      ),
    );
  }
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../providers/application_provider.dart';

/// Settings — pause / resume, delete account (DPDP self-serve), sign out.
/// Pause & delete go through callable functions: `status` is
/// server-authoritative, clients can never write it directly.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  FirebaseFunctions get _fns =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  Future<void> _call(String name) async {
    setState(() => _busy = true);
    try {
      await _fns.httpsCallable(name).call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('That did not go through. Please try again.',
                style: AppType.inter(13))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteFlow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DarkTokens.bg,
        title: Text('Delete your account?',
            style: AppType.fraunces(20, color: DarkTokens.ivory)),
        content: Text(
            'Your profile, application and photos are permanently removed. '
            'This cannot be undone.',
            style: AppType.inter(13.5, color: DarkTokens.muted(.7), height: 1.6)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Keep my account',
                  style: AppType.inter(13.5, color: DarkTokens.gold))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete permanently',
                  style: AppType.inter(13.5, color: DarkTokens.muted()))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _fns.httpsCallable('deleteAccount').call();
      await FirebaseAuth.instance.signOut();
      if (mounted) context.go('/landing');
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Deletion failed. Please try again.',
                style: AppType.inter(13))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(userStatusProvider);
    final paused = status == 'paused';

    return IkhlasScaffold(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.screenMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Row(children: [
              IconButton(
                onPressed: () => context.go('/home'),
                icon: Icon(Icons.arrow_back,
                    size: 22, color: DarkTokens.muted(.7)),
              ),
              const SizedBox(width: 4),
              Text('Settings',
                  style: AppType.fraunces(26, color: DarkTokens.ivory)),
            ]),
            const SizedBox(height: 32),
            _row(
              title: paused ? 'Resume my profile' : 'Pause my profile',
              subtitle: paused
                  ? 'Return to the pool and daily matching.'
                  : 'Hide from matching without deleting — for Ramadan, '
                      'exams, or an istikhara period.',
              onTap: _busy
                  ? null
                  : () => _call(paused ? 'resumeAccount' : 'pauseAccount'),
            ),
            const Hairline(),
            _row(
              title: 'Sign out',
              subtitle: 'You can sign back in anytime.',
              onTap: _busy
                  ? null
                  : () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) context.go('/landing');
                    },
            ),
            const Hairline(),
            _row(
              title: 'Delete my account',
              subtitle: 'Permanent removal of your profile, application and '
                  'photos.',
              onTap: _busy ? null : _deleteFlow,
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _row(
          {required String title,
          required String subtitle,
          VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.inter(15.5, color: DarkTokens.ivory)),
            const SizedBox(height: 3),
            Text(subtitle,
                style: AppType.inter(12.5,
                    color: DarkTokens.muted(), height: 1.5)),
          ]),
        ),
      );
}

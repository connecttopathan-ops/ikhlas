import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../data/auth/auth_service.dart';
import '../../providers/application_provider.dart';

/// Login — Google + Email OTP. Design follows the dark-emerald system;
/// awaiting its dedicated spec in the next design batch (per spec "Next:").
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  bool _busy = false;
  bool _linkSent = false;

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      final cred = await GoogleAuth().signIn();
      final repo = ref.read(applicationRepositoryProvider);
      await repo.ensureUserDoc(
          email: cred.user?.email ?? '', authProvider: 'google');
      // Resume where they left off — never re-ask for a phone/details a
      // returning member already provided.
      final route = await repo.resolveEntryRoute();
      if (mounted) context.go(route);
    } on AuthCancelled {
      // user backed out — no error surface needed
    } on FirebaseAuthException catch (e) {
      _err('Sign-in failed (${e.code}). Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailLink() async {
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _err('Enter a valid email address.');
      return;
    }
    setState(() => _busy = true);
    try {
      await EmailOtpAuth().sendCode(email);
      setState(() => _linkSent = true);
    } on FirebaseAuthException catch (e) {
      _err('Could not send the link (${e.code}).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _err(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg, style: AppType.inter(13))));

  @override
  Widget build(BuildContext context) {
    return IkhlasScaffold(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.screenMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text('BEGIN YOUR APPLICATION',
                style: AppType.eyebrow(DarkTokens.gold)),
            const SizedBox(height: 14),
            Text("Let's verify it's you.",
                style: AppType.fraunces(32, color: DarkTokens.ivory, height: 1.1)),
            const SizedBox(height: 10),
            Text('Sign in to begin. Your application is private until submitted.',
                style: AppType.inter(14, color: DarkTokens.muted(.62))),
            const SizedBox(height: 40),
            // Google
            SizedBox(
              height: 56,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _google,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: DarkTokens.hairline(.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control)),
                ),
                child: Text('Continue with Google',
                    style: AppType.inter(15,
                        weight: FontWeight.w500, color: DarkTokens.ivory)),
              ),
            ),
            const SizedBox(height: 28),
            Row(children: [
              const Expanded(child: Hairline()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: AppType.inter(12, color: DarkTokens.muted())),
              ),
              const Expanded(child: Hairline()),
            ]),
            const SizedBox(height: 28),
            if (!_linkSent) ...[
              Text('EMAIL', style: AppType.eyebrow(DarkTokens.gold.withOpacity(.8))),
              const SizedBox(height: 4),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: AppType.inter(16, color: DarkTokens.ivory),
                cursorColor: DarkTokens.gold,
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  hintStyle: AppType.inter(16, color: DarkTokens.muted(.4)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: DarkTokens.gold.withOpacity(.65))),
                  focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: DarkTokens.gold)),
                ),
              ),
              const SizedBox(height: 28),
              PrimaryCta(
                  label: 'Send sign-in link',
                  loading: _busy,
                  onPressed: _busy ? null : _emailLink),
            ] else ...[
              Row(children: [
                const DiamondBullet(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'A sign-in link is on its way to ${_emailCtrl.text.trim()}. '
                      'Open it on this device to continue.',
                      style: AppType.inter(14, color: DarkTokens.ivory)),
                ),
              ]),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

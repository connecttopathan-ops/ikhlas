import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/widgets.dart';
import '../../data/auth/auth_service.dart';
import '../../providers/application_provider.dart';

/// Login — Google + Email OTP (6-digit code via Resend), in the light 2d theme.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Shared post-sign-in routing — resume where the member left off.
  Future<void> _enter(String email, String provider) async {
    final repo = ref.read(applicationRepositoryProvider);
    await repo.ensureUserDoc(email: email, authProvider: provider);
    final route = await repo.resolveEntryRoute();
    if (mounted) context.go(route);
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      final cred = await GoogleAuth().signIn();
      await _enter(cred.user?.email ?? '', 'google');
    } on AuthCancelled {
      // user backed out — no error surface needed
    } on FirebaseAuthException catch (e) {
      _err('Sign-in failed (${e.code}). Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _err('Enter a valid email address.');
      return;
    }
    setState(() => _busy = true);
    try {
      await EmailOtpAuth().sendCode(email);
      _codeCtrl.clear();
      setState(() => _codeSent = true);
    } on FirebaseFunctionsException catch (e) {
      _err(e.message ?? 'Could not send the code. Please try again.');
    } catch (_) {
      _err('Could not send the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _err('Enter the 6-digit code.');
      return;
    }
    setState(() => _busy = true);
    try {
      await EmailOtpAuth().verifyCode(email, code);
      await _enter(email, 'email');
    } on FirebaseFunctionsException catch (e) {
      _err(e.message ?? 'That code did not work. Please try again.');
    } catch (_) {
      _err('That code did not work. Please try again.');
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
            if (!_codeSent) ...[
              Text('EMAIL', style: AppType.eyebrow(DarkTokens.gold.withOpacity(.8))),
              const SizedBox(height: 4),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: AppType.inter(16, color: DarkTokens.ivory),
                cursorColor: DarkTokens.gold,
                onSubmitted: (_) => _busy ? null : _sendCode(),
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
                  label: 'Email me a code',
                  loading: _busy,
                  onPressed: _busy ? null : _sendCode),
            ] else ...[
              Row(children: [
                const DiamondBullet(),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'We sent a 6-digit code to ${_emailCtrl.text.trim()}. '
                      'Enter it below to continue.',
                      style: AppType.inter(14, color: DarkTokens.ivory)),
                ),
              ]),
              const SizedBox(height: 24),
              Text('CODE', style: AppType.eyebrow(DarkTokens.gold.withOpacity(.8))),
              const SizedBox(height: 4),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppType.inter(24, color: DarkTokens.ivory)
                    .copyWith(letterSpacing: 10),
                cursorColor: DarkTokens.gold,
                onChanged: (v) {
                  if (v.length == 6 && !_busy) _verifyCode();
                },
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  hintStyle: AppType.inter(24, color: DarkTokens.muted(.3))
                      .copyWith(letterSpacing: 10),
                  enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: DarkTokens.gold.withOpacity(.65))),
                  focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: DarkTokens.gold)),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryCta(
                  label: 'Verify & continue',
                  loading: _busy,
                  onPressed: _busy ? null : _verifyCode),
              const SizedBox(height: 20),
              Row(children: [
                QuietLink(
                    linkText: _busy ? 'Sending…' : 'Resend code',
                    onTap: _busy ? null : _sendCode),
                const SizedBox(width: 20),
                QuietLink(
                    linkText: 'Use a different email',
                    onTap: () => setState(() => _codeSent = false)),
              ]),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'portal.dart';
import 'tokens.dart';

/// Ikhlas Wali portal (PRD §4.5): magic-link + OTP, no app, no password.
/// A guardian opens the SMS link (?invite=...), enters the code, and sees
/// their ward's conversations at the permission level she chose.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const WaliApp());
}

class WaliApp extends StatelessWidget {
  const WaliApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ikhlas — Wali',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: T.bg,
        colorScheme: const ColorScheme.dark(
            surface: T.bg, primary: T.gold, onPrimary: T.ctaText),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
            .apply(bodyColor: T.ivory, displayColor: T.ivory),
      ),
      home: const _Gate(),
    );
  }
}

class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  final _code = TextEditingController();
  String? _inviteId;
  bool _busy = false;
  String? _error;
  String? _ward;

  @override
  void initState() {
    super.initState();
    _inviteId = Uri.base.queryParameters['invite'];
  }

  Future<void> _verify() async {
    if (_inviteId == null || _code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your SMS.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('waliVerify')
          .call({'inviteId': _inviteId, 'code': _code.text.trim()});
      final token = res.data['token'] as String;
      await FirebaseAuth.instance.signInWithCustomToken(token);
      setState(() => _ward = res.data['ward'] as String);
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? 'Verification failed.');
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ward != null) return WaliPortal(ward: _ward!);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ikhlas', style: T.fraunces(34, color: T.gold)),
                const SizedBox(height: 6),
                Text('Guardian portal', style: T.inter(15, color: T.muted)),
                const SizedBox(height: 28),
                Text(
                  _inviteId == null
                      ? 'Please open the link from the SMS invitation you '
                          'received.'
                      : 'You have been invited to oversee an application on '
                          'Ikhlas, an app for Muslims seeking nikah. Enter the '
                          '6-digit code sent to your phone.',
                  style: T.inter(14, color: T.ivory, height: 1.7),
                ),
                if (_inviteId != null) ...[
                  const SizedBox(height: 24),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: T.inter(22, color: T.ivory),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      hintStyle: T.inter(22, color: T.muted),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: T.hairline)),
                      focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: T.gold)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    style: FilledButton.styleFrom(
                        backgroundColor: T.gold,
                        foregroundColor: T.ctaText,
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _busy
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Continue',
                            style: T.inter(15, weight: FontWeight.w600)),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      style: T.inter(13, color: const Color(0xFFC08A6B))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

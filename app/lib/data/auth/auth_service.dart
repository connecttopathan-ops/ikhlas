import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// ============================================================
/// AuthProvider abstraction — the swappable seam.
/// Phase 1: Google + Email OTP (6-digit code via Resend). Phase 2: Phone
/// OTP joins behind the SAME pattern. Apple joins for iOS.
/// ============================================================
abstract class IkhlasAuthProvider {
  Future<UserCredential> signIn();
}

class GoogleAuth implements IkhlasAuthProvider {
  @override
  Future<UserCredential> signIn() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw AuthCancelled();
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return FirebaseAuth.instance.signInWithCredential(credential);
  }
}

/// Email OTP: a 6-digit code emailed via Resend (Cloud Functions), then
/// exchanged for a Firebase custom token. Needs no deep-linking, so it
/// works the moment the app is installed — unlike email-link sign-in.
/// Two-step: sendCode(email) → verifyCode(email, code).
class EmailOtpAuth {
  final _fns = FirebaseFunctions.instanceFor(region: 'asia-south1');

  /// Emails a fresh code. Throws FirebaseFunctionsException (with a
  /// human-readable `.message`) on rate-limit / send failure.
  Future<void> sendCode(String email) =>
      _fns.httpsCallable('sendEmailOtp').call({'email': email});

  /// Verifies the code and signs in. Throws FirebaseFunctionsException
  /// (`.message`) on a wrong/expired code.
  Future<UserCredential> verifyCode(String email, String code) async {
    final res = await _fns
        .httpsCallable('verifyEmailOtp')
        .call({'email': email, 'code': code});
    final token = (res.data as Map)['token'] as String;
    return FirebaseAuth.instance.signInWithCustomToken(token);
  }
}

class AuthCancelled implements Exception {}

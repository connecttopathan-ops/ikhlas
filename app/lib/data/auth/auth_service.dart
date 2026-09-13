import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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

/// Sign in with Apple. App Store Review Guideline 4.8 REQUIRES this wherever
/// a third-party sign-in (our Google button) is offered, so iOS cannot ship
/// without it.
///
/// Two Apple-specific traps handled here:
///  · Firebase must receive the RAW nonce whose SHA-256 was handed to Apple,
///    otherwise the credential is rejected.
///  · Apple returns the member's name ONLY on the first authorisation. If it
///    isn't persisted then it is gone for good, so it is written to the
///    Firebase profile immediately.
///
/// Note the email may be absent on later sign-ins, or be an Apple private
/// relay address when the member chose "Hide My Email" — Firebase keeps the
/// address captured at first sign-in, so `user.email` stays populated.
class AppleAuth implements IkhlasAuthProvider {
  /// Unreserved URI characters only, so the nonce survives the round trip.
  static String _rawNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  @override
  Future<UserCredential> signIn() async {
    final rawNonce = _rawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) throw AuthCancelled();
      rethrow;
    }

    final cred = await FirebaseAuth.instance.signInWithCredential(
      OAuthProvider('apple.com').credential(
        idToken: apple.identityToken,
        rawNonce: rawNonce,
      ),
    );

    // First authorisation only — capture the name before Apple stops sending it.
    final name = [apple.givenName, apple.familyName]
        .where((p) => p != null && p.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (name.isNotEmpty && (cred.user?.displayName ?? '').isEmpty) {
      await cred.user?.updateDisplayName(name);
    }
    return cred;
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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// ============================================================
/// AuthProvider abstraction — the swappable seam.
/// Phase 1: Google + Email OTP. Phase 2: Phone OTP joins behind the
/// SAME interface (config change, not a rewrite). Apple joins for iOS.
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

/// Email OTP via Firebase email-link sign-in.
/// Two-step: sendCode(email) → completeSignIn(email, link).
class EmailOtpAuth {
  static final _acs = ActionCodeSettings(
    url: 'https://ikhlaas.io/auth', // must be an authorized domain in Firebase
    handleCodeInApp: true,
    androidPackageName: 'io.ikhlaas.app',
    androidInstallApp: true,
    androidMinimumVersion: '21',
    iOSBundleId: 'io.ikhlaas.app',
  );

  Future<void> sendCode(String email) => FirebaseAuth.instance
      .sendSignInLinkToEmail(email: email, actionCodeSettings: _acs);

  Future<UserCredential> completeSignIn(String email, String emailLink) =>
      FirebaseAuth.instance
          .signInWithEmailLink(email: email, emailLink: emailLink);

  bool isSignInLink(String link) =>
      FirebaseAuth.instance.isSignInWithEmailLink(link);
}

class AuthCancelled implements Exception {}

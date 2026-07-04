import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Writes the front half of the application. The application doc becomes
/// IMMUTABLE after full submission (enforced by firestore.rules) — during
/// Week-1 flow we stage locally and create the user doc + declaration.
class ApplicationRepository {
  final _db = FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// Creates users/{uid} on first login (status: applying — the only
  /// status a client may set, per security rules).
  Future<void> ensureUserDoc({required String email, String? authProvider}) async {
    final doc = _db.collection('users').doc(_uid);
    final snap = await doc.get();
    if (!snap.exists) {
      await doc.set({
        'status': 'applying',
        'strikes': 0,
        'phoneVerified': false,
        'email': email,
        'authProvider': authProvider ?? 'unknown',
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Phone: MANDATORY collect in Phase 1, stored UNVERIFIED.
  Future<void> savePhone(String phoneE164) => _db
      .collection('users')
      .doc(_uid)
      .update({'phone': phoneE164, 'lastActiveAt': FieldValue.serverTimestamp()});

  /// Intent declaration — staged on the user's application draft.
  /// (Final immutable applications/{uid} doc is created at questionnaire
  /// submission in Week 2; the declaration payload is included then.)
  Future<void> saveIntentDeclaration(
      {required List<String> affirmations, required String typedName}) async {
    await _db.collection('users').doc(_uid).update({
      'draft.intentDeclaration': {
        'affirmations': affirmations,
        'typedName': typedName,
        'timestamp': FieldValue.serverTimestamp(),
      },
    });
  }
}

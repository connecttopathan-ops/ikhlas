import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/gate/questionnaire/questionnaire_models.dart';

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

  /// Live user doc — drives the status-based router guards.
  Stream<DocumentSnapshot<Map<String, dynamic>>> userDocStream() =>
      _db.collection('users').doc(_uid).snapshots();

  /// Submits the full application: profile facts onto users/{uid}
  /// (never protected fields), then the create-once applications/{uid}
  /// doc that the gate engine reacts to. Immutable from this moment
  /// (firestore.rules) — the audit trail begins here.
  Future<void> submitApplication(QuestionnaireAnswers a) async {
    final userRef = _db.collection('users').doc(_uid);
    final snap = await userRef.get();
    final draft =
        (snap.data()?['draft'] as Map<String, dynamic>?)?['intentDeclaration'];
    if (draft == null) {
      throw StateError('Intent declaration missing — cannot submit.');
    }

    await userRef.update({
      'gender': a.gender,
      'dob': Timestamp.fromDate(a.dob!),
      'profile.maritalStatus': a.maritalStatus,
      'profile.hasChildren': a.hasChildren,
      'profile.revert': a.revert,
      'profile.country': a.country.trim(),
      'profile.city': a.city.trim(),
      'profile.willingToRelocate': a.willingToRelocate,
      'profile.languages': a.languagesList,
      if (a.ethnicity.trim().isNotEmpty) 'profile.ethnicity': a.ethnicity.trim(),
      'profile.education': a.education.trim(),
      'profile.profession': a.profession.trim(),
      if (a.sect.trim().isNotEmpty) 'profile.sect': a.sect.trim(),
      if (a.madhhab.trim().isNotEmpty) 'profile.madhhab': a.madhhab.trim(),
      'lastActiveAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('applications').doc(_uid).set({
      'submittedAt': FieldValue.serverTimestamp(),
      'intentDeclaration': draft,
      'answers': a.toAnswersMap(),
    });
  }
}

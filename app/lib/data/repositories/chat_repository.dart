import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Guarded-chat data access. Every mutation goes through a callable so
/// the contact-info filter, adab gate and lifecycle rules can't be
/// bypassed by writing Firestore directly (rules deny client writes).
class ChatRepository {
  final _db = FirebaseFirestore.instance;
  final _fns = FirebaseFunctions.instanceFor(region: 'asia-south1');
  String get uid => FirebaseAuth.instance.currentUser!.uid;

  /// Active + recently closed conversations for the signed-in member.
  Stream<QuerySnapshot<Map<String, dynamic>>> conversationsStream() => _db
      .collection('conversations')
      .where('participants', arrayContains: uid)
      .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> conversationStream(
          String convId) =>
      _db.collection('conversations').doc(convId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String convId) =>
      _db
          .collection('conversations')
          .doc(convId)
          .collection('messages')
          .orderBy('at')
          .snapshots();

  Future<void> acknowledgeAdab(String convId) =>
      _fns.httpsCallable('acknowledgeAdab').call({'convId': convId});

  /// Throws FirebaseFunctionsException with the warning message when the
  /// text contains blocked contact info — the UI surfaces `.message`.
  Future<void> sendMessage(String convId, String text) =>
      _fns.httpsCallable('sendMessage').call({'convId': convId, 'text': text});

  Future<void> endWithDua(String convId) =>
      _fns.httpsCallable('endWithDua').call({'convId': convId});

  Future<void> grantPhotoReveal(String convId, {bool revoke = false}) => _fns
      .httpsCallable('grantPhotoReveal')
      .call({'convId': convId, 'revoke': revoke});

  // ---- Family Stage ----
  Future<void> requestFamilyStage(String convId) =>
      _fns.httpsCallable('requestFamilyStage').call({'convId': convId});

  Future<void> confirmFamilyStage(String convId) =>
      _fns.httpsCallable('confirmFamilyStage').call({'convId': convId});

  // ---- Moderation ----
  Future<void> reportUser(String reportedUid, String reason,
          {String? convId, String? detail}) =>
      _fns.httpsCallable('reportUser').call({
        'reportedUid': reportedUid,
        'reason': reason,
        if (convId != null) 'convId': convId,
        if (detail != null) 'detail': detail,
      });

  Future<void> blockUser(String otherUid) =>
      _fns.httpsCallable('blockUser').call({'otherUid': otherUid});
}

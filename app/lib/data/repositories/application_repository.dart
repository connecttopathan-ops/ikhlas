import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  /// Uploads the verification selfie to the private verification path
  /// (storage.rules: owner-write only, no client reads). Returns the
  /// storage path recorded on the application doc.
  Future<String> uploadSelfie(File image) async {
    final path = 'users/$_uid/verification/selfie.jpg';
    await FirebaseStorage.instance.ref(path).putFile(
        image, SettableMetadata(contentType: 'image/jpeg'));
    return path;
  }

  /// Submits the full application: profile facts onto users/{uid}
  /// (never protected fields), then the create-once applications/{uid}
  /// doc that the gate engine reacts to. Immutable from this moment
  /// (firestore.rules) — the audit trail begins here.
  Future<void> submitApplication(QuestionnaireAnswers a,
      {required String selfieStoragePath}) async {
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
      // Fraud/abuse signals, disclosed to the applicant on the
      // verification step. Every field degrades gracefully — a denied
      // permission never blocks submission.
      'client': await _collectClientContext(),
      // Manual capture in Phase 1 — the liveness SDK later swaps
      // `provider` and adds checkId/livenessResult on this same shape.
      'verification': {
        'selfie': {
          'provider': 'manual_capture',
          'storagePath': selfieStoragePath,
          'capturedAt': FieldValue.serverTimestamp(),
        },
      },
    });
  }

  /// Uploads one profile photo; slot 0 is the primary photo.
  Future<String> uploadProfilePhoto(File image, int slot) async {
    final path = 'users/$_uid/photos/photo_$slot.jpg';
    await FirebaseStorage.instance.ref(path).putFile(
        image, SettableMetadata(contentType: 'image/jpeg'));
    return path;
  }

  /// Saves the completed profile builder in one write. photoPrivacy
  /// defaults to blur_until_match upstream (PRD §4.3 — privacy default).
  Future<void> saveProfileBuilder({
    required List<String> photoPaths,
    required String photoPrivacy,
    required List<Map<String, String>> bioPrompts,
    required Map<String, dynamic> preferences,
    Map<String, dynamic>? wali,
  }) async {
    await _db.collection('users').doc(_uid).update({
      'photos': [
        for (var i = 0; i < photoPaths.length; i++)
          {'storagePath': photoPaths[i], 'order': i},
      ],
      'photoPrivacy': photoPrivacy,
      'profile.bioPrompts': bioPrompts,
      'preferences': preferences,
      'wali': wali,
      'profileComplete': true,
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  /// Registers an FCM token on the user doc (map keyed by token so
  /// multiple devices coexist and dead tokens can be pruned server-side).
  Future<void> saveFcmToken(String token) => _db
      .collection('users')
      .doc(_uid)
      .set({'fcmTokens': {token: true}}, SetOptions(merge: true));

  /// Today's batch date key — IST calendar day, matching the backend.
  static String todayIst() {
    final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return '${ist.year.toString().padLeft(4, '0')}-'
        '${ist.month.toString().padLeft(2, '0')}-'
        '${ist.day.toString().padLeft(2, '0')}';
  }

  /// Live stream of today's match entries (server-generated snapshots).
  Stream<QuerySnapshot<Map<String, dynamic>>> todayEntriesStream() => _db
      .collection('matches')
      .doc(_uid)
      .collection('batches')
      .doc(todayIst())
      .collection('entries')
      .snapshots();

  /// Express interest / pass — the only client-writable matching fields.
  Future<void> setEntryAction(String otherUid, String action) => _db
      .collection('matches')
      .doc(_uid)
      .collection('batches')
      .doc(todayIst())
      .collection('entries')
      .doc(otherUid)
      .update({'action': action, 'actionAt': FieldValue.serverTimestamp()});

  Future<Map<String, dynamic>> _collectClientContext() async {
    final device = <String, dynamic>{};
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        device.addAll({
          'platform': 'android',
          'manufacturer': info.manufacturer,
          'model': info.model,
          'osVersion': info.version.release,
          'sdkInt': info.version.sdkInt,
          'isPhysicalDevice': info.isPhysicalDevice,
        });
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        device.addAll({
          'platform': 'ios',
          'model': info.utsname.machine,
          'osVersion': info.systemVersion,
          'isPhysicalDevice': info.isPhysicalDevice,
        });
      }
    } catch (_) {}
    try {
      final pkg = await PackageInfo.fromPlatform();
      device['appVersion'] = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {}

    Map<String, dynamic>? location;
    var locationStatus = 'unavailable';
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        locationStatus = 'service_off';
      } else {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low, // coarse — city-level is enough
              timeLimit: Duration(seconds: 8),
            ),
          );
          location = {
            'lat': pos.latitude,
            'lng': pos.longitude,
            'accuracyM': pos.accuracy,
          };
          locationStatus = 'captured';
        } else {
          locationStatus = 'denied';
        }
      }
    } catch (_) {
      locationStatus = 'error';
    }

    return {
      'device': device,
      if (location != null) 'location': location,
      'locationStatus': locationStatus,
    };
  }
}

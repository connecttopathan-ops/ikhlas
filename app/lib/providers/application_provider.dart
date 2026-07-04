import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/application_repository.dart';

final applicationRepositoryProvider =
    Provider<ApplicationRepository>((ref) => ApplicationRepository());

/// Auth state stream — drives the router guards.
final authStateProvider =
    StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

/// Live users/{uid} doc for the signed-in user (null when signed out).
/// `users.status` here is what the router's gate guards key off.
final userDocProvider =
    StreamProvider<DocumentSnapshot<Map<String, dynamic>>?>((ref) {
  final auth = ref.watch(authStateProvider);
  final user = auth.value;
  if (user == null) return Stream.value(null);
  return ref.read(applicationRepositoryProvider).userDocStream();
});

/// Convenience view of the gate status: null until known.
final userStatusProvider = Provider<String?>((ref) {
  final doc = ref.watch(userDocProvider).value;
  if (doc == null || !doc.exists) return null;
  return doc.data()?['status'] as String?;
});

/// Whether the profile builder has been completed.
final profileCompleteProvider = Provider<bool>((ref) {
  final doc = ref.watch(userDocProvider).value;
  return doc?.data()?['profileComplete'] == true;
});

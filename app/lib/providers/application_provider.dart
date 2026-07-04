import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/application_repository.dart';

final applicationRepositoryProvider =
    Provider<ApplicationRepository>((ref) => ApplicationRepository());

/// Auth state stream — drives the router guards.
final authStateProvider =
    StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

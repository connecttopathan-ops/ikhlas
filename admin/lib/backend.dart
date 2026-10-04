import 'package:firebase_core/firebase_core.dart';

/// Single source of truth for the deployed Cloud Functions host.
///
/// The moderator portal reveals ID documents through `idDocImageRaw`, a plain
/// HTTPS function whose URL is handed to an image loader and so must be built
/// as a string. That string used to hardcode the project id, which meant a
/// project migration silently broke ID review with nothing to catch it at
/// compile time.
class Backend {
  /// Functions are pinned to asia-south1 (same region as Firestore).
  static const region = 'asia-south1';

  /// Absolute URL of a deployed HTTPS function.
  static String fn(String name) =>
      'https://$region-${Firebase.app().options.projectId}.cloudfunctions.net/$name';
}

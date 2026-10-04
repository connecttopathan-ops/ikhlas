import 'package:firebase_core/firebase_core.dart';

/// Single source of truth for the deployed Cloud Functions host.
///
/// Most backend calls go through the `cloud_functions` SDK, which resolves the
/// host itself. Two endpoints cannot: `photo` and `idDocImageRaw` are plain
/// HTTPS functions whose URLs are handed to an image loader, so they have to be
/// built as strings. Those strings used to hardcode the project id, which meant
/// a project migration silently broke image loading in a way no compiler would
/// catch.
///
/// Derived from the Firebase options the app was initialised with, so it
/// follows the project automatically.
class Backend {
  /// Functions are pinned to asia-south1 (same region as Firestore).
  static const region = 'asia-south1';

  /// Absolute URL of a deployed HTTPS function.
  static String fn(String name) =>
      'https://$region-${Firebase.app().options.projectId}.cloudfunctions.net/$name';
}

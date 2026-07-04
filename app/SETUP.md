# Ikhlas — Firebase + Flutter Setup (Week 1)

Follow top to bottom. ~30–40 min the first time.

## 1. Prerequisites
- Flutter SDK installed (`flutter --version` → 3.x+)
- A Google account for Firebase
- Node.js 18+ (for Cloud Functions, later in the week)

## 2. Create the Firebase project
1. Go to https://console.firebase.google.com → **Add project** → name it `ikhlas` (or `ikhlas-prod`).
2. Disable Google Analytics for now (optional; add later) → **Create project**.
3. **Set the region:** the first time you create Firestore, you pick the location — choose **asia-south1 (Mumbai)**. ⚠️ This is permanent per project; do not skip.

## 3. Enable the services
In the console:
- **Build → Authentication → Get started →** enable **Google** and **Email/Password** — and inside the Email/Password provider, also switch on **Email link (passwordless sign-in)**; `EmailOtpAuth` uses `sendSignInLinkToEmail`, which needs that toggle. Later add **Apple** for iOS.
- **Authentication → Settings → Authorized domains →** add `ikhlaas.io` (the email-link `ActionCodeSettings.url` in `lib/data/auth/auth_service.dart` points there).
- **Build → Firestore Database → Create database →** start in **production mode** (our rules lock it down) → location **asia-south1**.
- **Build → Storage → Get started →** same region.

## 4. Wire Flutter to Firebase (FlutterFire CLI)
```bash
# one-time installs
dart pub global activate flutterfire_cli
npm install -g firebase-tools
firebase login

# from app/ (the Flutter project root):
flutterfire configure --project=ikhlas-caecf
```
(`ikhlas-caecf` is the live project ID; `.firebaserc` already points at it.)

This generates `lib/firebase_options.dart` (replacing the committed placeholder stub) and registers the apps automatically. Select **android** (and later ios) when prompted; the Android package name is `io.ikhlaas.app` (already set in `android/app/build.gradle.kts`, matching `auth_service.dart`). The generated file contains client identifiers, not secrets — committing it is safe and keeps the project compiling from a fresh clone.

## 5. Install dependencies
From `ikhlas/`:
```bash
flutter pub get
```
(pubspec.yaml is already in the repo with everything Week 1 needs.)

## 6. Google Sign-In extra config
- **Android:** FlutterFire adds the config, but you must add your SHA-1 fingerprint in the Firebase console (Project Settings → your Android app → Add fingerprint). Get it with:
  ```bash
  cd android && ./gradlew signingReport   # copy the SHA-1 from the debug variant
  ```
- **iOS:** add the reversed client ID to `ios/Runner/Info.plist` URL schemes (FlutterFire prints instructions).

## 7. Deploy the security rules
```bash
# from app/ — firebase.json + .firebaserc are checked in
firebase deploy --only firestore:rules,storage
```
(`firestore.rules` and `storage.rules` are in `firebase/`.)

## 8. Run it on an Android emulator
```bash
# one-time: create an emulator if you don't have one
sdkmanager "system-images;android-36;google_apis;x86_64" "emulator"
avdmanager create avd -n ikhlas_dev -d pixel_7 -k "system-images;android-36;google_apis;x86_64"

flutter emulators --launch ikhlas_dev
flutter run
```
You should see the splash → landing → login → phone capture → intent declaration flow.

---
**What's NOT set up yet (by design):** selfie SDK (Week 3), Cloud Functions gate engine (Week 2), AI triage (Week 3), admin dashboard (Week 3). Week 1 is auth + the front of the gate.

#!/usr/bin/env bash
# Ikhlaas deploy — functions, rules, hosting (admin + wali portal), and the
# member APK. Run from the repo root with the Firebase CLI logged in
# (`firebase login`) and Flutter on PATH.
#
#   ./deploy.sh              # everything
#   ./deploy.sh functions    # functions + firestore/storage rules only
#   ./deploy.sh admin        # build admin web + APK, deploy admin hosting
#   ./deploy.sh wali         # build + deploy the wali portal hosting
#   ./deploy.sh hosting      # admin + wali hosting (+ APK)
#
# Prereqs (one-time):
#   firebase functions:secrets:set WHATSAPP_TOKEN   # any value; manual path
#     stays active until config/whatsapp is set. Deploy fails without it.
set -euo pipefail

PROJECT="ikhlas-caecf"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-all}"
cd "$ROOT"

log() { printf '\n\033[1;33m▶ %s\033[0m\n' "$1"; }

deploy_functions() {
  log "Functions + Firestore/Storage rules"
  ( cd app/functions && npm ci )
  ( cd app && firebase deploy \
      --only functions,firestore:rules,firestore:indexes,storage \
      --project "$PROJECT" --non-interactive )
}

build_admin() {
  log "Build admin web"
  ( cd admin && flutter pub get && flutter build web --release )
}

build_apk() {
  log "Build member APK"
  ( cd app && flutter pub get && flutter build apk --release )
  cp app/build/app/outputs/flutter-apk/app-release.apk admin/build/web/ikhlas.apk
  log "APK copied into admin hosting ($(du -h admin/build/web/ikhlas.apk | cut -f1))"
}

build_wali() {
  log "Build wali portal web"
  ( cd wali && flutter pub get && flutter build web --release )
}

deploy_admin() {
  build_admin
  build_apk
  log "Deploy admin hosting"
  firebase deploy --only hosting:ikhlas-admin --project "$PROJECT" --non-interactive
}

deploy_wali() {
  build_wali
  log "Deploy wali hosting"
  firebase deploy --only hosting:ikhlas-wali --project "$PROJECT" --non-interactive
}

case "$TARGET" in
  functions) deploy_functions ;;
  admin)     deploy_admin ;;
  wali)      deploy_wali ;;
  hosting)   deploy_admin; deploy_wali ;;
  all)       deploy_functions; deploy_admin; deploy_wali ;;
  *) echo "Unknown target: $TARGET (functions|admin|wali|hosting|all)"; exit 1 ;;
esac

log "Done. Admin: https://ikhlas-admin.web.app   Wali: https://ikhlas-wali.web.app"

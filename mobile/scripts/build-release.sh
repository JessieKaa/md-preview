#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "[mobile-release] root: $ROOT"

if [ -f "$ROOT/.env.mobile-release" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env.mobile-release"
  set +a
fi

echo "[mobile-release] Android release APK/AAB"
(
  cd mobile/android
  gradle :app:clean :app:assembleRelease :app:bundleRelease
)

ANDROID_APK_DIR="$ROOT/mobile/android/app/build/outputs/apk/release"
mapfile -t ANDROID_APKS < <(find "$ANDROID_APK_DIR" -maxdepth 1 -type f -name '*.apk' | sort)
ANDROID_AAB="$ROOT/mobile/android/app/build/outputs/bundle/release/app-release.aab"

if [ "${#ANDROID_APKS[@]}" -eq 0 ]; then
  echo "[mobile-release] Android APKs: none found"
else
  echo "[mobile-release] Android APKs:"
  for apk in "${ANDROID_APKS[@]}"; do
    echo "  - $apk"
  done
fi

echo "[mobile-release] Android AAB: $ANDROID_AAB"

if command -v xcodegen >/dev/null 2>&1 && command -v xcodebuild >/dev/null 2>&1; then
  echo "[mobile-release] iOS project generation"
  (
    cd mobile/ios
    xcodegen generate
    if xcodebuild -project MDPreviewMobile.xcodeproj -scheme MDPreviewMobile -showdestinations 2>&1 | grep -q "not installed"; then
      echo "[mobile-release] iOS archive skipped: Xcode reports iOS platform/destination is not installed"
      exit 0
    fi
    if [ -n "${MD_PREVIEW_IOS_TEAM_ID:-}" ]; then
      xcodebuild archive \
        -project MDPreviewMobile.xcodeproj \
        -scheme MDPreviewMobile \
        -destination 'generic/platform=iOS' \
        -archivePath "$ROOT/mobile/ios/build/MDPreviewMobile.xcarchive" \
        DEVELOPMENT_TEAM="$MD_PREVIEW_IOS_TEAM_ID"
    else
      xcodebuild \
        -project MDPreviewMobile.xcodeproj \
        -scheme MDPreviewMobile \
        -destination 'generic/platform=iOS' \
        CODE_SIGNING_ALLOWED=NO \
        build
    fi
  )
else
  echo "[mobile-release] iOS skipped: xcodegen or xcodebuild missing"
fi

echo "[mobile-release] done"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [ -f "$ROOT/.env.mobile-release" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/.env.mobile-release"
  set +a
fi

fail() {
  echo "[release-readiness] FAIL: $*" >&2
  exit 1
}

echo "[release-readiness] root: $ROOT"

test -f mobile/ios/MDPreviewMobile/PrivacyInfo.xcprivacy || fail "missing iOS privacy manifest"
plutil -lint mobile/ios/MDPreviewMobile/Info.plist mobile/ios/MDPreviewMobile/PrivacyInfo.xcprivacy >/dev/null
python3 -m json.tool mobile/ios/MDPreviewMobile/Assets.xcassets/Contents.json >/dev/null
python3 -m json.tool mobile/ios/MDPreviewMobile/Assets.xcassets/AppIcon.appiconset/Contents.json >/dev/null

echo "[release-readiness] Android release build"
(
  cd mobile/android
  gradle :app:assembleRelease :app:bundleRelease
)

APK_DIR="mobile/android/app/build/outputs/apk/release"
mapfile -t APKS < <(find "$APK_DIR" -maxdepth 1 -type f -name '*.apk' | sort)
[ "${#APKS[@]}" -ge 3 ] || fail "expected at least 3 Android release APKs"
for abi in arm64-v8a armeabi-v7a x86_64; do
  find "$APK_DIR" -maxdepth 1 -type f -name "*${abi}*.apk" | grep -q . || fail "missing Android release APK for ${abi}"
done
test -f mobile/android/app/build/outputs/bundle/release/app-release.aab || fail "missing Android release AAB"

AAPT="$(find "$HOME/Library/Android/sdk/build-tools" -name aapt -type f | sort | tail -1 || true)"
if [ -n "$AAPT" ]; then
  for apk in "${APKS[@]}"; do
    "$AAPT" dump permissions "$apk" | grep -q "INTERNET" && fail "Android release requests INTERNET permission: $apk"
    "$AAPT" dump xmltree "$apk" AndroidManifest.xml | grep -q "android.intent.action.VIEW" || fail "Android VIEW intent missing: $apk"
    "$AAPT" dump xmltree "$apk" AndroidManifest.xml | grep -q "text/markdown" || fail "Android markdown MIME missing: $apk"
  done
fi

APKSIGNER="$(find "$HOME/Library/Android/sdk/build-tools" -name apksigner -type f | sort | tail -1 || true)"
if [ -n "${MD_PREVIEW_ANDROID_KEYSTORE:-}" ]; then
  if [ -n "$APKSIGNER" ]; then
    for apk in "${APKS[@]}"; do
      "$APKSIGNER" verify --verbose "$apk" >/dev/null || fail "Android release APK is not signed: $apk"
    done
  fi
  jarsigner -verify mobile/android/app/build/outputs/bundle/release/app-release.aab >/dev/null 2>&1 || fail "Android release AAB is not signed"
else
  echo "[release-readiness] Android signing env not set; release artifacts are buildable but not store-uploadable"
fi

if command -v xcodegen >/dev/null 2>&1; then
  echo "[release-readiness] iOS project generation"
  (cd mobile/ios && xcodegen generate)
else
  fail "xcodegen missing"
fi

if command -v xcrun >/dev/null 2>&1; then
  echo "[release-readiness] iOS Swift parse"
  xcrun --sdk iphoneos swiftc -parse \
    mobile/ios/MDPreviewMobile/AppDelegate.swift \
    mobile/ios/MDPreviewMobile/PreviewViewController.swift
fi

echo "[release-readiness] OK"

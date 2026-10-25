#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: Universal build failed at line $LINENO. Check the diagnostic above." >&2' ERR
cd "$(dirname "$0")/.."

# semver.txt line 1 is the single source of truth for the release version.
version="$(head -n 1 semver.txt | tr -d '[:space:]')"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: semver.txt line 1 must be MAJOR.MINOR.PATCH (found '$version')." >&2
  exit 1
fi
if [[ -n "${BUILD_NUMBER:-}" && ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: BUILD_NUMBER must be a positive integer (found '$BUILD_NUMBER')." >&2
  exit 1
fi
identity="${CODE_SIGN_IDENTITY:--}"
settings=()
if [[ "$identity" == "-" ]]; then settings+=("CODE_SIGN_IDENTITY=-"); fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then settings+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER"); fi
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then settings+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"); fi
output="${OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"

# Build outside the checkout: cloud-synced folders add Finder metadata that breaks codesign.
derived="$(mktemp -d "${TMPDIR:-/tmp}/Silentio-build.XXXXXX")"
trap 'rm -rf "$derived"' EXIT
# Mapping the checkout and build paths to "." keeps usernames and folders out of the binaries.
echo "==> Building universal app with Xcode (arm64 + x86_64)"
xcodebuild -project Silentio.xcodeproj -scheme Silentio -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO MARKETING_VERSION="$version" \
  "${settings[@]}" DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES \
  OTHER_SWIFT_FLAGS="\$(inherited) -file-prefix-map $PWD=. -file-prefix-map $derived=." \
  OTHER_CFLAGS="\$(inherited) -ffile-prefix-map=$PWD=. -ffile-prefix-map=$derived=." \
  OTHER_LDFLAGS="\$(inherited) -Wl,-oso_prefix,$derived" \
  build

echo "==> Xcode build completed; preparing app for signing"
app="$derived/package/Silentio.app"
mkdir -p "$derived/package"
ditto --norsrc "$derived/Build/Products/Release/Silentio.app" "$app"
xattr -cr "$app"
# Sign inside out, preserving Sparkle's sandbox entitlements on its nested services.
signing=(--force --options runtime --sign "$identity")
if [[ "$identity" != "-" ]]; then signing+=(--timestamp); fi
framework="$app/Contents/Frameworks/Sparkle.framework"
echo "==> Signing Sparkle Autoupdate"
codesign "${signing[@]}" "$framework/Versions/B/Autoupdate"
while IFS= read -r -d '' bundle; do
  printf '==> Signing %s\n' "${bundle#"$app/"}"
  codesign "${signing[@]}" --preserve-metadata=entitlements "$bundle"
done < <(find "$framework" -depth -type d \
  \( -name '*.xpc' -o -name '*.app' -o -name '*.framework' \) -print0)
# Re-signing must keep the sandbox and Apple Events entitlements Xcode applied.
echo "==> Signing Silentio.app"
codesign "${signing[@]}" --preserve-metadata=entitlements "$app"
echo "==> Verifying signatures, entitlements, architectures and embedded paths"
codesign --verify --deep --strict "$app"
entitlements="$(codesign -d --entitlements - --xml "$app" 2> /dev/null)"
for entitlement in com.apple.security.app-sandbox com.apple.security.network.client \
  com.apple.security.automation.apple-events; do
  if [[ "$entitlements" != *"<key>$entitlement</key><true/>"* ]]; then
    echo "ERROR: Signed app is missing the $entitlement entitlement." >&2
    exit 1
  fi
done
executable="$app/Contents/MacOS/Silentio"
lipo -verify_arch arm64 "$executable"
lipo -verify_arch x86_64 "$executable"
file "$executable"
if strings -a "$executable" | grep '/Users/' > /dev/null; then
  echo "ERROR: $executable embeds a local /Users/ path." >&2
  exit 1
fi
# Exclude cloud/Finder extended attributes from the redistributable archive.
echo "==> Creating ZIP and exporting app"
ditto -c -k --norsrc --keepParent "$app" "$derived/package/Silentio.zip"
# Replace only these named build products; never remove the output directory itself.
rm -rf "$output/Silentio.app"
ditto --norsrc "$app" "$output/Silentio.app"
cp "$derived/package/Silentio.zip" "$output/Silentio.zip"
xattr -cr "$output/Silentio.app"
if ! codesign --verify --deep --strict "$output/Silentio.app"; then
  echo "ERROR: Exported app failed verification. Try OUTPUT_DIR in a non-cloud-synced folder." >&2
  exit 1
fi
printf 'Built Silentio %s: %s\nRun: open "%s"\n' \
  "$version" "$output/Silentio.app" "$output/Silentio.app"

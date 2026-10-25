#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: Validation failed at line $LINENO. Check the diagnostic above." >&2' ERR
cd "$(dirname "$0")/.."

# --unit-only skips the UI test and the coverage gate. The UI test drives the menu bar
# and settings window, so it needs a logged-in graphical session.
unit_only=false
case "${1:-}" in
  "") ;;
  --unit-only) unit_only=true ;;
  *)
    echo "ERROR: Unknown option '$1'. Usage: bash scripts/test.sh [--unit-only]" >&2
    exit 2
    ;;
esac

xcrun swift-format lint --strict --recursive Silentio SilentioTests SilentioUITests \
  scripts/generate-menu-bar-icon.swift
bash -n scripts/build.sh scripts/test.sh scripts/release.sh scripts/generate-app-icon.sh
xmllint --noout appcast.xml
# Release pipeline: the appcast updater must keep stable entries and prune old betas.
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests

# Keep build products outside the checkout: cloud-synced folders break codesign.
work="$(mktemp -d "${TMPDIR:-/tmp}/Silentio-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
arch="$(uname -m)"
xcodebuild -project Silentio.xcodeproj -scheme Silentio -configuration Debug \
  -destination "platform=macOS,arch=$arch" -derivedDataPath "$work/DerivedData" \
  -enableCodeCoverage YES -quiet build-for-testing
xctestrun="$(find "$work/DerivedData/Build/Products" -maxdepth 1 -name '*.xctestrun' | head -n 1)"
if [[ -z "$xctestrun" ]]; then
  echo "ERROR: build-for-testing produced no .xctestrun file in $work/DerivedData." >&2
  exit 1
fi
only_testing=()
if [[ "$unit_only" == true ]]; then only_testing=(-only-testing:SilentioTests); fi
# Pin the host app's language so local machines and CI runners resolve the same UI strings.
/usr/bin/plutil -replace SilentioTests.CommandLineArguments \
  -json '["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]' "$xctestrun"
if ! xcodebuild -xctestrun "$xctestrun" -destination "platform=macOS,arch=$arch" \
  ${only_testing[@]+"${only_testing[@]}"} -parallel-testing-enabled NO \
  -resultBundlePath "$work/TestResults.xcresult" -quiet test-without-building; then
  # -quiet hides Swift Testing issues; print them from the result bundle for CI logs.
  xcrun xcresulttool get test-results summary --path "$work/TestResults.xcresult" \
    | /usr/bin/python3 -c '
import json
import sys

for failure in json.load(sys.stdin).get("testFailures", []):
    name = failure.get("testName")
    text = failure.get("failureText")
    print(f"FAILED {name}: {text}", file=sys.stderr)
' || true
  echo "ERROR: Xcode tests failed. See the failures above." >&2
  exit 1
fi

if [[ "$unit_only" == true ]]; then
  echo "Unit tests passed. The UI test and the coverage gate were skipped (--unit-only)."
  exit 0
fi

# Production code is the app target; test bundles and the UI test runner are excluded.
xcrun xccov view --report --json "$work/TestResults.xcresult" > "$work/coverage.json"
/usr/bin/python3 - "$work/coverage.json" <<'PY'
import json
import sys

targets = json.load(open(sys.argv[1]))["targets"]
production = [t for t in targets
              if not t["name"].endswith((".xctest", "-Runner.app"))]
for target in production:
    print(f'{target["name"]}: {100 * target["lineCoverage"]:.2f}%')
covered = sum(t["coveredLines"] for t in production)
executable = sum(t["executableLines"] for t in production)
percent = 100 * covered / executable
print(f"Production line coverage: {percent:.2f}% ({covered}/{executable} lines)")
if percent <= 80:
    sys.exit("ERROR: Production line coverage must be greater than 80%.")
PY

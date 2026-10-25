#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
master_icon="$repository_root/Design/AppIcon-master.png"
icon_set="$repository_root/Silentio/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$master_icon" ]]; then
  echo "Missing icon source: $master_icon" >&2
  exit 1
fi

for size in 16 32 64 128 256 512 1024; do
  sips -s format png -z "$size" "$size" "$master_icon" \
    --out "$icon_set/icon_${size}.png" >/dev/null
done

echo "Generated Silentio app icons in $icon_set"

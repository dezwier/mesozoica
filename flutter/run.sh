#!/usr/bin/env bash
# Local helper so Mapbox public token is always passed.
# Usage: ./run.sh   or   ./run.sh -d <deviceId> --release
set -euo pipefail
cd "$(dirname "$0")"

DEFINES=".dart_defines.json"
SECRETS="ios/Flutter/MapboxSecrets.xcconfig"

if [[ ! -f "$DEFINES" ]]; then
  echo "Missing $DEFINES — copy your pk.* token there first." >&2
  exit 1
fi

# Keep iOS Info.plist $(MAPBOX_ACCESS_TOKEN) in sync with dart-defines.
TOKEN="$(python3 -c "import json; print(json.load(open('$DEFINES'))['MAPBOX_ACCESS_TOKEN'])")"
if [[ -z "$TOKEN" || "$TOKEN" != pk.* ]]; then
  echo "MAPBOX_ACCESS_TOKEN in $DEFINES must be a public pk.* token." >&2
  exit 1
fi
printf 'MAPBOX_ACCESS_TOKEN=%s\n' "$TOKEN" > "$SECRETS"

exec flutter run --dart-define-from-file="$DEFINES" "$@"

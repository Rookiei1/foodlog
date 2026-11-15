#!/bin/bash
# Multi-screen screenshots for FoodLog on iPhone simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/screenshots"
mkdir -p "$OUT"
cp "$ROOT/FoodLog/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "$OUT/AppIcon.png"
sips -z 180 180 "$OUT/AppIcon.png" --out "$OUT/AppIcon-180.png" >/dev/null

APP="$(find "$ROOT/build/DerivedData" -path '*Debug-iphonesimulator/FoodLog.app' -type d | head -n 1)"
if [[ -z "$APP" ]]; then
  echo "Debug app was not built." >&2
  exit 1
fi

python3 - <<'PY' > "$OUT/devices.txt"
import json, subprocess
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
phones = []
for runtime, devices in data["devices"].items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and "iPhone" in device.get("name", ""):
            phones.append(device)

def pick(predicate):
    for device in phones:
        if predicate(device["name"]):
            return device
    return None

regular = (
    pick(lambda name: name in {"iPhone 16", "iPhone 17"})
    or pick(lambda name: "Pro" in name and "Max" not in name)
    or (phones[0] if phones else None)
)
if regular is None:
    raise SystemExit("No iPhone simulator is available")
print(regular["udid"])
print(regular["name"].replace(" ", "-"))
PY
PICKED=()
while IFS= read -r line; do
  PICKED+=("$line")
done < "$OUT/devices.txt"

UDID="${PICKED[0]}"
NAME="${PICKED[1]}"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

capture_screen() {
  local outfile="$1"
  shift
  xcrun simctl terminate "$UDID" com.rookiei1.foodlog || true
  xcrun simctl launch "$UDID" com.rookiei1.foodlog -FoodLogInMemoryStore -FoodLogSeedSample "$@"
  sleep 3
  xcrun simctl io "$UDID" screenshot "$OUT/$outfile"
}

capture_screen "01-home-dashboard.png" -FoodLogInitialTab dashboard
cp "$OUT/01-home-dashboard.png" "$OUT/home-${NAME}.png"
capture_screen "02-ai-photo-sheet.png" -FoodLogInitialTab dashboard -FoodLogOpenPhotoSheet
capture_screen "03-food-list.png" -FoodLogInitialTab food
capture_screen "04-weight-chart.png" -FoodLogInitialTab weight
capture_screen "05-ai-analysis.png" -FoodLogInitialTab analysis
capture_screen "06-settings.png" -FoodLogInitialTab settings

find "$OUT" -name '*.png' -print

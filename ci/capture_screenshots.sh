#!/bin/bash
# Home screenshots for FoodLog on iPhone simulator.
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

shoot() {
  local udid="$1"
  local name="$2"
  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl install "$udid" "$APP"
  xcrun simctl terminate "$udid" com.rookiei1.foodlog || true
  xcrun simctl launch "$udid" com.rookiei1.foodlog -FoodLogInMemoryStore -FoodLogSeedSample
  sleep 4
  xcrun simctl io "$udid" screenshot "$OUT/home-${name}.png"
}

shoot "${PICKED[0]}" "${PICKED[1]}"
find "$OUT" -name '*.png' -print

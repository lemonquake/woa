#!/bin/sh
# Parse-check only the named scripts (faster than tools/check.sh while building).
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd /a/Python/woa
"$GODOT" --headless --path . --import >/dev/null 2>&1
for f in "$@"; do
  out=$(timeout 120 "$GODOT" --headless --path . --check-only --script "$f" 2>&1 | grep -A1 "SCRIPT ERROR\|ERROR:" | grep -v "^--")
  if [ -n "$out" ]; then echo "== $f"; echo "$out" | head -20; fi
done
echo done

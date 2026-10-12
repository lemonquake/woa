#!/bin/sh
# Parse-check every GDScript file headless; prints only errors with locations.
GODOT="/a/Installer/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe"
cd /a/Python/woa
"$GODOT" --headless --path . --import >/dev/null 2>&1
for f in $(find src tests -name "*.gd"); do
  out=$(timeout 120 "$GODOT" --headless --path . --check-only --script "$f" 2>&1 | grep -A1 "SCRIPT ERROR" | grep -v "^--")
  if [ -n "$out" ]; then echo "== $f"; echo "$out" | head -${2:-12}; fi
done
# Naming rule (lemondev/references/naming.md): banned words and invented compounds in player-visible text.
python tools/check_names.py || exit 1

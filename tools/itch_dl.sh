#!/bin/sh
# Download a free itch.io asset file: itch_dl.sh <game_url> <upload_id> <out_file>
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
GAME="$1"; UP="$2"; OUT="$3"
T=$(mktemp -d)
curl -sL -c "$T/cj" -A "$UA" "$GAME" -o "$T/p.html"
CSRF=$(grep -o 'name="csrf_token" value="[^"]*"' "$T/p.html" | head -1 | sed 's/.*value="//;s/"//')
URL=$(curl -sL -b "$T/cj" -c "$T/cj" -A "$UA" -X POST --data-urlencode "csrf_token=$CSRF" "$GAME/download_url" | python -c "import json,sys;print(json.load(sys.stdin)['url'])")
curl -sL -b "$T/cj" -c "$T/cj" -A "$UA" "$URL" -o "$T/d.html"
CSRF2=$(grep -o 'name="csrf_token" value="[^"]*"' "$T/d.html" | head -1 | sed 's/.*value="//;s/"//')
if [ "$UP" = "list" ]; then
  python - "$T/d.html" <<'PY'
import re,sys
h=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
print(list(zip(re.findall(r'data-upload_id="(\d+)"',h),re.findall(r'class="upload_name"[^>]*>.*?title="([^"]+)"',h,re.S),re.findall(r'class="file_size"[^>]*><span>([^<]+)</span>',h))))
PY
  exit 0
fi
F=$(curl -sL -b "$T/cj" -c "$T/cj" -A "$UA" -e "$URL" -H "X-Requested-With: XMLHttpRequest" -X POST --data-urlencode "csrf_token=$CSRF2" "$GAME/file/$UP?source=game_download" | python -c "import json,sys;print(json.load(sys.stdin)['url'])")
curl -sL -A "$UA" "$F" -o "$OUT"
ls -la "$OUT"
rm -rf "$T"

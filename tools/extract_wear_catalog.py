"""Build assets/characters/hero/wear/catalog.json: wear id -> {name, slot} from beyond-heroes item data."""
import json, os, re, sys
BH = sys.argv[1]
WEAR = "assets/characters/hero/wear"
ids = sorted(f[:-4] for f in os.listdir(WEAR) if f.endswith(".glb"))
src = ""
for root, _, files in os.walk(os.path.join(BH, "src")):
    for f in files:
        if f.endswith(".gd"):
            src += open(os.path.join(root, f), encoding="utf-8").read() + "\n"
pat = re.compile(r'&"([a-z0-9_]+)",\s*"([^"]+)",\s*&"([a-z_0-9]+)"')
found = {m.group(1): (m.group(2), m.group(3)) for m in pat.finditer(src)}
man = json.load(open(os.path.join(WEAR, "manifest.json")))["items"]
out, missing = {}, []
for i in ids:
    if i in found:
        out[i] = {"name": found[i][0], "slot": found[i][1]}
    else:
        missing.append(i)
print("mapped", len(out), "missing", len(missing))
print(missing)
from collections import Counter
print(Counter(v["slot"] for v in out.values()))
json.dump({"items": out, "missing": missing}, open("work/wear_catalog_raw.json", "w"), indent=1)

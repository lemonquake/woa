"""Build assets/characters/hero/wear/catalog.json: every worn model's slot and display name.

Slot comes from what the piece covers (manifest.json "hide") and where its vertices sit on the 1.8 m body:
torso garments hide the trunk, leggings hide the legs, gloves/boots hide hands/feet, helms sit above the neck,
the rest (rings, pendants, charms) are accessories. Inner garments vs armour: beyond-heroes item data when known,
else by thickness (outer layers stand further from the body)."""
import json, os, re, struct, sys
WEAR = "assets/characters/hero/wear"
BH = sys.argv[1] if len(sys.argv) > 1 else ""
man = json.load(open(os.path.join(WEAR, "manifest.json")))["items"]
# Plain display names (lemondev/references/naming.md); they win over generated and beyond-heroes names.
NAMES = json.load(open("tools/wear_names.json", encoding="utf-8"))

def bounds(path):
    f = open(path, "rb").read()
    n = struct.unpack("<I", f[12:16])[0]
    j = json.loads(f[20:20 + n])
    lo, hi = [9e9] * 3, [-9e9] * 3
    names = []
    for node in j["nodes"]:
        if "mesh" in node:
            names.append(node.get("name", ""))
    for m in j["meshes"]:
        for p in m["primitives"]:
            a = j["accessors"][p["attributes"]["POSITION"]]
            for k in range(3):
                lo[k] = min(lo[k], a["min"][k]); hi[k] = max(hi[k], a["max"][k])
    return lo, hi, names

known = {}
if BH:
    src = ""
    for root, _, files in os.walk(os.path.join(BH, "src", "data")):
        for f in files:
            if f.endswith(".gd"):
                src += open(os.path.join(root, f), encoding="utf-8").read()
    for m in re.finditer(r'&"([a-z0-9_]+)",\s*"([^"]+)",\s*&"(inner_garment|armor|leggings|helm|gloves|boots|accessory)"', src):
        known[m.group(1)] = (m.group(2), m.group(3))

def title(i):
    i = re.sub(r"^(tc_|u_|depth_)", "", i)
    return " ".join(w.capitalize() for w in i.split("_"))

out = {}
for f in sorted(os.listdir(WEAR)):
    if not f.endswith(".glb"):
        continue
    i = f[:-4]
    info = man.get(i, {})
    hide = info.get("hide", {})
    lo, hi, names = bounds(os.path.join(WEAR, f))
    # glTF is Y-up: height is index 1
    y0, y1 = lo[1], hi[1]
    if i in known:
        name, slot = known[i]
    else:
        name = title(i)
        if "glove" in hide: slot = "gloves"
        elif "boot" in hide: slot = "boots"
        elif "z" in hide and hide["z"][1] <= 1.1: slot = "leggings"
        elif "z" in hide or "sleeve" in hide: slot = "armor"
        elif y0 > 1.45 or (i.endswith("_crown")): slot = "helm"
        else: slot = "accessory"
    name = NAMES.get(i, name)
    out[i] = {"name": name, "slot": slot, "sides": bool(info.get("sides", False)),
              "hair": info.get("hair", "hide"), "y": [round(y0, 3), round(y1, 3)], "base": i.startswith("_")}
json.dump(out, open(os.path.join(WEAR, "catalog.json"), "w"), indent=1, sort_keys=True)
from collections import Counter
print(Counter(v["slot"] for v in out.values() if not v["base"]))
for s in ["helm", "accessory", "inner_garment"]:
    print(s, [k for k, v in out.items() if v["slot"] == s])

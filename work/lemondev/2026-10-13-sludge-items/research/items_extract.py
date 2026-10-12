# Print the Dota 2 item data (work/research/d2_items.txt, Valve's items.txt) for the items this run adds.
import re, sys
src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
src = re.sub(r"//[^\n]*", "", src)
toks = re.findall(r'"([^"]*)"|([{}])', src)
def parse(i):
    d = {}
    while i < len(toks):
        s, b = toks[i]
        if b == "}":
            return d, i + 1
        key = s
        s2, b2 = toks[i + 1]
        if b2 == "{":
            v, i = parse(i + 2)
        else:
            v, i = s2, i + 2
        d[key] = v
    return d, i
root, _ = parse(2)  # skip "DOTAAbilities" {
names = sys.argv[2].split(",")
for n in names:
    for key in ("item_" + n, "item_recipe_" + n):
        it = root.get(key)
        if not isinstance(it, dict):
            continue
        out = {k: it[k] for k in ("ItemCost", "AbilityCooldown", "AbilityManaCost", "AbilityCastRange", "AbilityCastPoint",
               "ItemInitialCharges", "ItemRequirements", "ItemShopTags", "AbilityChannelTime") if k in it}
        av = it.get("AbilityValues", {})
        vals = {}
        for k, v in av.items():
            vals[k] = v if not isinstance(v, dict) else v.get("value", v)
        print(key, out, vals)

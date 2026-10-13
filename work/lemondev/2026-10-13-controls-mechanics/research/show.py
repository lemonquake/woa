import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))["pages"]
t = d[sys.argv[2]] or ""
# drop long SkillListRich blocks to the name and notes
t = re.sub(r"\{\{SkillListRich(.*?)\n\}\}", lambda m: "  * " + " | ".join(
    x.strip() for x in m.group(1).split("\n|") if x.strip().split("=")[0].strip() in ("source", "name", "notes", "trait1", "value1", "trait2", "value2")), t, flags=re.S)
t = re.sub(r"\[\[File:[^\]]*\]\]", "", t)
t = re.sub(r"<ref>.*?</ref>", "", t)
lim = int(sys.argv[3]) if len(sys.argv) > 3 else 6000
start = t.find(sys.argv[4]) if len(sys.argv) > 4 else 0
print(t[max(0, start):max(0, start) + lim])

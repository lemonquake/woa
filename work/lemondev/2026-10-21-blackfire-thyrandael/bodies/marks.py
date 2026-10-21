import json, sys
J = json.load(open(sys.argv[1]))
m = {}
for k, (a, b) in J.items():
    m[k] = a
    if k.startswith(("hand", "toe", "head")):
        m[k + ">"] = b
json.dump(m, open(sys.argv[2], "w"))

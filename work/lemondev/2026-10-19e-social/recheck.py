"""The blind review's recheck (run 2026-10-19 e), on a social_probe transcript:
  * every Triple Kill or better: lines from at least one other player within 6 s (Ultra / Rampage: two, one naming it);
  * the enemy with the biggest streak (10+): at least one smurf / cheat / report line about them;
  * no player sends the same line more than twice in a match.
    python work/lemondev/2026-10-19e-social/recheck.py review/new_7.txt ...
"""
import re
import sys
from collections import Counter

LINE = re.compile(r"^\[(-?)(\d+):(\d+)\] (.*)$")
WORDS = ["smurf", "hack", "maphack", "script", "cheat", "report", "account", "daya"]


def secs(m):
    s = int(m.group(2)) * 60 + int(m.group(3))
    return -s if m.group(1) == "-" else s


def check(path):
    rows = []
    for raw in open(path, encoding="utf-8"):
        m = LINE.match(raw.rstrip("\n"))
        if m:
            rows.append((secs(m), m.group(4)))
    multis = [(t, x) for t, x in rows if x.startswith("*") and re.search(r"\((Triple Kill|Ultra Kill|Rampage)\)", x)]
    missed = 0
    for t, x in multis:
        killer = x[2:].split(" killed ")[0].split(" (")[0]
        near = [y for tt, y in rows if t < tt <= t + 6 and not y.startswith("*") and not y.split(": ")[0].endswith(killer)
                and killer not in y.split(": ")[0]]
        big = "Ultra" in x or "Rampage" in x
        named = any(re.search(r"\b(3|4|5|triple|ultra|rampage)\b", y.split(": ", 1)[-1].lower()) for y in near)
        if len(near) < (2 if big else 1) or (big and not named):
            missed += 1
    streaks = Counter()
    for t, x in rows:
        m = re.search(r"^\* (.+?) \(.*\((\d+) kill streak\)", x)
        if m:
            streaks[m.group(1)] = max(streaks[m.group(1)], int(m.group(2)))
    top = streaks.most_common(1)
    accused = None
    if top and top[0][1] >= 10:
        name = top[0][0].lower()
        accused = sum(1 for t, x in rows if not x.startswith("*") and name in x.split(": ", 1)[-1].lower()
                      and any(w in x.lower() for w in WORDS))
    said = Counter()
    for t, x in rows:
        if not x.startswith("*") and ": " in x:
            who, text = x.split(": ", 1)
            said[(who.replace("(All) ", "").replace("(Team) ", ""), text.lower().strip(" .!"))] += 1
    reps = [(k, n) for k, n in said.items() if n > 2 and k[0] != "YOU"]
    print("%s: triple+ kills %d, under-reacted %d; top streak %s, accusations about them %s; lines said 3+ times by one player %d %s" % (
        path, len(multis), missed, top[0] if top else "-", accused, len(reps), reps[:3]))


for p in sys.argv[1:]:
    check(p)

"""The critic's recheck condition (run 2026-10-19 d, pass 1 -> 2), measured on a bot game transcript:
  1. no line longer than 2 words comes word for word (case and end marks ignored) from two different players;
  2. no filler word (sheesh, man, bro, lods, pre, tol, bai, mate, fr, ngl ...) after end-of-sentence punctuation;
  3. no player sends the same line more than twice.
Over the first 14 minutes.   python work/lemondev/2026-10-19d-living/recheck.py <transcript.txt> [minutes]
"""
import re
import sys
from collections import defaultdict

FILLER = {"sheesh", "man", "bro", "lods", "pre", "tol", "bai", "mate", "fr", "ngl", "bruh", "dude", "guys", "boss", "par",
          "idol", "grabe", "hala", "jusko", "pare", "bes", "lowkey", "tbh", "oi"}


def main():
    path = sys.argv[1]
    until = float(sys.argv[2]) * 60 if len(sys.argv) > 2 else 14 * 60
    who_said = defaultdict(set)
    per_player = defaultdict(int)
    filler_after = []
    n = 0
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*\[(-?)(\d+):(\d+)\] (?:\(All\) )?(Ancient Light|Black Sun) (.+?): (.*)$", line.rstrip("\n"))
        if not m:
            continue
        t = (int(m.group(2)) * 60 + int(m.group(3))) * (-1 if m.group(1) else 1)
        if t > until:
            break
        n += 1
        who, text = m.group(5), m.group(6)
        norm = re.sub(r"[.!?]+$", "", text.strip().lower())
        if len(norm.split()) > 2:
            who_said[norm].add(who)
        per_player[(who, norm)] += 1
        mm = re.search(r"[.!?]\s+(\w+)\s*$", text.strip())
        if mm and mm.group(1).lower() in FILLER:
            filler_after.append(text)
    echoes = {k: v for k, v in who_said.items() if len(v) >= 2}
    repeats = {k: c for k, c in per_player.items() if c > 2}
    print("lines %d" % n)
    print("1. lines over 2 words from two or more players: %d %s" % (len(echoes), list(echoes)[:8]))
    print("2. filler after end punctuation: %d %s" % (len(filler_after), filler_after[:5]))
    print("3. a player sending the same line 3+ times: %d %s" % (len(repeats), [(k[0], k[1], c) for k, c in list(repeats.items())[:8]]))
    ok = not echoes and not filler_after and not repeats
    print("RECHECK " + ("PASS" if ok else "FAIL"))


if __name__ == "__main__":
    main()

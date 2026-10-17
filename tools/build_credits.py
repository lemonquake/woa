"""Write assets/ui/credits.txt (the in-game Credits screen) from docs/ASSET_CREDITS.md.

Every row of the credits table becomes one entry: what it is, by whom, where from, under which licence (CC BY
assets must be credited where players can see it). Run after editing ASSET_CREDITS.md:
  python tools/build_credits.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "ASSET_CREDITS.md")
OUT = os.path.join(ROOT, "assets", "ui", "credits.txt")


def clean(cell: str) -> str:
    cell = re.sub(r"`([^`]*)`", r"\1", cell)
    cell = cell.replace("**", "").strip()
    return cell


def main() -> None:
    rows = []
    for line in open(SRC, encoding="utf8"):
        if not line.startswith("|") or line.startswith("|---") or line.startswith("| Asset |"):
            continue
        cells = [clean(c) for c in line.strip().strip("|").split("|")]
        if len(cells) < 5:
            continue
        what, _where, who, source, licence = cells[:5]
        rows.append((what, who, source, licence))
    out = ["Warriors of Aether, a game by Aljay Leodones.", "",
           "Game rules and numbers follow Dota 2. Every name, model, icon and texture is original or from the sources "
           "below.", ""]
    for what, who, source, licence in rows:
        out.append("[b]%s[/b]" % what)
        out.append("By %s. %s. Licence: %s." % (who, source, licence))
        out.append("")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf8", newline="\n").write("\n".join(out).rstrip() + "\n")
    print("wrote %s (%d entries)" % (OUT, len(rows)))


if __name__ == "__main__":
    main()

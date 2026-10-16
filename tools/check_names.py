"""Naming rule checker (lemondev/references/naming.md).

Scans player-visible text for banned words and fake-epic compounds:
  * string literals in src/**/*.gd that look like display text (contain a capital letter or a space,
    and are not paths or format-only strings),
  * text = "..." properties in src/**/*.tscn,
  * "name" fields in assets/characters/hero/wear/catalog.json.
Prints every hit as file:line: word -> "text" and exits 1 if any are found.

Run: python tools/check_names.py
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

BANNED_WORDS = {
    "aether", "ashen", "ember", "embers", "gale", "crown", "crowns", "gloom", "rune", "runes", "runic", "sigil",
    "veil", "rift", "void", "astral", "celestial", "arcane", "mystic", "eternal", "sanctum", "bastion", "spire",
    "aegis", "hallow", "hallowed", "dread", "umbral", "nether", "ether", "eclipse", "oath", "sworn", "wraith",
    "whisper", "twilight", "starlight", "moonlit", "sunforged", "primal", "fabled", "abyssal", "empyrean",
    "radiant", "verdant",
}
# Suffixes that make fake-epic compounds when glued onto another word ("Galewarden", "Crownfall").
BANNED_SUFFIXES = ("warden", "fall", "forged", "bound", "born", "keeper", "caller", "walker", "strider", "weaver",
                   "bane", "shard", "heart", "song", "fang", "guard", "wright", "mantle")
# Real English words that end in one of those suffixes.
ENGLISH_OK = {
    "downfall", "waterfall", "rainfall", "pitfall", "snowfall", "footfall", "landfall", "shortfall", "windfall",
    "freefall", "outbound", "inbound", "rebound", "unbound", "spellbound", "housebound", "firstborn", "newborn",
    "reborn", "stillborn", "unborn", "airborne", "goalkeeper", "gatekeeper", "shopkeeper", "innkeeper",
    "timekeeper", "doorkeeper", "zookeeper", "beekeeper", "housekeeper", "scorekeeper", "storekeeper",
    "sweetheart", "bodyguard", "lifeguard", "safeguard", "mudguard", "fireguard", "playwright", "wheelwright",
    "shipwright", "birdsong", "singsong", "sleepwalker", "streetwalker", "jaywalker", "skywalker",
    "warden", "fall", "bound", "born", "keeper", "caller", "walker", "strider", "weaver", "bane", "shard", "heart",
    "song", "fang", "guard", "wright", "mantle",
}
# Fantasy roots: a single word made of one of these plus another word ("Sunfruit", "Galeblade", "Duskrunner",
# "Ironwood", "Bloodmoon") is an invented compound. Write two words, or a plain word, instead.
ROOTS = ("aether", "ember", "gale", "gloom", "rune", "rift", "void", "dread", "oath", "crown", "dusk", "dawn",
         "sun", "moon", "star", "storm", "wind", "frost", "fire", "flame", "shadow", "night", "blood", "bone", "grave",
         "iron", "stone", "steel", "thorn", "wolf", "dragon", "soul", "spirit", "light", "dark", "deep", "sky",
         "tide", "ash", "thunder", "swift", "silent", "elven", "vault", "prism", "twin", "gold", "silver",
         "doom", "hell", "death", "war", "battle", "rage", "life", "mind", "heart", "dream", "rime", "mist", "cinder")
COMPOUND_OK = {
    "firefly", "sunflower", "starfish", "sunlight", "moonlight", "firewood", "fireplace", "firework", "fireworks",
    "nightmare", "sunset", "sunrise", "nightclub", "lifetime", "lifestyle", "battlefield", "warlord", "warrior",
    "warriors", "warlock", "darkness", "lighthouse", "lightning", "sunshine", "stonework", "ironwork", "goldfish",
    "silverware", "windmill", "windows", "window", "skyline", "deepest", "darker", "lighter", "stoned", "boneless",
    "bloody", "starts", "start", "started", "stars", "storms", "winds", "fires", "souls", "spirits", "lights",
    "nights", "bones", "graves", "dragons", "wolves", "thorns", "minds", "hearts", "dreams", "golden", "silvery",
    "warm", "ward", "wards", "warp", "warn", "warning", "ready", "war", "wars", "sunny", "starry", "stormy",
    "windy", "fiery", "icy", "rage", "raged", "deathmatch", "mindful", "gravel", "stoneware", "iced", "ashes",
    "ashore", "ashamed", "ashy", "swiftly", "silently", "deeply", "lifesteal", "lifesteals", "skin", "mists",
    "mistake", "misty", "ironic", "irons", "steels", "dawning", "starve", "starting", "startup", "sunk", "sunken",
    "ward", "wardrobe", "warband", "warcry", "lightweight", "darkened", "heartbeat", "heartbeats", "fireball",
    "firebolt", "nightly", "skyward", "lifeline", "deathblow", "battleground", "bloodshed", "bloodstain",
    "bloodstained", "heartless", "soulless", "steelwork", "starboard", "windward", "heated", "starlit",
    "moonless", "twins", "twine", "goldsmith", "ashtray", "thunderstorm", "icicle", "iceberg", "rimes", "frosty",
    "firelight", "sunburn", "fireproof", "dreamy", "soulmate", "deathly", "dragonfly", "lightly", "nighttime",
    "daylight", "lifeguard", "lifelike", "warhammer", "warhorse", "wartime", "silvers", "golds", "windup",
    "stonemason", "moonstone", "bonfire", "campfire", "wildfire", "gunfire", "starter", "sundial", "suntan",
}
# Names the owner chose (never flagged). Matched case-insensitively and removed before checking.
OWNER_NAMES = [
    "Warriors of Aether", "Ancient Light", "Black Sun", "Blood Ranger", "Ezee the Dark Paladin", "Ezee", "Sludge",
    "Burst Shot", "Gale Impact", "Masterful Archery", "Dark Stomp", "Leap Strike", "Tainted Touch", "Unholy Might",
    "Mini-Axe", "Vegan Picker", "Bot Gerald",
    # 2026-10-14: Azrin and her abilities; Sange, Yasha and Kaya renamed by the owner
    "Azrin", "the Flamemander", "Flamemander", "Fiery Javelin", "Touch of Ember", "Spirit of Fire", "Divine Smite",
    "Kugmo", "Igit", "Atuli",
    # 2026-10-14 b: Froster and Caziel with their titles and abilities
    "Froster", "the Winter Master", "Caziel", "the Void Assassin", "Breath of Cold", "Ice Pulse", "Frost Heart",
    "Endless Winter", "Swift Dagger", "Sweet Poison", "Master of Shadows", "Death Order",
    # 2026-10-16: Roydo and Blau with their titles and abilities
    "Roydo", "the Anomaly", "Anomaly", "Grip of the Ruler", "Void Rush", "Dark Matter Skin", "Blau",
    "the Master Tactician", "Master Tactician", "Bounce Shot", "Summon Boulders", "Lay Trap", "Place Turret",
]
# The owner named the pure damage type "Aether" (2026-10-14). Only these exact texts may use it, so a new
# "Aether ..." compound is still caught.
OWNER_EXACT = {"Aether", "Spells: magic damage uses Magic, pure damage uses Aether; physical spell damage only meets armor."}

WORD = re.compile(r"[A-Za-z]+")
GD_STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
TSCN_TEXT = re.compile(r'^\s*(?:text|title|tooltip_text|placeholder_text)\s*=\s*"((?:[^"\\]|\\.)*)"')


def looks_like_display(s):
    if not s or "res://" in s or "user://" in s or s.startswith("--"):
        return False
    if re.fullmatch(r"[a-z0-9_./:%-]*", s):  # ids, paths, flags
        return False
    if " " not in s and ("/" in s or "_" in s or "." in s):  # paths, ids, node and material names
        return False
    return bool(WORD.search(s))


def hits_in(text):
    if text in OWNER_EXACT:
        return []
    low = text
    for name in OWNER_NAMES:
        low = re.sub(re.escape(name), " ", low, flags=re.IGNORECASE)
    found = []
    # Split CamelCase ("DarkSteel" -> "Dark Steel") so code-style names are judged word by word.
    low = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", low)
    for w in WORD.findall(low):
        lw = w.lower()
        if lw in BANNED_WORDS:
            found.append(w)
            continue
        if lw in ENGLISH_OK:
            continue
        bad = False
        for suf in BANNED_SUFFIXES:
            if lw.endswith(suf) and len(lw) - len(suf) >= 3:
                bad = True
                break
        if not bad and lw not in COMPOUND_OK:
            for r in ROOTS:
                rest = None
                if lw.startswith(r) and len(lw) - len(r) >= 3:
                    rest = lw[len(r):]
                elif lw.endswith(r) and len(lw) - len(r) >= 3:
                    rest = lw[:-len(r)]
                if rest is not None and not rest.startswith(("s", "y", "ed", "er", "ing", "ly", "ish", "ness"))                         and not rest.endswith(("ed", "ing")):
                    bad = True
                    break
        if bad:
            found.append(w)
    return found


def strip_comment(line):
    # Drop a trailing GDScript comment that is not inside a string.
    out, in_str = [], False
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and in_str:
            out.append(line[i:i + 2])
            i += 2
            continue
        if c == '"':
            in_str = not in_str
        elif c == "#" and not in_str:
            break
        out.append(c)
        i += 1
    return "".join(out)


def scan():
    problems = []
    src = os.path.join(ROOT, "src")
    for dirpath, _, files in os.walk(src):
        for fn in sorted(files):
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            if fn.endswith(".gd"):
                with open(path, encoding="utf-8") as f:
                    for n, line in enumerate(f, 1):
                        code = strip_comment(line)
                        for m in GD_STRING.finditer(code):
                            s = m.group(1)
                            if looks_like_display(s):
                                for w in hits_in(s):
                                    problems.append((rel, n, w, s))
            elif fn.endswith(".tscn"):
                with open(path, encoding="utf-8") as f:
                    for n, line in enumerate(f, 1):
                        m = TSCN_TEXT.match(line)
                        if m:
                            for w in hits_in(m.group(1)):
                                problems.append((rel, n, w, m.group(1)))
    cat = os.path.join(ROOT, "assets", "characters", "hero", "wear", "catalog.json")
    if os.path.exists(cat):
        with open(cat, encoding="utf-8") as f:
            data = json.load(f)
        entries = data.values() if isinstance(data, dict) else data
        for e in entries:
            if isinstance(e, dict):
                for piece in ([e] if "name" in e else e.values()):
                    if isinstance(piece, dict) and isinstance(piece.get("name"), str):
                        for w in hits_in(piece["name"]):
                            problems.append(("assets/characters/hero/wear/catalog.json", 0, w, piece["name"]))
    return problems


def main():
    problems = scan()
    for rel, n, w, s in problems:
        print(f"{rel}:{n}: {w} -> \"{s}\"")
    if problems:
        print(f"\n{len(problems)} naming problem(s). See lemondev/references/naming.md")
        return 1
    print("Names OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

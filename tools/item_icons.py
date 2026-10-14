"""Item icons for Warriors of Aether (run 2026-10-15 b): SVGs in assets/ui/items/gen/, one per item id.

Every icon shares one look so the shop and the inventory read as a set:
  * a rounded backdrop coloured by what the item is for (red strength, green agility, blue intelligence, gold
    support, steel armor, violet magic, orange fire, pale blue ice, deep blue lightning, crimson blood), with a soft
    light behind the object and faint rays;
  * the object itself, large, outlined dark and lit from the top left;
  * a badge in the lower right corner that says what the item does (a clock for faster cooldowns, a bolt for
    lightning, rings for an aura, a cracked ring for armor loss, a cross for healing, arrows for switching...).

    python tools/item_icons.py            # writes the SVGs
    python tools/item_icons.py --list     # prints the item ids it draws

The game maps item ids to these files in src/ui/ui_kit.gd (ITEM_ICONS, "items/gen/<id>").
"""
import math
import os
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "items", "gen")
INK = "#0a0610"

# backdrop colours: (centre, edge, glow)
BACK = {
    "str": ("#7a2418", "#1c0605", "#ff8a5a"),
    "agi": ("#2f6a24", "#071405", "#a8ff7a"),
    "int": ("#24479a", "#060b1e", "#8ab8ff"),
    "support": ("#7a5a18", "#1a1204", "#ffd77a"),
    "armor": ("#4a5466", "#0b0e13", "#d8e4ff"),
    "magic": ("#58268a", "#10061c", "#d8a0ff"),
    "fire": ("#8a3410", "#1e0802", "#ffb050"),
    "ice": ("#2a6a8a", "#04121a", "#bff0ff"),
    "storm": ("#2a3a8e", "#050820", "#a8c8ff"),
    "blood": ("#7a0e1c", "#180206", "#ff6070"),
    "gold": ("#8a6a10", "#1e1402", "#ffe28a"),
    "nature": ("#3a6a1a", "#0a1404", "#d0ff8a"),
    "dark": ("#3a2a4a", "#08060c", "#c8a8ff"),
}

# metals and materials: (light, mid, dark)
STEEL = ("#ffffff", "#b8c4d6", "#2c3440")
GOLD = ("#fff2b0", "#e0a83a", "#5a3a0c")
BRONZE = ("#ffd8a0", "#b8763a", "#3e200a")
IRON = ("#d8dce4", "#7a8494", "#1e2229")
WOOD = ("#d8a070", "#8a5428", "#2e1606")
LEATHER = ("#c88a5a", "#7a4420", "#2a1206")
RED = ("#ff9a8a", "#d02a24", "#4a0606")
GREEN = ("#d0ff9a", "#3caa30", "#0c3a08")
BLUE = ("#c0dcff", "#2a6ae0", "#081e5a")
VIOLET = ("#f0c8ff", "#9a40e0", "#2a0848")
CYAN = ("#e0ffff", "#40c8f0", "#08405a")
ORANGE = ("#fff0a0", "#ff8a20", "#6a1a02")
BLACK = ("#8a8a9a", "#2a2a36", "#06060a")
BONE = ("#fffaf0", "#d8ccb0", "#6a5a40")
WHITE = ("#ffffff", "#e8eef8", "#7a8496")


class Icon:
    def __init__(self, back):
        self.defs = []
        self.body = []
        self.n = 0
        self.back = back

    def gid(self, kind):
        self.n += 1
        return "%s%d" % (kind, self.n)

    def lin(self, stops, x1=-20, y1=-40, x2=20, y2=40):
        i = self.gid("l")
        s = "".join('<stop offset="%s" stop-color="%s"%s/>' % (o, c, (' stop-opacity="%s"' % a) if a is not None else "")
                    for o, c, a in [(st + (None,))[:3] for st in stops])
        self.defs.append('<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>'
                         % (i, x1, y1, x2, y2, s))
        return "url(#%s)" % i

    def rad(self, stops, cx=0, cy=0, r=40):
        i = self.gid("r")
        s = "".join('<stop offset="%s" stop-color="%s"%s/>' % (o, c, (' stop-opacity="%s"' % a) if a is not None else "")
                    for o, c, a in [(st + (None,))[:3] for st in stops])
        self.defs.append('<radialGradient id="%s" gradientUnits="userSpaceOnUse" cx="%s" cy="%s" r="%s">%s</radialGradient>'
                         % (i, cx, cy, r, s))
        return "url(#%s)" % i

    def metal(self, m, x1=-20, y1=-40, x2=20, y2=40):
        return self.lin([(0, m[0]), (0.45, m[1]), (1, m[2])], x1, y1, x2, y2)

    def add(self, s):
        self.body.append(s)

    def g(self, x, y, rot=0.0, sc=1.0, inner=""):
        self.add('<g transform="translate(%s %s) rotate(%s) scale(%s)">%s</g>' % (x, y, rot, sc, inner))

    def svg(self):
        c, e, glow = BACK[self.back]
        bg = self.rad([(0, c), (0.7, e), (1, e)], 58, 50, 86)
        halo = self.rad([(0, glow, 0.55), (0.5, glow, 0.16), (1, glow, 0)], 62, 58, 52)
        rays = []
        for k in range(12):
            a = k * math.pi / 6 + 0.13
            x1, y1 = 62 + math.cos(a - 0.09) * 90, 58 + math.sin(a - 0.09) * 90
            x2, y2 = 62 + math.cos(a + 0.09) * 90, 58 + math.sin(a + 0.09) * 90
            rays.append('<path d="M62,58 L%.1f,%.1f L%.1f,%.1f Z" fill="%s" opacity="0.06"/>' % (x1, y1, x2, y2, glow))
        head = ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
                '<defs><clipPath id="clip"><rect x="3" y="3" width="122" height="122" rx="14"/></clipPath>%s</defs>'
                % "".join(self.defs))
        back = ('<rect x="3" y="3" width="122" height="122" rx="14" fill="%s"/>'
                '<g clip-path="url(#clip)">%s<circle cx="62" cy="58" r="52" fill="%s"/></g>' % (bg, "".join(rays), halo))
        rim = ('<rect x="4.5" y="4.5" width="119" height="119" rx="13" fill="none" stroke="%s" stroke-opacity="0.35" stroke-width="2"/>'
               '<rect x="2" y="2" width="124" height="124" rx="15" fill="none" stroke="#000" stroke-opacity="0.8" stroke-width="2.5"/>'
               % glow)
        return head + back + "".join(self.body) + rim + "</svg>"


def P(d, fill, stroke=INK, sw=3.0, extra=""):
    return '<path d="%s" fill="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round" stroke-linecap="round"%s/>' % (
        d, fill, stroke, sw, extra)


def C(cx, cy, r, fill, stroke=INK, sw=2.5, extra=""):
    return '<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="%s"%s/>' % (cx, cy, r, fill, stroke, sw, extra)


def E(cx, cy, rx, ry, fill, stroke=INK, sw=2.5, extra=""):
    return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s" stroke="%s" stroke-width="%s"%s/>' % (cx, cy, rx, ry, fill, stroke, sw, extra)


def L(d, col, sw=2.0, op=1.0):
    return '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round" opacity="%s"/>' % (d, col, sw, op)


# ---- Objects (drawn round the origin, roughly -50..50) --------------------------------------------------------------

def sword(ic, blade=STEEL, hilt=GOLD, length=78, width=11, curve=0.0, grip=LEATHER, gem=None, heavy=False):
    """A sword pointing up, hilt at y=+30."""
    hw = width / 2
    top = 30 - length
    bend = curve * 18
    d = "M%s,30 L%s,%s Q%s,%s %s,%s Q%s,%s %s,%s L%s,30 Z" % (
        -hw, -hw + bend * 0.4, top + 18, -hw + bend, top + 6, bend * 0.9, top - 2, hw + bend, top + 6,
        hw + bend * 0.4, top + 18, hw)
    if heavy:
        d = "M%s,30 L%s,%s L%s,%s L%s,%s L%s,30 Z" % (-hw, -hw - 2, top + 16, 0, top - 4, hw + 2, top + 16, hw)
    s = P(d, ic.metal(blade, -hw, top, hw, 30), sw=3)
    s += L("M%s,26 Q%s,%s %s,%s" % (0, bend * 0.25, (top + 30) / 2, bend * 0.7, top + 14), "#ffffff", 1.6, 0.55)
    gw = width * 1.9 + 6
    s += P("M%s,28 L%s,28 L%s,36 L%s,36 Z" % (-gw / 2, gw / 2, gw / 2 - 3, -gw / 2 + 3), ic.metal(hilt, 0, 26, 0, 38), sw=2.5)
    s += P("M-3.5,36 L3.5,36 L3.5,52 L-3.5,52 Z", ic.metal(grip, -4, 0, 4, 0), sw=2.5)
    s += C(0, 55, 5, ic.metal(hilt, -5, 50, 5, 60), sw=2.2)
    if gem:
        s += C(0, 32, 3.4, gem, sw=1.5)
    return s


def axe(ic, head=STEEL, haft=WOOD, big=False, double=False):
    s = P("M-3,-44 L3,-44 L4,50 L-4,50 Z", ic.metal(haft, -4, 0, 4, 0), sw=2.5)
    w = 34 if big else 26
    blade = "M2,-38 Q%s,-50 %s,-16 Q%s,6 2,-4 Z" % (w * 0.8, w, w * 0.8)
    s += P(blade, ic.metal(head, 0, -40, w, -4), sw=3)
    s += L("M%s,-40 Q%s,-16 %s,2" % (w * 0.75, w + 4, w * 0.75), "#ffffff", 1.6, 0.6)
    if double:
        s += P("M-2,-38 Q%s,-50 %s,-16 Q%s,6 -2,-4 Z" % (-w * 0.8, -w, -w * 0.8), ic.metal(head, 0, -40, -w, -4), sw=3)
    s += P("M-6,-42 L6,-42 L6,-30 L-6,-30 Z", ic.metal(IRON), sw=2)
    return s


def hammer(ic, head=IRON, haft=WOOD, wide=40):
    s = P("M-3.5,-30 L3.5,-30 L4,50 L-4,50 Z", ic.metal(haft, -4, 0, 4, 0), sw=2.5)
    s += P("M%s,-46 L%s,-46 L%s,-40 L%s,-18 L%s,-12 L%s,-12 L%s,-18 L%s,-40 Z" % (
        -wide / 2, wide / 2, wide / 2 + 3, wide / 2 + 3, wide / 2, -wide / 2, -wide / 2 - 3, -wide / 2 - 3),
        ic.metal(head, -wide / 2, -46, wide / 2, -12), sw=3)
    s += L("M%s,-42 L%s,-42" % (-wide / 2 + 4, wide / 2 - 4), "#ffffff", 1.8, 0.5)
    s += P("M-5,-12 L5,-12 L5,-4 L-5,-4 Z", ic.metal(GOLD), sw=2)
    return s


def staff(ic, wood=WOOD, orb=BLUE, head=GOLD, crook=False, orb_r=11):
    s = P("M-3,-30 L3,-30 L3.5,52 L-3.5,52 Z", ic.metal(wood, -4, 0, 4, 0), sw=2.5)
    for y in (-8, 14, 34):
        s += P("M-5,%s L5,%s L5,%s L-5,%s Z" % (y, y, y + 4, y + 4), ic.metal(head), sw=1.6)
    if crook:
        s += P("M-3,-30 Q-4,-56 16,-54 Q30,-50 22,-36", "none", sw=6)
        s += L("M-3,-30 Q-4,-56 16,-54 Q30,-50 22,-36", wood[1], 4)
        return s
    s += P("M-12,-30 Q-14,-46 -6,-52 L0,-40 L6,-52 Q14,-46 12,-30 Z", ic.metal(head, -12, -52, 12, -30), sw=2.5)
    s += C(0, -44, orb_r, ic.rad([(0, orb[0]), (0.5, orb[1]), (1, orb[2])], -3, -48, orb_r * 1.3), sw=2.5)
    s += C(-3.5, -48, orb_r * 0.28, "#ffffff", stroke="none", sw=0, extra=' opacity="0.8"')
    return s


def dagger(ic, blade=STEEL, hilt=BLACK, length=46, curve=0.0):
    return sword(ic, blade, hilt, length=length, width=10, curve=curve, grip=BLACK)


def spear(ic, head=STEEL, haft=WOOD, long=True):
    s = P("M-2.6,-30 L2.6,-30 L3,58 L-3,58 Z", ic.metal(haft, -3, 0, 3, 0), sw=2.3)
    s += P("M0,-62 L9,-34 L3,-28 L-3,-28 L-9,-34 Z", ic.metal(head, -9, -62, 9, -28), sw=2.8)
    s += P("M-6,-28 L6,-28 L5,-22 L-5,-22 Z", ic.metal(GOLD), sw=2)
    return s


def bow(ic, wood=WOOD, string="#f0e8d0"):
    s = L("M8,-50 Q-30,0 8,50", string, 1.6)
    s = P("M6,-52 Q-26,-30 -26,0 Q-26,30 6,52 Q-18,30 -18,0 Q-18,-30 6,-52 Z", ic.metal(wood, -26, 0, 6, 0), sw=2.5) \
        + L("M6,-50 L6,50", string, 1.6)
    return s


def boot(ic, leather=LEATHER, trim=GOLD, wing=False, plate=False):
    s = ""
    if wing:
        s += P("M-14,-30 Q-40,-50 -46,-34 Q-36,-34 -40,-24 Q-30,-26 -32,-16 Q-22,-22 -14,-18 Z", ic.metal(WHITE, -46, -50, -14, -16), sw=2.2)
    d = "M-12,-40 L12,-40 L12,4 Q22,12 34,16 Q42,20 40,28 L-16,28 Q-20,26 -18,14 Q-16,4 -12,-6 Z"
    s += P(d, ic.metal(IRON if plate else leather, -18, -40, 40, 28), sw=3)
    s += P("M-15,-44 L15,-44 L14,-34 L-14,-34 Z", ic.metal(trim, 0, -44, 0, -34), sw=2.4)
    s += P("M-18,24 L40,24 L40,31 L-17,31 Z", ic.metal(BLACK), sw=2)
    s += L("M12,6 Q20,12 30,16", trim[1], 2.2, 0.9)
    if plate:
        for y in (-24, -10):
            s += L("M-12,%s L12,%s" % (y, y), "#ffffff", 1.4, 0.5)
    return s


def shield(ic, face=STEEL, rim=GOLD, round_=False):
    if round_:
        s = C(0, 0, 40, ic.metal(rim, -40, -40, 40, 40), sw=3)
        s += C(0, 0, 32, ic.metal(face, -32, -32, 32, 32), sw=2.5)
        s += C(0, 0, 9, ic.metal(rim), sw=2.2)
        return s
    d = "M0,-44 Q24,-40 38,-34 Q40,10 0,46 Q-40,10 -38,-34 Q-24,-40 0,-44 Z"
    s = P(d, ic.metal(rim, -38, -44, 38, 46), sw=3)
    s += P("M0,-36 Q18,-33 30,-28 Q31,6 0,36 Q-31,6 -30,-28 Q-18,-33 0,-36 Z", ic.metal(face, -30, -36, 30, 36), sw=2)
    return s


def cuirass(ic, metal=STEEL, trim=GOLD):
    d = "M-30,-36 Q-18,-44 -10,-40 Q0,-34 10,-40 Q18,-44 30,-36 L34,-16 L26,-12 L28,30 Q0,44 -28,30 L-26,-12 L-34,-16 Z"
    s = P(d, ic.metal(metal, -34, -44, 34, 40), sw=3)
    s += L("M0,-34 L0,36", "#000000", 1.6, 0.35)
    s += L("M-22,-6 Q0,4 22,-6", trim[1], 2.6)
    s += L("M-24,10 Q0,20 24,10", trim[1], 2.6)
    s += L("M-26,-30 Q-10,-24 -6,-36", "#ffffff", 1.6, 0.6)
    return s


def gem(ic, col=BLUE, r=26, sides=6):
    pts = []
    for k in range(sides):
        a = -math.pi / 2 + k * 2 * math.pi / sides
        pts.append((math.cos(a) * r, math.sin(a) * r * 1.15))
    d = "M" + " L".join("%.1f,%.1f" % p for p in pts) + " Z"
    s = P(d, ic.metal(col, -r, -r, r, r), sw=3)
    inner = " L".join("%.1f,%.1f" % (x * 0.5, y * 0.5) for x, y in pts)
    s += P("M" + inner + " Z", ic.lin([(0, col[0]), (1, col[1])], -r, -r, r, r), sw=1.4)
    for x, y in pts:
        s += L("M%.1f,%.1f L%.1f,%.1f" % (x, y, x * 0.5, y * 0.5), INK, 1.2, 0.6)
    s += P("M%.1f,%.1f L%.1f,%.1f L%.1f,%.1f Z" % (pts[-1][0] * 0.45, pts[-1][1] * 0.45, pts[0][0] * 0.45, pts[0][1] * 0.45, 0, 0),
           "#ffffff", stroke="none", sw=0, extra=' opacity="0.45"')
    return s


def crystal(ic, col=CYAN):
    s = ""
    for x, h, w, rot in ((-16, 40, 12, -18), (16, 36, 12, 16), (0, 54, 16, 0)):
        d = "M%s,30 L%s,%s L%s,%s L%s,%s L%s,30 Z" % (x - w / 2, x - w / 2, 30 - h * 0.7, x, 30 - h, x + w / 2, 30 - h * 0.7, x + w / 2)
        s += '<g transform="rotate(%s %s 30)">%s%s</g>' % (rot, x, P(d, ic.metal(col, x - w, 30 - h, x + w, 30), sw=2.6),
                                                          L("M%s,26 L%s,%s" % (x - w / 4, x - w / 4, 30 - h * 0.66), "#ffffff", 1.4, 0.6))
    return s


def band(ic, metal=GOLD, gem_col=RED):
    s = E(0, 6, 34, 22, "none", stroke=INK, sw=13)
    s += E(0, 6, 34, 22, "none", stroke=ic.metal(metal, -34, -16, 34, 28), sw=9)
    s += L("M-30,-2 Q0,-18 30,-2", "#ffffff", 1.6, 0.5)
    s += gem(ic, gem_col, 12, 6).replace("<path", '<path transform="translate(0 -14)"')
    return s


def ring(ic, metal=GOLD, gem_col=BLUE):
    s = E(0, 10, 26, 22, "none", stroke=INK, sw=11)
    s += E(0, 10, 26, 22, "none", stroke=ic.metal(metal, -26, -12, 26, 32), sw=7)
    s += C(0, -16, 13, ic.rad([(0, gem_col[0]), (0.5, gem_col[1]), (1, gem_col[2])], -4, -20, 16), sw=2.5)
    s += C(-4, -20, 3.4, "#ffffff", stroke="none", sw=0, extra=' opacity="0.8"')
    return s


def book(ic, cover=BLUE, trim=GOLD):
    s = P("M-36,-30 L0,-24 L36,-30 L36,32 L0,38 L-36,32 Z", ic.metal(cover, -36, -30, 36, 38), sw=3)
    s += P("M-32,-26 L0,-20 L32,-26 L32,28 L0,34 L-32,28 Z", ic.lin([(0, "#fffaf0"), (1, "#c8b890")], 0, -26, 0, 34), sw=2)
    s += L("M0,-20 L0,34", INK, 2)
    for y in (-12, -2, 8, 18):
        s += L("M-26,%s L-6,%s" % (y, y + 2), "#7a6a50", 1.4, 0.8) + L("M6,%s L26,%s" % (y + 2, y), "#7a6a50", 1.4, 0.8)
    s += P("M-36,32 L0,38 L36,32 L36,36 L0,42 L-36,36 Z", ic.metal(trim), sw=2)
    return s


def heart(ic, col=RED):
    d = "M0,36 C-50,4 -40,-38 -14,-34 C-4,-32 0,-24 0,-18 C0,-24 4,-32 14,-34 C40,-38 50,4 0,36 Z"
    s = P(d, ic.rad([(0, col[0]), (0.45, col[1]), (1, col[2])], -12, -18, 50), sw=3)
    s += P("M-24,-22 Q-30,-10 -24,0", "none", stroke="#ffffff", sw=3, extra=' opacity="0.6"')
    return s


def feather(ic, col=WHITE, quill=GOLD):
    d = "M18,-50 Q40,-30 22,6 Q8,34 -22,48 Q-10,20 -8,-4 Q-4,-34 18,-50 Z"
    s = P(d, ic.metal(col, -20, -50, 40, 48), sw=3)
    s += L("M18,-46 Q4,-6 -20,46", quill[2], 2.2)
    for k in range(6):
        y = -36 + k * 12
        s += L("M%s,%s L%s,%s" % (14 - k * 5, y, 26 - k * 5, y + 8), INK, 1.2, 0.45)
    return s


def drum(ic, body=RED, skin=BONE, trim=GOLD):
    s = P("M-34,-16 L34,-16 L30,30 L-30,30 Z", ic.metal(body, -34, -16, 34, 30), sw=3)
    for x in (-26, -10, 6, 22):
        s += L("M%s,-14 L%s,28" % (x, x + 8), trim[1], 2.2)
        s += L("M%s,-14 L%s,28" % (x + 8, x), trim[1], 2.2)
    s += E(0, -16, 34, 10, ic.metal(skin, 0, -26, 0, -6), sw=3)
    s += P("M18,-40 L30,-28", "none", sw=5) + L("M18,-40 L30,-28", WOOD[1], 3)
    s += C(16, -42, 5, ic.metal(BONE), sw=2)
    return s


def cape(ic, col=ORANGE, lining=RED):
    d = "M-14,-40 Q0,-44 14,-40 Q30,-10 40,34 Q20,26 10,40 Q0,28 -10,40 Q-20,26 -40,34 Q-30,-10 -14,-40 Z"
    s = P(d, ic.metal(col, -40, -44, 40, 40), sw=3)
    s += L("M-6,-36 Q-14,0 -22,30", lining[2], 1.8, 0.7) + L("M6,-36 Q14,0 22,30", lining[2], 1.8, 0.7)
    s += P("M-16,-44 Q0,-50 16,-44 L12,-36 Q0,-40 -12,-36 Z", ic.metal(GOLD), sw=2.2)
    return s


def totem(ic, wood=WOOD, skull=BONE):
    s = P("M-6,-20 L6,-20 L7,52 L-7,52 Z", ic.metal(wood, -7, 0, 7, 0), sw=2.5)
    s += P("M-20,-46 Q0,-60 20,-46 Q24,-30 14,-18 L-14,-18 Q-24,-30 -20,-46 Z", ic.metal(skull, -20, -56, 20, -18), sw=3)
    s += C(-8, -36, 5, "#200608", sw=1.5) + C(8, -36, 5, "#200608", sw=1.5)
    s += C(-8, -36, 2, "#ff4040", stroke="none", sw=0) + C(8, -36, 2, "#ff4040", stroke="none", sw=0)
    for x in (-10, -4, 2, 8):
        s += P("M%s,-20 L%s,-12 L%s,-20 Z" % (x, x + 3, x + 6), "#fffaf0", sw=1.4)
    s += P("M-22,-2 Q-36,6 -30,22 Q-22,8 -10,6 Z", ic.metal(RED), sw=2.2)
    s += P("M22,-2 Q36,6 30,22 Q22,8 10,6 Z", ic.metal(RED), sw=2.2)
    return s


def clock(ic, r=16, face=WHITE, rim=GOLD):
    s = C(0, 0, r, ic.metal(rim, -r, -r, r, r), sw=2.5)
    s += C(0, 0, r * 0.78, ic.lin([(0, "#ffffff"), (1, "#c8d0dc")], 0, -r, 0, r), sw=1.4)
    for k in range(12):
        a = k * math.pi / 6
        s += L("M%.1f,%.1f L%.1f,%.1f" % (math.cos(a) * r * 0.6, math.sin(a) * r * 0.6, math.cos(a) * r * 0.72,
                                        math.sin(a) * r * 0.72), INK, 1.2)
    s += L("M0,0 L0,%.1f" % (-r * 0.55), INK, 2.2) + L("M0,0 L%.1f,%.1f" % (r * 0.38, r * 0.22), INK, 2.2)
    return s


def bolt(ic, col=("#ffffff", "#a8d0ff", "#2a4aa0"), sc=1.0):
    d = "M6,-44 L-16,4 L-2,4 L-10,44 L18,-10 L4,-10 L14,-44 Z"
    return '<g transform="scale(%s)">%s</g>' % (sc, P(d, ic.metal(col, -16, -44, 18, 44), sw=3))


def flame(ic, sc=1.0):
    d = "M0,40 Q-30,30 -26,4 Q-22,-14 -8,-24 Q-10,-10 0,-6 Q-4,-30 12,-46 Q12,-24 24,-10 Q34,6 24,26 Q16,40 0,40 Z"
    s = P(d, ic.lin([(0, "#fff8b0"), (0.4, "#ffb030"), (1, "#c02a08")], 0, -46, 0, 40), sw=3)
    s += P("M0,32 Q-12,26 -10,12 Q-6,0 2,-4 Q2,10 10,14 Q14,26 0,32 Z", "#fff6c0", stroke="none", sw=0, extra=' opacity="0.85"')
    return '<g transform="scale(%s)">%s</g>' % (sc, s)


def snowflake(ic, col="#e8faff", sc=1.0):
    s = ""
    for k in range(6):
        a = k * 60
        arm = L("M0,0 L0,-34", INK, 7) + L("M0,0 L0,-34", col, 4) + L("M0,-20 L-8,-28 M0,-20 L8,-28", INK, 5) \
            + L("M0,-20 L-8,-28 M0,-20 L8,-28", col, 2.6)
        s += '<g transform="rotate(%s)">%s</g>' % (a, arm)
    s += C(0, 0, 6, col, sw=2)
    return '<g transform="scale(%s)">%s</g>' % (sc, s)


def cycle_arrows(col="#ffe28a", r=40):
    s = ""
    for k in range(3):
        a0 = math.radians(k * 120 + 20)
        a1 = math.radians(k * 120 + 100)
        x0, y0 = math.cos(a0) * r, math.sin(a0) * r
        x1, y1 = math.cos(a1) * r, math.sin(a1) * r
        arc = "M%.1f,%.1f A%s,%s 0 0 1 %.1f,%.1f" % (x0, y0, r, r, x1, y1)
        s += L(arc, INK, 7) + L(arc, col, 3.6)
        hx, hy = math.cos(a1 + 0.12) * r, math.sin(a1 + 0.12) * r
        tx, ty = -math.sin(a1), math.cos(a1)
        nx, ny = math.cos(a1), math.sin(a1)
        tri = "M%.1f,%.1f L%.1f,%.1f L%.1f,%.1f Z" % (hx + tx * 7, hy + ty * 7, hx - tx * 3 + nx * 7, hy - ty * 3 + ny * 7,
                                                    hx - tx * 3 - nx * 7, hy - ty * 3 - ny * 7)
        s += P(tri, col, sw=2)
    return s


def speed_lines(col="#ffffff", n=4, x0=-48, length=30, y0=-16, dy=11, op=0.7):
    s = ""
    for k in range(n):
        y = y0 + k * dy
        ln = length - (k % 2) * 10
        s += L("M%s,%s L%s,%s" % (x0, y, x0 + ln, y), INK, 5, op) + L("M%s,%s L%s,%s" % (x0, y, x0 + ln, y), col, 2.4, op)
    return s


def rings(col="#ffe28a", r0=14, n=3, step=12, op=0.8):
    s = ""
    for k in range(n):
        s += C(0, 0, r0 + k * step, "none", stroke=col, sw=2.4, extra=' opacity="%.2f"' % (op * (1 - k / (n + 0.5))))
    return s


def sheep(ic):
    s = ""
    for x, y, r in ((-14, -6, 14), (2, -12, 16), (16, -4, 13), (-4, 6, 16), (12, 8, 13)):
        s += C(x, y, r, ic.metal(WHITE, x - r, y - r, x + r, y + r), sw=2.6)
    s += E(-26, -10, 9, 11, ic.metal(BLACK), sw=2.4)
    s += C(-28, -12, 2, "#ffffff", stroke="none", sw=0)
    for x in (-10, 2, 12):
        s += P("M%s,18 L%s,32 L%s,32 L%s,18 Z" % (x - 2, x - 2, x + 2, x + 2), "#2a2a36", sw=1.6)
    return s


def net(ic, col="#d8c890"):
    s = ""
    for k in range(-3, 4):
        s += L("M%s,-40 Q%s,0 %s,40" % (k * 12, k * 15, k * 12), INK, 4.5) + L("M%s,-40 Q%s,0 %s,40" % (k * 12, k * 15, k * 12), col, 2)
        s += L("M-40,%s Q0,%s 40,%s" % (k * 12, k * 15, k * 12), INK, 4.5) + L("M-40,%s Q0,%s 40,%s" % (k * 12, k * 15, k * 12), col, 2)
    for x, y in ((-40, -40), (40, -40), (-40, 40), (40, 40)):
        s += C(x, y, 5, ic.metal(IRON), sw=2)
    return s


def coin(ic, x, y, r=9):
    return C(x, y, r, ic.metal(GOLD, x - r, y - r, x + r, y + r), sw=2.2) + C(x, y, r * 0.55, "none", stroke=GOLD[2], sw=1.4)


def glove(ic, col=GOLD):
    d = "M-22,40 L-24,0 Q-26,-12 -20,-14 L-18,-30 Q-16,-38 -10,-34 L-8,-18 L-6,-40 Q-2,-46 3,-40 L4,-18 L8,-38 Q12,-44 17,-38 L16,-14 L22,-30 Q28,-34 30,-26 L24,8 Q22,30 18,40 Z"
    return P(d, ic.metal(col, -26, -44, 30, 40), sw=3) + P("M-24,30 L20,30 L18,44 L-22,44 Z", ic.metal(RED), sw=2.4)


def mask(ic, col=RED):
    d = "M0,-40 Q32,-38 34,-6 Q34,24 0,40 Q-34,24 -34,-6 Q-32,-38 0,-40 Z"
    s = P(d, ic.metal(col, -34, -40, 34, 40), sw=3)
    s += P("M-24,-6 L-6,-2 L-8,6 L-22,4 Z", "#1a0204", sw=2) + P("M24,-6 L6,-2 L8,6 L22,4 Z", "#1a0204", sw=2)
    s += P("M-12,20 Q0,14 12,20 L8,28 L-8,28 Z", "#1a0204", sw=2)
    for x in (-8, -2, 4):
        s += P("M%s,20 L%s,26 L%s,20 Z" % (x, x + 2, x + 4), "#fffaf0", sw=1)
    return s


def helm(ic, col=IRON, trim=GOLD):
    d = "M-30,24 L-30,-8 Q-28,-40 0,-42 Q28,-40 30,-8 L30,24 L14,24 L14,4 L-14,4 L-14,24 Z"
    s = P(d, ic.metal(col, -30, -42, 30, 24), sw=3)
    s += L("M0,-40 L0,4", trim[1], 3)
    s += L("M-14,-6 L14,-6", INK, 3) + L("M-14,-6 L14,-6", "#000", 1.4)
    s += P("M-32,24 L32,24 L30,32 L-30,32 Z", ic.metal(trim), sw=2.2)
    return s


def leaf(ic, col=GREEN, sc=1.0):
    d = "M0,30 Q-26,8 -4,-30 Q26,-6 0,30 Z"
    return '<g transform="scale(%s)">%s%s</g>' % (sc, P(d, ic.metal(col, -20, -30, 20, 30), sw=2.4), L("M0,28 Q-4,0 -3,-26", col[2], 1.6))


def droplet(ic, col=BLUE, sc=1.0):
    d = "M0,-30 Q22,0 18,14 Q12,30 0,30 Q-12,30 -18,14 Q-22,0 0,-30 Z"
    return '<g transform="scale(%s)">%s%s</g>' % (sc, P(d, ic.rad([(0, col[0]), (0.5, col[1]), (1, col[2])], -6, 4, 34), sw=2.6),
                                                  C(-6, 8, 4, "#ffffff", stroke="none", sw=0, extra=' opacity="0.7"'))


def cross(col=("#c8ffc8", "#30c040", "#0a4010"), sz=14):
    w = sz * 0.36
    d = "M%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s Z" % (
        -w, -sz, w, -sz, w, -w, sz, -w, sz, w, w, w, w, sz, -w, sz, -w, w, -sz, w, -sz, -w, -w, -w)
    return P(d, col[1], sw=2.4)


def star(col="#ffe060", r=12, r2=5, n=5):
    pts = []
    for k in range(n * 2):
        a = -math.pi / 2 + k * math.pi / n
        rr = r if k % 2 == 0 else r2
        pts.append("%.1f,%.1f" % (math.cos(a) * rr, math.sin(a) * rr))
    return P("M" + " L".join(pts) + " Z", col, sw=2)


def crack_ring(col="#ff6040"):
    s = C(0, 0, 11, "none", stroke=INK, sw=6) + C(0, 0, 11, "none", stroke=col, sw=3)
    s += L("M-2,-14 L2,-4 L-3,2 L3,14", INK, 4) + L("M-2,-14 L2,-4 L-3,2 L3,14", "#ffffff", 1.8)
    return s


def eye(col="#ffe080"):
    s = P("M-14,0 Q0,-12 14,0 Q0,12 -14,0 Z", "#ffffff", sw=2.2)
    s += C(0, 0, 5, col, sw=1.6) + C(0, 0, 2, INK, stroke="none", sw=0)
    return s


def badge(ic, inner, col="#1a1206", rim=GOLD, x=102, y=102, r=17):
    s = C(x, y, r, ic.rad([(0, col), (1, "#000000")], x, y, r), sw=2.5)
    s += C(x, y, r - 2.5, "none", stroke=rim[1], sw=2)
    s += '<g transform="translate(%s %s)">%s</g>' % (x, y, inner)
    return s


def at(ic, x, y, inner, rot=0.0, sc=1.0):
    ic.g(x, y, rot, sc, inner)


# ---- The items -------------------------------------------------------------------------------------------------------

def make_icons():
    R = {}

    def icon(item_id, back):
        def deco(fn):
            def run():
                ic = Icon(back)
                fn(ic)
                return ic.svg()
            R[item_id] = run
            return fn
        return deco

    # ---- Owner's Kugmo, Igit, Atuli family (Sange, Yasha, Kaya) and the pairs ----
    @icon("heavy_sword", "str")
    def _(ic):  # Kugmo: a heavy crimson blade, a heart for health restoration, a chain for slow resistance
        at(ic, 60, 60, sword(ic, RED, GOLD, length=86, width=16, heavy=True, gem="#ff4040"), -20)
        ic.add(badge(ic, heart(ic).replace('stroke-width="3"', 'stroke-width="5"'), "#3a0606").replace(
            "<g transform=\"translate(102 102)\">", "<g transform=\"translate(102 102) scale(0.32)\">"))

    @icon("yasha", "agi")
    def _(ic):  # Igit: a curved green blade with speed lines
        at(ic, 66, 62, sword(ic, GREEN, GOLD, length=86, width=11, curve=1.0, gem="#80ff80"), 25)
        at(ic, 0, 0, '<g transform="translate(70 70)">%s</g>' % speed_lines("#c8ffb0", 4, -66, 34, -30, 12))

    @icon("spell_sword", "int")
    def _(ic):  # Atuli: an open blue spellbook with a magic burst above it
        at(ic, 64, 74, book(ic, BLUE), 0, 0.95)
        at(ic, 64, 36, star("#c8e0ff", 18, 6, 8), 0, 1.0)
        at(ic, 64, 36, C(0, 0, 6, "#ffffff", stroke="none", sw=0))

    @icon("twin_swords", "agi")
    def _(ic):
        at(ic, 64, 64, sword(ic, RED, GOLD, length=80, width=14, heavy=True), -35)
        at(ic, 64, 64, sword(ic, GREEN, GOLD, length=80, width=10, curve=1.0), 35)

    @icon("kugmo_atuli", "magic")
    def _(ic):
        at(ic, 72, 80, book(ic, BLUE), 0, 0.7)
        at(ic, 52, 56, sword(ic, RED, GOLD, length=80, width=14, heavy=True), -28)

    @icon("igit_atuli", "magic")
    def _(ic):
        at(ic, 72, 80, book(ic, BLUE), 0, 0.7)
        at(ic, 52, 56, sword(ic, GREEN, GOLD, length=80, width=10, curve=1.0), -20)

    # ---- Boots ----
    @icon("power_treads", "support")
    def _(ic):  # Switch Boots: a boot inside three attribute gems joined by turning arrows
        at(ic, 64, 64, cycle_arrows("#ffe28a", 46))
        at(ic, 64, 70, boot(ic, LEATHER, GOLD), 0, 0.8)
        for x, y, col in ((64, 16, RED), (22, 92, GREEN), (106, 92, BLUE)):
            at(ic, x, y, gem(ic, col, 11, 6))

    @icon("slip_boots", "agi")
    def _(ic):  # Slip Boots: a boot passing through a unit, ghost copies behind it
        for k, op in ((2, 0.22), (1, 0.42)):
            ic.add('<g opacity="%s" transform="translate(%s 66) scale(0.82)">%s</g>' % (op, 70 - k * 18, boot(ic, CYAN, WHITE)))
        at(ic, 72, 66, boot(ic, LEATHER, STEEL, plate=False), 0, 0.82)
        ic.add(L("M98,18 L98,110", "#ffffff", 3, 0.35))
        ic.add(L("M106,26 L106,102", "#ffffff", 2, 0.25))

    @icon("mana_boots", "int")
    def _(ic):  # Mana Boots: a blue boot with a burst of mana
        at(ic, 60, 70, boot(ic, BLUE, GOLD), 0, 0.85)
        ic.add(badge(ic, droplet(ic, BLUE, 0.42), "#081a4a"))

    @icon("boots", "support")
    def _(ic):
        at(ic, 60, 66, boot(ic, LEATHER, BRONZE), 0, 0.95)
        at(ic, 0, 0, '<g transform="translate(66 60)">%s</g>' % speed_lines("#fff0c0", 3, -62, 26, -10, 12, 0.6))

    @icon("travel_boots", "gold")
    def _(ic):  # Travel Boots: golden winged boots and a teleport ring
        at(ic, 64, 104, E(0, 0, 40, 9, "none", stroke="#a8e0ff", sw=3, extra=' opacity="0.8"'))
        at(ic, 68, 62, boot(ic, GOLD, WHITE, wing=True), 0, 0.85)
        ic.add(badge(ic, rings("#a8e0ff", 4, 3, 4), "#06203a"))

    @icon("guard_boots", "support")
    def _(ic):  # Guard Boots: armored boots with a healing cross and an aura
        at(ic, 64, 60, rings("#a0ffb0", 34, 2, 12, 0.5))
        at(ic, 60, 64, boot(ic, IRON, GOLD, plate=True), 0, 0.85)
        ic.add(badge(ic, cross(sz=10), "#06300a"))

    # ---- Bands, wands, rings ----
    @icon("wraith_band", "agi")
    def _(ic):
        at(ic, 64, 70, band(ic, GOLD, GREEN))
        at(ic, 0, 0, '<g transform="translate(70 72)">%s</g>' % speed_lines("#c8ffb0", 3, -62, 22, -8, 10, 0.6))

    @icon("tough_band", "str")
    def _(ic):
        at(ic, 64, 70, band(ic, IRON, RED))
        ic.add(badge(ic, heart(ic).replace('stroke-width="3"', 'stroke-width="6"'), "#3a0606").replace(
            "<g transform=\"translate(102 102)\">", "<g transform=\"translate(102 102) scale(0.3)\">"))

    @icon("smart_band", "int")
    def _(ic):
        at(ic, 64, 70, band(ic, GOLD, BLUE))
        ic.add(badge(ic, star("#c8e0ff", 11, 4, 6), "#081a4a"))

    @icon("magic_wand", "magic")
    def _(ic):  # Zap Wand: a wand crackling with stored charges
        at(ic, 60, 66, staff(ic, WOOD, VIOLET, GOLD, orb_r=9), 35, 0.9)
        for x, y in ((92, 30), (100, 50), (84, 18)):
            at(ic, x, y, star("#f0d0ff", 7, 3, 4))

    @icon("mana_ring", "int")
    def _(ic):
        at(ic, 64, 60, rings("#8ab8ff", 30, 2, 12, 0.55))
        at(ic, 64, 66, ring(ic, GOLD, BLUE), 0, 0.9)

    @icon("leaf_hat", "nature")
    def _(ic):
        at(ic, 64, 60, rings("#c8ff8a", 32, 2, 12, 0.5))
        at(ic, 64, 74, P("M-38,10 Q-30,-28 0,-30 Q30,-28 38,10 Q0,20 -38,10 Z", ic.metal(GREEN, -38, -30, 38, 16), sw=3))
        for x, r in ((-18, -30), (0, 0), (18, 30)):
            at(ic, 64 + x, 44, leaf(ic, GREEN, 0.55), r)

    @icon("steady_ring", "support")
    def _(ic):
        at(ic, 52, 68, ring(ic, GOLD, RED), -12, 0.75)
        at(ic, 80, 62, ring(ic, GOLD, BLUE), 12, 0.75)

    @icon("medic_kit", "support")
    def _(ic):  # Medic Kit: a bronze medallion with a green cross and a healing pulse
        at(ic, 64, 60, rings("#a0ffb0", 34, 2, 12, 0.5))
        at(ic, 64, 64, C(0, 0, 34, ic.metal(BRONZE, -34, -34, 34, 34), sw=3) + C(0, 0, 26, ic.metal(WHITE), sw=2)
           + cross(sz=18))

    @icon("small_shield", "armor")
    def _(ic):
        at(ic, 64, 62, shield(ic, IRON, BRONZE, round_=True), 0, 0.85)
        ic.add(badge(ic, rings("#ffe28a", 4, 3, 4), "#2a1a04"))

    @icon("block_shield", "armor")
    def _(ic):
        at(ic, 64, 64, shield(ic, IRON, GOLD), 0, 0.95)
        at(ic, 64, 60, L("M-14,0 L14,0", INK, 9) + L("M-14,0 L14,0", "#ffe28a", 5))

    @icon("team_shield", "blood")
    def _(ic):  # Team Shield: a red shield and smaller allied shields behind it
        at(ic, 34, 58, shield(ic, IRON, BRONZE), -14, 0.55)
        at(ic, 94, 58, shield(ic, IRON, BRONZE), 14, 0.55)
        at(ic, 64, 66, shield(ic, RED, GOLD), 0, 0.85)
        at(ic, 64, 62, cross(("#fff", "#ffe28a", "#000"), 12))

    @icon("spike_armor", "blood")
    def _(ic):
        at(ic, 64, 66, cuirass(ic, IRON, RED), 0, 0.9)
        for x, y, r in ((24, 30, -50), (104, 30, 50), (16, 68, -90), (112, 68, 90), (34, 100, -130), (94, 100, 130)):
            at(ic, x, y, P("M-5,8 L0,-12 L5,8 Z", ic.metal(STEEL), sw=2), r)

    @icon("battle_armor", "armor")
    def _(ic):  # Battle Armor: a gilded cuirass in a golden aura and a cracked enemy ring
        at(ic, 64, 60, rings("#ffe28a", 36, 2, 10, 0.5))
        at(ic, 64, 64, cuirass(ic, GOLD, STEEL), 0, 0.92)
        at(ic, 64, 58, star("#fff4c0", 9, 4, 4))
        ic.add(badge(ic, crack_ring("#ff6040"), "#3a0a06"))

    @icon("frost_plate", "ice")
    def _(ic):
        at(ic, 64, 64, cuirass(ic, CYAN, WHITE), 0, 0.9)
        at(ic, 64, 58, snowflake(ic, "#e8faff", 0.42))
        ic.add(badge(ic, rings("#bff0ff", 4, 3, 4), "#04202a"))

    @icon("giant_heart", "str")
    def _(ic):
        at(ic, 64, 64, heart(ic, RED), 0, 1.05)
        at(ic, 64, 60, L("M-22,0 L-10,0 L-4,-12 L4,12 L10,0 L22,0", INK, 6) + L("M-22,0 L-10,0 L-4,-12 L4,12 L10,0 L22,0", "#ffffff", 2.6))

    @icon("halberd", "armor")
    def _(ic):
        at(ic, 64, 64, axe(ic, STEEL, WOOD, big=True) + spear(ic), 20)
        ic.add(badge(ic, L("M-8,-8 L8,8 M8,-8 L-8,8", "#ff6040", 3), "#3a0a06"))

    @icon("spell_shield", "gold")
    def _(ic):
        at(ic, 64, 60, C(0, 0, 44, "none", stroke="#ffe28a", sw=3, extra=' opacity="0.6"'))
        at(ic, 64, 64, shield(ic, GOLD, STEEL), 0, 0.85)
        at(ic, 64, 60, star("#fff4c0", 14, 6, 8))

    # ---- Weapons ----
    @icon("shock_hammer", "storm")
    def _(ic):
        at(ic, 60, 66, hammer(ic, IRON, WOOD), 25, 0.95)
        at(ic, 86, 40, bolt(ic, sc=0.55))

    @icon("storm_hammer", "storm")
    def _(ic):  # Storm Hammer: a huge hammer in a storm of bolts
        at(ic, 62, 66, hammer(ic, BLUE, WOOD, 48), 25, 1.0)
        at(ic, 30, 36, bolt(ic, sc=0.45), -15)
        at(ic, 96, 34, bolt(ic, sc=0.55), 15)
        at(ic, 98, 92, bolt(ic, sc=0.35), 10)

    @icon("cleave_axe", "str")
    def _(ic):
        at(ic, 64, 64, P("M-46,-10 Q0,-56 46,-10", "none", stroke="#ffffff", sw=4, extra=' opacity="0.45"'))
        at(ic, 64, 66, axe(ic, STEEL, WOOD, big=True, double=True), 0, 0.9)

    @icon("armor_breaker", "dark")
    def _(ic):
        at(ic, 60, 66, axe(ic, BLACK, BLACK, big=True), -20, 0.95)
        ic.add(badge(ic, crack_ring("#ff6040"), "#3a0a06"))

    @icon("sneak_blade", "dark")
    def _(ic):
        ic.add('<g opacity="0.4" transform="translate(52 64) rotate(30)">%s</g>' % sword(ic, VIOLET, BLACK, 70, 10))
        at(ic, 66, 64, sword(ic, STEEL, BLACK, 70, 10), 30)

    @icon("break_blade", "dark")
    def _(ic):
        ic.add('<g opacity="0.4" transform="translate(52 64) rotate(30)">%s</g>' % sword(ic, VIOLET, BLACK, 76, 12))
        at(ic, 66, 64, sword(ic, STEEL, BLACK, 76, 12, gem="#c060ff"), 30)
        ic.add(badge(ic, crack_ring("#c070ff"), "#200a30"))

    @icon("crit_sword", "str")
    def _(ic):
        at(ic, 60, 64, sword(ic, STEEL, GOLD, 82, 13), -30)
        at(ic, 92, 34, star("#ff5030", 20, 7, 8))

    @icon("crit_bow", "blood")
    def _(ic):
        at(ic, 58, 64, bow(ic, BLACK), -20, 1.0)
        at(ic, 92, 34, star("#ff3020", 22, 8, 8))
        at(ic, 92, 34, star("#ffe0a0", 9, 4, 8))

    @icon("stun_club", "str")
    def _(ic):
        at(ic, 60, 66, hammer(ic, IRON, WOOD, 32), -20, 0.95)
        for x, y in ((90, 26), (106, 40), (82, 40)):
            at(ic, x, y, star("#ffe060", 8, 3, 5))

    @icon("stun_blade", "blood")
    def _(ic):
        at(ic, 60, 66, sword(ic, RED, BLACK, 84, 15, heavy=True), -25)
        for x, y in ((92, 24), (108, 40), (84, 40)):
            at(ic, x, y, star("#ffe060", 8, 3, 5))

    @icon("sure_hit_staff", "gold")
    def _(ic):
        at(ic, 58, 66, staff(ic, WOOD, GOLD, GOLD), -25, 0.95)
        at(ic, 0, 0, badge(ic, C(0, 0, 9, "none", stroke="#ffffff", sw=2) + L("M-13,0 L13,0 M0,-13 L0,13", "#ffffff", 2), "#3a2a04"))

    @icon("silence_staff", "magic")
    def _(ic):
        at(ic, 58, 66, staff(ic, BLACK, VIOLET, GOLD), -25, 0.95)
        ic.add(badge(ic, P("M-10,-2 Q0,-10 10,-2 Q0,6 -10,-2 Z", "#ffffff", sw=1.6) + L("M-12,8 L12,-10", "#ff6060", 3), "#200a30"))

    @icon("root_staff", "nature")
    def _(ic):
        at(ic, 58, 62, staff(ic, WOOD, GREEN, BRONZE), -15, 0.9)
        at(ic, 64, 104, L("M-36,0 Q-20,-10 -10,2 Q0,-12 12,2 Q24,-10 36,0", INK, 7) + L("M-36,0 Q-20,-10 -10,2 Q0,-12 12,2 Q24,-10 36,0", "#a0d070", 3.4))

    @icon("net_staff", "nature")
    def _(ic):  # Net Staff: a staff throwing a weighted net
        at(ic, 74, 56, net(ic), 10, 0.62)
        at(ic, 46, 70, staff(ic, WOOD, GREEN, BRONZE), -20, 0.8)

    @icon("hex_staff", "magic")
    def _(ic):  # Hex Staff: the staff that turns enemies into sheep
        at(ic, 44, 64, staff(ic, BLACK, VIOLET, GOLD), -20, 0.85)
        at(ic, 84, 80, sheep(ic), 0, 0.62)

    @icon("push_staff", "support")
    def _(ic):
        at(ic, 56, 66, staff(ic, WOOD, CYAN, GOLD), -25, 0.9)
        at(ic, 0, 0, '<g transform="translate(118 46)">%s</g>' % speed_lines("#e0ffff", 3, -34, 26, 0, 12, 0.7))

    @icon("battle_staff", "magic")
    def _(ic):
        at(ic, 64, 64, staff(ic, BLACK, VIOLET, GOLD), 30, 0.95)

    @icon("upgrade_staff", "int")
    def _(ic):  # Upgrade Staff: a tall staff with three gems
        at(ic, 64, 66, staff(ic, GOLD, BLUE, GOLD, orb_r=13), 0, 0.95)
        for x, y, col in ((38, 40, RED), (90, 40, GREEN)):
            at(ic, x, y, gem(ic, col, 9))

    @icon("upgrade_gem", "int")
    def _(ic):
        at(ic, 64, 64, gem(ic, BLUE, 34, 6))

    @icon("mask_of_madness", "blood")
    def _(ic):
        at(ic, 64, 64, mask(ic, RED), 0, 1.0)

    @icon("gold_glove", "gold")
    def _(ic):
        at(ic, 58, 64, glove(ic, GOLD), -10, 0.95)
        ic.add(coin(ic, 94, 30) + coin(ic, 104, 46) + coin(ic, 88, 46))

    @icon("dragon_lance", "agi")
    def _(ic):
        at(ic, 64, 64, spear(ic, STEEL, WOOD), 40, 1.05)
        at(ic, 0, 0, '<g transform="translate(70 96)">%s</g>' % speed_lines("#d0ffb0", 2, -60, 30, 0, 10, 0.6))

    @icon("leech_blade", "blood")
    def _(ic):  # Leech Blade: a jagged dark-red blade dripping blood
        at(ic, 60, 62, sword(ic, RED, BLACK, 86, 14, gem="#ff2030"), -25)
        at(ic, 96, 84, droplet(ic, RED, 0.5))
        at(ic, 84, 100, droplet(ic, RED, 0.32))

    @icon("moth_blade", "agi")
    def _(ic):  # Moth Blade: a slim blade between moth wings
        for sx in (-1, 1):
            at(ic, 64, 56, P("M0,0 Q%s,-46 %s,-20 Q%s,-4 0,0 Z" % (sx * 20, sx * 50, sx * 40), ic.metal(GREEN, 0, -40, sx * 50, 0), sw=2.6))
            at(ic, 64, 56, P("M0,4 Q%s,30 %s,22 Q%s,8 0,4 Z" % (sx * 16, sx * 38, sx * 30), ic.metal(CYAN, 0, 4, sx * 38, 30), sw=2.4))
        at(ic, 64, 66, sword(ic, STEEL, GOLD, 78, 9), 0)

    @icon("burning_cape", "fire")
    def _(ic):  # Burning Cape: a cape on fire with a ring of heat
        at(ic, 64, 60, rings("#ffb050", 34, 2, 12, 0.5))
        at(ic, 64, 66, cape(ic, ORANGE, RED), 0, 0.85)
        at(ic, 64, 60, flame(ic, 0.42))

    @icon("crash_knife", "str")
    def _(ic):  # Crash Knife: the Jump Knife hitting the ground with a shockwave
        at(ic, 64, 104, E(0, 0, 50, 10, "none", stroke="#ffb070", sw=3, extra=' opacity="0.8"'))
        at(ic, 64, 104, E(0, 0, 30, 6, "none", stroke="#ffffff", sw=2, extra=' opacity="0.6"'))
        at(ic, 64, 56, dagger(ic, RED, GOLD, 60), 180, 1.05)
        for x, r in ((30, -30), (98, 30)):
            at(ic, x, 90, P("M-4,8 L0,-10 L4,8 Z", ic.metal(BONE), sw=2), r)

    @icon("jump_knife", "magic")
    def _(ic):
        ic.add('<g opacity="0.35" transform="translate(46 70) rotate(40)">%s</g>' % dagger(ic, VIOLET, BLACK, 60))
        at(ic, 70, 58, dagger(ic, STEEL, VIOLET, 60), 40)

    # ---- Casting items ----
    def blast_rod(lv):
        def draw(ic):  # Blast Rod: a rod firing a red-hot beam; its level as dots in the badge
            at(ic, 44, 80, staff(ic, BLACK, ORANGE, GOLD, orb_r=10), 45, 0.8)
            at(ic, 0, 0, L("M60,62 L112,14", "#ff6020", 6 + 2 * lv, 0.6) + L("M60,62 L112,14", "#fff0a0", 2 + lv))
            dots = ""
            for k in range(lv):
                a = -math.pi / 2 + k * 2 * math.pi / lv
                rr = 0 if lv == 1 else 7
                dots += C(math.cos(a) * rr, math.sin(a) * rr, 3.4, "#ffe0a0", sw=1.4)
            ic.add(badge(ic, dots, "#3a0a02"))
        return draw
    for lv in range(1, 6):
        icon("dagon" if lv == 1 else "dagon_%d" % lv, "fire")(blast_rod(lv))

    @icon("net_staff_placeholder", "nature")
    def _(ic):
        pass

    @icon("long_lens", "int")
    def _(ic):  # Long Lens: a lens with a long beam: more cast range
        at(ic, 52, 64, C(0, 0, 30, ic.metal(GOLD), sw=3) + C(0, 0, 22, ic.rad([(0, "#ffffff", 0.9), (0.6, "#8ab8ff", 0.7), (1, "#2a5ae0", 0.8)], -6, -6, 26), sw=2))
        at(ic, 0, 0, L("M80,56 L118,40", "#c0dcff", 6, 0.6) + L("M80,72 L118,88", "#c0dcff", 6, 0.6))
        ic.add(L("M84,64 L120,64", INK, 6) + L("M84,64 L120,64", "#ffffff", 3))
        ic.add(P("M112,56 L122,64 L112,72 Z", "#ffffff", sw=2))

    @icon("soul_gem", "magic")
    def _(ic):  # Soul Gem: one red and one blue gem bound together
        at(ic, 48, 64, gem(ic, RED, 24, 6), -12)
        at(ic, 80, 64, gem(ic, BLUE, 24, 6), 12)

    @icon("time_crystal", "int")
    def _(ic):  # Time Crystal: a crystal with a clock face: shorter cooldowns
        at(ic, 64, 68, crystal(ic, CYAN), 0, 1.0)
        ic.add(badge(ic, clock(ic, 12)))

    @icon("refresh_stone", "storm")
    def _(ic):  # Refresh Stone: a round stone with turning arrows: cooldowns reset
        at(ic, 64, 64, cycle_arrows("#a8e0ff", 42))
        at(ic, 64, 64, C(0, 0, 24, ic.rad([(0, "#e0f4ff"), (0.5, "#3a8ae0"), (1, "#0a1e5a")], -6, -8, 30), sw=3))
        at(ic, 64, 64, clock(ic, 13))

    @icon("war_drum", "support")
    def _(ic):
        at(ic, 64, 60, rings("#ffe28a", 36, 2, 10, 0.45))
        at(ic, 64, 70, drum(ic, RED, BONE, GOLD), 0, 0.9)

    @icon("leech_totem", "blood")
    def _(ic):  # Leech Totem: a skull totem in a red aura
        at(ic, 64, 60, rings("#ff8090", 34, 2, 12, 0.5))
        at(ic, 64, 64, totem(ic), 0, 0.9)

    # ---- New parts ----
    @icon("mana_gem", "int")
    def _(ic):
        at(ic, 64, 64, gem(ic, BLUE, 30, 8))

    @icon("swift_stone", "agi")
    def _(ic):
        at(ic, 64, 64, gem(ic, ORANGE, 30, 5))
        at(ic, 0, 0, '<g transform="translate(66 66)">%s</g>' % speed_lines("#fff0c0", 3, -60, 22, -12, 12, 0.6))

    @icon("plate_armor", "armor")
    def _(ic):
        at(ic, 64, 64, cuirass(ic, STEEL, IRON), 0, 0.98)

    @icon("gold_band", "gold")
    def _(ic):  # Gold Band (Dota's Crown): a gold circlet with three gems
        at(ic, 64, 70, E(0, 0, 40, 16, "none", stroke=INK, sw=14) + E(0, 0, 40, 16, "none", stroke=ic.metal(GOLD, -40, -16, 40, 16), sw=10))
        for x, col in ((-24, RED), (0, GREEN), (24, BLUE)):
            at(ic, 64 + x, 58 if x == 0 else 62, gem(ic, col, 9, 6))

    @icon("wide_stone", "magic")
    def _(ic):  # Wide Stone (Chasm Stone): a stone with rings spreading out: bigger spell areas
        at(ic, 64, 64, rings("#e0b0ff", 30, 3, 10, 0.7))
        at(ic, 64, 64, P("M-20,-14 L4,-24 L22,-8 L18,16 L-6,22 L-22,8 Z", ic.metal(VIOLET, -22, -24, 22, 22), sw=3))

    @icon("relic", "gold")
    def _(ic):  # Relic: a holy war blade on a pedestal of light
        at(ic, 64, 66, sword(ic, GOLD, STEEL, 90, 16, heavy=True, gem="#fff0a0"), 0)

    @icon("war_axe", "str")
    def _(ic):
        at(ic, 64, 64, axe(ic, IRON, WOOD, big=True, double=True), -15, 1.0)

    @icon("troll_ring", "nature")
    def _(ic):
        at(ic, 64, 66, ring(ic, BRONZE, GREEN), 0, 1.0)
        ic.add(badge(ic, cross(sz=10), "#06300a"))

    @icon("feather", "agi")
    def _(ic):
        at(ic, 64, 64, feather(ic, WHITE, GOLD), 0, 1.0)

    @icon("iron_helm", "armor")
    def _(ic):
        at(ic, 64, 66, helm(ic, IRON, BRONZE), 0, 1.05)

    @icon("speed_ribbon", "agi")
    def _(ic):
        at(ic, 64, 64, P("M-40,-10 Q-20,-30 0,-10 Q20,10 40,-10 L40,4 Q20,24 0,4 Q-20,-16 -40,4 Z", ic.metal(CYAN, -40, -30, 40, 24), sw=3))
        at(ic, 0, 0, '<g transform="translate(70 92)">%s</g>' % speed_lines("#e0ffff", 2, -60, 30, 0, 10, 0.6))

    R.pop("net_staff_placeholder")
    return R


# ---- Ability icons for Tock and Kragg (assets/ui/skills/gen) ---------------------------------------------------------

SKILL_OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "skills", "gen")


def magnet(ic, sc=1.0):
    """A horseshoe magnet, poles down: red and steel."""
    arc = "M-26,10 L-26,-6 A26,26 0 0 1 26,-6 L26,10"
    s = L(arc, INK, 22) + L(arc, ic.metal(RED, -26, -32, 26, 10), 15)
    s += L("M-26,-6 A26,26 0 0 1 -6,-30", "#ffffff", 3, 0.45)
    s += P("M-34,8 L-18,8 L-18,30 L-34,30 Z", ic.metal(STEEL, -34, 8, -18, 30), sw=3)
    s += P("M18,8 L34,8 L34,30 L18,30 Z", ic.metal(STEEL, 18, 8, 34, 30), sw=3)
    return '<g transform="scale(%s)">%s</g>' % (sc, s)


def arrows_in(col="#a8c8ff", r=46, n=4, inward=True):
    s = ""
    for k in range(n):
        a = k * 2 * math.pi / n + math.pi / 4
        x0, y0 = math.cos(a) * r, math.sin(a) * r
        x1, y1 = math.cos(a) * (r - 16), math.sin(a) * (r - 16)
        if not inward:
            x0, y0, x1, y1 = x1, y1, x0, y0
        s += L("M%.1f,%.1f L%.1f,%.1f" % (x0, y0, x1, y1), INK, 6) + L("M%.1f,%.1f L%.1f,%.1f" % (x0, y0, x1, y1), col, 3)
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy)
        ux, uy = dx / ln, dy / ln
        tri = "M%.1f,%.1f L%.1f,%.1f L%.1f,%.1f Z" % (x1 + ux * 6, y1 + uy * 6, x1 - uy * 6, y1 + ux * 6, x1 + uy * 6, y1 - ux * 6)
        s += P(tri, col, sw=2)
    return s


def chevrons(col="#d0ffb0", back=False):
    s = ""
    for k in (-1, 1):
        x = k * 14
        d = "M%d,-22 L%d,0 L%d,22" % ((x - 12, x + 12, x - 12) if not back else (x + 12, x - 12, x + 12))
        s += L(d, INK, 12) + L(d, col, 7)
    return s


def make_skills():
    R = {}

    def icon(aid, back):
        def deco(fn):
            def run():
                ic = Icon(back)
                fn(ic)
                return ic.svg()
            R[aid] = run
            return fn
        return deco

    @icon("time_bolt", "gold")
    def _(ic):
        at(ic, 0, 0, L("M14,104 L80,44", "#ffe28a", 12, 0.45) + L("M14,104 L80,44", "#ffffff", 4, 0.8))
        at(ic, 82, 42, clock(ic, 26))

    @icon("fast_forward", "nature")
    def _(ic):
        at(ic, 64, 64, rings("#d0ff9a", 34, 2, 12, 0.5))
        at(ic, 64, 64, chevrons("#e0ffb0"))
        ic.add(badge(ic, clock(ic, 11)))

    @icon("rewind", "storm")
    def _(ic):
        ic.add('<g opacity="0.35" transform="translate(84 64)">%s</g>' % clock(ic, 26))
        at(ic, 52, 64, chevrons("#c0e0ff", back=True))

    @icon("slow_field", "ice")
    def _(ic):
        at(ic, 64, 72, E(0, 0, 50, 22, "none", stroke="#bff0ff", sw=3, extra=' opacity="0.8"'))
        at(ic, 64, 72, E(0, 0, 34, 14, "none", stroke="#ffffff", sw=2, extra=' opacity="0.5"'))
        hg = (P("M-16,-30 L16,-30 L2,0 L16,30 L-16,30 L-2,0 Z", ic.lin([(0, "#e8faff"), (1, "#7ac8e8")], 0, -30, 0, 30), sw=3)
              + P("M-10,26 L10,26 L2,14 L-2,14 Z", "#ffe28a", stroke="none", sw=0)
              + P("M-19,-34 L19,-34 L19,-28 L-19,-28 Z M-19,28 L19,28 L19,34 L-19,34 Z", ic.metal(GOLD), sw=2))
        at(ic, 64, 54, hg, 0, 0.95)

    @icon("quick_hands", "gold")
    def _(ic):
        at(ic, 58, 66, glove(ic, BRONZE), -15, 0.8)
        at(ic, 92, 36, clock(ic, 18))
        at(ic, 0, 0, '<g transform="translate(66 34)">%s</g>' % speed_lines("#fff0c0", 3, -60, 24, 0, 10, 0.6))

    @icon("stop_time", "ice")
    def _(ic):
        at(ic, 64, 64, C(0, 0, 46, "none", stroke="#e8faff", sw=3, extra=' opacity="0.7"'))
        at(ic, 64, 64, clock(ic, 34))
        at(ic, 64, 64, L("M-50,-30 L-20,-10 M50,-26 L22,-8 M-44,40 L-18,14 M46,38 L20,16", "#ffffff", 2.4, 0.7))

    @icon("iron_grip", "storm")
    def _(ic):
        at(ic, 52, 60, magnet(ic, 1.0), -30)
        at(ic, 98, 92, gem(ic, IRON, 12, 6))
        at(ic, 0, 0, L("M64,74 Q82,70 94,86", "#a8c8ff", 3, 0.9))

    @icon("repel", "storm")
    def _(ic):
        at(ic, 64, 64, arrows_in("#c0dcff", 52, 4, inward=False))
        at(ic, 64, 66, magnet(ic, 0.7), 180)

    @icon("magnetize", "storm")
    def _(ic):
        at(ic, 60, 66, magnet(ic, 0.9), 20)
        for x, y in ((96, 30), (104, 50), (86, 22)):
            at(ic, x, y, star("#c0dcff", 7, 3, 4))

    @icon("overload", "storm")
    def _(ic):
        at(ic, 64, 64, rings("#a8c8ff", 20, 3, 12, 0.6))
        at(ic, 64, 62, bolt(ic, sc=1.0))

    @icon("magnet_field", "storm")
    def _(ic):
        at(ic, 64, 64, rings("#a8c8ff", 30, 2, 14, 0.6))
        at(ic, 64, 64, arrows_in("#c0dcff", 58, 4, inward=True))
        at(ic, 64, 66, magnet(ic, 0.6))

    return R


def main():
    icons = make_icons()
    if "--list" in sys.argv:
        print(" ".join(sorted(icons)))
        return
    os.makedirs(OUT, exist_ok=True)
    for k, fn in icons.items():
        with open(os.path.join(OUT, k + ".svg"), "w", newline="\n") as f:
            f.write(fn())
    print("item icons: %d written to %s" % (len(icons), os.path.abspath(OUT)))
    skills = make_skills()
    os.makedirs(SKILL_OUT, exist_ok=True)
    for k, fn in skills.items():
        with open(os.path.join(SKILL_OUT, k + ".svg"), "w", newline=chr(10)) as f:
            f.write(fn())
    print("skill icons: %d written to %s" % (len(skills), os.path.abspath(SKILL_OUT)))


if __name__ == "__main__":
    main()

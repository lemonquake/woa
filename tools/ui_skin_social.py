"""Warriors of Aether: the social screens' skin (Ranked, Profile, Players, Forums; run 2026-10-20), generated.

The same craft as tools/ui_skin.py (height fields lit with the gold, steel and bronze matcaps over dark enamel), for
the pieces the social screens need: the page backdrop, the top bar, the profile banner, panels, stat cards, list rows
(plain, hover, won, lost, yours), the right-click menu and its highlight, tabs, chips, the avatar frame, and a set of
relief icons (medallions and bare glyphs) for kills, deaths, assists, last hits, denies, gold, experience, MVP, rampage,
triple kill, first blood, lane, wards, damage, wins, streaks, time, healing, comments, visitors, friends, reports,
commends, blocking, copying, comparing, history, the leaderboard and the forum.

    python tools/ui_skin_social.py [--preview work/shots/social_skin.png]

Writes into assets/ui/skin/ and merges its entries into skin.json (tools/ui_skin.py calls build() too, so a full
rebuild keeps them).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui_skin_ornaments as O  # noqa: E402

K = None          # the ui_skin module (set by build)


def _S():
    return K.S


# ---- shapes --------------------------------------------------------------------------------------------------------

def relief(mask, bevel, power=0.7):
    """Height of a raised shape: a bevel from its edge, flat on top."""
    d = O.inside_distance(mask)
    return np.clip(d / max(1e-3, bevel), 0, 1) ** power


def poly_mask(n, polys, k=4):
    return O.mask_from_poly(n, n, polys, k)


def circle(n, cx, cy, r):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.sqrt((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2)
    return np.clip(r - d + 0.5, 0, 1)


def ring(n, cx, cy, r0, r1):
    return np.clip(circle(n, cx, cy, r1) - circle(n, cx, cy, r0), 0, 1)


def ellipse(n, cx, cy, rx, ry):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.sqrt(((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2)
    return np.clip((1 - d) * min(rx, ry) + 0.5, 0, 1)


def thick_line(n, pts, width, k=4):
    img = Image.new("L", (n * k, n * k), 0)
    d = ImageDraw.Draw(img)
    d.line([(x * k, y * k) for x, y in pts], fill=255, width=max(1, int(width * k)), joint="curve")
    r = width * k / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x * k - r, y * k - r, x * k + r, y * k + r), fill=255)
    return np.asarray(img.resize((n, n), Image.LANCZOS), np.float32) / 255.0


def star_pts(cx, cy, r0, r1, points=5, rot=-math.pi / 2):
    out = []
    for i in range(points * 2):
        a = rot + i * math.pi / points
        r = r1 if i % 2 == 0 else r0
        out.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return out


def rot_rect(cx, cy, length, width, ang, tip=0.0):
    """A blade: a rectangle along `ang` centred at (cx, cy), with a pointed tip of `tip` length at the far end."""
    ca, sa = math.cos(ang), math.sin(ang)
    hx, hy = ca * length / 2, sa * length / 2
    nx, ny = -sa * width / 2, ca * width / 2
    a = (cx - hx + nx, cy - hy + ny)
    b = (cx + hx - ca * tip + nx, cy + hy - sa * tip + ny)
    t = (cx + hx, cy + hy)
    c = (cx + hx - ca * tip - nx, cy + hy - sa * tip - ny)
    d = (cx - hx - nx, cy - hy - ny)
    return [a, b, t, c, d]


# ---- the glyphs: each a mask in an n x n square (the symbol's own drawing) ------------------------------------------

def g_swords(n):
    m = np.zeros((n, n), np.float32)
    for s in (-1, 1):
        ang = math.radians(-45 if s > 0 else -135)
        cx, cy = n * 0.5, n * 0.5
        m = np.maximum(m, poly_mask(n, [rot_rect(cx + s * n * 0.02, cy - n * 0.02, n * 0.8, n * 0.11, ang, n * 0.13)]))
        # cross-guard and grip near the lower end
        gx = cx - math.cos(ang) * n * 0.25
        gy = cy - math.sin(ang) * n * 0.25
        m = np.maximum(m, poly_mask(n, [rot_rect(gx, gy, n * 0.3, n * 0.08, ang + math.pi / 2)]))
        px = cx - math.cos(ang) * n * 0.39
        py = cy - math.sin(ang) * n * 0.39
        m = np.maximum(m, circle(n, px, py, n * 0.065))
    return m


def g_skull(n):
    m = circle(n, n * 0.5, n * 0.42, n * 0.3)
    m = np.maximum(m, poly_mask(n, [[(n * 0.33, n * 0.55), (n * 0.67, n * 0.55), (n * 0.63, n * 0.8), (n * 0.37, n * 0.8)]]))
    holes = circle(n, n * 0.39, n * 0.45, n * 0.085) + circle(n, n * 0.61, n * 0.45, n * 0.085)
    holes += poly_mask(n, [[(n * 0.5, n * 0.54), (n * 0.46, n * 0.62), (n * 0.54, n * 0.62)]])
    for i in range(3):
        x = n * (0.43 + 0.07 * i)
        holes += poly_mask(n, [[(x - n * 0.012, n * 0.68), (x + n * 0.012, n * 0.68), (x + n * 0.012, n * 0.8), (x - n * 0.012, n * 0.8)]])
    return np.clip(m - holes, 0, 1)


def g_links(n):
    a = ring(n, n * 0.38, n * 0.5, n * 0.12, n * 0.21)
    b = ring(n, n * 0.62, n * 0.5, n * 0.12, n * 0.21)
    return np.clip(a + b, 0, 1)


def g_coin(n, slash=False):
    m = ring(n, n * 0.5, n * 0.5, n * 0.26, n * 0.36)
    m = np.maximum(m, poly_mask(n, [[(n * 0.5, n * 0.33), (n * 0.6, n * 0.5), (n * 0.5, n * 0.67), (n * 0.4, n * 0.5)]]))
    if slash:
        m = np.maximum(m, thick_line(n, [(n * 0.22, n * 0.78), (n * 0.78, n * 0.22)], n * 0.07))
    return m


def g_coins(n):
    m = np.zeros((n, n), np.float32)
    for i in range(3):
        y = n * (0.68 - 0.14 * i)
        m = np.maximum(m, ellipse(n, n * 0.45, y, n * 0.24, n * 0.1))
        m = np.maximum(m, poly_mask(n, [[(n * 0.21, y), (n * 0.69, y), (n * 0.69, y + n * 0.05), (n * 0.21, y + n * 0.05)]]))
    m = np.maximum(m, thick_line(n, [(n * 0.74, n * 0.6), (n * 0.74, n * 0.24)], n * 0.06))
    m = np.maximum(m, poly_mask(n, [[(n * 0.74, n * 0.14), (n * 0.84, n * 0.28), (n * 0.64, n * 0.28)]]))
    return m


def g_spark(n):
    return poly_mask(n, [star_pts(n * 0.5, n * 0.5, n * 0.1, n * 0.38, 4, -math.pi / 2)]) + \
        poly_mask(n, [star_pts(n * 0.5, n * 0.5, n * 0.06, n * 0.2, 4, -math.pi / 4)]) * 0.0


def g_star_laurel(n):
    m = poly_mask(n, [star_pts(n * 0.5, n * 0.44, n * 0.11, n * 0.24, 5)])
    for s in (-1, 1):
        for i in range(4):
            a = math.radians(200 - i * 28) if s < 0 else math.radians(-20 + i * 28)
            cx = n * 0.5 + math.cos(a) * n * 0.34
            cy = n * 0.5 + math.sin(a) * n * 0.34 * 0.95 + n * 0.04
            ta = a + s * math.pi / 2.2
            pts = rot_rect(cx, cy, n * 0.14, n * 0.07, ta, n * 0.05)
            m = np.maximum(m, poly_mask(n, [pts]))
    return np.clip(m, 0, 1)


def chaikin(pts, n=3):
    for _ in range(n):
        out = []
        for i in range(len(pts)):
            p, q = pts[i], pts[(i + 1) % len(pts)]
            out += [(0.75 * p[0] + 0.25 * q[0], 0.75 * p[1] + 0.25 * q[1]), (0.25 * p[0] + 0.75 * q[0], 0.25 * p[1] + 0.75 * q[1])]
        pts = out
    return pts


def g_flame(n):
    """A fire: a tall centre tongue, two side tongues, a rounded base, a hollow core."""
    outline = [(0.5, 0.88), (0.68, 0.84), (0.79, 0.7), (0.8, 0.52), (0.74, 0.36), (0.78, 0.2), (0.64, 0.32), (0.6, 0.18),
               (0.5, 0.04), (0.44, 0.22), (0.36, 0.3), (0.26, 0.18), (0.24, 0.38), (0.2, 0.54), (0.22, 0.7), (0.33, 0.84)]
    m = poly_mask(n, [[(n * x, n * y) for x, y in chaikin(outline)]])
    core = [(0.5, 0.82), (0.6, 0.76), (0.63, 0.62), (0.57, 0.5), (0.52, 0.38), (0.46, 0.5), (0.39, 0.6), (0.4, 0.75)]
    inner = poly_mask(n, [[(n * x, n * y) for x, y in chaikin(core)]])
    return np.clip(m - inner * 0.8, 0, 1)


def g_claws(n):
    m = np.zeros((n, n), np.float32)
    for i in range(3):
        x0 = n * (0.3 + 0.18 * i)
        pts = O.bezier((x0, n * 0.2), (x0 + n * 0.06, n * 0.4), (x0 - n * 0.02, n * 0.6), (x0 - n * 0.1, n * 0.82), 30)
        hh, mm = O.taper_stroke(n, n, pts, n * 0.03, n * 0.11, soft=0)
        m = np.maximum(m, mm)
    return np.clip(m, 0, 1)


def g_drop(n):
    pts = []
    for i in range(61):
        t = i / 60 * 2 * math.pi
        x = math.sin(t) * 0.24 * (1 - max(0.0, -math.cos(t)) ** 1.6 * 0.95)
        y = -math.cos(t) * 0.34
        pts.append((n * (0.5 + x), n * (0.54 + y)))
    m = poly_mask(n, [pts])
    shine = ellipse(n, n * 0.42, n * 0.6, n * 0.04, n * 0.08)
    return np.clip(m - shine, 0, 1)


def g_road(n):
    m = poly_mask(n, [[(n * 0.42, n * 0.16), (n * 0.46, n * 0.16), (n * 0.3, n * 0.86), (n * 0.18, n * 0.86)]])
    m += poly_mask(n, [[(n * 0.54, n * 0.16), (n * 0.58, n * 0.16), (n * 0.82, n * 0.86), (n * 0.7, n * 0.86)]])
    for i in range(3):
        y0 = n * (0.22 + 0.22 * i)
        w0 = n * (0.012 + 0.012 * i)
        m += poly_mask(n, [[(n * 0.5 - w0, y0), (n * 0.5 + w0, y0), (n * 0.5 + w0 * 1.3, y0 + n * 0.12), (n * 0.5 - w0 * 1.3, y0 + n * 0.12)]])
    return np.clip(m, 0, 1)


def g_eye(n):
    pts = []
    for i in range(41):
        t = i / 40 * 2 * math.pi
        pts.append((n * (0.5 + math.cos(t) * 0.36), n * (0.5 + math.sin(t) * 0.2 * (1 - 0.15 * math.cos(t) ** 2))))
    m = poly_mask(n, [pts])
    m = np.clip(m - circle(n, n * 0.5, n * 0.5, n * 0.15), 0, 1)
    m = np.maximum(m, circle(n, n * 0.5, n * 0.5, n * 0.08))
    return m


def g_burst(n):
    return poly_mask(n, [star_pts(n * 0.5, n * 0.5, n * 0.16, n * 0.38, 8, -math.pi / 2)])


def g_cup(n):
    m = poly_mask(n, [[(n * 0.28, n * 0.2), (n * 0.72, n * 0.2), (n * 0.66, n * 0.46), (n * 0.56, n * 0.56), (n * 0.44, n * 0.56),
                       (n * 0.34, n * 0.46)]])
    m = np.maximum(m, ring(n, n * 0.28, n * 0.33, n * 0.06, n * 0.12) * (np.mgrid[0:n, 0:n][1] < n * 0.3))
    m = np.maximum(m, ring(n, n * 0.72, n * 0.33, n * 0.06, n * 0.12) * (np.mgrid[0:n, 0:n][1] > n * 0.7))
    m = np.maximum(m, poly_mask(n, [[(n * 0.46, n * 0.56), (n * 0.54, n * 0.56), (n * 0.56, n * 0.7), (n * 0.44, n * 0.7)]]))
    m = np.maximum(m, poly_mask(n, [[(n * 0.32, n * 0.7), (n * 0.68, n * 0.7), (n * 0.7, n * 0.8), (n * 0.3, n * 0.8)]]))
    return np.clip(m, 0, 1)


def g_bolt(n):
    return poly_mask(n, [[(n * 0.56, n * 0.12), (n * 0.3, n * 0.54), (n * 0.48, n * 0.54), (n * 0.4, n * 0.88), (n * 0.72, n * 0.42),
                          (n * 0.53, n * 0.42), (n * 0.66, n * 0.12)]])


def g_hourglass(n):
    m = poly_mask(n, [[(n * 0.3, n * 0.2), (n * 0.7, n * 0.2), (n * 0.53, n * 0.5), (n * 0.7, n * 0.8), (n * 0.3, n * 0.8),
                       (n * 0.47, n * 0.5)]])
    m = np.maximum(m, poly_mask(n, [[(n * 0.24, n * 0.13), (n * 0.76, n * 0.13), (n * 0.76, n * 0.2), (n * 0.24, n * 0.2)]]))
    m = np.maximum(m, poly_mask(n, [[(n * 0.24, n * 0.8), (n * 0.76, n * 0.8), (n * 0.76, n * 0.87), (n * 0.24, n * 0.87)]]))
    return m


def g_cross(n):
    return O.mask_from_rects(n, n, [(int(n * 0.4), int(n * 0.18), int(n * 0.6), int(n * 0.82)),
                                    (int(n * 0.18), int(n * 0.4), int(n * 0.82), int(n * 0.6))], chamfer=int(n * 0.03))


def g_bubble(n):
    m = np.zeros((n, n), np.float32)
    m = np.maximum(m, poly_mask(n, [[(n * 0.2, n * 0.22), (n * 0.8, n * 0.22), (n * 0.8, n * 0.64), (n * 0.46, n * 0.64),
                                     (n * 0.3, n * 0.8), (n * 0.32, n * 0.64), (n * 0.2, n * 0.64)]]))
    for i in range(3):
        m -= circle(n, n * (0.36 + 0.14 * i), n * 0.43, n * 0.045)
    return np.clip(m, 0, 1)


def g_bust(n, x=0.5, s=1.0):
    m = circle(n, n * x, n * (0.36 + (1 - s) * 0.1), n * 0.14 * s)
    m = np.maximum(m, ellipse(n, n * x, n * 0.82, n * 0.27 * s, n * 0.24 * s) * (np.mgrid[0:n, 0:n][0] < n * 0.8))
    return np.clip(m, 0, 1)


def g_friends(n):
    return np.clip(g_bust(n, 0.38, 0.85) + g_bust(n, 0.64, 0.85), 0, 1)


def g_flag(n):
    m = O.mask_from_rects(n, n, [(int(n * 0.26), int(n * 0.14), int(n * 0.32), int(n * 0.86))])
    m = np.maximum(m, poly_mask(n, [[(n * 0.32, n * 0.16), (n * 0.76, n * 0.24), (n * 0.62, n * 0.36), (n * 0.76, n * 0.5),
                                     (n * 0.32, n * 0.5)]]))
    return m


def g_heart(n):
    m = circle(n, n * 0.38, n * 0.4, n * 0.15) + circle(n, n * 0.62, n * 0.4, n * 0.15)
    m += poly_mask(n, [[(n * 0.24, n * 0.46), (n * 0.76, n * 0.46), (n * 0.5, n * 0.8)]])
    return np.clip(m, 0, 1)


def g_block(n):
    m = ring(n, n * 0.5, n * 0.5, n * 0.26, n * 0.35)
    m = np.maximum(m, thick_line(n, [(n * 0.3, n * 0.7), (n * 0.7, n * 0.3)], n * 0.08))
    return m


def g_copy(n):
    a = O.mask_from_rects(n, n, [(int(n * 0.22), int(n * 0.18), int(n * 0.62), int(n * 0.66))])
    a -= O.mask_from_rects(n, n, [(int(n * 0.28), int(n * 0.24), int(n * 0.56), int(n * 0.6))])
    b = O.mask_from_rects(n, n, [(int(n * 0.38), int(n * 0.34), int(n * 0.78), int(n * 0.82))])
    return np.clip(np.maximum(a, b), 0, 1)


def g_scales(n):
    m = O.mask_from_rects(n, n, [(int(n * 0.47), int(n * 0.18), int(n * 0.53), int(n * 0.8)),
                                 (int(n * 0.16), int(n * 0.26), int(n * 0.84), int(n * 0.31)),
                                 (int(n * 0.32), int(n * 0.78), int(n * 0.68), int(n * 0.84))])
    for x in (0.25, 0.75):
        m = np.maximum(m, poly_mask(n, [[(n * x, n * 0.31), (n * (x + 0.12), n * 0.56), (n * (x - 0.12), n * 0.56)]]) * 0.0 +
                       poly_mask(n, [[(n * (x - 0.14), n * 0.56), (n * (x + 0.14), n * 0.56), (n * (x + 0.08), n * 0.63),
                                      (n * (x - 0.08), n * 0.63)]]))
        m = np.maximum(m, thick_line(n, [(n * x, n * 0.31), (n * (x - 0.12), n * 0.56)], n * 0.02))
        m = np.maximum(m, thick_line(n, [(n * x, n * 0.31), (n * (x + 0.12), n * 0.56)], n * 0.02))
    return m


def g_clock(n):
    m = ring(n, n * 0.5, n * 0.5, n * 0.27, n * 0.35)
    m = np.maximum(m, thick_line(n, [(n * 0.5, n * 0.5), (n * 0.5, n * 0.3)], n * 0.06))
    m = np.maximum(m, thick_line(n, [(n * 0.5, n * 0.5), (n * 0.64, n * 0.58)], n * 0.06))
    return m


def g_podium(n):
    return O.mask_from_rects(n, n, [(int(n * 0.38), int(n * 0.3), int(n * 0.62), int(n * 0.8)),
                                    (int(n * 0.14), int(n * 0.48), int(n * 0.38), int(n * 0.8)),
                                    (int(n * 0.62), int(n * 0.58), int(n * 0.86), int(n * 0.8))])


GLYPHS = {
    "kill": (g_swords, (150, 34, 30)), "death": (g_skull, (40, 44, 54)), "assist": (g_links, (24, 92, 120)),
    "lh": (lambda n: g_coin(n), (128, 92, 20)), "deny": (lambda n: g_coin(n, True), (92, 70, 30)), "gpm": (g_coins, (128, 92, 20)),
    "xpm": (g_spark, (82, 52, 140)), "mvp": (g_star_laurel, (150, 108, 24)), "rampage": (g_flame, (170, 50, 20)),
    "triple": (g_claws, (140, 30, 40)), "fb": (g_drop, (150, 18, 24)), "lane": (g_road, (40, 80, 130)),
    "ward": (g_eye, (30, 110, 90)), "damage": (g_burst, (160, 70, 20)), "win": (g_cup, (40, 120, 60)),
    "streak": (g_bolt, (150, 120, 20)), "time": (g_hourglass, (60, 66, 84)), "heal": (g_cross, (40, 130, 70)),
    "comment": (g_bubble, (40, 80, 130)), "visitor": (lambda n: g_bust(n), (60, 66, 84)), "friend": (g_friends, (40, 110, 80)),
    "report": (g_flag, (150, 40, 30)), "commend": (g_heart, (150, 50, 90)), "block": (g_block, (90, 40, 40)),
    "copy": (g_copy, (60, 66, 84)), "compare": (g_scales, (90, 76, 40)), "history": (g_clock, (60, 66, 84)),
    "board": (g_podium, (120, 90, 24)), "profile": (lambda n: g_bust(n), (50, 70, 110)),
}


def medallion(name, glyph, tint, size=64):
    """A round medallion: a gold rim, tinted enamel inside, the glyph in gold relief with a soft drop shadow."""
    S = _S()
    n = size * S
    c = n / 2
    disc = circle(n, c, c, n * 0.47)
    rim = ring(n, c, c, n * 0.39, n * 0.47)
    rim_h = np.sin(np.clip((np.sqrt((np.mgrid[0:n, 0:n][1] + 0.5 - c) ** 2 + (np.mgrid[0:n, 0:n][0] + 0.5 - c) ** 2) - n * 0.39) / (n * 0.08), 0, 1) * math.pi)
    base = K.enamel(n, n, tint, seed=sum(map(ord, name)) % 97, pattern=False)
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    shade = np.clip(1.15 - ((x - c * 0.7) ** 2 + (y - c * 0.6) ** 2) ** 0.5 / n * 1.1, 0.45, 1.2)
    base = base * shade[..., None] * 1.25
    # the glyph, a little smaller than the inside
    g = glyph(n)
    gi = Image.fromarray((np.clip(g, 0, 1) * 255).astype(np.uint8)).resize((int(n * 0.74), int(n * 0.74)), Image.LANCZOS)
    gm = np.zeros((n, n), np.float32)
    off = (n - gi.width) // 2
    gm[off:off + gi.height, off:off + gi.width] = np.asarray(gi, np.float32) / 255.0
    gh = relief(gm, n * 0.035)
    rgb, alpha = K.shade_layers(base, [(rim_h * rim, rim, K.GOLD, 4.0 * S, 0.0), (gh, gm, K.GOLD, 5.0 * S, 0.55)])
    alpha = np.maximum(alpha, disc)
    # a soft outer shadow so it sits on any panel
    sh = K.blur(disc, 1.5 * S) * 0.5
    a2 = np.maximum(alpha, sh)
    rgb = rgb * (alpha / np.maximum(a2, 1e-4))[..., None]
    return K.save_rgba(name, rgb, a2, None, kind="image")


def glyph_only(name, glyph, size=48):
    """The glyph alone in gold relief (menus, small labels)."""
    S = _S()
    n = size * S
    g = glyph(n)
    gh = relief(g, n * 0.04)
    rgb, alpha = K.shade_layers(np.zeros((n, n, 3), np.float32), [(gh, g, K.GOLD, 5.0 * S, 0.45)])
    return K.save_rgba(name, rgb, alpha, None, kind="image")


# ---- surfaces ---------------------------------------------------------------------------------------------------------

def page_backdrop(name, w=1920, h=1080, base=(8, 11, 18)):
    """The social screens' backdrop: deep enamel, smoke, a faint engraved diamond lattice, a warm glow from the top and a
    large faint crest behind the content."""
    W, H = w, h                                   # soft: drawn at 1x
    rgb = K.enamel(W, H, base, seed=53, pattern=False)
    smoke = K.fbm(W, H, cell=220, octaves=5, seed=57)
    rgb = rgb + (smoke[..., None] - 0.5) * np.array([0.06, 0.065, 0.09])
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    p = 38.0
    lat = (np.abs(((x + y) % p) - p / 2) < 0.6) | (np.abs(((x - y) % p) - p / 2) < 0.6)
    fade = np.clip(1.0 - ((x - W / 2) / (W * 0.7)) ** 2 - ((y - H * 0.3) / (H * 0.9)) ** 2, 0, 1)
    rgb = rgb + lat[..., None] * np.array([0.016, 0.014, 0.01]) * fade[..., None]
    glow = np.exp(-(((x - W / 2) / (W * 0.42)) ** 2 + ((y + H * 0.05) / (H * 0.42)) ** 2))
    rgb = rgb + glow[..., None] * np.array([0.13, 0.095, 0.04])
    # a faint big crest, top centre
    ch, cm, _ = O.crest(W, H, W / 2, H * 0.16, 200, True)
    rgb = rgb + (K.normals(ch, 6.0)[..., 0:1] * 0.0 + cm[..., None]) * np.array([0.02, 0.016, 0.008])
    rgb = rgb * K.vignette(W, H, 0.6, 1.8)[..., None]
    return K.save_rgba(name, rgb, np.ones((H, W), np.float32), None, kind="image")


def top_bar(name, w=1920, h=96):
    """The social screens' top bar: dark steel with a brushed grain, a gold ridge with beads along the bottom, a small
    crest at the centre of the ridge."""
    S = _S()
    W, H = w * S, h * S
    grain = K.fbm(W, H, cell=3 * S, octaves=2, seed=61)
    streak = ndimage.uniform_filter1d(K.fbm(W, H, cell=2 * S, octaves=1, seed=63), size=60 * S, axis=1)
    base = np.array([0.035, 0.042, 0.062]) * (0.9 + 0.25 * grain[..., None] + 0.35 * (streak[..., None] - 0.5))
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    base = base * (0.8 + 0.4 * (1 - y / H))[..., None]
    base = base + np.exp(-((y - 2 * S) ** 2) / (2 * (1.2 * S) ** 2))[..., None] * np.array([0.06, 0.05, 0.04])
    d = (H - y)                                    # distance up from the bottom
    bands = [(0.0, 1.0 * S, "flat"), (1.0 * S, 4.6 * S, "ridge"), (4.6 * S, 5.8 * S, "groove"), (5.8 * S, 7.4 * S, "ridge")]
    hgt, mask = K.frame_profile(d.astype(np.float32), bands)
    mask = mask * (d < 7.4 * S)
    bh, bm = O.beads(W, H, [(px, H - 10.6 * S) for px in np.arange(24 * S, W, 18 * S)], 1.3 * S)
    rgb, alpha = K.shade_layers(base, [(hgt, mask, K.GOLD, 5.0 * S, 0.0), (bh, bm * 0.8, K.BRONZE, 4.0 * S, 0.0)])
    ch, cm, cc = O.crest(W, H, W / 2, H - 6 * S, 16 * S, False)
    gh, gm = O.faceted_gem(W, H, cc[0], cc[1], 16 * S * 0.26, 6, 0)
    rgb, a2 = K.shade_layers(rgb, [(ch, cm, K.GOLD, 7 * S, 0.5), (gh, gm, K.gem_colors((255, 196, 90)), 3 * S, 0.0)])
    return K.save_rgba(name, rgb, np.ones((H, W), np.float32), None, kind="image")


def banner(name, w=1840, h=250, base=(14, 18, 30)):
    """The profile banner: a brushed dark plate with a cool-to-warm light sweep, a large engraved crest at the right,
    a gold ridge top and bottom with beads, gem studs in the four corners."""
    S = _S()
    W, H = w * S, h * S
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    rgb = K.enamel(W, H, base, seed=71, pattern=True)
    streak = ndimage.uniform_filter1d(K.fbm(W, H, cell=2 * S, octaves=1, seed=73), size=90 * S, axis=1)
    rgb = rgb * (0.92 + 0.3 * (streak[..., None] - 0.5))
    sweep = np.exp(-(((x - W * 0.18) / (W * 0.3)) ** 2 + ((y - H * 0.2) / (H * 1.2)) ** 2))
    rgb = rgb + sweep[..., None] * np.array([0.05, 0.06, 0.09])
    warm = np.exp(-(((x - W * 0.82) / (W * 0.22)) ** 2 + ((y - H * 0.5) / (H * 0.9)) ** 2))
    rgb = rgb + warm[..., None] * np.array([0.08, 0.055, 0.02])
    # engraved crest watermark: a sunken ornament lit faintly
    ch, cm, cc = O.crest(W, H, W * 0.82, H * 0.42, 70 * S, True)
    n = K.normals(ch, 3.0 * S)
    lit = np.clip(-n[..., 0] * 0.6 - n[..., 1] * 0.8, -1, 1)
    rgb = rgb + (lit * cm)[..., None] * np.array([0.05, 0.04, 0.02]) - cm[..., None] * 0.012
    # ridges top and bottom
    d = np.minimum(y, H - 1 - y)
    bands = [(0.0, 1.2 * S, "flat"), (1.2 * S, 5.0 * S, "ridge"), (5.0 * S, 6.4 * S, "groove"), (6.4 * S, 8.2 * S, "ridge")]
    hgt, mask = K.frame_profile(d.astype(np.float32) + 0.5, bands)
    mask = mask * (d < 8.2 * S)
    side = np.minimum(x, W - 1 - x)
    hs, ms = K.frame_profile(side.astype(np.float32) + 0.5, [(0.0, 1.0 * S, "flat"), (1.0 * S, 3.6 * S, "ridge")])
    ms = ms * (side < 3.6 * S)
    inner_shadow = (1 - K.smoothstep(8 * S, 26 * S, d)) * 0.45
    rgb = rgb * (1 - inner_shadow[..., None])
    bpts = [(px, 12.5 * S) for px in np.arange(40 * S, W - 30 * S, 22 * S)] + \
        [(px, H - 12.5 * S) for px in np.arange(40 * S, W - 30 * S, 22 * S)]
    bh, bm = O.beads(W, H, bpts, 1.3 * S)
    rgb, alpha = K.shade_layers(rgb, [(hgt, mask, K.GOLD, 5.0 * S, 0.0), (hs, ms, K.GOLD, 4.0 * S, 0.0),
                                      (bh, bm * 0.7, K.BRONZE, 4.0 * S, 0.0)])
    for gx, gy in ((16 * S, 16 * S), (W - 16 * S, 16 * S), (16 * S, H - 16 * S), (W - 16 * S, H - 16 * S)):
        bz = K.dome(W, H, gx, gy, 9 * S)
        gh, gm = O.faceted_gem(W, H, gx, gy, 6.5 * S, 8, math.pi / 8)
        rgb, _ = K.shade_layers(rgb, [(bz, (bz > 0.02).astype(np.float32), K.GOLD, 6 * S, 0.5),
                                      (gh, gm, K.gem_colors((255, 190, 80)), 3 * S, 0.0)])
    return K.save_rgba(name, rgb, np.ones((H, W), np.float32), None, kind="image")


def card(name, w=96, h=96, rim=None, glow=0.0, base=(15, 19, 29), accent=None):
    """A stat card / inset: a dark well with an inner shadow under the top edge, a thin metal ridge, a sheen across the
    top, and (accent) a coloured bar along the left."""
    S = _S()
    rim = K.BRONZE if rim is None else rim
    W, H = w * S, h * S
    d = K.rect_dist(W, H, 6 * S)
    hgt, mask = K.frame_profile(d, [(0.0, 0.8 * S, "flat"), (0.8 * S, 2.6 * S, "ridge")])
    inner = (d >= 2.6 * S).astype(np.float32)
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    rgb = K.enamel(W, H, base, seed=81, pattern=False)
    rgb = rgb * (1.1 - 0.25 * (y / H))[..., None]
    top = (1 - K.smoothstep(2.6 * S, 14 * S, y)) * inner
    rgb = rgb * (1 - 0.35 * top[..., None])
    sheen = np.exp(-((y - 6 * S) ** 2) / (2 * (3 * S) ** 2)) * inner * 0.04
    rgb = rgb + sheen[..., None]
    if glow > 0:
        gl = np.exp(-((d - 3.2 * S) ** 2) / (2 * (1.6 * S) ** 2)) * inner
        rgb = rgb + gl[..., None] * np.array([0.95, 0.75, 0.35]) * 0.22 * glow
    if accent is not None:
        bar = ((x > 2.6 * S) & (x < 6.6 * S) & (d >= 2.6 * S)).astype(np.float32)
        col = np.array(accent, np.float32) / 255.0
        rgb = rgb * (1 - bar[..., None]) + bar[..., None] * col * (0.75 + 0.35 * (1 - y / H))[..., None]
    rgb, alpha = K.shade_layers(rgb, [(hgt, mask, rim, 3.5 * S, 0.0)])
    alpha = np.maximum(alpha, inner * 0.93)
    m = 14
    return K.save_rgba(name, rgb, alpha, [m, m, m, m])


def row(name, accent=None, hover=False, mine=False):
    """A list row plate: a thin dark glass slab with a faint top light; hover: a warm glow and a gold rim; accent: a
    bar on the left (won, lost); mine: a blue tint (you)."""
    S = _S()
    W, H = 200 * S, 52 * S
    d = K.rect_dist(W, H, 5 * S)
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    base = (16, 22, 36) if mine else (13, 16, 24)
    rgb = K.enamel(W, H, base, seed=91, pattern=False) * (1.08 - 0.22 * (y / H))[..., None]
    if hover:
        rgb = rgb + np.exp(-(((y - H) / (H * 0.9)) ** 2))[..., None] * np.array([0.09, 0.07, 0.03])
    hgt, mask = K.frame_profile(d, [(0.0, 0.6 * S, "flat"), (0.6 * S, 1.8 * S, "ridge")])
    inner = (d >= 1.8 * S).astype(np.float32)
    rgb = rgb + np.exp(-((y - 2.2 * S) ** 2) / (2 * (0.8 * S) ** 2))[..., None] * 0.05
    if accent is not None:
        bar = ((x > 1.8 * S) & (x < 5.8 * S) & (d >= 1.8 * S)).astype(np.float32)
        col = np.array(accent, np.float32) / 255.0
        rgb = rgb * (1 - bar[..., None]) + bar[..., None] * col
        tint = np.exp(-((x - 6 * S) / (60 * S)) ** 2) * inner
        rgb = rgb + tint[..., None] * col * 0.12
    rimcap = K.GOLD if hover else (K.STEEL if mine else K.DARKMETAL)
    rgb, alpha = K.shade_layers(rgb, [(hgt, mask * (1.0 if hover else 0.8), rimcap, 3.0 * S, 0.0)])
    alpha = np.maximum(alpha, inner * (0.92 if hover else 0.82))
    return K.save_rgba(name, rgb, alpha, [12, 10, 12, 10])


def menu_panel(name, w=120, h=120):
    """The right-click menu: a dark plate, a gold rim with a groove, tiny corner studs, a baked drop shadow."""
    S = _S()
    pad = 10
    W, H = (w + pad * 2) * S, (h + pad * 2) * S
    d_out = K.rect_dist(W, H, 14 * S)
    d = d_out - pad * S
    hgt, mask = K.frame_profile(np.clip(d, 0, None), [(0.0, 1.0 * S, "flat"), (1.0 * S, 3.4 * S, "ridge"), (3.4 * S, 4.4 * S, "groove"),
                                                      (4.4 * S, 5.6 * S, "ridge")])
    mask = mask * (d > 0)
    inner = (d >= 5.6 * S).astype(np.float32)
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    rgb = K.enamel(W, H, (12, 15, 23), seed=101, pattern=True) * (1.05 - 0.2 * y / H)[..., None]
    rgb = rgb * (1 - 0.5 * ((1 - K.smoothstep(5.6 * S, 14 * S, d)) * inner)[..., None])
    shadow = K.blur((d > -3 * S).astype(np.float32), 4 * S) * 0.6
    rgb, alpha = K.shade_layers(rgb, [(hgt, mask, K.GOLD, 4.5 * S, 0.0)])
    alpha = np.maximum(alpha, inner * 0.97)
    for gx, gy in ((pad * S + 5 * S, pad * S + 5 * S), (W - pad * S - 5 * S, pad * S + 5 * S), (pad * S + 5 * S, H - pad * S - 5 * S),
                   (W - pad * S - 5 * S, H - pad * S - 5 * S)):
        bz = K.dome(W, H, gx, gy, 3.2 * S)
        rgb, a3 = K.shade_layers(rgb, [(bz, (bz > 0.02).astype(np.float32), K.GOLD, 5 * S, 0.0)])
        alpha = np.maximum(alpha, a3)
    out_a = np.maximum(alpha, shadow * (1 - alpha))
    rgb = rgb * (alpha / np.maximum(out_a, 1e-4))[..., None]
    m = 24 + pad
    return K.save_rgba(name, rgb, out_a, [m, m, m, m], extra={"content": [pad + 10, pad + 10, pad + 10, pad + 10]})


def menu_highlight(name, w=120, h=32):
    """The hovered item of a menu: a warm gold wash fading to the right, a bright edge on the left."""
    S = _S()
    W, H = w * S, h * S
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    d = K.rect_dist(W, H, 4 * S)
    a = np.clip(d / (1.2 * S), 0, 1) * (0.55 - 0.4 * x / W)
    rgb = np.zeros((H, W, 3), np.float32) + np.array([0.95, 0.72, 0.3])
    edge = (x < 3 * S).astype(np.float32) * np.clip(d / S, 0, 1)
    rgb = rgb * (1 - edge[..., None]) + edge[..., None] * np.array([1.0, 0.9, 0.6])
    a = np.maximum(a, edge)
    a = a * (0.6 + 0.4 * np.exp(-((y - H / 2) / (H * 0.6)) ** 2))
    return K.save_rgba(name, rgb, a, [10, 8, 10, 8])


def tab_plate(name, active):
    """A top tab: a soft light from below and a gold bar with a centre gem (active), a faint bar (hover)."""
    S = _S()
    W, H = 160 * S, 60 * S
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    lift = np.exp(-(((y - H) / (H * 0.8)) ** 2 + ((x - W / 2) / (W * 0.55)) ** 2))
    rgb = np.zeros((H, W, 3), np.float32) + np.array([0.95, 0.78, 0.42])
    a = lift * (0.16 if active else 0.08)
    bar = ((y > H - 5 * S) & (y < H - 1 * S) & (x > 12 * S) & (x < W - 12 * S)).astype(np.float32)
    bar = K.blur(bar, 0.6 * S)
    hgt = bar
    base = rgb * 0.0
    lit, la = K.shade_layers(base, [(hgt, bar * (1.0 if active else 0.45), K.GOLD, 3 * S, 0.0)])
    rgb = rgb * (1 - la[..., None]) + lit * la[..., None]
    a = np.maximum(a, la)
    return K.save_rgba(name, rgb, a, [24, 16, 24, 8])


def chip(name, gold=False):
    S = _S()
    W, H = 52 * S, 26 * S
    d = K.rect_dist(W, H, 13 * S)
    hgt, mask = K.frame_profile(d, [(0.0, 0.7 * S, "flat"), (0.7 * S, 2.0 * S, "ridge")])
    inner = (d >= 2.0 * S).astype(np.float32)
    y = np.mgrid[0:H, 0:W][0].astype(np.float32)
    if gold:
        dome_h = np.clip(d / (6 * S), 0, 1) ** 0.6
        rgb, alpha = K.shade_layers(np.zeros((H, W, 3), np.float32), [(dome_h * 0.6, (d > 0).astype(np.float32), K.GOLD, 2.5 * S, 0.0),
                                                                     (hgt, mask, K.GOLD, 3 * S, 0.0)])
        rgb = rgb * 0.9
    else:
        rgb = K.enamel(W, H, (18, 22, 34), seed=111, pattern=False) * (1.1 - 0.3 * y / H)[..., None]
        rgb, alpha = K.shade_layers(rgb, [(hgt, mask, K.BRONZE, 3 * S, 0.0)])
        alpha = np.maximum(alpha, inner * 0.95)
    return K.save_rgba(name, rgb, alpha, [13, 12, 13, 12])


def avatar_frame(name, size=128):
    """A square portrait frame: a bevelled gold border, inner shadow lip, a gem stud at each corner (centre clear)."""
    S = _S()
    W = H = size * S
    d = K.rect_dist(W, H, 8 * S)
    hgt, mask = K.frame_profile(d, [(0.0, 1.2 * S, "flat"), (1.2 * S, 5.2 * S, "ridge"), (5.2 * S, 6.6 * S, "groove"),
                                    (6.6 * S, 8.4 * S, "ridge")])
    mask = mask * (d < 8.4 * S)
    lip = (d >= 8.4 * S) & (d < 16 * S)
    sh = np.where(lip, (1 - (d - 8.4 * S) / (7.6 * S)) * 0.55, 0.0).astype(np.float32)
    rgb, alpha = K.shade_layers(np.zeros((H, W, 3), np.float32), [(hgt, mask, K.GOLD, 5 * S, 0.0)])
    alpha = np.maximum(alpha, sh)
    for gx, gy in ((7 * S, 7 * S), (W - 7 * S, 7 * S), (7 * S, H - 7 * S), (W - 7 * S, H - 7 * S)):
        bz = K.dome(W, H, gx, gy, 7.5 * S)
        gh, gm = O.faceted_gem(W, H, gx, gy, 5.2 * S, 8, math.pi / 8)
        rgb, a3 = K.shade_layers(rgb, [(bz, (bz > 0.02).astype(np.float32), K.GOLD, 6 * S, 0.4),
                                       (gh, gm, K.gem_colors((255, 190, 80)), 3 * S, 0.0)])
        alpha = np.maximum(alpha, a3)
    return K.save_rgba(name, rgb, alpha, None, kind="image")


def build(k_module):
    """Make every social piece into K's manifest (K = the ui_skin module)."""
    global K
    K = k_module
    K.ornate_panel("soc_panel", 120, 120, 26, gem=(255, 190, 80), base=(11, 14, 22), corner=12, radius=8, alpha_inside=0.9,
                   bands=[(0.0, 1.0, "flat"), (1.0, 3.6, "ridge"), (3.6, 4.6, "groove"), (4.6, 6.0, "ridge")])
    K.ornate_panel("soc_panel_blue", 120, 120, 26, gem=(90, 150, 255), base=(10, 15, 26), corner=12, radius=8, alpha_inside=0.9,
                   bands=[(0.0, 1.0, "flat"), (1.0, 3.6, "ridge"), (3.6, 4.6, "groove"), (4.6, 6.0, "ridge")])
    card("soc_card")
    card("soc_card_hi", rim=K.GOLD, glow=1.0)
    card("soc_card_gold", rim=K.GOLD, base=(24, 20, 14))
    card("soc_card_win", accent=(60, 190, 90))
    card("soc_card_loss", accent=(220, 70, 60))
    row("soc_row")
    row("soc_row_hover", hover=True)
    row("soc_row_win", accent=(60, 190, 90))
    row("soc_row_loss", accent=(220, 70, 60))
    row("soc_row_win_hover", accent=(60, 190, 90), hover=True)
    row("soc_row_loss_hover", accent=(220, 70, 60), hover=True)
    row("soc_row_you", accent=(90, 150, 255), mine=True)
    row("soc_row_gold", accent=(240, 190, 80))
    menu_panel("soc_menu")
    menu_highlight("soc_menu_hi")
    tab_plate("soc_tab_on", True)
    tab_plate("soc_tab_hover", False)
    chip("soc_chip")
    chip("soc_chip_gold", gold=True)
    avatar_frame("soc_avatar")
    top_bar("soc_topbar")
    banner("soc_banner")
    page_backdrop("soc_bg")
    for key, (fn, tint) in GLYPHS.items():
        medallion("ic_" + key, fn, tint)
        glyph_only("gl_" + key, fn)


if __name__ == "__main__":
    import ui_skin  # noqa: E402
    build(ui_skin)
    path = os.path.join(ui_skin.OUT, "skin.json")
    prev = json.load(open(path)) if os.path.exists(path) else {"scale": ui_skin.S, "textures": {}}
    prev["textures"].update(ui_skin.MANIFEST)
    with open(path, "w") as f:
        json.dump({"scale": ui_skin.S, "textures": prev["textures"]}, f, indent=1)
    print("social skin: %d textures" % len(ui_skin.MANIFEST))
    if "--preview" in sys.argv:
        out = sys.argv[sys.argv.index("--preview") + 1]
        names = list(ui_skin.MANIFEST.keys())
        bg = Image.open(os.path.join(ui_skin.OUT, "soc_bg.png")).convert("RGBA")
        sheet = Image.new("RGBA", (1920, 2400), (0, 0, 0, 255))
        sheet.paste(bg, (0, 0))
        x, y, rowh = 10, 10, 0
        for nm in names:
            if nm == "soc_bg":
                continue
            e = ui_skin.MANIFEST[nm]
            img = Image.open(os.path.join(ui_skin.OUT, e["file"])).convert("RGBA")
            w, h = e["size"]
            img = img.resize((max(1, w), max(1, h)), Image.LANCZOS)
            if x + img.width > 1910:
                x = 10
                y += rowh + 24
                rowh = 0
            sheet.alpha_composite(img, (x, y))
            ImageDraw.Draw(sheet).text((x, y + img.height + 2), nm, fill=(230, 220, 200, 255))
            x += img.width + 16
            rowh = max(rowh, img.height)
        sheet.crop((0, 0, 1920, min(2400, y + rowh + 30))).save(out)
        print("preview", out)

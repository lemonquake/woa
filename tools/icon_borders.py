"""Warriors of Aether: the border packs drawn round skill and item icons, generated.

A border pack is a folder with border.json and its PNGs (assets/ui/borders/<id>/, or user://borders/<id>/ for packs
added later, such as ones bought in a store). The game draws a pack through src/ui/icon_border.gd; Options picks
which pack is used ("icon_border", Options > Game > Icon border).

border.json:
    {"name": "Default", "scale": 4, "ref": 64, "min": 0.5, "max": 1.6,
     "pieces": {"skill": {"file": "skill.png", "margins": [l, t, r, b], "outset": 3, "shine": "shine.png"},
                "passive": {...}, "item": {...}}}
  scale    texture pixels per drawn pixel at the reference size
  ref      the icon size (drawn pixels) the margins are made for; smaller or larger icons scale the rim between
           min and max times
  margins  the nine-slice margins in drawn pixels at the reference size
  outset   how far the frame reaches outside the icon (drawn pixels at the reference size)
  shine    optional image stretched over the whole icon under the frame (light from above)
  Kinds the game asks for: skill (an active ability), passive (passive and innate abilities), item; also
  "ultimate" if a pack has it (otherwise skill). A missing kind falls back to skill, then to no frame.

    python tools/icon_borders.py [--preview work/shots/icon_borders.png]
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui_skin as K  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "borders")
R = 4                                   # texture pixels per drawn pixel
REF = 64                                # drawn size of the reference icon


def _save(folder, name, rgb, alpha):
    os.makedirs(folder, exist_ok=True)
    arr = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)])
    img = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")
    img.save(os.path.join(folder, name + ".png"))
    return img


def _shade(d, bands, cap, strength):
    hgt, mask = K.frame_profile(d, bands)
    n = K.normals(hgt, strength)
    return K.matcap_shade(n, cap), mask


def _inner_shadow(d, start, width, strength):
    """Darkness thrown onto the icon just inside the rim (recessed look)."""
    inside = (d >= start).astype(np.float32)
    return (1 - K.smoothstep(start, start + width, d)) * inside * strength


def _studs(W, H, at, r, cap):
    """Small domed rivets (one per corner) on the rim."""
    hgt = np.zeros((H, W), np.float32)
    for cx, cy in at:
        hgt = np.maximum(hgt, K.dome(W, H, cx, cy, r))
    mask = K.smoothstep(0.0, 0.25, hgt)
    n = K.normals(hgt, 3.0 * R)
    return K.matcap_shade(n, cap), mask


def frame(kind, folder, *, metal, bands, chamfer=0.0, radius=0.0, shadow=(6.5, 7.0, 0.62), studs=False,
          outline=(0.02, 0.015, 0.01), glow_line=None):
    """One frame piece: a rim of metal bands with a dark outline outside it, a soft inner shadow onto the icon and,
    optionally, corner rivets and a fine bright line along the inner edge."""
    W = H = REF * R
    d = K.rect_dist(W, H, radius * R, chamfer=chamfer * R)
    px = [(a * R, b * R, k) for a, b, k in bands]
    rgb, mask = _shade(d, px, metal, 4.5 * R)
    # a crisp dark line round the outside so the frame reads on any background
    out = (1 - K.smoothstep(0.6 * R, 1.1 * R, d)) * K.smoothstep(0.0, 0.5, d)
    rgb = rgb * (1 - out[..., None]) + np.array(outline, np.float32) * out[..., None]
    alpha = np.maximum(mask, out)
    rim_end = px[-1][1]
    if glow_line is not None:
        # a thin bright line where the rim meets the icon
        g = np.exp(-((d - rim_end - 0.35 * R) ** 2) / (2 * (0.35 * R) ** 2))
        col = np.array(glow_line[:3], np.float32)
        rgb = rgb * (1 - g[..., None] * glow_line[3]) + col * g[..., None] * glow_line[3]
        alpha = np.maximum(alpha, g * glow_line[3])
    sh = _inner_shadow(d, rim_end, shadow[1] * R, shadow[2])
    keep = alpha > 0.02
    rgb = np.where(keep[..., None], rgb, 0.0)
    alpha = np.maximum(alpha, sh)
    if studs:
        o = (bands[0][1] + bands[-1][1]) * 0.5 * R + chamfer * R * 0.32
        at = [(o, o), (W - o, o), (o, H - o), (W - o, H - o)]
        srgb, sm = _studs(W, H, at, 1.9 * R, K.GOLD)
        rgb = rgb * (1 - sm[..., None]) + srgb * sm[..., None]
        alpha = np.maximum(alpha, sm)
    _save(folder, kind, rgb, alpha)


def shine(folder, name="shine", top=0.16, bottom=0.22):
    """Light from above and a darker foot, stretched over the whole icon under the frame."""
    W = H = 64 * R // 2
    y = (np.mgrid[0:H, 0:W][0].astype(np.float32) + 0.5) / H
    x = (np.mgrid[0:H, 0:W][1].astype(np.float32) + 0.5) / W
    light = np.clip(1 - y / 0.42, 0, 1) ** 1.8 * top
    # a faint diagonal sheen across the upper left
    sheen = np.exp(-(((x + y) - 0.55) ** 2) / (2 * 0.06 ** 2)) * (1 - y) * 0.06
    dark = np.clip((y - 0.62) / 0.38, 0, 1) ** 1.6 * bottom
    a_light = np.clip(light + sheen, 0, 1)
    rgb = np.ones((H, W, 3), np.float32) * (a_light / np.maximum(a_light + dark, 1e-6))[..., None]
    alpha = np.clip(a_light + dark, 0, 1)
    _save(folder, name, rgb, alpha)


def build_default():
    folder = os.path.join(ROOT, "default")
    # an active skill: a heavy gold rim with cut corners, a groove and an inner bead, gold rivets at the corners
    frame("skill", folder, metal=K.GOLD, chamfer=5.0,
          bands=[(0.0, 1.0, "flat"), (1.0, 4.2, "ridge"), (4.2, 5.0, "groove"), (5.0, 6.4, "ridge")],
          studs=True, glow_line=(1.0, 0.86, 0.5, 0.55))
    # a passive or innate skill: a sunken bronze rim with round corners and a deeper shadow (no rivets, no bright
    # line), so it reads as "always on" next to the gold active frames, as Dota marks passives
    frame("passive", folder, metal=K.BRONZE, radius=9.0,
          bands=[(0.0, 1.0, "flat"), (1.0, 3.6, "bevel"), (3.6, 4.6, "groove"), (4.6, 5.6, "ridge")],
          shadow=(5.6, 9.0, 0.8))
    # an item: a slimmer gold rim with softly rounded corners
    frame("item", folder, metal=K.GOLD, radius=4.0,
          bands=[(0.0, 0.9, "flat"), (0.9, 3.4, "ridge"), (3.4, 4.0, "groove"), (4.0, 5.0, "ridge")],
          shadow=(5.0, 5.5, 0.5), glow_line=(1.0, 0.86, 0.5, 0.35))
    shine(folder)
    m = {"name": "Default", "scale": R, "ref": REF, "min": 0.5, "max": 1.6, "pieces": {
        "skill": {"file": "skill.png", "margins": [14, 14, 14, 14], "outset": 3, "shine": "shine.png"},
        "passive": {"file": "passive.png", "margins": [15, 15, 15, 15], "outset": 3, "shine": "shine.png"},
        "item": {"file": "item.png", "margins": [11, 11, 11, 11], "outset": 2, "shine": "shine.png"},
    }}
    _write(folder, m)


def build_plain():
    """A minimal pack: a thin dark line with a faint light edge (proves packs swap; some players like less frame)."""
    folder = os.path.join(ROOT, "plain")
    for kind, radius in (("skill", 1.0), ("passive", 7.0), ("item", 3.0)):
        W = H = REF * R
        d = K.rect_dist(W, H, radius * R)
        line = K.smoothstep(0.0, 0.5, d) * (1 - K.smoothstep(1.6 * R, 2.1 * R, d))
        edge = np.exp(-((d - 2.4 * R) ** 2) / (2 * (0.3 * R) ** 2)) * 0.45
        rgb = np.zeros((H, W, 3), np.float32) + np.array([0.04, 0.04, 0.05])
        rgb = rgb * (1 - edge[..., None]) + np.array([0.85, 0.85, 0.85]) * edge[..., None]
        alpha = np.maximum(line * 0.95, edge) + _inner_shadow(d, 2.6 * R, 4 * R, 0.35 if kind != "passive" else 0.6)
        _save(folder, kind, rgb, alpha)
    m = {"name": "Plain", "scale": R, "ref": REF, "min": 0.5, "max": 1.6, "pieces": {
        "skill": {"file": "skill.png", "margins": [8, 8, 8, 8], "outset": 1},
        "passive": {"file": "passive.png", "margins": [9, 9, 9, 9], "outset": 1},
        "item": {"file": "item.png", "margins": [7, 7, 7, 7], "outset": 1},
    }}
    _write(folder, m)


def _write(folder, m):
    with open(os.path.join(folder, "border.json"), "w", newline="\n") as f:
        json.dump(m, f, indent=1)
        f.write("\n")


def preview(path, icons):
    """Each pack's pieces round real icons at 32, 48, 64 and 96 drawn pixels (nine-sliced as the game does)."""
    packs = sorted(p for p in os.listdir(ROOT) if os.path.isfile(os.path.join(ROOT, p, "border.json")))
    sizes = [32, 48, 64, 96]
    cell = 120
    sheet = Image.new("RGBA", (40 + cell * len(sizes) * 3, 40 + cell * len(packs) + 20), (22, 26, 34, 255))
    dr = ImageDraw.Draw(sheet)
    for pi, pack in enumerate(packs):
        m = json.load(open(os.path.join(ROOT, pack, "border.json")))
        for ki, kind in enumerate(["skill", "passive", "item"]):
            piece = m["pieces"][kind]
            tex = Image.open(os.path.join(ROOT, pack, piece["file"])).convert("RGBA")
            sh = Image.open(os.path.join(ROOT, pack, piece["shine"])).convert("RGBA") if piece.get("shine") else None
            icon = Image.open(icons[ki]).convert("RGBA")
            for si, s in enumerate(sizes):
                k = min(max(s / m["ref"], m["min"]), m["max"])
                x0 = 30 + (ki * len(sizes) + si) * cell + 10
                y0 = 30 + pi * cell + 10
                sheet.alpha_composite(icon.resize((s, s), Image.LANCZOS), (x0, y0))
                if sh:
                    sheet.alpha_composite(sh.resize((s, s), Image.LANCZOS), (x0, y0))
                o = int(round(piece["outset"] * k))
                fr = nine(tex, s + 2 * o, [v * k for v in piece["margins"]], m["scale"] / k)
                sheet.alpha_composite(fr, (x0 - o, y0 - o))
            dr.text((30 + ki * len(sizes) * cell + 10, 14), "%s: %s" % (m["name"], kind) if pi == 0 else kind,
                    fill=(220, 210, 190, 255))
        dr.text((6, 30 + pi * cell + cell - 22), m["name"], fill=(220, 210, 190, 255))
    sheet.save(path)


def nine(tex, size, margins, sc):
    """Nine-slice `tex` into a size x size image: margins in drawn pixels, sc texture pixels per drawn pixel."""
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tw, th = tex.size
    l, t, r, b = [min(v, size / 2) for v in margins]
    xs = [0, l, size - r, size]
    ys = [0, t, size - b, size]
    us = [0, margins[0] * sc, tw - margins[2] * sc, tw]
    vs = [0, margins[1] * sc, th - margins[3] * sc, th]
    for j in range(3):
        for i in range(3):
            dw, dh = int(round(xs[i + 1])) - int(round(xs[i])), int(round(ys[j + 1])) - int(round(ys[j]))
            if dw <= 0 or dh <= 0:
                continue
            src = tex.crop((int(us[i]), int(vs[j]), int(us[i + 1]), int(vs[j + 1]))).resize((dw, dh), Image.LANCZOS)
            out.alpha_composite(src, (int(round(xs[i])), int(round(ys[j]))))
    return out


if __name__ == "__main__":
    build_default()
    build_plain()
    if "--preview" in sys.argv:
        art = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "art")
        preview(sys.argv[sys.argv.index("--preview") + 1],
                [os.path.join(art, "skills", "chomp.png"), os.path.join(art, "skills", "blubber.png"),
                 os.path.join(art, "items", "battle_armor.png")])
    print("borders built in", os.path.abspath(ROOT))

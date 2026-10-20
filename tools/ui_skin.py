"""Warriors of Aether: the interface skin, generated.

Every frame, button, slot, bar and ornament of the game's interface is made here from code: height fields (bevels,
ridges, beads, engraved scrolls, faceted gems) shaded with a gold or steel matcap and composited over dark enamel.
Textures are written at twice the size they are drawn at 1920x1080 (crisp at 3840x2160) to assets/ui/skin/, with
skin.json describing each one's nine-slice margins in drawn (1x) pixels.

    python tools/ui_skin.py [--preview work/shots/ui_skin_preview.png]
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ui_skin_ornaments as O  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "skin")
S = 2                                   # texture pixels per drawn pixel
RNG = np.random.default_rng(7)
MANIFEST = {}

# ---- noise and helpers ---------------------------------------------------------------------------------------------


def value_noise(w, h, cell, seed=0):
    """Smooth value noise: a random grid upsampled bicubically."""
    rng = np.random.default_rng(seed)
    gw, gh = max(2, int(math.ceil(w / cell)) + 2), max(2, int(math.ceil(h / cell)) + 2)
    grid = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray((grid * 255).astype(np.uint8)).resize((gw * cell, gh * cell), Image.BICUBIC)
    a = np.asarray(img, dtype=np.float32)[:h, :w] / 255.0
    return a


def fbm(w, h, cell=64, octaves=5, seed=0, gain=0.5):
    total = np.zeros((h, w), np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        c = max(2, int(cell / (2 ** o)))
        total += value_noise(w, h, c, seed + o * 17) * amp
        norm += amp
        amp *= gain
    return total / norm


def blur(a, r):
    if r <= 0:
        return a
    return ndimage.gaussian_filter(a, r)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def rect_dist(w, h, radius=0.0, chamfer=0.0):
    """Distance inward from the edge of a w x h rectangle (positive inside), with rounded or chamfered corners."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    x += 0.5
    y += 0.5
    dx = np.minimum(x, w - x)
    dy = np.minimum(y, h - y)
    d = np.minimum(dx, dy)
    if radius > 0:
        cx = np.clip(radius - dx, 0, None)
        cy = np.clip(radius - dy, 0, None)
        corner = (cx > 0) & (cy > 0)
        d = np.where(corner, radius - np.sqrt(cx * cx + cy * cy), d)
    if chamfer > 0:
        dc = (dx + dy - chamfer) / math.sqrt(2.0)
        d = np.minimum(d, dc)
    return d


# ---- shading ---------------------------------------------------------------------------------------------------------

def normals(height, strength):
    gy, gx = np.gradient(height * strength)
    n = np.dstack([-gx, -gy, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n


def make_matcap(stops, size=256, key=(-0.55, -0.62, 0.56), rim=0.35, spec_pow=28, spec=1.0):
    """A matcap sphere: a colour ramp lit by a key light, with a hot specular and a cool rim (a studio look)."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    nx = (x + 0.5) / size * 2 - 1
    ny = (y + 0.5) / size * 2 - 1
    r2 = nx * nx + ny * ny
    nz = np.sqrt(np.clip(1 - r2, 0, 1))
    k = np.array(key, np.float32)
    k /= np.linalg.norm(k)
    diff = np.clip(nx * k[0] + ny * k[1] + nz * k[2], 0, 1)
    # reflection of the view (0,0,1) about the normal, against the key light
    rz = 2 * nz * nz - 1
    rx = 2 * nz * nx
    ry = 2 * nz * ny
    sp = np.clip(rx * k[0] + ry * k[1] + rz * k[2], 0, 1) ** spec_pow * spec
    t = np.clip(0.12 + 0.85 * diff, 0, 1)
    pos = np.array([s[0] for s in stops], np.float32)
    cols = np.array([s[1] for s in stops], np.float32) / 255.0
    rgb = np.dstack([np.interp(t, pos, cols[:, c]) for c in range(3)])
    rim_t = smoothstep(0.55, 1.0, np.sqrt(r2)) * rim
    rgb = rgb + sp[..., None] + rim_t[..., None] * np.array([0.35, 0.32, 0.28])
    return np.clip(rgb, 0, 1)


GOLD = make_matcap([(0.0, (38, 22, 8)), (0.3, (110, 70, 26)), (0.55, (186, 136, 62)), (0.78, (236, 196, 112)),
                    (1.0, (255, 240, 196))])
STEEL = make_matcap([(0.0, (14, 16, 22)), (0.35, (52, 58, 70)), (0.62, (112, 120, 136)), (0.85, (176, 184, 198)),
                     (1.0, (236, 240, 248))], spec_pow=40)
BRONZE = make_matcap([(0.0, (24, 14, 8)), (0.4, (78, 46, 24)), (0.7, (138, 92, 52)), (1.0, (220, 170, 112))],
                     spec_pow=22, spec=0.7)
DARKMETAL = make_matcap([(0.0, (6, 7, 10)), (0.4, (22, 25, 33)), (0.75, (52, 58, 72)), (1.0, (120, 128, 146))],
                        spec_pow=30, spec=0.5)


def matcap_shade(n, cap):
    size = cap.shape[0]
    u = np.clip(((n[..., 0] + 1) * 0.5 * (size - 1)).astype(np.int32), 0, size - 1)
    v = np.clip(((n[..., 1] + 1) * 0.5 * (size - 1)).astype(np.int32), 0, size - 1)
    return cap[v, u]


def gem_colors(base):
    """A faceted gem's matcap from a base colour (deep core, bright facets)."""
    b = np.array(base, np.float32)
    return make_matcap([(0.0, tuple(b * 0.12)), (0.4, tuple(b * 0.45)), (0.72, tuple(b * 0.85)),
                        (0.92, tuple(np.clip(b * 1.2 + 40, 0, 255))), (1.0, (255, 255, 255))], spec_pow=60, spec=1.4)


# ---- surfaces --------------------------------------------------------------------------------------------------------

def enamel(w, h, base=(13, 17, 26), seed=3, pattern=True):
    """The panels' dark enamel: deep blue-black with a soft cloudy grain and a faint engraved lattice."""
    n = fbm(w, h, cell=96 * S, octaves=5, seed=seed)
    fine = fbm(w, h, cell=6 * S, octaves=2, seed=seed + 9)
    c = np.array(base, np.float32) / 255.0
    rgb = c[None, None, :] * (0.78 + 0.45 * n[..., None]) + (fine[..., None] - 0.5) * 0.025
    if pattern:
        y, x = np.mgrid[0:h, 0:w].astype(np.float32)
        p = 26.0 * S
        a = (np.abs(((x + y) % p) - p / 2) < 0.7 * S) | (np.abs(((x - y) % p) - p / 2) < 0.7 * S)
        rgb = rgb + a[..., None] * np.array([0.012, 0.014, 0.02])
    return np.clip(rgb, 0, 1)


def vignette(w, h, strength=0.45, power=2.2):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    nx = (x / max(1, w - 1)) * 2 - 1
    ny = (y / max(1, h - 1)) * 2 - 1
    v = np.clip(1 - (np.abs(nx) ** power + np.abs(ny) ** power) * 0.5, 0, 1)
    return 1 - strength * (1 - v)


# ---- ornaments as height fields --------------------------------------------------------------------------------------

def stroke_height(w, h, paths, width, soft):
    """Height of tubes along polylines: drawn as thick lines at 4x, downsampled, blurred into a rounded profile."""
    k = 4
    img = Image.new("L", (w * k, h * k), 0)
    d = ImageDraw.Draw(img)
    for path in paths:
        pts = [(px * k, py * k) for px, py in path]
        if len(pts) > 1:
            d.line(pts, fill=255, width=max(1, int(width * k)), joint="curve")
        r = width * k / 2
        for px, py in (pts[0], pts[-1]):
            d.ellipse((px - r, py - r, px + r, py + r), fill=255)
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    return blur(a, soft)


def spiral(cx, cy, r0, r1, turns, start, ccw=1, n=120):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = start + ccw * t * turns * 2 * math.pi
        r = r0 + (r1 - r0) * t
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def bezier(p0, p1, p2, p3, n=60):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0]
        y = u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]
        pts.append((x, y))
    return pts


def dome(w, h, cx, cy, r):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d2 = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) / (r * r)
    return np.sqrt(np.clip(1 - d2, 0, 1))


def faceted_gem(w, h, cx, cy, r, sides=8, rot=0.0):
    """A cut gem: a flat table in the middle, sloped facets around (a pyramid of `sides` faces)."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = x + 0.5 - cx
    dy = y + 0.5 - cy
    a = np.arctan2(dy, dx) - rot
    seg = 2 * math.pi / sides
    af = (np.mod(a, seg) - seg / 2)
    rr = np.sqrt(dx * dx + dy * dy) * np.cos(af) / math.cos(seg / 2)   # polygon radius
    hgt = np.clip(1 - rr / r, 0, 1)
    table = np.minimum(hgt, 0.45)
    mask = (rr < r).astype(np.float32)
    return table / 0.45 * mask, mask


# ---- composition -----------------------------------------------------------------------------------------------------

def shade_layers(base_rgb, layers):
    """Composite metal layers over a base. layers: [(height, mask, matcap, strength, shadow)]: each layer's height is
    lit with its matcap where mask > 0, casting a soft drop shadow onto what lies below."""
    rgb = base_rgb.copy()
    alpha = np.zeros(base_rgb.shape[:2], np.float32)
    for hgt, mask, cap, strength, shadow in layers:
        if shadow > 0:
            sh = blur(np.roll(np.roll(mask, int(2 * S), 0), int(1 * S), 1), 2.0 * S) * shadow
            rgb = rgb * (1 - sh[..., None])
            alpha = np.maximum(alpha, sh * 0.85)
        n = normals(hgt, strength)
        lit = matcap_shade(n, cap)
        m = np.clip(mask, 0, 1)[..., None]
        rgb = rgb * (1 - m) + lit * m
        alpha = np.maximum(alpha, mask)
    return rgb, alpha


def save_rgba(name, rgb, alpha, margins=None, kind="nine", extra=None):
    os.makedirs(OUT, exist_ok=True)
    a = np.clip(alpha, 0, 1)
    arr = np.dstack([np.clip(rgb, 0, 1), a])
    img = Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, name + ".png"))
    entry = {"file": name + ".png", "size": [img.width // S, img.height // S], "kind": kind}
    if margins is not None:
        entry["margins"] = margins
    if extra:
        entry.update(extra)
    MANIFEST[name] = entry
    return img


def frame_profile(d, bands):
    """Height and metal mask from inward distance d: bands [(start, end, kind)] in texture pixels.
    kind 'ridge' (rounded bead), 'bevel' (slope up then flat), 'groove' (dark channel)."""
    hgt = np.zeros_like(d)
    mask = np.zeros_like(d)
    for a, b, kind in bands:
        t = np.clip((d - a) / (b - a), 0, 1)
        inside = ((d >= a) & (d < b)).astype(np.float32)
        aa = smoothstep(a - 0.8, a + 0.8, d) * (1 - smoothstep(b - 0.8, b + 0.8, d))
        if kind == "ridge":
            hh = np.sin(t * math.pi)
        elif kind == "bevel":
            hh = np.minimum(1.0, t * 3.0) * 0.9 + 0.1
        elif kind == "flat":
            hh = np.full_like(t, 0.55)
        else:
            hh = np.zeros_like(t)
        hgt = np.where(inside > 0, np.maximum(hgt, hh), hgt)
        if kind != "groove":
            mask = np.maximum(mask, aa)
    # nothing outside the shape (a distance of 0 means outside)
    return hgt, mask * smoothstep(0.0, 1.0, d)


def corner_crest(w, h, cx, cy, size, flip_x=False, flip_y=False, gem=(70, 140, 255)):
    """A corner ornament: a faceted gem in a gold bezel with two scroll curls running along the edges."""
    sx = -1 if flip_x else 1
    sy = -1 if flip_y else 1
    paths = []
    # curls along both edges, rolling inward
    paths.append(bezier((cx, cy), (cx + sx * size * 0.9, cy - sy * size * 0.05), (cx + sx * size * 1.4, cy + sy * size * 0.05),
                        (cx + sx * size * 1.9, cy + sy * size * 0.22)))
    paths.append(spiral(cx + sx * size * 2.05, cy + sy * size * 0.42, size * 0.22, size * 0.04, 0.85, -math.pi / 2 * sy,
                        ccw=sx * sy))
    paths.append(bezier((cx, cy), (cx - sx * size * 0.05, cy + sy * size * 0.9), (cx + sx * size * 0.05, cy + sy * size * 1.4),
                        (cx + sx * size * 0.22, cy + sy * size * 1.9)))
    paths.append(spiral(cx + sx * size * 0.42, cy + sy * size * 2.05, size * 0.22, size * 0.04, 0.85, math.pi if sx > 0 else 0,
                        ccw=-sx * sy))
    curls = stroke_height(w, h, paths, size * 0.16, 0.9 * S)
    bezel = dome(w, h, cx, cy, size * 0.62)
    ring = np.clip(bezel - dome(w, h, cx, cy, size * 0.46) * 1.1, 0, 1)
    gem_h, gem_m = faceted_gem(w, h, cx, cy, size * 0.44, sides=8, rot=math.pi / 8)
    metal_h = np.maximum(curls * 0.9, ring)
    metal_m = np.clip(curls * 1.6, 0, 1)
    metal_m = np.maximum(metal_m, (bezel > 0.02).astype(np.float32))
    return metal_h, metal_m, gem_h, gem_m, gem_colors(gem)


def panel_frame(name, w, h, border, *, crest=True, gem=(86, 150, 255), base=(13, 17, 26), radius=10, chamfer=0,
                inner_glow=(0.9, 0.75, 0.4), alpha_inside=0.94, bands=None, metal=GOLD, interior=True, shadow=True):
    """A nine-slice panel: a gold (or other metal) frame with a rounded or cut corner, corner crests, enamel inside."""
    W, H, B = w * S, h * S, border * S
    d = rect_dist(W, H, radius * S, chamfer * S)
    if bands is None:
        bands = [(0.0 * S, 1.2 * S, "flat"), (1.2 * S, 5.0 * S, "ridge"), (5.0 * S, 6.5 * S, "groove"),
                 (6.5 * S, 8.5 * S, "ridge")]
    hgt, mask = frame_profile(d, bands)
    wear = fbm(W, H, cell=10 * S, octaves=3, seed=11)
    hgt = hgt + (wear - 0.5) * 0.08 * mask
    inner = (d >= bands[-1][1]).astype(np.float32)
    base_rgb = enamel(W, H, base) * vignette(W, H, 0.35)[..., None] if interior else np.zeros((H, W, 3), np.float32)
    # inner shadow below the frame lip and a faint warm glow line just inside
    lip = bands[-1][1]
    ish = (1 - smoothstep(lip, lip + 9 * S, d)) * inner
    base_rgb = base_rgb * (1 - 0.55 * ish[..., None])
    glow = np.exp(-((d - lip - 1.2 * S) ** 2) / (2 * (0.9 * S) ** 2)) * inner
    base_rgb = base_rgb + glow[..., None] * np.array(inner_glow) * 0.18
    layers = [(hgt, mask, metal, 5.0 * S, 0.0)]
    rgb, alpha = shade_layers(base_rgb, layers)
    alpha = np.maximum(alpha, inner * alpha_inside) if interior else alpha
    if crest:
        cs = B * 0.42
        for fx, fy in ((False, False), (True, False), (False, True), (True, True)):
            cx = (B * 0.5) if not fx else W - B * 0.5
            cy = (B * 0.5) if not fy else H - B * 0.5
            mh, mm, gh, gm, gcap = corner_crest(W, H, cx, cy, cs, fx, fy, gem)
            rgb, a2 = shade_layers(rgb, [(mh, mm, metal, 6.0 * S, 0.5), (gh, gm, gcap, 3.0 * S, 0.0)])
            alpha = np.maximum(alpha, a2)
    if shadow:
        pass
    return save_rgba(name, rgb, alpha, [border, border, border, border])


def plain_frame(name, w, h, border, base=(12, 15, 22), metal=GOLD, radius=6, alpha_inside=0.95, glow=(0.95, 0.8, 0.45)):
    W, H = w * S, h * S
    d = rect_dist(W, H, radius * S)
    bands = [(0.0, 1.0 * S, "flat"), (1.0 * S, 3.2 * S, "ridge")]
    hgt, mask = frame_profile(d, bands)
    inner = (d >= 3.2 * S).astype(np.float32)
    base_rgb = enamel(W, H, base, pattern=False) * vignette(W, H, 0.25)[..., None]
    ish = (1 - smoothstep(3.2 * S, 10 * S, d)) * inner
    base_rgb = base_rgb * (1 - 0.45 * ish[..., None])
    gl = np.exp(-((d - 4.2 * S) ** 2) / (2 * (0.7 * S) ** 2)) * inner
    base_rgb = base_rgb + gl[..., None] * np.array(glow) * 0.12
    rgb, alpha = shade_layers(base_rgb, [(hgt, mask, metal, 4.0 * S, 0.0)])
    alpha = np.maximum(alpha, inner * alpha_inside)
    return save_rgba(name, rgb, alpha, [border, border, border, border])


def button(name, w, h, *, face, metal=GOLD, glow=0.0, pressed=False, disabled=False, radius=6, text_dark=False):
    """A bevelled button: a metal rim, a domed face (dark steel, gold, crimson), a light catch along the top."""
    W, H = w * S, h * S
    d = rect_dist(W, H, radius * S)
    rim_h, rim_m = frame_profile(d, [(0.0, 1.0 * S, "flat"), (1.0 * S, 3.6 * S, "ridge")])
    inner = smoothstep(3.4 * S, 4.4 * S, d)
    # the face: a soft pillow (higher in the middle), inverted when pressed
    pillow = smoothstep(3.6 * S, 16 * S, d)
    if pressed:
        pillow = 1 - pillow * 0.6
    face_cap = make_matcap(face, spec_pow=30, spec=0.55 if not disabled else 0.15)
    tex = fbm(W, H, cell=8 * S, octaves=2, seed=5) * 0.06
    base = np.zeros((H, W, 3), np.float32)
    rgb, alpha = shade_layers(base, [(pillow + tex, inner, face_cap, 1.4 * S, 0.0), (rim_h, rim_m, metal, 4.5 * S, 0.0)])
    if glow > 0:
        g = np.exp(-((d - 5 * S) ** 2) / (2 * (2.2 * S) ** 2)) * inner
        rgb = rgb + g[..., None] * np.array([1.0, 0.82, 0.45]) * glow
        top = (1 - smoothstep(0, H * 0.5, np.mgrid[0:H, 0:W][0].astype(np.float32))) * inner
        rgb = rgb + top[..., None] * 0.05 * glow
    if disabled:
        grey = rgb.mean(axis=2, keepdims=True)
        rgb = rgb * 0.25 + grey * 0.55
    return save_rgba(name, np.clip(rgb, 0, 1), alpha, [12, 12, 12, 12])


def slot_frame(name, w, h, *, metal=GOLD, inner_dark=0.9, radius=4, gem=None, notch=True):
    """An ability or item slot: a heavy bevelled rim with cut corners; the inside is clear (the icon shows through)."""
    W, H = w * S, h * S
    d = rect_dist(W, H, 0, chamfer=(7 * S if notch else 0))
    if radius and not notch:
        d = rect_dist(W, H, radius * S)
    hgt, mask = frame_profile(d, [(0.0, 1.0 * S, "flat"), (1.0 * S, 4.4 * S, "ridge"), (4.4 * S, 5.2 * S, "groove"),
                                  (5.2 * S, 6.6 * S, "ridge")])
    base = np.zeros((H, W, 3), np.float32)
    rgb, alpha = shade_layers(base, [(hgt, mask, metal, 5.0 * S, 0.0)])
    # inner shadow onto the icon: a dark gradient inside the rim
    inner = d >= 6.6 * S
    sh = (1 - smoothstep(6.6 * S, 15 * S, d)) * inner
    alpha = np.maximum(alpha, sh * inner_dark * 0.75)
    return save_rgba(name, rgb, alpha, [10, 10, 10, 10])


def bar_frame(name, w, h, metal=GOLD):
    W, H = w * S, h * S
    d = rect_dist(W, H, 3 * S)
    hgt, mask = frame_profile(d, [(0.0, 0.8 * S, "flat"), (0.8 * S, 2.8 * S, "ridge")])
    inner = (d >= 2.8 * S).astype(np.float32)
    base = np.zeros((H, W, 3), np.float32) + np.array([0.02, 0.022, 0.03])
    rgb, alpha = shade_layers(base, [(hgt, mask, metal, 3.5 * S, 0.0)])
    alpha = np.maximum(alpha, inner * 0.96)
    return save_rgba(name, rgb, alpha, [6, 6, 6, 6])


def bar_fill(name, w, h, top, mid, bot, pattern="hp"):
    """A bar's fill (tiles along x): a glossy tube in the colour, a fine pattern, a bright line along the top."""
    W, H = w * S, h * S
    y = (np.mgrid[0:H, 0:W][0].astype(np.float32) + 0.5) / H
    pos = [0.0, 0.18, 0.55, 1.0]
    cols = np.array([top, top, mid, bot], np.float32) / 255.0
    rgb = np.dstack([np.interp(y, pos, cols[:, c]) for c in range(3)])
    gloss = np.exp(-((y - 0.22) ** 2) / (2 * 0.06 ** 2)) * 0.35
    rgb = rgb + gloss[..., None]
    x = np.mgrid[0:H, 0:W][1].astype(np.float32)
    if pattern == "hp":
        stripe = (np.abs(((x + y * H * 0.6) % (10 * S)) - 5 * S) < 0.8 * S).astype(np.float32)
        rgb = rgb * (1 - stripe[..., None] * 0.08)
    else:
        sparkle = fbm(W, H, cell=5 * S, octaves=2, seed=21)
        rgb = rgb * (0.92 + 0.16 * sparkle[..., None])
    rgb = rgb * (0.82 + 0.18 * (1 - np.abs(y - 0.45) * 1.6))[..., None]
    alpha = np.ones((H, W), np.float32)
    return save_rgba(name, np.clip(rgb, 0, 1), alpha, None, kind="tile")


def divider(name, w, h, metal=GOLD, gem=(232, 180, 90)):
    """A horizontal ornament line: a fine double rule with a diamond and two scrolls in the middle."""
    W, H = w * S, h * S
    cy = H / 2
    cx = W / 2
    rule = stroke_height(W, H, [[(6 * S, cy), (cx - 26 * S, cy)], [(cx + 26 * S, cy), (W - 6 * S, cy)]], 1.6 * S, 0.5 * S)
    fade = np.clip(1 - np.abs((np.mgrid[0:H, 0:W][1] + 0.5) - cx) / (W / 2), 0, 1) ** 0.6
    rule = rule * fade
    curls = stroke_height(W, H, [spiral(cx - 16 * S, cy, 7 * S, 1.5 * S, 0.9, 0, -1), spiral(cx + 16 * S, cy, 7 * S, 1.5 * S, 0.9, math.pi, -1)],
                          2.0 * S, 0.5 * S)
    gh, gm = faceted_gem(W, H, cx, cy, 6.5 * S, sides=4, rot=0)
    base = np.zeros((H, W, 3), np.float32)
    rgb, alpha = shade_layers(base, [(np.maximum(rule, curls), np.clip((rule + curls) * 1.5, 0, 1), metal, 3 * S, 0.0),
                                     (gh, gm, gem_colors(gem), 2.5 * S, 0.0)])
    return save_rgba(name, rgb, alpha, None, kind="image")


def ring_frame(name, size, thick, metal=GOLD, gem=None, spikes=0):
    """A round frame (level badge, portrait rim, minimap pins): a domed metal ring with optional studs."""
    W = H = size * S
    c = W / 2
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt((x + 0.5 - c) ** 2 + (y + 0.5 - c) ** 2)
    outer = c - 1.0 * S
    inner = outer - thick * S
    t = np.clip((r - inner) / (outer - inner), 0, 1)
    hgt = np.sin(t * math.pi) * ((r >= inner) & (r <= outer))
    mask = smoothstep(inner - 0.8, inner + 0.8, r) * (1 - smoothstep(outer - 0.8, outer + 0.8, r))
    layers = [(hgt, mask, metal, 5 * S, 0.0)]
    if spikes:
        for k in range(spikes):
            a = k * 2 * math.pi / spikes - math.pi / 2
            sx = c + math.cos(a) * (outer - thick * S * 0.5)
            sy = c + math.sin(a) * (outer - thick * S * 0.5)
            st = dome(W, H, sx, sy, thick * S * 0.7)
            layers.append((st, (st > 0.02).astype(np.float32), metal, 4 * S, 0.3))
    base = np.zeros((H, W, 3), np.float32)
    rgb, alpha = shade_layers(base, layers)
    return save_rgba(name, rgb, alpha, None, kind="image")


def gem_icon(name, size, color, sides=8):
    W = H = size * S
    gh, gm = faceted_gem(W, H, W / 2, H / 2, W * 0.42, sides=sides, rot=math.pi / sides)
    bez = dome(W, H, W / 2, H / 2, W * 0.49)
    ring = np.clip(bez - dome(W, H, W / 2, H / 2, W * 0.42) * 1.15, 0, 1)
    base = np.zeros((H, W, 3), np.float32)
    rgb, alpha = shade_layers(base, [(ring, (bez > 0.02).astype(np.float32), GOLD, 4 * S, 0.3),
                                     (gh, gm, gem_colors(color), 3 * S, 0.0)])
    return save_rgba(name, rgb, alpha, None, kind="image")


def ribbon(name, w, h, color=(120, 18, 22)):
    """A title banner: cloth with folded tails and a gold edge (nine-slice in x)."""
    W, H = w * S, h * S
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    tail = 22 * S
    # the cloth shape: a band with swallow-tail cuts at both ends
    cut = np.minimum(x, W - x)
    notch = np.abs(y - H / 2) / (H / 2) * (tail * 0.6)
    inside = (cut > notch) & (y > 2 * S) & (y < H - 2 * S)
    m = blur(inside.astype(np.float32), 0.6)
    folds = fbm(W, H, cell=30 * S, octaves=3, seed=31)
    hgt = 0.6 + 0.25 * np.sin(y / H * math.pi) + (folds - 0.5) * 0.2
    cloth = make_matcap([(0.0, tuple(np.array(color) * 0.25)), (0.5, tuple(np.array(color) * 0.75)),
                         (0.85, tuple(np.clip(np.array(color) * 1.25, 0, 255))), (1.0, tuple(np.clip(np.array(color) * 1.6 + 30, 0, 255)))],
                        spec_pow=12, spec=0.25)
    edge = (m > 0.1) & ((y < 5 * S) | (y > H - 5 * S))
    em = blur(edge.astype(np.float32), 0.5) * m
    eh = np.sin(np.clip(np.minimum(y - 2 * S, H - 2 * S - y) / (3 * S), 0, 1) * math.pi)
    base = np.zeros((H, W, 3), np.float32)
    rgb, alpha = shade_layers(base, [(hgt, m, cloth, 1.0 * S, 0.0), (eh, em, GOLD, 3 * S, 0.0)])
    return save_rgba(name, rgb, alpha, [tail // S + 6, 0, tail // S + 6, 0])


def glow_dot(name, size, color):
    W = H = size * S
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    r = np.sqrt((x + 0.5 - W / 2) ** 2 + (y + 0.5 - H / 2) ** 2) / (W / 2)
    a = np.clip(1 - r, 0, 1) ** 2.2
    rgb = np.zeros((H, W, 3), np.float32) + np.array(color, np.float32) / 255.0
    return save_rgba(name, rgb, a, None, kind="image")


def backdrop(name, w, h, base=(9, 12, 19)):
    """A large dark backdrop for menu panels: enamel, a deep vignette, faint smoke."""
    W, H = w * S // 2, h * S // 2                   # backdrops are soft: half resolution is plenty
    rgb = enamel(W, H, base, seed=41, pattern=False)
    smoke = fbm(W, H, cell=160, octaves=5, seed=43)
    rgb = rgb + (smoke[..., None] - 0.5) * np.array([0.05, 0.06, 0.09])
    rgb = rgb * vignette(W, H, 0.55, 1.6)[..., None]
    return save_rgba(name, rgb, np.ones((H, W), np.float32), None, kind="image")



# ---- v2: ornate panels, bespoke HUD pieces, the title -------------------------------------------------------------

FRAME_BANDS = [(0.0, 1.2, "flat"), (1.2, 5.0, "ridge"), (5.0, 6.5, "groove"), (6.5, 8.5, "ridge")]


def bands_px(bands):
    return [(a * S, b * S, k) for a, b, k in bands]


def ornate_panel(name, w, h, border, *, gem=(90, 150, 255), base=(13, 17, 26), radius=10, corner=26, crest_size=0,
                 metal=None, alpha_inside=0.95, bands=None, crest_gem=(255, 196, 90)):
    """A nine-slice panel with filigree corners (scrolls, leaves, a gem on a diamond plate) and, for wide panels, a
    crest in the middle of the top edge (drawn separately: see crest_piece)."""
    metal = GOLD if metal is None else metal
    W, H = w * S, h * S
    d = rect_dist(W, H, radius * S)
    bp = bands_px(bands or FRAME_BANDS)
    hgt, mask = frame_profile(d, bp)
    wear = fbm(W, H, cell=10 * S, octaves=3, seed=11)
    hgt = hgt + (wear - 0.5) * 0.08 * mask
    lip = bp[-1][1]
    inner = (d >= lip).astype(np.float32)
    base_rgb = enamel(W, H, base) * vignette(W, H, 0.3)[..., None]
    ish = (1 - smoothstep(lip, lip + 10 * S, d)) * inner
    base_rgb = base_rgb * (1 - 0.6 * ish[..., None])
    glow = np.exp(-((d - lip - 1.2 * S) ** 2) / (2 * (0.9 * S) ** 2)) * inner
    base_rgb = base_rgb + glow[..., None] * np.array([0.95, 0.78, 0.42]) * 0.16
    rgb, alpha = shade_layers(base_rgb, [(hgt, mask, metal, 5.0 * S, 0.0)])
    alpha = np.maximum(alpha, inner * alpha_inside)
    if corner > 0:
        cs = corner * S
        for fx, fy, ox, oy in ((1, 1, lip, lip), (-1, 1, W - lip, lip), (1, -1, lip, H - lip), (-1, -1, W - lip, H - lip)):
            mh, mm, gc = O.filigree_corner(W, H, (ox, oy), cs, fx, fy)
            gh, gm = O.faceted_gem(W, H, gc[0], gc[1], cs * 0.24, 8, math.pi / 8)
            rgb, a2 = shade_layers(rgb, [(mh, mm, metal, 7.0 * S, 0.55), (gh, gm, gem_colors(gem), 3.0 * S, 0.0)])
            alpha = np.maximum(alpha, a2)
    # the drawn margin must hold the whole corner ornament (else the nine-slice stretches it); content sits at `border`
    m = max(border, int(math.ceil(corner * 2.6 + (bp[-1][1] / S))) if corner > 0 else border)
    return save_rgba(name, rgb, alpha, [m, m, m, m], extra={"content": [border, border, border, border]})


def crest_piece(name, w, h, size, gem=(255, 196, 90), down=True):
    """The top-centre crest as its own image (drawn over a panel's top edge)."""
    W, H = w * S, h * S
    ch, cm, cc = O.crest(W, H, W / 2, (H * 0.32) if down else (H * 0.68), size * S, down)
    gh, gm = O.faceted_gem(W, H, cc[0], cc[1], size * S * 0.26, 6, 0)
    base = np.zeros((H, W, 3), np.float32)
    rgb, alpha = shade_layers(base, [(ch, cm, GOLD, 7 * S, 0.5), (gh, gm, gem_colors(gem), 3 * S, 0.0)])
    return save_rgba(name, rgb, alpha, None, kind="image")


def corner_piece(name, size, gem=(90, 150, 255)):
    """One filigree corner as its own image (top-left orientation; flip for the others)."""
    W = H = int(size * 2.4) * S
    mh, mm, gc = O.filigree_corner(W, H, (2 * S, 2 * S), size * S, 1, 1)
    gh, gm = O.faceted_gem(W, H, gc[0], gc[1], size * S * 0.24, 8, math.pi / 8)
    base = np.zeros((H, W, 3), np.float32)
    rgb, alpha = shade_layers(base, [(mh, mm, GOLD, 7.0 * S, 0.55), (gh, gm, gem_colors(gem), 3.0 * S, 0.0)])
    return save_rgba(name, rgb, alpha, None, kind="image")


def logo(name, line1="WARRIORS", line2="OF AETHER"):
    """The game's title: chiselled gold capitals on a dark bevelled backing, with a soft golden glow."""
    font = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "fonts", "Cinzel.ttf")
    m1 = O.embossed_text(line1, font, 168, 900, 48, 10)
    m2 = O.embossed_text(line2, font, 84, 800, 30, 26)
    w = max(m1.shape[1], m2.shape[1]) + 40
    h = m1.shape[0] + m2.shape[0] - 70
    m = np.zeros((h, w), np.float32)
    x1 = (w - m1.shape[1]) // 2
    m[0:m1.shape[0], x1:x1 + m1.shape[1]] = np.maximum(m[0:m1.shape[0], x1:x1 + m1.shape[1]], m1)
    x2 = (w - m2.shape[1]) // 2
    y2 = m1.shape[0] - 70
    m[y2:y2 + m2.shape[0], x2:x2 + m2.shape[1]] = np.maximum(m[y2:y2 + m2.shape[0], x2:x2 + m2.shape[1]], m2)
    # a rule with a gem between the lines
    cy = y2 + 22
    rule = O.taper_stroke(w, h, [(w * 0.18, cy), (w * 0.82, cy)], 4, 4, soft=1.0)[0]
    gh, gm = O.faceted_gem(w, h, w / 2, cy, 15, 4, 0)
    d = O.inside_distance(m)
    letters = np.clip(d / 7.0, 0, 1) ** 0.75
    yy = np.mgrid[0:h, 0:w][0].astype(np.float32) / h
    backing = np.clip(ndimage.gaussian_filter(ndimage.maximum_filter(m, 15), 2.0) * 1.2, 0, 1)
    bh = np.clip(O.inside_distance(backing > 0.5) / 5.0, 0, 1)
    base = np.zeros((h, w, 3), np.float32)
    rgb, alpha = shade_layers(base, [(bh * 0.6, backing, DARKMETAL, 3.0, 0.0),
                                     (letters, np.clip(m * 1.15, 0, 1), GOLD, 10.0, 0.0),
                                     (rule, np.clip(rule * 1.5, 0, 1), GOLD, 3.0, 0.0),
                                     (gh, gm, gem_colors((255, 70, 50)), 3.0, 0.0)])
    # brighter top, deeper bottom on the letters
    rgb = rgb * (1.12 - 0.28 * yy)[..., None]
    glow = ndimage.gaussian_filter(m, 22) * 0.75
    alpha = np.maximum(alpha, glow * 0.55)
    rgb = rgb + (1 - np.clip(m + backing, 0, 1))[..., None] * glow[..., None] * np.array([1.0, 0.7, 0.3]) * 0.6
    img = save_rgba(name, np.clip(rgb, 0, 1), alpha, None, kind="image")
    MANIFEST[name]["size"] = [img.width // 2, img.height // 2]   # drawn at half its pixel size (crisp at 4K)
    return img


def button2(name, w, h, *, face, glow=0.0, pressed=False, disabled=False, metal=None, notch=6):
    """A button with a cut-corner gold rim, a pillowed face with a brushed grain, a light catch along the top edge."""
    metal = GOLD if metal is None else metal
    W, H = w * S, h * S
    d = rect_dist(W, H, 0, chamfer=notch * S)
    rim_h, rim_m = frame_profile(d, [(0.0, 0.9 * S, "flat"), (0.9 * S, 3.4 * S, "ridge"), (3.4 * S, 4.2 * S, "groove"),
                                     (4.2 * S, 5.0 * S, "ridge")])
    inner = smoothstep(4.8 * S, 5.6 * S, d)
    pillow = smoothstep(5.0 * S, 18 * S, d)
    if pressed:
        pillow = 1 - pillow * 0.5
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    brushed = value_noise(W, H, 3, 77)
    brushed = ndimage.gaussian_filter1d(brushed, 12, axis=1) * 0.12
    face_cap = make_matcap(face, spec_pow=26, spec=0.6 if not disabled else 0.1)
    base = np.zeros((H, W, 3), np.float32)
    rgb, alpha = shade_layers(base, [(pillow + brushed, inner, face_cap, 1.5 * S, 0.0), (rim_h, rim_m, metal, 4.5 * S, 0.0)])
    top = (1 - smoothstep(5 * S, H * 0.55, y)) * inner
    rgb = rgb + top[..., None] * 0.06
    bot = smoothstep(H * 0.55, H - 5 * S, y) * inner
    rgb = rgb * (1 - bot[..., None] * 0.25)
    if glow > 0:
        g = np.exp(-((d - 6.5 * S) ** 2) / (2 * (2.6 * S) ** 2)) * inner
        rgb = rgb + g[..., None] * np.array([1.0, 0.8, 0.42]) * 0.55 * glow
    if disabled:
        grey = rgb.mean(axis=2, keepdims=True)
        rgb = rgb * 0.2 + grey * 0.5
    return save_rgba(name, np.clip(rgb, 0, 1), alpha, [14, 14, 14, 14])


def tab_piece(name, w, h, active):
    """A tab: active tabs are raised gold-trimmed plates open at the bottom, inactive ones dark and flat."""
    W, H = w * S, h * S
    m = O.mask_from_poly(W, H, [[(4 * S, H), (4 * S, 8 * S), (12 * S, 1 * S), (W - 12 * S, 1 * S), (W - 4 * S, 8 * S), (W - 4 * S, H)]])
    d = O.inside_distance(m)
    hgt, mask = frame_profile(d, [(0.0, 0.8 * S, "flat"), (0.8 * S, 3.0 * S, "ridge")])
    # no rim along the bottom edge (it opens into the page)
    y = np.mgrid[0:H, 0:W][0].astype(np.float32)
    open_bottom = smoothstep(H - 4 * S, H - 1 * S, y)
    mask = mask * (1 - open_bottom)
    inner = (d >= 3.0 * S).astype(np.float32) * m
    face = enamel(W, H, (24, 28, 40) if active else (10, 12, 17), pattern=False)
    if active:
        face = face + (1 - smoothstep(0, H, y))[..., None] * np.array([0.12, 0.09, 0.03])
    rgb, alpha = shade_layers(face, [(hgt, mask, GOLD if active else DARKMETAL, 4 * S, 0.0)])
    alpha = np.maximum(alpha, inner * (0.97 if active else 0.85))
    return save_rgba(name, rgb, alpha, [14, 12, 14, 4])


def slider_parts():
    W, H = 64 * S, 14 * S
    d = rect_dist(W, H, 6 * S)
    hgt, mask = frame_profile(d, [(0.0, 0.8 * S, "flat"), (0.8 * S, 2.6 * S, "ridge")])
    inner = (d >= 2.6 * S).astype(np.float32)
    base = np.zeros((H, W, 3), np.float32) + np.array([0.015, 0.017, 0.024])
    ish = (1 - smoothstep(2.6 * S, 7 * S, d)) * inner
    base = base * (1 - ish[..., None] * 0.5)
    rgb, alpha = shade_layers(base, [(hgt, mask, GOLD, 3 * S, 0.0)])
    alpha = np.maximum(alpha, inner)
    save_rgba("slider_track", rgb, alpha, [8, 6, 8, 6])
    bar_fill("slider_fill", 64, 14, (255, 226, 150), (214, 156, 54), (110, 66, 14), pattern="mana")
    gem_icon("slider_grabber", 26, (255, 196, 90), sides=8)
    gem_icon("slider_grabber_hover", 26, (255, 236, 160), sides=8)


def check_parts():
    for nm, on in (("check_off", False), ("check_on", True)):
        W = H = 28 * S
        d = rect_dist(W, H, 0, chamfer=5 * S)
        hgt, mask = frame_profile(d, [(0.0, 0.8 * S, "flat"), (0.8 * S, 3.2 * S, "ridge")])
        inner = (d >= 3.2 * S).astype(np.float32)
        base = np.zeros((H, W, 3), np.float32) + np.array([0.02, 0.022, 0.03])
        layers = [(hgt, mask, GOLD, 3.5 * S, 0.0)]
        if on:
            gh, gm = O.faceted_gem(W, H, W / 2, H / 2, 8.5 * S, 4, 0)
            layers.append((gh, gm, gem_colors((255, 200, 90)), 2.5 * S, 0.0))
        rgb, alpha = shade_layers(base, layers)
        alpha = np.maximum(alpha, inner * 0.95)
        save_rgba(nm, rgb, alpha, None, kind="image")


def field_parts():
    """A text field: a dark inset with a fine gold hairline; and its focused look (brighter, a soft inner glow)."""
    for nm, focus in (("field", False), ("field_focus", True)):
        W, H = 64 * S, 36 * S
        d = rect_dist(W, H, 4 * S)
        hgt, mask = frame_profile(d, [(0.0, 0.7 * S, "flat"), (0.7 * S, 2.2 * S, "ridge")])
        inner = (d >= 2.2 * S).astype(np.float32)
        base = enamel(W, H, (6, 8, 12), pattern=False)
        ish = (1 - smoothstep(2.2 * S, 9 * S, d)) * inner
        base = base * (1 - ish[..., None] * 0.6)
        if focus:
            g = np.exp(-((d - 3.2 * S) ** 2) / (2 * (1.6 * S) ** 2)) * inner
            base = base + g[..., None] * np.array([1.0, 0.8, 0.4]) * 0.25
        rgb, alpha = shade_layers(base, [(hgt, mask, GOLD if focus else BRONZE, 3 * S, 0.0)])
        alpha = np.maximum(alpha, inner * 0.97)
        save_rgba(nm, rgb, alpha, [8, 8, 8, 8])


def scroll_parts():
    W, H = 12 * S, 48 * S
    d = rect_dist(W, H, 6 * S)
    hgt, mask = frame_profile(d, [(0.0, 0.7 * S, "flat"), (0.7 * S, 6 * S, "ridge")])
    rgb, alpha = shade_layers(np.zeros((H, W, 3), np.float32), [(hgt, mask, GOLD, 3 * S, 0.0)])
    save_rgba("scroll_grabber", rgb, alpha, [6, 8, 6, 8])
    hgt2, mask2 = frame_profile(d, [(0.0, 0.7 * S, "flat"), (0.7 * S, 2.0 * S, "ridge")])
    inner = (d >= 2 * S).astype(np.float32)
    base = np.zeros((H, W, 3), np.float32) + 0.02
    rgb, alpha = shade_layers(base, [(hgt2, mask2, DARKMETAL, 3 * S, 0.0)])
    save_rgba("scroll_track", rgb, np.maximum(alpha, inner * 0.8), [6, 8, 6, 8])


# ---- bespoke HUD pieces ------------------------------------------------------------------------------------------

def _carve(rgb, alpha, rect, depth=0.62, metal=None, base=(8, 10, 15)):
    """A recessed inner panel (a darker well with a thin bevelled lip) cut into a larger piece. rect in drawn units."""
    metal = BRONZE if metal is None else metal
    x0, y0, x1, y1 = [int(v * S) for v in rect]
    Hh, Ww = alpha.shape
    m = np.zeros((Hh, Ww), np.float32)
    m[y0:y1, x0:x1] = 1.0
    d = O.inside_distance(m)
    hgt, mask = frame_profile(d, [(0.0, 0.8 * S, "flat"), (0.8 * S, 2.4 * S, "ridge")])
    inner = (d >= 2.4 * S).astype(np.float32)
    well = enamel(Ww, Hh, base, seed=y0 + x0, pattern=False)
    ish = (1 - smoothstep(2.4 * S, 12 * S, d)) * inner
    well = well * (1 - ish[..., None] * depth)
    rgb = rgb * (1 - inner[..., None]) + well * inner[..., None]
    rgb, a2 = shade_layers(rgb, [(hgt, mask, metal, 3.5 * S, 0.0)])
    return rgb, np.maximum(alpha, a2)


def _socket(rgb, alpha, rect, chamfer=6):
    """A dark socket for a slot frame to sit in (the frame itself is drawn by the game, lit or not)."""
    x0, y0, x1, y1 = rect
    m = O.mask_from_rects(alpha.shape[1], alpha.shape[0], [(x0 * S - 3 * S, y0 * S - 3 * S, x1 * S + 3 * S, y1 * S + 3 * S)],
                          chamfer * S)
    d = O.inside_distance(m)
    sh = (1 - smoothstep(0, 7 * S, d)) * m
    rgb = rgb * (1 - m[..., None] * 0.55) * (1 - sh[..., None] * 0.35)
    return rgb, alpha


def console_layout(n):
    """The ability row for n skill slots (matches BottomPanel in src/ui/hud.gd): step between slots, slot size and
    how much wider than the four-slot console it is."""
    n = max(4, min(10, n))
    step = {7: 72, 8: 66, 9: 62, 10: 58}.get(n, 80)
    return step, step - 8, n * step - 320


def console(name="hud_console", n=4):
    """The bottom HUD: a sculpted gold-framed console. Sections (drawn units, four skills): portrait 0-188, stats
    188-372, abilities 372-726 (raised), items 726-978, gold / shop 978-1140; height 206. With more skills the ability
    section widens by dx and everything right of it moves along (hud_console_<n>)."""
    step, size, dx = console_layout(n)
    w, h = 1140 + dx, 206
    W, H = w * S, h * S
    m = O.mask_from_rects(W, H, [(0, 22 * S, W, H + 20 * S)], 16 * S)
    m = np.maximum(m, O.mask_from_poly(W, H, [[(370 * S, 22 * S), (394 * S, 2 * S), ((732 + dx) * S, 2 * S),
                                               ((756 + dx) * S, 22 * S), ((756 + dx) * S, 60 * S), (370 * S, 60 * S)]]))
    m = np.maximum(m, O.mask_from_rects(W, H, [(2 * S, 6 * S, 190 * S, H + 20 * S)], 12 * S))
    m = np.maximum(m, O.mask_from_rects(W, H, [((974 + dx) * S, 12 * S, W - 2 * S, H + 20 * S)], 12 * S))
    d = O.inside_distance(m)
    bp = bands_px([(0.0, 1.4, "flat"), (1.4, 6.0, "ridge"), (6.0, 7.6, "groove"), (7.6, 10.0, "ridge")])
    hgt, mask = frame_profile(d, bp)
    hgt = hgt + (fbm(W, H, cell=12 * S, octaves=3, seed=5) - 0.5) * 0.08 * mask
    lip = bp[-1][1]
    inner = (d >= lip).astype(np.float32)
    base = enamel(W, H, (12, 16, 25), seed=9) * vignette(W, H, 0.25)[..., None]
    ish = (1 - smoothstep(lip, lip + 12 * S, d)) * inner
    base = base * (1 - 0.55 * ish[..., None])
    rgb, alpha = shade_layers(base, [(hgt, mask, GOLD, 5 * S, 0.0)])
    alpha = np.maximum(alpha, inner * 0.97)
    # wells for each section
    rgb, alpha = _carve(rgb, alpha, (192, 34, 364, 198))                  # stats
    rgb, alpha = _carve(rgb, alpha, (396, 124, 730 + dx, 194))            # health and mana
    rgb, alpha = _carve(rgb, alpha, (728 + dx, 26, 972 + dx, 198))        # items
    rgb, alpha = _carve(rgb, alpha, (980 + dx, 30, 1132 + dx, 198))       # gold, Teleport, courier, shop
    # sockets for the ability slots, each with a carved tray under it for the level pips
    for i in range(max(4, n)):
        x = 404 + i * step
        rgb, alpha = _socket(rgb, alpha, (x, 102 - size, x + size, 102))
        rgb, alpha = _carve(rgb, alpha, (x + 2, 107, x + size - 2, 121), depth=0.8, base=(4, 5, 8))
    # sockets for the item slots
    for i in range(6):
        x = 734 + dx + (i % 3) * 80
        y = 30 + (i // 3) * 62
        rgb, alpha = _socket(rgb, alpha, (x, y, x + 74, y + 56), 3)
    for i in range(3):
        x = 734 + dx + i * 80
        rgb, alpha = _socket(rgb, alpha, (x, 158, x + 74, 194), 3)
    # ornaments: filigree on the raised centre's shoulders, a crest above the abilities, gems at the joints
    layers = []
    for fx, ox in ((1, 404 * S), (-1, (722 + dx) * S)):
        mh, mm, gc = O.filigree_corner(W, H, (ox, 12 * S), 18 * S, fx, 1)
        layers.append((mh * 0.9, mm * (1 - smoothstep(94 * S, 102 * S, np.mgrid[0:H, 0:W][0])), GOLD, 7 * S, 0.5))
    ch, cm, cc = O.crest(W, H, (563 + dx / 2) * S, 5 * S, 20 * S, True)
    layers.append((ch, cm, GOLD, 7 * S, 0.5))
    gh, gm = O.faceted_gem(W, H, cc[0], cc[1], 6 * S, 6, 0)
    layers.append((gh, gm, gem_colors((255, 190, 80)), 3 * S, 0.0))
    for gx, gy in ((188, 30), (974 + dx, 26), (370, 30), (756 + dx, 30)):
        bh, bm = O.beads(W, H, [(gx * S, gy * S)], 5 * S)
        layers.append((bh, bm, GOLD, 4 * S, 0.4))
        g2, g2m = O.faceted_gem(W, H, gx * S, gy * S, 3.6 * S, 8, math.pi / 8)
        layers.append((g2, g2m, gem_colors((90, 150, 255)), 2 * S, 0.0))
    rgb, a2 = shade_layers(rgb, layers)
    alpha = np.maximum(alpha, a2)
    return save_rgba(name, rgb, alpha, None, kind="image")


def minimap_frame(name="hud_minimap", s=272, pad=14):
    """The minimap's frame: a heavy gold rim with filigree corners and a socket at the top right for Fortify."""
    w = h = s + pad * 2
    W, H = w * S, h * S
    outer = O.mask_from_rects(W, H, [(0, 0, W, H)], 14 * S)
    d = O.inside_distance(outer)
    bp = bands_px([(0.0, 1.4, "flat"), (1.4, 6.0, "ridge"), (6.0, 7.4, "groove"), (7.4, 10.0, "ridge"), (10.0, 14.0, "flat")])
    hgt, mask = frame_profile(d, bp)
    hole = (d >= pad * S).astype(np.float32)
    rgb, alpha = shade_layers(enamel(W, H, (12, 16, 25)), [(hgt, mask, GOLD, 5 * S, 0.0)])
    alpha = alpha * (1 - hole)
    # inner shadow cast onto the map
    ish = (1 - smoothstep(pad * S, pad * S + 10 * S, d)) * hole
    alpha = np.maximum(alpha, ish * 0.6)
    rgb = rgb * (1 - hole[..., None])
    layers = []
    for fx, fy, ox, oy in ((1, 1, pad * S, pad * S), (1, -1, pad * S, H - pad * S), (-1, -1, W - pad * S, H - pad * S)):
        mh, mm, gc = O.filigree_corner(W, H, (ox, oy), 22 * S, fx, fy)
        layers.append((mh, mm, GOLD, 7 * S, 0.55))
        gh, gm = O.faceted_gem(W, H, gc[0], gc[1], 5 * S, 8, math.pi / 8)
        layers.append((gh, gm, gem_colors((90, 150, 255)), 3 * S, 0.0))
    rgb, a2 = shade_layers(rgb, layers)
    alpha = np.maximum(alpha, a2)
    return save_rgba(name, rgb, alpha, None, kind="image", extra={"inner": [pad, pad, s, s]})


def topbar_art(name="hud_topbar", w=1200, h=80):
    """The top bar (drawn units): a central medallion for the clock (510-690), score plaques either side (420-510,
    690-780) and two wings of five hero sockets (64 x 44 each, 70 apart: left from x 346 down to 66, right from 784)."""
    W, H = w * S, h * S
    cx = W / 2
    wing = O.mask_from_rects(W, H, [(56 * S, 0, 424 * S, 56 * S), (776 * S, 0, 1144 * S, 56 * S)], 10 * S)
    plaques = O.mask_from_rects(W, H, [(412 * S, 0, 528 * S, 60 * S), (672 * S, 0, 788 * S, 60 * S)], 9 * S)
    med = O.mask_from_poly(W, H, [[(cx - 94 * S, 0), (cx + 94 * S, 0), (cx + 82 * S, 54 * S), (cx + 38 * S, 76 * S),
                                   (cx - 38 * S, 76 * S), (cx - 82 * S, 54 * S)]])
    rgb = enamel(W, H, (12, 16, 25), seed=21)
    alpha = np.zeros((H, W), np.float32)
    for m, metal, bands in ((wing, BRONZE, [(0.0, 1.0, "flat"), (1.0, 4.0, "ridge")]),
                            (plaques, GOLD, [(0.0, 1.0, "flat"), (1.0, 4.4, "ridge"), (4.4, 5.4, "groove"), (5.4, 7.0, "ridge")]),
                            (med, GOLD, [(0.0, 1.2, "flat"), (1.2, 5.6, "ridge"), (5.6, 7.0, "groove"), (7.0, 9.2, "ridge")])):
        d = O.inside_distance(m)
        bp = bands_px(bands)
        hgt, mask = frame_profile(d, bp)
        inner = (d >= bp[-1][1]).astype(np.float32)
        fill = enamel(W, H, (13, 17, 26), seed=int(m.sum()) % 97)
        ish = (1 - smoothstep(bp[-1][1], bp[-1][1] + 10 * S, d)) * inner
        fill = fill * (1 - ish[..., None] * 0.55)
        rgb = rgb * (1 - inner[..., None]) + fill * inner[..., None]
        rgb, a2 = shade_layers(rgb, [(hgt, mask, metal, 5 * S, 0.0)])
        alpha = np.maximum(alpha, np.maximum(a2, inner * 0.96))
    for i in range(5):
        for x in (346 - i * 70, 784 + i * 70):
            rgb, alpha = _socket(rgb, alpha, (x, 4, x + 64, 48), 3)
    layers = []
    ch, cm, cc = O.crest(W, H, cx, 70 * S, 16 * S, False)
    layers += [(ch, cm, GOLD, 7 * S, 0.5)]
    gh, gm = O.faceted_gem(W, H, cc[0], cc[1], 4.5 * S, 6, 0)
    layers += [(gh, gm, gem_colors((255, 190, 80)), 3 * S, 0.0)]
    for gx, col in ((470, (90, 150, 255)), (730, (255, 70, 60))):
        g2, g2m = O.faceted_gem(W, H, gx * S, 50 * S, 4 * S, 8, math.pi / 8)
        layers += [(g2, g2m, gem_colors(col), 2 * S, 0.0)]
    rgb, a2 = shade_layers(rgb, layers)
    alpha = np.maximum(alpha, a2)
    return save_rgba(name, rgb, alpha, None, kind="image")


def hero_card(name, w=150, h=196):
    """The frame of a hero's card on Hero Select and in the lobby: a tall gold frame with a name plate at the foot."""
    W, H = w * S, h * S
    d = rect_dist(W, H, 0, chamfer=10 * S)
    bp = bands_px([(0.0, 1.0, "flat"), (1.0, 4.4, "ridge"), (4.4, 5.4, "groove"), (5.4, 7.0, "ridge")])
    hgt, mask = frame_profile(d, bp)
    y = np.mgrid[0:H, 0:W][0].astype(np.float32)
    plate_m = O.mask_from_rects(W, H, [(6 * S, H - 40 * S, W - 6 * S, H - 6 * S)], 6 * S)
    pd = O.inside_distance(plate_m)
    ph, pm = frame_profile(pd, bands_px([(0.0, 0.8, "flat"), (0.8, 2.6, "ridge")]))
    plate_in = (pd >= 2.6 * S).astype(np.float32)
    base = np.zeros((H, W, 3), np.float32)
    plate_rgb = enamel(W, H, (10, 12, 18), pattern=False)
    rgb = base * (1 - plate_in[..., None]) + plate_rgb * plate_in[..., None]
    rgb, alpha = shade_layers(rgb, [(hgt, mask, GOLD, 4.5 * S, 0.0), (ph, pm, GOLD, 3.5 * S, 0.0)])
    alpha = np.maximum(alpha, plate_in * 0.94)
    # a soft dark fade over the portrait above the plate (the name reads over it)
    fade = smoothstep(H - 80 * S, H - 40 * S, y) * (d > 7 * S) * (1 - plate_in)
    alpha = np.maximum(alpha, fade * 0.7)
    return save_rgba(name, rgb, alpha, None, kind="image")


# ---- v3: the Main Menu (run 2026-10-15 g) ---------------------------------------------------------------------------


def menu_plate(name, w, h, *, face, glow=0.0, pressed=False, metal=None):
    """A menu entry: a long blade-shaped plate. A round socket on the left holds the entry's icon, the right end comes
    to a chevron point like a sword tip; a gold rim runs round it, the face is brushed metal. Nine-slice in x."""
    metal = GOLD if metal is None else metal
    W, H = w * S, h * S
    tip = H * 0.42
    cut = 7 * S
    poly = [(cut, 2 * S), (W - tip, 2 * S), (W - 2 * S, H / 2), (W - tip, H - 2 * S), (cut, H - 2 * S), (2 * S, H - cut),
            (2 * S, cut)]
    m = O.mask_from_poly(W, H, [poly])
    d = O.inside_distance(m)
    rim_h, rim_m = frame_profile(d, [(0.0, 0.9 * S, "flat"), (0.9 * S, 3.2 * S, "ridge"), (3.2 * S, 4.0 * S, "groove"),
                                     (4.0 * S, 4.8 * S, "ridge")])
    inner = smoothstep(4.6 * S, 5.4 * S, d)
    pillow = smoothstep(5.0 * S, H * 0.38, d)
    if pressed:
        pillow = 1 - pillow * 0.5
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    brushed = ndimage.gaussian_filter1d(value_noise(W, H, 3, 91), 16, axis=1) * 0.14
    cap = make_matcap(face, spec_pow=24, spec=0.55)
    # the icon socket: a dark well with a gold ring, at the left
    sc = (H * 0.5 + 3 * S, H / 2)
    sr = H * 0.34
    well = dome(W, H, sc[0], sc[1], sr)
    outer = dome(W, H, sc[0], sc[1], sr + 3.4 * S)
    ring = np.clip(outer - well * 1.05, 0, 1)
    ring_m = (outer > 0).astype(np.float32) * (1 - (well > 0.02))
    base = np.zeros((H, W, 3), np.float32)
    face_h = pillow + brushed - well * 0.9
    rgb, alpha = shade_layers(base, [(face_h, inner, cap, 1.6 * S, 0.0), (rim_h, rim_m, metal, 4.4 * S, 0.0),
                                     (ring * 0.9, ring_m * inner, metal, 3.0 * S, 0.25)])
    sock = (well > 0.0).astype(np.float32)
    rgb = rgb * (1 - sock[..., None] * 0.72) + sock[..., None] * np.array([0.02, 0.025, 0.04]) * (1 - well[..., None] * 0.3)
    # light along the top, shade along the bottom
    top = (1 - smoothstep(5 * S, H * 0.5, y)) * inner
    rgb = rgb + top[..., None] * 0.07
    bot = smoothstep(H * 0.55, H - 5 * S, y) * inner
    rgb = rgb * (1 - bot[..., None] * 0.28)
    if glow > 0:
        g = np.exp(-((d - 6.0 * S) ** 2) / (2 * (2.8 * S) ** 2)) * inner
        rgb = rgb + g[..., None] * np.array([1.0, 0.8, 0.42]) * 0.6 * glow
        rgb = rgb + (inner * (1 - sock))[..., None] * np.array([0.06, 0.045, 0.02]) * glow
    left = int(math.ceil((sc[0] + sr + 6 * S) / S))
    right = int(math.ceil(tip / S)) + 4
    return save_rgba(name, np.clip(rgb, 0, 1), alpha, [left, 14, right, 14], extra={"content": [left + 6, 8, right, 8]})


def menu_banner(name, w=440, h=1000, cloth=(16, 22, 40)):
    """The hanging banner behind the Main Menu: woven cloth in deep blue-black with soft vertical folds, gold trim
    down both sides, an embroidered border, a gold rod at the top, a swallow-tail bottom, and the two suns of the
    game at its foot (the gold sun of Ancient Light and the black sun of Black Sun) in one emblem."""
    W, H = w * S, h * S
    tail = 90 * S
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    notch_depth = (1 - np.abs(x - W / 2) / (W / 2)) * tail
    inside = (y < H - 2 * S - notch_depth) & (x > 14 * S) & (x < W - 14 * S) & (y > 30 * S)
    m = blur(inside.astype(np.float32), 0.7 * S)
    weave = (np.sin(x / (1.4 * S)) * np.sin(y / (1.4 * S))) * 0.5 + 0.5
    folds = np.sin(x / W * math.pi * 3.0 + fbm(W, H, cell=200 * S, octaves=2, seed=5) * 2.0) * 0.5 + 0.5
    n = fbm(W, H, cell=60 * S, octaves=4, seed=7)
    c = np.array(cloth, np.float32) / 255.0
    rgb = c[None, None, :] * (0.65 + 0.55 * folds[..., None] + 0.25 * (n[..., None] - 0.5)) + (weave[..., None] - 0.5) * 0.018
    rgb = rgb * (1.15 - 0.45 * (y / H))[..., None]
    d = O.inside_distance(m > 0.5)
    thread = np.exp(-((d - 26 * S) ** 2) / (2 * (1.0 * S) ** 2)) + np.exp(-((d - 31 * S) ** 2) / (2 * (0.6 * S) ** 2)) * 0.6
    rgb = rgb + (thread * m)[..., None] * np.array([0.55, 0.40, 0.16]) * 0.8
    trim_h, trim_m = frame_profile(d, [(0.0, 1.0 * S, "flat"), (1.0 * S, 7.0 * S, "ridge"), (7.0 * S, 8.5 * S, "groove"),
                                       (8.5 * S, 11.0 * S, "ridge")])
    braid = (np.sin((y + x * 0.5) / (2.2 * S)) * 0.5 + 0.5) * 0.25
    trim_h = trim_h + braid * trim_m
    rod = O.mask_from_rects(W, H, [(0, 12 * S, W, 34 * S)], chamfer=4 * S)
    rod_h = np.sin(np.clip((y - 12 * S) / (22 * S), 0, 1) * math.pi)
    fin_h = np.maximum(dome(W, H, 10 * S, 23 * S, 16 * S), dome(W, H, W - 10 * S, 23 * S, 16 * S))
    fin_m = (fin_h > 0).astype(np.float32)
    # the emblem: a gold sun on the left half, a black sun with a crimson corona on the right, in a gold ring
    cx, cy = W / 2, H - tail - 118 * S
    R = 92 * S
    rr = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    ang = np.arctan2(y - cy, x - cx)
    disc = (rr < R).astype(np.float32)
    rays = (np.cos(ang * 16) * 0.5 + 0.5) ** 6
    band = (rr > R * 0.46) & (rr < R * 0.9)
    sun_gold = ((rr < R * 0.42) & (x < cx)).astype(np.float32)
    corona = np.exp(-((rr - R * 0.44) ** 2) / (2 * (5 * S) ** 2)) * (x >= cx)
    em_rgb = np.zeros_like(rgb)
    em_rgb += (rays * band * (x < cx))[..., None] * np.array([0.9, 0.62, 0.2]) * 0.55
    em_rgb += (rays * band * (x >= cx))[..., None] * np.array([0.6, 0.06, 0.08]) * 0.45
    sun_shade = np.clip(1.15 - rr / (R * 0.42) * 0.55 - (y - cy) / R * 0.25, 0.4, 1.2)
    em_rgb += sun_gold[..., None] * np.array([1.0, 0.8, 0.35]) * sun_shade[..., None]
    em_rgb += (np.exp(-((rr - R * 0.42) ** 2) / (2 * (4 * S) ** 2)) * (x < cx))[..., None] * np.array([1.0, 0.7, 0.25]) * 0.6
    em_rgb += corona[..., None] * np.array([1.0, 0.18, 0.12]) * 1.2
    rgb = rgb * (1 - disc[..., None] * 0.5) + em_rgb * disc[..., None]
    rd = np.clip(6 * S - np.abs(rr - R), 0, None)
    ring_h, ring_m = frame_profile(rd, [(0.0, 1.0 * S, "flat"), (1.0 * S, 6.0 * S, "ridge")])
    split = O.mask_from_rects(W, H, [(cx - 2 * S, cy - R, cx + 2 * S, cy + R)]) * disc
    rgb, alpha = shade_layers(rgb, [(trim_h, trim_m * m, GOLD, 4.0 * S, 0.0),
                                    (ring_h, ring_m, GOLD, 4.0 * S, 0.5),
                                    (np.ones_like(split) * 0.6, split, GOLD, 1.0 * S, 0.0),
                                    (rod_h, rod, GOLD, 5.0 * S, 0.6), (fin_h, fin_m, GOLD, 5.0 * S, 0.4)])
    alpha = np.maximum(alpha, m)
    return save_rgba(name, np.clip(rgb, 0, 1), alpha, None, kind="image")


def menu_footer(name, w=256, h=44):
    """The bar along the bottom of the Main Menu: dark enamel fading upward, a gold rule along its top edge
    (nine-slice in x)."""
    W, H = w * S, h * S
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    rgb = enamel(W, H, (9, 11, 17), seed=19, pattern=False)
    a = 0.55 + 0.4 * smoothstep(0, H * 0.6, y)
    rule = ((y > 3 * S) & (y < 6.5 * S)).astype(np.float32)
    rule_h = np.sin(np.clip((y - 3 * S) / (3.5 * S), 0, 1) * math.pi)
    rgb, a2 = shade_layers(rgb, [(rule_h, rule, GOLD, 3.0 * S, 0.0)])
    alpha = np.maximum(a, a2)
    return save_rgba(name, np.clip(rgb, 0, 1), alpha, [8, 10, 8, 2])


def build():
    # panels
    ornate_panel("panel_main", 140, 140, 34, gem=(90, 150, 255), corner=24)
    ornate_panel("panel_menu", 180, 180, 40, gem=(255, 190, 80), corner=30, radius=12)
    ornate_panel("panel_dusk", 140, 140, 34, gem=(255, 70, 60), corner=24)
    ornate_panel("panel_dawn", 140, 140, 34, gem=(90, 150, 255), corner=24)
    ornate_panel("panel_steel", 96, 96, 22, corner=0, metal=STEEL, radius=6,
                 bands=[(0.0, 1.0, "flat"), (1.0, 3.6, "ridge"), (3.6, 4.6, "groove"), (4.6, 6.0, "ridge")])
    plain_frame("panel_tip", 48, 48, 12)
    plain_frame("panel_card", 64, 64, 14, base=(14, 18, 27))
    plain_frame("panel_dark", 48, 48, 12, base=(7, 9, 13), metal=DARKMETAL, glow=(0.5, 0.6, 0.8))
    crest_piece("crest", 140, 56, 22)
    crest_piece("crest_small", 100, 40, 15)
    corner_piece("corner_blue", 26, (90, 150, 255))
    corner_piece("corner_gold", 26, (255, 190, 80))
    corner_piece("corner_red", 26, (255, 70, 60))
    logo("logo")
    # buttons
    steel_face = [(0.0, (8, 10, 14)), (0.45, (24, 29, 40)), (0.8, (50, 58, 74)), (1.0, (92, 102, 122))]
    gold_face = [(0.0, (54, 30, 8)), (0.42, (140, 92, 28)), (0.75, (214, 164, 72)), (1.0, (255, 228, 156))]
    red_face = [(0.0, (30, 4, 6)), (0.5, (104, 16, 18)), (0.85, (178, 40, 34)), (1.0, (236, 116, 96))]
    dark_face = [(0.0, (4, 5, 8)), (0.6, (13, 16, 22)), (1.0, (34, 40, 52))]
    for nm, face in (("btn", steel_face), ("btn_gold", gold_face), ("btn_red", red_face), ("btn_dark", dark_face)):
        button2(nm + "_normal", 72, 48, face=face)
        button2(nm + "_hover", 72, 48, face=face, glow=1.0)
        button2(nm + "_pressed", 72, 48, face=face, pressed=True, glow=0.5)
        button2(nm + "_disabled", 72, 48, face=face, disabled=True)
    tab_piece("tab_on", 72, 40, True)
    tab_piece("tab_off", 72, 40, False)
    slider_parts()
    check_parts()
    field_parts()
    scroll_parts()
    # slots and bars
    slot_frame("slot_ability", 72, 72)
    slot_frame("slot_item", 64, 48, notch=False, radius=4)
    slot_frame("slot_small", 40, 40, notch=False, radius=3, metal=BRONZE)
    bar_frame("bar_frame", 64, 22)
    bar_fill("bar_hp", 64, 22, (120, 230, 120), (46, 170, 56), (14, 70, 22))
    bar_fill("bar_hp_enemy", 64, 22, (255, 140, 120), (210, 50, 40), (90, 10, 10))
    bar_fill("bar_mana", 64, 22, (130, 180, 255), (44, 108, 236), (12, 34, 110), pattern="mana")
    bar_fill("bar_xp", 64, 22, (240, 200, 255), (160, 100, 230), (60, 24, 110), pattern="mana")
    bar_fill("bar_gold", 64, 22, (255, 230, 150), (220, 160, 50), (100, 60, 10), pattern="mana")
    divider("divider", 320, 24)
    ring_frame("ring_level", 56, 7, spikes=8)
    ring_frame("ring_portrait", 96, 9, spikes=4)
    ring_frame("ring_small", 28, 4)
    gem_icon("gem_dawn", 28, (90, 160, 255))
    gem_icon("gem_dusk", 28, (255, 70, 60))
    gem_icon("gem_gold", 28, (255, 196, 80))
    gem_icon("gem_green", 28, (90, 230, 110))
    ribbon("ribbon_dusk", 160, 44, (120, 16, 22))
    ribbon("ribbon_dawn", 160, 44, (24, 54, 128))
    ribbon("ribbon_gold", 160, 44, (150, 104, 34))
    glow_dot("glow_gold", 64, (255, 200, 110))
    glow_dot("glow_blue", 64, (110, 170, 255))
    glow_dot("glow_red", 64, (255, 90, 70))
    backdrop("backdrop", 1024, 1024)
    hero_card("hero_card")
    # the Main Menu (run 2026-10-15 g)
    steel_plate = [(0.0, (6, 8, 12)), (0.45, (20, 25, 36)), (0.8, (46, 54, 72)), (1.0, (90, 100, 124))]
    gold_plate = [(0.0, (50, 28, 6)), (0.42, (132, 86, 24)), (0.75, (206, 156, 66)), (1.0, (255, 226, 150))]
    for nm, face in (("menu_plate", steel_plate), ("menu_plate_gold", gold_plate)):
        menu_plate(nm + "_normal", 200, 64, face=face)
        menu_plate(nm + "_hover", 200, 64, face=face, glow=1.0)
        menu_plate(nm + "_pressed", 200, 64, face=face, pressed=True, glow=0.5)
    menu_banner("menu_banner")
    menu_footer("menu_footer")
    ornate_panel("menu_nameplate", 160, 120, 30, gem=(255, 190, 80), corner=22, radius=10, alpha_inside=0.88)
    # bespoke HUD
    console()
    for n in range(5, 11):
        console("hud_console_%d" % n, n)
    minimap_frame()
    topbar_art()
    # the social screens (Ranked, Profile, Players, Forums; run 2026-10-20)
    import ui_skin_social
    ui_skin_social.build(sys.modules[__name__])
    with open(os.path.join(OUT, "skin.json"), "w") as f:
        json.dump({"scale": S, "textures": MANIFEST}, f, indent=1)


def preview(path):
    tiles = []
    for name, e in MANIFEST.items():
        if name in ("backdrop",):
            continue
        img = Image.open(os.path.join(OUT, e["file"]))
        w, h = e["size"]
        tiles.append((name, img.resize((max(1, w), max(1, h)), Image.LANCZOS)))
    big = [t for t in tiles if t[1].width > 380]
    small = [t for t in tiles if t[1].width <= 380]
    cols = 8
    cw, ch = 200, 200
    rows = (len(small) + cols - 1) // cols
    big_h = sum(t[1].height + 30 for t in big)
    sheet = Image.new("RGBA", (max(cols * cw, max([t[1].width for t in big] + [0]) + 20), rows * ch + big_h + 20), (0, 0, 0, 255))
    bg = Image.open(os.path.join(OUT, "backdrop.png")).resize(sheet.size)
    sheet.paste(bg, (0, 0))
    d = ImageDraw.Draw(sheet)
    for i, (name, img) in enumerate(small):
        x = (i % cols) * cw + 10
        y = (i // cols) * ch + 10
        sheet.alpha_composite(img, (x, y))
        d.text((x, y + ch - 24), name, fill=(220, 210, 190, 255))
    y = rows * ch + 10
    for name, img in big:
        sheet.alpha_composite(img, (10, y))
        d.text((10, y + img.height + 4), name, fill=(220, 210, 190, 255))
        y += img.height + 30
    sheet.save(path)


if __name__ == "__main__":
    if "--consoles" in sys.argv:
        _ = [console("hud_console_%d" % n, n) for n in range(5, 11)]
        prev = json.load(open(os.path.join(OUT, "skin.json")))
        prev["textures"].update(MANIFEST)
        MANIFEST.clear()
        MANIFEST.update(prev["textures"])
        with open(os.path.join(OUT, "skin.json"), "w") as f:
            json.dump({"scale": S, "textures": MANIFEST}, f, indent=1)
        print("consoles built")
        sys.exit(0)
    build()
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1])
    print("skin: %d textures in %s" % (len(MANIFEST), os.path.abspath(OUT)))

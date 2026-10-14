"""Ornament and shape primitives for tools/ui_skin.py: tapered scrolls, leaves, beads, engraving, bevels on any
silhouette (distance transform), filigree corners and crests, and an embossed title from a font."""
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage


def inside_distance(mask):
    """Distance (pixels) from each inside pixel to the outside (the image border counts as outside); 0 outside."""
    padded = np.pad(mask > 0.5, 1, constant_values=False)
    return ndimage.distance_transform_edt(padded)[1:-1, 1:-1].astype(np.float32)


def mask_from_rects(w, h, rects, chamfer=0):
    """A silhouette from rectangles [(x0, y0, x1, y1)] (union), each with optional cut corners."""
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    for x0, y0, x1, y1 in rects:
        c = chamfer
        poly = [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]
        d.polygon(poly, fill=255)
    return np.asarray(img, np.float32) / 255.0


def mask_from_poly(w, h, polys, k=4):
    img = Image.new("L", (w * k, h * k), 0)
    d = ImageDraw.Draw(img)
    for poly in polys:
        d.polygon([(x * k, y * k) for x, y in poly], fill=255)
    return np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0


def taper_stroke(w, h, path, w0, w1, k=4, soft=1.0):
    """A tube along `path` whose width runs from w0 to w1 (a scroll that thins to its tip)."""
    img = Image.new("L", (w * k, h * k), 0)
    d = ImageDraw.Draw(img)
    n = len(path)
    for i, (x, y) in enumerate(path):
        t = i / max(1, n - 1)
        r = (w0 + (w1 - w0) * t) * k / 2
        d.ellipse((x * k - r, y * k - r, x * k + r, y * k + r), fill=255)
    a = np.asarray(img.resize((w, h), Image.LANCZOS), np.float32) / 255.0
    hgt = ndimage.gaussian_filter(a, soft) if soft > 0 else a
    # a rounded profile: blur of the mask, normalised by the local width
    return np.clip(hgt * 1.4, 0, 1), np.clip(a * 1.2, 0, 1)


def leaf(w, h, base, tip, width, bend=0.25, k=4):
    """An acanthus leaf: a pointed blade from base to tip, curved to one side, with an engraved vein."""
    bx, by = base
    tx, ty = tip
    dx, dy = tx - bx, ty - by
    ln = math.hypot(dx, dy)
    nx, ny = -dy / ln, dx / ln
    left, right, vein = [], [], []
    for i in range(41):
        t = i / 40
        cx = bx + dx * t + nx * math.sin(t * math.pi) * bend * ln
        cy = by + dy * t + ny * math.sin(t * math.pi) * bend * ln
        wid = width * math.sin(min(1.0, t * 1.25) * math.pi * 0.5) * (1 - t) ** 0.8
        left.append((cx + nx * wid, cy + ny * wid))
        right.append((cx - nx * wid * 0.7, cy - ny * wid * 0.7))
        vein.append((cx, cy))
    m = mask_from_poly(w, h, [left + right[::-1]], k)
    hgt = ndimage.gaussian_filter(m, 1.6) * 1.2
    vh, _ = taper_stroke(w, h, vein[:34], width * 0.16, width * 0.05, soft=0.5)
    hgt = np.clip(hgt - vh * 0.45, 0, 1)
    return hgt, m


def beads(w, h, pts, r):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    hgt = np.zeros((h, w), np.float32)
    for px, py in pts:
        d2 = ((x + 0.5 - px) ** 2 + (y + 0.5 - py) ** 2) / (r * r)
        hgt = np.maximum(hgt, np.sqrt(np.clip(1 - d2, 0, 1)))
    return hgt, (hgt > 0.02).astype(np.float32)


def bezier(p0, p1, p2, p3, n=60):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def spiral(cx, cy, r0, r1, turns, start, ccw=1, n=90):
    out = []
    for i in range(n + 1):
        t = i / n
        a = start + ccw * t * turns * 2 * math.pi
        r = r0 + (r1 - r0) * t
        out.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return out


def scroll(p0, p1, curl_r, side=1, turns=1.1):
    """An S-scroll from p0 towards p1 that rolls into a spiral at the end (side picks which way it curls)."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(dx, dy)
    ux, uy = dx / ln, dy / ln
    nx, ny = -uy * side, ux * side
    c1 = (p0[0] + dx * 0.35 + nx * ln * 0.18, p0[1] + dy * 0.35 + ny * ln * 0.18)
    c2 = (p0[0] + dx * 0.7 - nx * ln * 0.12, p0[1] + dy * 0.7 - ny * ln * 0.12)
    body = bezier(p0, c1, c2, p1, 50)
    # the spiral starts where the body ends, rolling back towards the curve's inside
    cx, cy = p1[0] + nx * curl_r, p1[1] + ny * curl_r
    start = math.atan2(p1[1] - cy, p1[0] - cx)
    ccw = 1 if side > 0 else -1
    tail = spiral(cx, cy, curl_r, curl_r * 0.12, turns, start, ccw=-ccw if (ux * ny - uy * nx) > 0 else ccw)
    return body + tail[1:]


def faceted_gem(w, h, cx, cy, r, sides=8, rot=0.0):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    dx = x + 0.5 - cx
    dy = y + 0.5 - cy
    a = np.arctan2(dy, dx) - rot
    seg = 2 * math.pi / sides
    af = np.mod(a, seg) - seg / 2
    rr = np.sqrt(dx * dx + dy * dy) * np.cos(af) / math.cos(seg / 2)
    hgt = np.clip(1 - rr / r, 0, 1)
    table = np.minimum(hgt, 0.45) / 0.45
    m = np.clip((r - rr) / 1.2, 0, 1)
    return table * m, m


def dome(w, h, cx, cy, r):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d2 = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) / (r * r)
    return np.sqrt(np.clip(1 - d2, 0, 1))


def plate(w, h, poly, bevel):
    """A bevelled metal plate in any polygon shape."""
    m = mask_from_poly(w, h, [poly])
    d = inside_distance(m)
    hgt = np.clip(d / bevel, 0, 1) ** 0.7
    return hgt, m


def transform(pts, origin, fx, fy, swap=False):
    ox, oy = origin
    out = []
    for x, y in pts:
        if swap:
            x, y = y, x
        out.append((ox + x * fx, oy + y * fy))
    return out


def filigree_corner(w, h, origin, s, fx=1, fy=1):
    """A corner ornament at `origin` (the frame's inner corner), growing into the panel (fx, fy = +1 or -1).
    Returns (metal height, metal mask, gem centre)."""
    hs = []
    ms = []
    # two scrolls running along the edges, mirrored across the diagonal
    for swap in (False, True):
        path = scroll((s * 0.2, s * 0.05), (s * 1.75, s * 0.32), s * 0.22, side=1)
        pts = transform(path, origin, fx, fy, swap)
        hh, mm = taper_stroke(w, h, pts, s * 0.2, s * 0.05, soft=1.2)
        hs.append(hh)
        ms.append(mm)
        # a small leaf off each scroll
        base = transform([(s * 0.7, s * 0.2)], origin, fx, fy, swap)[0]
        tip = transform([(s * 1.05, s * 0.62)], origin, fx, fy, swap)[0]
        lh, lm = leaf(w, h, base, tip, s * 0.13, bend=0.3 * (1 if not swap else -1) * fx * fy)
        hs.append(lh)
        ms.append(lm)
    # the fleur on the diagonal: a centre leaf and two side leaves
    o = transform([(s * 0.3, s * 0.3)], origin, fx, fy)[0]
    for ang, ln, wid in ((45, 1.15, 0.2), (20, 0.72, 0.13), (70, 0.72, 0.13)):
        a = math.radians(ang)
        tip = transform([(s * 0.3 + math.cos(a) * s * ln, s * 0.3 + math.sin(a) * s * ln)], origin, fx, fy)[0]
        lh, lm = leaf(w, h, o, tip, s * wid, bend=0.0 if ang == 45 else (0.18 if ang < 45 else -0.18) * fx * fy)
        hs.append(lh * 0.95)
        ms.append(lm)
    # a diamond plate under the gem
    cx, cy = transform([(s * 0.28, s * 0.28)], origin, fx, fy)[0]
    r = s * 0.42
    ph, pm = plate(w, h, [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], s * 0.12)
    hs.append(ph)
    ms.append(pm)
    # beads along the edges
    bpts = transform([(s * (2.05 + 0.18 * i), s * 0.06) for i in range(3)], origin, fx, fy) + \
        transform([(s * 0.06, s * (2.05 + 0.18 * i)) for i in range(3)], origin, fx, fy)
    bh, bm = beads(w, h, bpts, s * 0.06)
    hs.append(bh)
    ms.append(bm)
    hgt = np.maximum.reduce(hs)
    msk = np.clip(np.maximum.reduce(ms), 0, 1)
    return hgt, msk, (cx, cy)


def crest(w, h, cx, cy, s, down=True):
    """A centre-top ornament: a gem on a shield plate between two scrolls that sweep outwards."""
    hs, ms = [], []
    sy = 1 if down else -1
    for side in (-1, 1):
        path = scroll((cx + side * s * 0.25, cy), (cx + side * s * 1.9, cy + sy * s * 0.15), s * 0.2, side=side * sy)
        hh, mm = taper_stroke(w, h, path, s * 0.18, s * 0.05, soft=1.2)
        hs.append(hh)
        ms.append(mm)
        lh, lm = leaf(w, h, (cx + side * s * 0.3, cy + sy * s * 0.1), (cx + side * s * 1.0, cy + sy * s * 0.55), s * 0.12,
                      bend=0.25 * side)
        hs.append(lh)
        ms.append(lm)
    shield = [(cx - s * 0.42, cy - sy * s * 0.18), (cx + s * 0.42, cy - sy * s * 0.18), (cx + s * 0.36, cy + sy * s * 0.3),
              (cx, cy + sy * s * 0.62), (cx - s * 0.36, cy + sy * s * 0.3)]
    ph, pm = plate(w, h, shield, s * 0.1)
    hs.append(ph)
    ms.append(pm)
    return np.maximum.reduce(hs), np.clip(np.maximum.reduce(ms), 0, 1), (cx, cy + sy * s * 0.12)


def embossed_text(text, font_path, size, weight=800, pad=40, tracking=0):
    """A text mask (white on black) at `size` px, for an embossed title. Returns the float mask."""
    f = ImageFont.truetype(font_path, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    # measure with tracking
    widths = [f.getbbox(ch)[2] - f.getbbox(ch)[0] if ch != " " else size * 0.32 for ch in text]
    asc, desc = f.getmetrics()
    total = sum(f.getlength(ch) for ch in text) + tracking * (len(text) - 1)
    w = int(total + pad * 2)
    h = int(asc + desc + pad * 2)
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    x = pad
    for ch in text:
        d.text((x, pad), ch, font=f, fill=255)
        x += f.getlength(ch) + tracking
    _ = widths
    return np.asarray(img, np.float32) / 255.0

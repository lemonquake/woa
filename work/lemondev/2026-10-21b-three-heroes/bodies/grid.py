"""Shaded front / back splats of <feat.npz> with a world grid (x every 0.02, height fraction h every 0.02), in two big
images so regions can be drawn as polygons in (x, h). python -I grid.py <feat.npz> <out prefix> [x0 x1 h0 h1]"""
import sys, numpy as np
from PIL import Image, ImageDraw
f = np.load(sys.argv[1]); out = sys.argv[2]
co, nr = f["co"], f["nr"]
z0, H = co[:, 2].min(), co[:, 2].max() - co[:, 2].min()
h = (co[:, 2] - z0) / H
x0, x1, h0, h1 = (float(a) for a in sys.argv[3:7]) if len(sys.argv) > 6 else (co[:, 0].min() - 0.01, co[:, 0].max() + 0.01, 0.0, 1.0)
S = 1400
sc = S / max(x1 - x0, (h1 - h0) * H)
for name, sign in (("front", 1), ("back", -1)):
    W_, H_ = int((x1 - x0) * sc), int((h1 - h0) * H * sc)
    img = np.full((H_, W_, 3), 0.35); zb = np.full((H_, W_), -1e9)
    px = ((co[:, 0] - x0) if sign == 1 else (x1 - co[:, 0])) * sc
    pz = (h1 - h) * H * sc
    depth = -sign * co[:, 1]
    lt = np.clip(0.5 + 0.5 * (nr @ np.array([0.3 * sign, -0.7 * sign, 0.5])), 0.25, 1.0)
    keep = (px >= 0) & (px < W_) & (pz >= 0) & (pz < H_)
    o = np.argsort(depth[keep]); P, Z, D, Lt = px[keep][o].astype(int), pz[keep][o].astype(int), depth[keep][o], lt[keep][o]
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            X = np.clip(P + dx, 0, W_ - 1); Zz = np.clip(Z + dz, 0, H_ - 1)
            m = D >= zb[Zz, X]; zb[Zz[m], X[m]] = D[m]
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            X = np.clip(P + dx, 0, W_ - 1); Zz = np.clip(Z + dz, 0, H_ - 1)
            m = D >= zb[Zz, X] - 0.003; img[Zz[m], X[m]] = Lt[m, None] * np.array([0.85, 0.85, 0.85])
    im = Image.fromarray((img * 255).astype(np.uint8)); d = ImageDraw.Draw(im)
    for gx in np.arange(np.ceil(x0 / 0.02) * 0.02, x1, 0.02):
        X = ((gx - x0) if sign == 1 else (x1 - gx)) * sc
        d.line([(X, 0), (X, H_)], fill=(255, 60, 60) if abs(gx) < 1e-6 or abs(round(gx / 0.1) * 0.1 - gx) < 1e-6 else (120, 90, 90), width=1)
        if abs(round(gx / 0.1) * 0.1 - gx) < 1e-6:
            d.text((X + 2, 2), "x%.1f" % gx, fill=(255, 255, 0))
    for gh in np.arange(np.ceil(h0 / 0.02) * 0.02, h1, 0.02):
        Z = (h1 - gh) * H * sc
        major = abs(round(gh / 0.1) * 0.1 - gh) < 1e-6
        d.line([(0, Z), (W_, Z)], fill=(60, 160, 255) if major else (80, 90, 120), width=1)
        d.text((2, Z + 1), "h%.2f" % gh, fill=(120, 255, 255))
    im.save("%s_%s.png" % (out, name))

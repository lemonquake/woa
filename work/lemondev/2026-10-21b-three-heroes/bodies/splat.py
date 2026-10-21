"""Fast rule preview without Blender: splat the painted vertices of <name>_feat.npz front and back (depth-tested).
python -I splat.py <feat.npz> <rules.py> <out.png> [feature]"""
import sys, runpy, numpy as np
from PIL import Image
feat, rules_p, out = sys.argv[1:4]
show = sys.argv[4] if len(sys.argv) > 4 else ""
f = np.load(feat)
co, nr, e = f["co"], f["nr"], f["e"]
n = len(co)
deg = np.bincount(e.ravel(), minlength=n).astype(float); deg[deg == 0] = 1
def spread(v, it):
    v = v.copy()
    for _ in range(it):
        s = np.zeros_like(v)
        np.add.at(s, e[:, 0], v[e[:, 1]]); np.add.at(s, e[:, 1], v[e[:, 0]])
        v = 0.5 * v + 0.5 * s / (deg[:, None] if v.ndim > 1 else deg)
    return v
F = {k: f[k] for k in f.files}
F.update({"n": n, "spread": spread, "x": co[:, 0], "y": co[:, 1], "H": co[:, 2].max() - co[:, 2].min()})
R = runpy.run_path(rules_p)
if show:
    v = F[show]; lo, hi = np.percentile(v, [3, 97])
    t = np.clip((v - lo) / (hi - lo + 1e-12), 0, 1)
    col = np.c_[t, 0.3 + 0.0 * t, 1 - t]
else:
    W, mats = R["weights"](F, np)
    W = np.clip(W, 0, None); W /= np.maximum(W.sum(1, keepdims=True), 1e-6)
    col = W @ np.array(R["preview"])[:W.shape[1]]
light = np.clip(0.55 + 0.45 * (nr @ np.array([0.3, -0.6, 0.6])), 0.3, 1.0)
S = 900
def view(sign):
    img = np.full((S, S, 3), 0.4); zb = np.full((S, S), -1e9)
    mn, mx = co.min(0), co.max(0); c = (mn + mx) / 2; sz = (mx[2] - mn[2]) * 1.05
    px = ((sign * (co[:, 0] - c[0])) / sz + 0.5) * S
    pz = (0.5 - (co[:, 2] - c[2]) / sz) * S
    depth = -sign * co[:, 1]
    lt = np.clip(0.55 + 0.45 * (nr @ np.array([0.3 * sign, -0.6 * sign, 0.6])), 0.3, 1.0)
    order = np.argsort(depth)
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            X = np.clip(px[order].astype(int) + dx, 0, S - 1); Z = np.clip(pz[order].astype(int) + dz, 0, S - 1)
            d = depth[order]
            m = d >= zb[Z, X]
            zb[Z[m], X[m]] = d[m]
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            X = np.clip(px[order].astype(int) + dx, 0, S - 1); Z = np.clip(pz[order].astype(int) + dz, 0, S - 1)
            d = depth[order]
            m = d >= zb[Z, X] - 0.004
            img[Z[m], X[m]] = (col[order] * lt[order][:, None])[m]
    return img
a, b = view(1), view(-1)
Image.fromarray((np.clip(np.concatenate([a, b], 1), 0, 1) * 255).astype(np.uint8)).save(out)

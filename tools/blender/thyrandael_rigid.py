"""Thyrandael's wings ride the chest and the halo rides the head (run 2026-10-21): works out the hero_body.py --rigid
balls that hold every wing and halo vertex of the source model, and no vertex of the body, arms or head.

Wings: vertices of the main piece behind the back (y > --back) or wide of the trunk (|x| > --wide), above --low,
farther than the limb radii from the arm, head and neck bones of the joints file and outside a ball round each
shoulder (the pauldrons stay with the arms). Halo: the separate piece above the head. The wanted vertices are covered
by balls on a grid (cells of --cell, halved twice near the body); a ball is kept only when no other vertex lies in
it, so the body never rides the chest by mistake. Vertices inside --cut shapes (the sword, cut away) count for
neither side. The spec goes to --out (one line, for --rigid).

Run: blender -b --factory-startup --python tools/blender/thyrandael_rigid.py -- --src=<fbx> --joints=<json>
       --out=<txt> [--cut=<hero_body --cut spec>] [--cell=0.05] [--back=0.125] [--wide=0.21] [--low=0.33]
"""
import bpy
import json
import sys
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree

args = sys.argv[sys.argv.index("--") + 1:]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args if a.startswith("--") and "=" in a}
CELL = float(opt.get("cell", "0.05"))
BACK = float(opt.get("back", "0.125"))
WIDE = float(opt.get("wide", "0.21"))
LOW = float(opt.get("low", "0.33"))
LIMB_R = {"upper_arm": 0.062, "forearm": 0.052, "hand": 0.048, "head": 0.068, "neck": 0.055}
SHOULDER_R = 0.075


def seg_dist(p, a, b):
    a, b = np.asarray(a), np.asarray(b)
    d = b - a
    t = np.clip(((p - a) @ d) / max(1e-12, d @ d), 0.0, 1.0)
    return np.linalg.norm(p - (a + np.outer(t, d)), axis=1)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=opt["src"])
o = next(x for x in bpy.context.scene.objects if x.type == 'MESH')
me = o.data
n = len(me.vertices)
co = np.empty(n * 3)
me.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
M = np.array(o.matrix_world)
co = (np.c_[co, np.ones(n)] @ M.T)[:, :3]
ed = np.empty(len(me.edges) * 2, dtype=np.int64)
me.edges.foreach_get("vertices", ed)
ed = ed.reshape(-1, 2)
# connected pieces (coincident vertices joined)
_, inv = np.unique(np.round(co / 1e-5).astype(np.int64), axis=0, return_inverse=True)
inv = inv.ravel()
a_, b_ = inv[ed[:, 0]], inv[ed[:, 1]]
lab = np.arange(inv.max() + 1)
while True:
    lo = np.minimum(lab[a_], lab[b_])
    new = lab.copy()
    np.minimum.at(new, a_, lo)
    np.minimum.at(new, b_, lo)
    new = new[new]
    if np.array_equal(new, lab):
        break
    lab = new
vl = lab[inv]
ids, counts = np.unique(vl, return_counts=True)
main = ids[np.argmax(counts)]
J = json.load(open(opt["joints"]))
cut = np.zeros(n, dtype=bool)
for c in [c for c in opt.get("cut", "").split(";") if c.strip()]:
    if c.startswith("cap:"):
        v = [float(x) for x in c[4:].split(",")]
        cut |= seg_dist(co, v[0:3], v[3:6]) < v[6]
    elif c.startswith("ball:"):
        v = [float(x) for x in c[5:].split(",")]
        cut |= np.linalg.norm(co - np.array(v[0:3]), axis=1) < v[3]
    else:
        x0, x1, y0, y1, z0, z1 = [float(x) for x in c.split(",")]
        cut |= ((co[:, 0] >= x0) & (co[:, 0] <= x1) & (co[:, 1] >= y0) & (co[:, 1] <= y1) & (co[:, 2] >= z0) & (co[:, 2] <= z1))
near = np.zeros(n, dtype=bool)
for bone, (h, t) in J.items():
    key = bone.split(".")[0]
    if key in LIMB_R:
        near |= seg_dist(co, h, t) < LIMB_R[key]
for s in ("L", "R"):
    near |= np.linalg.norm(co - np.array(J["upper_arm." + s][0]), axis=1) < SHOULDER_R
cx = J["hips"][0][0]
wing = (vl == main) & ~cut & ~near & (co[:, 2] > LOW) & ((co[:, 1] > BACK) | (np.abs(co[:, 0] - cx) > WIDE))
halo = (vl != main) & ~cut
targets = {"chest": wing, "head": halo}
print("[thyr_rigid] wing %d, halo %d, near limbs %d of %d vertices" % (wing.sum(), halo.sum(), near.sum(), n), flush=True)
specs = []
for bone, want in targets.items():
    other = ~want & ~cut
    # the others near the wanted ones, thinned to a 2 mm grid, in a KD tree
    lo_, hi_ = co[want].min(0) - 0.1, co[want].max(0) + 0.1
    sel = other & np.all((co >= lo_) & (co <= hi_), axis=1)
    pts = np.unique(np.round(co[sel] / 0.002).astype(np.int64), axis=0) * 0.002
    kd = KDTree(len(pts))
    for i, p in enumerate(pts):
        kd.insert(Vector(p), i)
    kd.balance()
    wp = co[want]
    left = np.ones(len(wp), dtype=bool)
    cell = CELL
    for level in range(3):
        if not left.any():
            break
        keys = np.floor(wp[left] / cell).astype(np.int64)
        cells = np.unique(keys, axis=0)
        r = cell * 0.5 * 3 ** 0.5 * 1.02
        kept = 0
        for k in cells:
            c = (k + 0.5) * cell
            if len(pts) and kd.find(Vector(c))[2] < r:
                continue
            specs.append("%s:ball:%.4f,%.4f,%.4f,%.4f" % (bone, c[0], c[1], c[2], r))
            kept += 1
            inside = np.linalg.norm(wp - c, axis=1) < r
            left &= ~inside
        print("[thyr_rigid] %s level %d: %d cells, %d balls kept, %d vertices left" % (bone, level, len(cells), kept,
              left.sum()), flush=True)
        cell *= 0.5
spec = ";".join(specs)
open(opt["out"], "w").write(spec)
print("[thyr_rigid] %d balls, %d characters -> %s" % (len(specs), len(spec), opt["out"]), flush=True)

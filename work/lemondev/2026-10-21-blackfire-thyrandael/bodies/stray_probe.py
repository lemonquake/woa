"""Built body: vertices whose main weight is a trunk or leg bone but which lie nearer an arm bone (and the reverse),
grouped in 4 cm cells. Rest pose, game space.
Run: blender -b --factory-startup --python stray_probe.py -- <body.glb> [--margin=0.02]
"""
import bpy
import sys
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args[1:] if a.startswith("--") and "=" in a}
MARGIN = float(opt.get("margin", "0.02"))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mw = arm.matrix_world
J = {b.name: (np.array(mw @ b.head_local), np.array(mw @ b.tail_local)) for b in arm.data.bones}


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(1e-9, ab @ ab), 0.0, 1.0)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


ARMB = [b for b in J if b.split(".")[0] in ("upper_arm", "forearm", "hand")]
BODY = [b for b in J if b.split(".")[0] in ("hips", "spine", "chest", "neck", "head", "thigh", "shin", "foot")]
for m in [o for o in bpy.data.objects if o.type == 'MESH']:
    co = np.array([(m.matrix_world @ v.co)[:] for v in m.data.vertices])
    names = {g.index: g.name for g in m.vertex_groups}
    main = []
    armw = np.zeros(len(co))
    for v in m.data.vertices:
        gs = [(names[g.group], g.weight) for g in v.groups]
        main.append(max(gs, key=lambda x: x[1])[0] if gs else "")
        armw[v.index] = sum(w for n, w in gs if n in ARMB)
    da = np.min(np.stack([seg_dist(co, *J[b]) for b in ARMB], 1), 1)
    db = np.min(np.stack([seg_dist(co, *J[b]) for b in BODY], 1), 1)
    for label, sel in (("body-weighted near arm", (armw < 0.5) & (da + MARGIN < db)),
                       ("arm-weighted near body", (armw > 0.5) & (db + MARGIN < da))):
        p = co[sel]
        print("%s: %d vertices" % (label, len(p)))
        if not len(p):
            continue
        if "zmax" in opt:
            p = p[p[:, 2] < float(opt["zmax"])]
        print("   below zmax: %d" % len(p))
        if not len(p):
            continue
        keys, cnt = np.unique(np.floor(p / 0.04).astype(int), axis=0, return_counts=True)
        order = np.argsort(-cnt)
        for i in order[:25]:
            c = (keys[i] + 0.5) * 0.04
            print("   cell %s  %d" % (tuple(round(x, 2) for x in c), cnt[i]))

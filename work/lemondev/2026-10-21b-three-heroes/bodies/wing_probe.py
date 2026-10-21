# Wing vertex clouds of Thyrandael's source (the old --rigid balls, split by side): extents and a fitted root / tip.
import bpy, sys, numpy as np
argv = sys.argv[sys.argv.index("--") + 1:]
src, rigid = argv[0], open(argv[1]).read()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=True)
ms = [o for o in bpy.data.objects if o.type == 'MESH']
co = np.concatenate([np.array([o.matrix_world @ v.co for v in o.data.vertices]) for o in ms])
print("model bounds", co.min(0).round(3), co.max(0).round(3), len(co))
balls = [s.split(":") for s in rigid.split(";") if s.strip()]
for side, sel in (("L", lambda c: c[0] > 0.0), ("R", lambda c: c[0] < 0.0)):
    m = np.zeros(len(co), bool)
    for bone, kind, nums in balls:
        if bone != "chest":
            continue
        v = [float(x) for x in nums.split(",")]
        c = np.array(v[:3])
        if not sel(c):
            continue
        m |= np.linalg.norm(co - c, axis=1) < v[3]
    p = co[m]
    ax = np.abs(p[:, 0])
    root = p[ax < np.percentile(ax, 4)].mean(0)
    tip = p[ax > np.percentile(ax, 97)].mean(0)
    low = p[p[:, 2] < np.percentile(p[:, 2], 3)].mean(0)
    print(side, "n", m.sum(), "x", p[:, 0].min().round(3), p[:, 0].max().round(3), "y", p[:, 1].min().round(3), p[:, 1].max().round(3),
          "z", p[:, 2].min().round(3), p[:, 2].max().round(3), "root", root.round(3), "tip", tip.round(3), "lowest", low.round(3))

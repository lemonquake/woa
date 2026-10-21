"""List the connected pieces of a source model (vertices at the same place joined), largest first, with bounds.
Run: blender -b --factory-startup --python islands_probe.py -- <model> [--top=30] [--save=<npz of labels>]
"""
import bpy
import sys
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
src = args[0]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args[1:] if a.startswith("--") and "=" in a}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
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
# weld coincident vertices
key = np.round(co / 1e-5).astype(np.int64)
_, inv = np.unique(key, axis=0, return_inverse=True)
inv = inv.ravel()
a, b = inv[ed[:, 0]], inv[ed[:, 1]]
m = inv.max() + 1
lab = np.arange(m)
while True:
    la, lb = lab[a], lab[b]
    lo = np.minimum(la, lb)
    new = lab.copy()
    np.minimum.at(new, a, lo)
    np.minimum.at(new, b, lo)
    new = new[new]
    if np.array_equal(new, lab):
        break
    lab = new
vl = lab[inv]
ids, counts = np.unique(vl, return_counts=True)
order = np.argsort(-counts)
print("PIECES", len(ids))
for i in order[:int(opt.get("top", "30"))]:
    p = co[vl == ids[i]]
    print("PIECE %8d verts  min %s max %s mean %s" % (counts[i], p.min(0).round(3), p.max(0).round(3), p.mean(0).round(3)))
if "save" in opt:
    np.savez_compressed(opt["save"], labels=vl, co=co.astype(np.float32))

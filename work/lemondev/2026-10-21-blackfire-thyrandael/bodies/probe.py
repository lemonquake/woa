"""Probe a source model: pieces, rig, materials, and vertex statistics inside boxes (model space as hero_body reads it).
Run: blender -b --factory-startup --python probe.py -- <model> [--yaw=0] [--boxes=name:x0,x1,y0,y1,z0,z1;...]
       [--slices=x0,x1,z0,z1,dz]  (per z slab inside an x range: y min/mean/max and x min/max)
"""
import bpy
import math
import sys
import numpy as np
from mathutils import Matrix

args = sys.argv[sys.argv.index("--") + 1:]
src = args[0]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args[1:] if a.startswith("--") and "=" in a}
bpy.ops.wm.read_factory_settings(use_empty=True)
if src.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=True)
else:
    bpy.ops.import_scene.gltf(filepath=src)
yaw = float(opt.get("yaw", "0"))
R = Matrix.Rotation(math.radians(yaw), 4, 'Z')
co_all = []
for o in bpy.context.scene.objects:
    print("OBJ", o.name, o.type, "parent", o.parent.name if o.parent else None,
          "verts" if o.type == 'MESH' else "", len(o.data.vertices) if o.type == 'MESH' else "",
          "faces", len(o.data.polygons) if o.type == 'MESH' else "",
          "mats", [s.material.name for s in o.material_slots if s.material] if o.type == 'MESH' else "")
    if o.type == 'ARMATURE':
        print("  bones", len(o.data.bones), [b.name for b in o.data.bones][:40])
    if o.type == 'MESH':
        dg = bpy.context.evaluated_depsgraph_get()
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        co = np.array([(R @ o.matrix_world @ v.co)[:] for v in me.vertices])
        e.to_mesh_clear()
        co_all.append(co)
        for s in o.material_slots:
            m = s.material
            if m and m.node_tree:
                for n in m.node_tree.nodes:
                    if n.type == 'TEX_IMAGE' and n.image:
                        print("  tex", n.image.name, n.image.size[:], [l.to_socket.name for l in n.outputs[0].links])
co = np.vstack(co_all)
print("BOUNDS", co.min(0).round(3), co.max(0).round(3), "n", len(co))
for spec in [b for b in opt.get("boxes", "").split(";") if b.strip()]:
    name, nums = spec.split(":")
    x0, x1, y0, y1, z0, z1 = [float(x) for x in nums.split(",")]
    m = (co[:, 0] >= x0) & (co[:, 0] <= x1) & (co[:, 1] >= y0) & (co[:, 1] <= y1) & (co[:, 2] >= z0) & (co[:, 2] <= z1)
    p = co[m]
    if len(p):
        print("BOX %-12s n=%6d min %s max %s mean %s" % (name, len(p), p.min(0).round(3), p.max(0).round(3), p.mean(0).round(3)))
    else:
        print("BOX %-12s empty" % name)
if "slices" in opt:
    x0, x1, z0, z1, dz = [float(x) for x in opt["slices"].split(",")]
    z = z0
    while z < z1 - 1e-9:
        m = (co[:, 0] >= x0) & (co[:, 0] <= x1) & (co[:, 2] >= z) & (co[:, 2] < z + dz) & (co[:, 1] <= float(opt.get("ymax", "9"))) & (co[:, 1] >= float(opt.get("ymin", "-9")))
        p = co[m]
        if len(p):
            print("SLICE z %.3f-%.3f n=%6d x %.3f..%.3f (mean %.3f)  y %.3f..%.3f (mean %.3f)" % (
                z, z + dz, len(p), p[:, 0].min(), p[:, 0].max(), p[:, 0].mean(), p[:, 1].min(), p[:, 1].max(), p[:, 1].mean()))
        z += dz

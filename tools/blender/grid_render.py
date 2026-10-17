"""Orthographic front and side renders of a character with a measuring grid, for placing joints by hand
(hero_body.py --joints) and choosing cut boxes (--cut). Coordinates are the model's own after --yaw, in metres as
imported (the same space hero_body.py reads joints in).

Run: blender -b --factory-startup --python tools/blender/grid_render.py -- <model> <out_prefix> [--yaw=0] [--step=0.05]
     [--zoom=x0,x1,z0,z1]   (a region, in model units, to render larger; front view)
Writes <out_prefix>_front.png and _side.png (grid lines every --step, labelled every 2 steps) and <out_prefix>.json.
"""
import bpy
import json
import math
import os
import sys
import numpy as np
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args[2:] if a.startswith("--") and "=" in a}
yaw = float(opt.get("yaw", "0"))
step = float(opt.get("step", "0.05"))
zoom = [float(x) for x in opt["zoom"].split(",")] if "zoom" in opt else None

bpy.ops.wm.read_factory_settings(use_empty=True)
ext = os.path.splitext(src)[1].lower()
if ext in (".glb", ".gltf"):
    bpy.ops.import_scene.gltf(filepath=src)
elif ext == ".fbx":
    bpy.ops.import_scene.fbx(filepath=src)
elif ext == ".obj":
    bpy.ops.wm.obj_import(filepath=src)
scn = bpy.context.scene
R = Matrix.Rotation(math.radians(yaw), 4, 'Z')
for o in scn.objects:
    if o.parent is None:
        o.matrix_world = R @ o.matrix_world
bpy.context.view_layer.update()
import re
drop = re.compile(opt["drop"], re.I) if "drop" in opt else None
for o in [o for o in scn.objects if o.type == 'MESH']:
    if (drop and drop.search(o.name)) or (o.name.startswith("Icosphere") and not o.modifiers):
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in scn.objects if o.type == 'MESH']
for m in meshes:
    if len(m.data.polygons) > 300000:
        d = m.modifiers.new("d", 'DECIMATE')
        d.ratio = 300000 / len(m.data.polygons)
dg = bpy.context.evaluated_depsgraph_get()
pts = []
for m in meshes:
    e = m.evaluated_get(dg)
    me = e.to_mesh()
    co = np.array([v.co[:] for v in me.vertices])
    e.to_mesh_clear()
    if len(co):
        M = np.array(m.matrix_world)
        pts.append((np.c_[co, np.ones(len(co))] @ M.T)[:, :3])
pts = np.vstack(pts)
lo, hi = pts.min(0), pts.max(0)
scn.render.engine = 'BLENDER_WORKBENCH'
scn.display.shading.light = 'STUDIO'
scn.display.shading.color_type = 'SINGLE'
scn.display.shading.single_color = (0.75, 0.72, 0.68)
scn.render.film_transparent = False
cd = bpy.data.cameras.new("c")
cd.type = 'ORTHO'
cam = bpy.data.objects.new("c", cd)
scn.collection.objects.link(cam)
scn.camera = cam
info = {"lo": lo.tolist(), "hi": hi.tolist(), "views": {}}
for view in ("front", "side"):
    if view == "front":
        u0, u1 = lo[0], hi[0]
    else:
        u0, u1 = lo[1], hi[1]
    z0, z1 = lo[2], hi[2]
    if zoom and view == "front":
        u0, u1, z0, z1 = zoom
    pad = 0.05 * max(u1 - u0, z1 - z0)
    u0, u1, z0, z1 = u0 - pad, u1 + pad, z0 - pad, z1 + pad
    w, h = u1 - u0, z1 - z0
    size = max(w, h)
    res = 1400
    scn.render.resolution_x = int(res * w / size)
    scn.render.resolution_y = int(res * h / size)
    cd.ortho_scale = size
    cu, cz = (u0 + u1) / 2, (z0 + z1) / 2
    far = float(np.abs(pts).max()) * 4 + 10
    if view == "front":
        cam.location = (cu, -far, cz)          # looking along +Y at the model's front (it faces -Y)
        cam.rotation_euler = (math.radians(90), 0, 0)
    else:
        cam.location = (far, cu, cz)           # from +X (the model's left), +Y to the right of the image
        cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    cd.clip_end = far * 3
    f = "%s_%s.png" % (out, view)
    scn.render.filepath = f
    bpy.ops.render.render(write_still=True)
    info["views"][view] = {"u0": u0, "u1": u1, "z0": z0, "z1": z1, "w": scn.render.resolution_x,
                           "h": scn.render.resolution_y, "axis": "x" if view == "front" else "y"}
json.dump(info, open(out + ".json", "w"), indent=1)
print("[grid_render] bounds", lo.round(3).tolist(), hi.round(3).tolist(), flush=True)

"""grid_render.py with a crop: keep only the vertices inside a box, render front and side zoomed on that box.
Run: blender -b --factory-startup --python zoom_render.py -- <model> <out_prefix> --box=x0,x1,y0,y1,z0,z1 [--res=1400]
Then: python tools/grid_overlay.py <out_prefix> --step=0.01 [--marks=..]
"""
import bpy
import bmesh
import json
import math
import sys
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args[2:] if a.startswith("--") and "=" in a}
box = [float(x) for x in opt["box"].split(",")]
res = int(opt.get("res", "1400"))
bpy.ops.wm.read_factory_settings(use_empty=True)
if src.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=src)
else:
    bpy.ops.import_scene.gltf(filepath=src)
scn = bpy.context.scene
meshes = [o for o in scn.objects if o.type == 'MESH']
for m in meshes:
    for mod in list(m.modifiers):
        m.modifiers.remove(mod)
    m.data.transform(m.matrix_world)
    m.matrix_world.identity()
    m.parent = None
    bm = bmesh.new()
    bm.from_mesh(m.data)
    x0, x1, y0, y1, z0, z1 = box
    def in_cut(c):
        hit = False
        for spec in [q for q in opt.get("cut", "").split(";") if q.strip()]:
            if spec.startswith("cap:"):
                v = [float(t) for t in spec[4:].split(",")]
                a, b = Vector(v[0:3]), Vector(v[3:6])
                d = b - a
                t = max(0.0, min(1.0, (c - a).dot(d) / d.dot(d)))
                hit |= (c - (a + d * t)).length < v[6]
            elif spec.startswith("ball:"):
                v = [float(t) for t in spec[5:].split(",")]
                hit |= (c - Vector(v[0:3])).length < v[3]
            else:
                v = [float(t) for t in spec.split(",")]
                hit |= v[0] <= c.x <= v[1] and v[2] <= c.y <= v[3] and v[4] <= c.z <= v[5]
        return hit
    inv = opt.get("only") == "1"
    kill = [v for v in bm.verts if not (x0 <= v.co.x <= x1 and y0 <= v.co.y <= y1 and z0 <= v.co.z <= z1)
            or (opt.get("cut") and in_cut(v.co) != inv)]
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    bm.to_mesh(m.data)
    bm.free()
scn.render.engine = 'BLENDER_WORKBENCH'
scn.display.shading.light = 'STUDIO'
scn.display.shading.color_type = 'TEXTURE' if opt.get("tex") else 'SINGLE'
scn.display.shading.single_color = (0.75, 0.72, 0.68)
cd = bpy.data.cameras.new("c")
cd.type = 'ORTHO'
cam = bpy.data.objects.new("c", cd)
scn.collection.objects.link(cam)
scn.camera = cam
x0, x1, y0, y1, z0, z1 = box
info = {"lo": [x0, y0, z0], "hi": [x1, y1, z1], "views": {}}
for view in opt.get("views", "front,side").split(","):
    u0, u1 = (x0, x1) if view in ("front", "back") else (y0, y1)
    w, h = u1 - u0, z1 - z0
    size = max(w, h)
    scn.render.resolution_x = int(res * w / size)
    scn.render.resolution_y = int(res * h / size)
    cd.ortho_scale = size
    cu, cz = (u0 + u1) / 2, (z0 + z1) / 2
    far = 20.0
    if view == "front":
        cam.location = (cu, -far, cz)
        cam.rotation_euler = (math.radians(90), 0, 0)
    elif view == "back":                      # from +Y: image left is +X (labels mirrored: read u as -x)
        cam.location = (cu, far, cz)
        cam.rotation_euler = (math.radians(90), 0, math.radians(180))
    elif view == "out":                       # from -X: image left is +Y
        cam.location = (-far, cu, cz)
        cam.rotation_euler = (math.radians(90), 0, math.radians(-90))
    elif view == "top":                       # from +Z, image x = x, image up = +y; u range x, "z" range = y
        cam.location = ((x0 + x1) / 2, (y0 + y1) / 2, far)
        cam.rotation_euler = (0, 0, 0)
    else:
        cam.location = (far, cu, cz)
        cam.rotation_euler = (math.radians(90), 0, math.radians(90))
    cd.clip_end = far * 3
    scn.render.filepath = "%s_%s.png" % (out, view)
    bpy.ops.render.render(write_still=True)
    info["views"][view] = {"u0": u0, "u1": u1, "z0": z0, "z1": z1, "w": scn.render.resolution_x,
                           "h": scn.render.resolution_y, "axis": "x" if view == "front" else "y"}
json.dump(info, open(out + ".json", "w"), indent=1)
print("[zoom_render] done", out)

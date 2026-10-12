"""Render a GLB from three sides into PNGs for a quick look (Workbench, studio light).

Run: blender -b --factory-startup --python tools/blender/preview_glb.py -- <file.glb> <out_prefix>
Writes <out_prefix>_front.png, _side.png, _top.png.
"""
import bpy
import math
import sys
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=src)
pts = []
for o in bpy.context.scene.objects:
    if o.type == 'MESH':
        pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
c = (lo + hi) / 2
size = max(hi - lo) * 1.25
scn = bpy.context.scene
scn.render.engine = 'BLENDER_WORKBENCH'
scn.display.shading.light = 'STUDIO'
scn.display.shading.color_type = 'MATERIAL'
scn.display.shading.show_specular_highlight = True
scn.render.resolution_x = 700
scn.render.resolution_y = 700
cd = bpy.data.cameras.new("c")
cd.type = 'ORTHO'
cd.ortho_scale = size
cam = bpy.data.objects.new("c", cd)
scn.collection.objects.link(cam)
scn.camera = cam
for nm, d, rot in [("front", Vector((0, -1, 0)), (math.radians(90), 0, 0)),
                   ("side", Vector((1, 0, 0)), (math.radians(90), 0, math.radians(90))),
                   ("top", Vector((0, 0, 1)), (0, 0, 0))]:
    cam.location = c + d * size * 3
    cam.rotation_euler = rot
    scn.render.filepath = "%s_%s.png" % (out, nm)
    bpy.ops.render.render(write_still=True)

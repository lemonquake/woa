"""Render a GLB with EEVEE under a key, rim and fill light, from several angles, into one contact sheet per call.
Used to judge new hero bodies and gear before they go into the game.

Run: blender -b --factory-startup --python tools/blender/look_render.py -- <file.glb> <out.png>
       [--angles=0,45,180,270] [--elev=8] [--size=700] [--pose=<clip name>] [--frame=<n>] [--bg=0.16]
Angles are degrees round the model; 0 looks at its front (the hero faces -Y in Blender, +Z in Godot).
"""
import bpy
import math
import os
import sys
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args[2:] if a.startswith("--") and "=" in a}
angles = [float(a) for a in opt.get("angles", "0,45,180,270").split(",")]
elev = math.radians(float(opt.get("elev", "8")))
size = int(opt.get("size", "700"))
bgv = float(opt.get("bg", "0.16"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
scn = bpy.context.scene
arm = next((o for o in scn.objects if o.type == 'ARMATURE'), None)
if arm and "pose" in opt and arm.animation_data is not None:
    act = bpy.data.actions.get(opt["pose"])
    if act:
        arm.animation_data.action = act
        scn.frame_set(int(opt.get("frame", "1")))
elif arm and arm.animation_data:
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
pts = []
for o in scn.objects:
    if o.type == 'MESH':
        e = o.evaluated_get(dg)
        m = e.to_mesh()
        pts += [o.matrix_world @ v.co for i, v in enumerate(m.vertices) if i % 7 == 0]
        e.to_mesh_clear()
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
c = (lo + hi) / 2
ext = max(hi - lo)

engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
scn.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
scn.render.resolution_x = size
scn.render.resolution_y = size
scn.render.film_transparent = False
scn.view_settings.view_transform = 'AgX' if 'AgX' in [i.identifier for i in scn.view_settings.bl_rna.properties['view_transform'].enum_items] else 'Filmic'
scn.world = bpy.data.worlds.new("W")
scn.world.use_nodes = True
bg = scn.world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (bgv, bgv * 1.05, bgv * 1.2, 1.0)
bg.inputs["Strength"].default_value = 0.6


def light(name, kind, energy, loc, color=(1, 1, 1), size_=1.0):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    if kind == 'AREA':
        ld.size = size_
    lo_ = bpy.data.objects.new(name, ld)
    scn.collection.objects.link(lo_)
    lo_.location = loc
    lo_.rotation_euler = (c - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return lo_


cd = bpy.data.cameras.new("cam")
cd.lens = 60
cam = bpy.data.objects.new("cam", cd)
scn.collection.objects.link(cam)
scn.camera = cam
shots = []
for a in angles:
    for o in [o for o in scn.objects if o.type == 'LIGHT']:
        bpy.data.objects.remove(o)
    r = math.radians(a)
    fwd = Vector((math.sin(r), -math.cos(r), 0.0))       # from the model toward the camera
    side = Vector((math.cos(r), math.sin(r), 0.0))
    dist = ext * 2.3
    cam.location = c + fwd * dist * math.cos(elev) + Vector((0, 0, dist * math.sin(elev)))
    cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
    light("key", 'AREA', 70 * ext * ext, c + (fwd * 1.0 + side * 0.9 + Vector((0, 0, 1.0))) * ext * 1.6, (1.0, 0.96, 0.9), ext)
    light("rim", 'AREA', 60 * ext * ext, c + (-fwd * 1.2 - side * 0.6 + Vector((0, 0, 0.8))) * ext * 1.6, (0.8, 0.88, 1.0), ext * 0.6)
    light("fill", 'AREA', 20 * ext * ext, c + (fwd * 1.0 - side * 1.2 + Vector((0, 0, 0.1))) * ext * 1.6, (0.9, 0.92, 1.0), ext * 1.5)
    f = os.path.splitext(out)[0] + "_%d.png" % int(a)
    scn.render.filepath = f
    bpy.ops.render.render(write_still=True)
    shots.append(f)

# one sheet: the shots side by side
imgs = [bpy.data.images.load(f) for f in shots]
W = size * len(imgs)
sheet = bpy.data.images.new("sheet", W, size)
px = [0.0] * (W * size * 4)
for k, im in enumerate(imgs):
    p = list(im.pixels)
    for y in range(size):
        row = p[y * size * 4:(y + 1) * size * 4]
        start = (y * W + k * size) * 4
        px[start:start + size * 4] = row
sheet.pixels = px
sheet.filepath_raw = out
sheet.file_format = 'PNG'
sheet.save()
for f in shots:
    os.remove(f)
print("[look_render] wrote", out, flush=True)

"""Render a hero body GLB holding its weapons in chosen clips (contact sheet: one row per clip, one column per angle).

Run: blender -b --factory-startup --python tools/blender/pose_render.py -- <body.glb> <out.png>
       --clips=idle_staff:10,staff_1:12 [--angles=0,60,150] [--size=420] [--R=<weapon.glb>] [--L=<weapon.glb>]
       [--float=0.0] [--lean=0] [--dist=5.2] [--aim=1.0]   (camera distance and the height it looks at)
Weapons sit on weapon.R / weapon.L with the game's convention (grip at the bone, +Y along the bone's -Y? no: the
weapon's +Y follows the bone's own +Y), as ModelCatalog attaches them.
"""
import bpy
import math
import os
import sys
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args[2:] if a.startswith("--") and "=" in a}
clips = [(c.split(":")[0], int(c.split(":")[1]) if ":" in c else 1) for c in opt.get("clips", "idle:1").split(",")]
angles = [float(a) for a in opt.get("angles", "0,60,150").split(",")]
size = int(opt.get("size", "420"))
lean = math.radians(float(opt.get("lean", "0")))
lift = float(opt.get("float", "0"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
arm.location.z += lift
arm.rotation_euler.x += lean
for side in ("R", "L"):
    if side in opt:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=opt[side])
        new = [o for o in bpy.data.objects if o not in before]
        root = next(o for o in new if o.parent is None)
        # glTF import turns +Y-up into +Z-up: the weapon's +Y (Godot) is +Z here, put it along the bone's +Y
        root.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
        fix = Matrix.Rotation(math.radians(-90), 4, 'X')
        for o in new:
            if o.parent is None:
                o.matrix_world = fix @ o.matrix_world
        bpy.context.view_layer.update()
        for o in new:
            if o.parent is None:
                mw = o.matrix_world.copy()
                o.parent = arm
                o.parent_type = 'BONE'
                o.parent_bone = "weapon." + side
                bone = arm.data.bones["weapon." + side]
                o.matrix_parent_inverse = Matrix.Identity(4)
                o.matrix_basis = Matrix.Translation((0.0, -bone.length, 0.0)) @ mw
sc = bpy.context.scene
engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
sc.render.resolution_x = size
sc.render.resolution_y = size
sc.world = bpy.data.worlds.new("W")
sc.world.color = (0.17, 0.18, 0.21)
for nm, loc, e in (("k", (2.5, -3.0, 4.5), 900), ("f", (-3.0, -2.0, 1.5), 300), ("r", (0.0, 4.0, 3.0), 500)):
    l = bpy.data.objects.new(nm, bpy.data.lights.new(nm, 'POINT'))
    l.data.energy = e
    l.location = loc
    sc.collection.objects.link(l)
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
cam.data.lens = 50
sc.collection.objects.link(cam)
sc.camera = cam
arm.animation_data_create()
shots = []
for clip, frame in clips:
    act = bpy.data.actions.get(clip)
    arm.animation_data.action = act
    if act is not None and hasattr(arm.animation_data, "action_slot") and len(getattr(act, "slots", [])):
        arm.animation_data.action_slot = act.slots[0]
    sc.frame_set(frame)
    for a in angles:
        r = math.radians(a)
        dist = float(opt.get("dist", "5.2"))
        aim_z = float(opt.get("aim", "1.0"))
        bn = opt.get("bone", "")
        if bn:
            pbn = arm.pose.bones[bn]
            tgt = arm.matrix_world @ ((pbn.head + pbn.tail) * 0.5)
        else:
            tgt = Vector((0, 0, aim_z + lift))
        el = math.radians(float(opt.get("elev", "15")))
        cam.location = tgt + Vector((math.sin(r) * math.cos(el) * dist, -math.cos(r) * math.cos(el) * dist, math.sin(el) * dist))
        cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
        f = os.path.splitext(out)[0] + "_%s_%d.png" % (clip, int(a))
        sc.render.filepath = f
        bpy.ops.render.render(write_still=True)
        shots.append(f)
cols = len(angles)
rows = len(clips)
sheet = bpy.data.images.new("sheet", size * cols, size * rows)
px = [0.0] * (size * cols * size * rows * 4)
for i, f in enumerate(shots):
    im = bpy.data.images.load(f)
    p = list(im.pixels)
    c, rr = i % cols, rows - 1 - i // cols
    for y in range(size):
        start = ((rr * size + y) * size * cols + c * size) * 4
        px[start:start + size * 4] = p[y * size * 4:(y + 1) * size * 4]
    os.remove(f)
sheet.pixels = px
sheet.filepath_raw = out
sheet.file_format = 'PNG'
sheet.save()
print("[pose_render] wrote", out, flush=True)

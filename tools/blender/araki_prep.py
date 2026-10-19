"""Araki's body source (2026-10-19 c): the Shadowflame Samurai (dark_igorek, CC BY 4.0, a Character Creator rig) made
ready for tools/blender/hero_body.py.

The Sketchfab conversion keeps its rest skeleton broken: the rest bones lie Y-up and several (the upper arms, the
twist ends) sit at the origin, so the mesh only looks right through the armature's pose. As for Azrael
(azrael_prep.py), the shown pose (an A-pose, katana in the right hand) is baked into every skinned piece and made the
rest pose. The katana (its own unskinned mesh) and the helper sphere stay; hero_body.py drops them with --drop.

Writes <out>/araki_src.blend:
  blender -b --factory-startup --python tools/blender/araki_prep.py -- --src=work/downloads/sf_heroes/shadowflame_samurai.glb
          --out=work/araki_src
"""
import bpy
import os
import sys

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in ARGS if a.startswith("--") and "=" in a}
SRC = OPT.get("src", "A:/Python/woa/work/downloads/sf_heroes/shadowflame_samurai.glb")
OUT = os.path.abspath(OPT.get("out", "A:/Python/woa/work/araki_src"))


def log(*a):
    print("[araki_prep]", *a, flush=True)


os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = max((o for o in bpy.data.objects if o.type == 'ARMATURE'), key=lambda a: len(a.data.bones))
skinned = [o for o in bpy.data.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)]
for o in skinned:
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    for m in [m for m in o.modifiers if m.type == 'ARMATURE']:
        bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.object.select_all(action='DESELECT')
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.select_all(action='SELECT')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
for o in skinned:
    m = o.modifiers.new("Armature", 'ARMATURE')
    m.object = arm
log("baked the shown pose into %d pieces and made it the rest pose" % len(skinned))
# flatten the converter's empties (two 0.01 scales and a Y-up turn) into the objects, so the .blend stands on its own
# (hero_body.py links the objects, not the empties' chain)
keep = [o for o in bpy.data.objects if o.type in ('MESH', 'ARMATURE')]
bpy.ops.object.select_all(action='DESELECT')
for o in keep:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in [o for o in bpy.data.objects if o.type == 'EMPTY']:
    bpy.data.objects.remove(o, do_unlink=True)
for o in skinned:
    o.parent = arm
bpy.context.view_layer.update()
for b in arm.data.bones:
    if b.name.startswith(("CC_Base_Hip_", "CC_Base_Head_", "CC_Base_L_Hand_", "CC_Base_L_Upperarm_0")):
        log("  rest", b.name, tuple(round(x, 3) for x in (arm.matrix_world @ b.head_local)))
for img in bpy.data.images:
    if img.packed_file is None and img.source == 'FILE' and img.has_data:
        img.pack()
path = os.path.join(OUT, "araki_src.blend")
bpy.ops.wm.save_as_mainfile(filepath=path)
log("saved", path)

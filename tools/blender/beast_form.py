"""Ghorman's Beast Form (2026-10-17): the owner's troll download as a form model of its own, like Roydo's Anomaly.

The troll keeps its own skeleton and its eight clips (renamed beast_idle, beast_run, beast_walk, beast_attack1,
beast_attack2, beast_hit, beast_death, beast_idle_break), its mace stays in its right hand; it is scaled to --height
metres (feet on the ground) and the stray helper sphere of the download is dropped.

Run: blender -b --factory-startup --python tools/blender/beast_form.py -- [--src=<glb>] [--out=<glb>] [--height=2.4]
"""
import bpy
import os
import sys
import numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args if a.startswith("--") and "=" in a}
SRC = opt.get("src", "A:/Python/woa/work/downloads/sf_heroes/ghorman_transform.glb")
OUT = opt.get("out", "A:/Python/woa/assets/characters/heroes17/ghorman_beast.glb")
HEIGHT = float(opt.get("height", "2.4"))
NAMES = {"idle": "beast_idle", "run": "beast_run", "walk": "beast_walk", "attack1": "beast_attack1",
         "attack2": "beast_attack2", "take_damage": "beast_hit", "death": "beast_death", "idle_break": "beast_idle_break"}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name.startswith("Icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
root = arm
while root.parent:
    root = root.parent
# measure the standing troll on its idle
arm.animation_data_create()
idle = bpy.data.actions.get("idle")
arm.animation_data.action = idle
if hasattr(arm.animation_data, "action_slot") and len(idle.slots):
    arm.animation_data.action_slot = idle.slots[0]
bpy.context.scene.frame_set(int(idle.frame_range[0]))
dg = bpy.context.evaluated_depsgraph_get()
pts = []
for o in bpy.data.objects:
    if o.type == 'MESH':
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        pts += [tuple(o.matrix_world @ v.co) for v in me.vertices]
        e.to_mesh_clear()
p = np.array(pts)
body_top = np.percentile(p[:, 2], 99.7)
k = HEIGHT / (body_top - p[:, 2].min())
root.matrix_world = Matrix.Scale(k, 4) @ Matrix.Translation(Vector((0.0, 0.0, -p[:, 2].min()))) @ root.matrix_world
print("[beast_form] scaled x%.4f to %.2f m" % (k, HEIGHT), flush=True)
for a in bpy.data.actions:
    if a.name in NAMES:
        a.name = NAMES[a.name]
        a.use_fake_user = True
arm.animation_data.action = None
bpy.ops.object.select_all(action='SELECT')
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animations=True, export_animation_mode='ACTIONS',
                          export_skins=True, export_yup=True, export_apply=False)
print("[beast_form] wrote", OUT, "clips:", sorted(a.name for a in bpy.data.actions), flush=True)

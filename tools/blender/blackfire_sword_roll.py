"""Turn a sword cut out by extract_prop.py about its own length so the blade's width lies along X (the game's swing
direction, as prep_weapon.py does for axes), keeping the grip exactly where extract_prop put it. Used for Blackfire's
and Thyrandael's swords (run 2026-10-21).

Run: blender -b --factory-startup --python tools/blender/blackfire_sword_roll.py -- --src=<extract_prop glb>
       --out=assets/weapons/<name>.glb [--part=0.5]   (the blade part measured: the far --part of the length)
"""
import bpy
import math
import os
import sys
import numpy as np
from mathutils import Matrix

args = sys.argv[sys.argv.index("--") + 1:]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args if a.startswith("--") and "=" in a}
PART = float(opt.get("part", "0.5"))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=opt["src"])
w = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
bpy.ops.object.select_all(action='DESELECT')
w.select_set(True)
bpy.context.view_layer.objects.active = w
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.empty(len(w.data.vertices) * 3)
w.data.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
z0, z1 = co[:, 2].min(), co[:, 2].max()
blade = co[co[:, 2] > z1 - (z1 - z0) * PART]
xy = blade[:, :2] - blade[:, :2].mean(0)
_, sv, vt = np.linalg.svd(xy, full_matrices=False)
ang = math.atan2(vt[0][1], vt[0][0])
w.data.transform(Matrix.Rotation(-ang, 4, 'Z'))
w.data.update()
co = np.empty(len(w.data.vertices) * 3)
w.data.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
print("[sword_roll] turned %.1f deg; blade width/thickness %.2f; bounds %s %s" % (
    math.degrees(-ang), sv[0] / max(1e-9, sv[1]), co.min(0).round(3).tolist(), co.max(0).round(3).tolist()), flush=True)
os.makedirs(os.path.dirname(os.path.abspath(opt["out"])), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=opt["out"], use_selection=True, export_format='GLB', export_yup=True, export_apply=True)
print("[sword_roll] wrote", opt["out"], flush=True)

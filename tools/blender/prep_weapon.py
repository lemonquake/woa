"""Turn a downloaded weapon model into a game weapon: grip at the origin, pointing up +Y in Godot (+Z here).

The weapon's long axis is found from its shape; its head is the end where it is widest (an axe's blade, a mace's
ball); the grip sits --grip of the way from the other end. It is scaled to --length metres and its textures are kept.

Run: blender -b --factory-startup --python tools/blender/prep_weapon.py -- --src=<model> --out=<weapon.glb>
       [--length=0.7] [--grip=0.15] [--faces=6000] [--flip_head]
"""
import bpy
import math
import os
import sys
import numpy as np
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
opt = {a.split("=", 1)[0][2:]: (a.split("=", 1)[1] if "=" in a else "1") for a in args if a.startswith("--")}
SRC, OUT = opt["src"], opt["out"]
LENGTH = float(opt.get("length", "0.7"))
GRIP = float(opt.get("grip", "0.15"))
FACES = int(opt.get("faces", "6000"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.name.startswith("Icosphere")]
for o in [o for o in bpy.context.scene.objects if o.type == 'MESH' and o not in meshes]:
    bpy.data.objects.remove(o)
for m in meshes:
    mw = m.matrix_world.copy()
    m.parent = None
    m.matrix_world = mw
bpy.ops.object.select_all(action='DESELECT')
for m in meshes:
    m.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
w = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in [o for o in bpy.context.scene.objects if o != w]:
    bpy.data.objects.remove(o)
if len(w.data.polygons) > FACES:
    d = w.modifiers.new("d", 'DECIMATE')
    d.ratio = FACES / len(w.data.polygons)
    d.delimit = {'UV', 'SEAM', 'MATERIAL'}
    bpy.ops.object.modifier_apply(modifier="d")
co = np.empty(len(w.data.vertices) * 3)
w.data.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
c = co.mean(0)
_, _, vt = np.linalg.svd(co - c, full_matrices=False)
ax = vt[0]
t = (co - c) @ ax
t0, t1 = t.min(), t.max()
# the head end: the end with the wider cross-section
def width(lo, hi):
    sel = (t >= lo) & (t <= hi)
    p = co[sel] - c
    p = p - np.outer(p @ ax, ax)
    return np.linalg.norm(p, axis=1).max() if sel.any() else 0.0
span = t1 - t0
if width(t0, t0 + span * 0.25) > width(t1 - span * 0.25, t1):
    ax = -ax
    t = -t
    t0, t1 = -t1, -t0
if "flip_head" in opt:
    ax = -ax
    t = -t
    t0, t1 = -t1, -t0
butt = Vector((c + ax * t0).tolist())
grip = butt + Vector(ax.tolist()) * (span * GRIP)
k = LENGTH / span
rot = Vector(ax.tolist()).rotation_difference(Vector((0.0, 0.0, 1.0))).to_matrix().to_4x4()
w.data.transform(Matrix.Scale(k, 4) @ rot @ Matrix.Translation(-grip))
w.data.update()
# the blade's flat faces sideways (X), so a swing cuts edge first: turn about the long axis so the head's spread
# lies along X
co = np.empty(len(w.data.vertices) * 3)
w.data.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
head = co[co[:, 2] > co[:, 2].max() - LENGTH * 0.25]
if len(head) > 3:
    hx = head[:, :2] - head[:, :2].mean(0)
    _, _, v2 = np.linalg.svd(hx, full_matrices=False)
    ang = math.atan2(v2[0][1], v2[0][0])
    w.data.transform(Matrix.Rotation(-ang, 4, 'Z'))
    # the blade on +X, as the game's own axe and cleaver (the swing clips lead with the weapon's +X)
    co = np.empty(len(w.data.vertices) * 3)
    w.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    head = co[co[:, 2] > co[:, 2].max() - LENGTH * 0.25]
    if abs(head[:, 0].min()) > abs(head[:, 0].max()):
        w.data.transform(Matrix.Rotation(math.pi, 4, 'Z'))
for p in w.data.polygons:
    p.use_smooth = True
bpy.ops.object.select_all(action='DESELECT')
w.select_set(True)
bpy.context.view_layer.objects.active = w
os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format='GLB', export_yup=True, export_apply=True)
print("[prep_weapon] wrote %s: %d faces, %.2f m, grip %.0f%% from the end" % (OUT, len(w.data.polygons), LENGTH, GRIP * 100), flush=True)

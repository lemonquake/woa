"""Lord Kaileh's jousting lance: the low-poly lance of "Lance/Joust Weapon" by Rio.Puntar (CC BY 4.0) out of its
Sketchfab download (the high-poly copy and two loose cylinders sit beside it) into a GLB of its own, in world space
with every transform applied, for tools/blender/prep_weapon.py to turn into a game weapon.

Run: blender -b --factory-startup --python tools/blender/kaileh_lance.py -- --src=<scene.gltf> --out=<x.glb>
Then: blender ... --python tools/blender/prep_weapon.py -- --src=<x.glb> --out=assets/weapons/kaileh_lance.glb
       --length=2.4 --grip=0.4 --faces=2000 --flip_head
(the tip and the butt are as thin as each other, so prep_weapon's widest-end guess is overridden; the grip sits just
behind the hand guard)
"""
import bpy
import sys

args = sys.argv[sys.argv.index("--") + 1:]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args if a.startswith("--") and "=" in a}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=opt["src"])
keep = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name.startswith("Lance_LP")]
if not keep:
    raise SystemExit("no low-poly lance")
dg = bpy.context.evaluated_depsgraph_get()
parts = []
for k in keep:
    me = bpy.data.meshes.new_from_object(k.evaluated_get(dg), depsgraph=dg)
    me.transform(k.matrix_world)
    parts.append(bpy.data.objects.new("lance_" + k.name, me))
for ob in list(bpy.context.scene.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for o in parts:
    bpy.context.scene.collection.objects.link(o)
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
print("lance faces", len(parts[0].data.polygons))
bpy.ops.export_scene.gltf(filepath=opt["out"], export_format='GLB', use_selection=True)

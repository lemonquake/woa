"""Cut Araki's katana out of the Shadowflame Samurai model (its own mesh, held in the right hand) into a GLB of its own,
in world space with every transform applied, for tools/blender/prep_weapon.py to turn into a game weapon.

Run: blender -b --factory-startup --python tools/blender/araki_katana.py -- --src=<shadowflame_samurai.glb> --out=<x.glb>
Then: blender ... --python tools/blender/prep_weapon.py -- --src=<x.glb> --out=assets/weapons/araki_katana.glb
       --length=1.0 --grip=0.13 [--flip_head]
"""
import bpy
import sys

args = sys.argv[sys.argv.index("--") + 1:]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args if a.startswith("--") and "=" in a}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=opt["src"])
keep = [o for o in bpy.context.scene.objects if o.type == 'MESH' and "katana" in (o.name + o.data.name).lower()]
if not keep:
    raise SystemExit("no katana mesh")
k = keep[0]
dg = bpy.context.evaluated_depsgraph_get()
me = bpy.data.meshes.new_from_object(k.evaluated_get(dg), depsgraph=dg)
me.transform(k.matrix_world)
o = bpy.data.objects.new("katana", me)
for ob in list(bpy.context.scene.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
bpy.context.scene.collection.objects.link(o)
bpy.ops.object.select_all(action='DESELECT')
o.select_set(True)
bpy.context.view_layer.objects.active = o
print("katana verts", len(me.vertices), "bounds", [tuple(round(c, 3) for c in v) for v in (o.bound_box[0], o.bound_box[6])])
bpy.ops.export_scene.gltf(filepath=opt["out"], export_format='GLB', use_selection=True)

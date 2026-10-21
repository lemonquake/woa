"""Dracoxinia's five swords out of "UTTVM Sword Color Pack" by EvesStudio2008 (CC BY 4.0; the owner's download): the
pack holds ten copies of one sword whose blade colour lives in loose atlas textures (textures/dkmkccz-*.png, stored
upside down against the GLB's UVs). One sword (blade and hilt meshes) is kept and its atlas swapped per colour; the
blade glows in its colour (the pack's own emission). Each GLB is world space with every transform applied, for
tools/blender/prep_weapon.py.

Run: blender -b --factory-startup --python tools/blender/dracoxinia_swords.py -- --pack=<dracoxinia_swords dir>
       --out=<dir>   (writes dracoxinia_sword_<colour>.glb)
Then per colour: blender ... --python tools/blender/prep_weapon.py -- --src=<dir>/dracoxinia_sword_pink.glb
       --out=assets/weapons/dracoxinia_sword_pink.glb --length=1.6 --grip=0.1
"""
import bpy
import os
import sys

args = sys.argv[sys.argv.index("--") + 1:]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args if a.startswith("--") and "=" in a}
PACK, OUT = os.path.abspath(opt["pack"]), os.path.abspath(opt["out"])
COLOURS = {"pink": "6718b309", "gold": "9566eb01", "blue": "eed8a2d1", "red": "d746051e", "green": "5996f9fe"}
os.makedirs(OUT, exist_ok=True)


def atlas(key):
    f = [n for n in os.listdir(os.path.join(PACK, "textures")) if n.startswith("dkmkccz-" + key)][0]
    im = bpy.data.images.load(os.path.join(PACK, "textures", f))
    im.scale(1024, 1024)
    w, h = im.size
    px = list(im.pixels[:])
    row = w * 4
    im.pixels[:] = [v for y in range(h - 1, -1, -1) for v in px[y * row:(y + 1) * row]]
    im.name = "dracoxinia_sword_" + key
    return im


for name, key in COLOURS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PACK, "source", "Sword_UTTVM_Color_Pack.glb"))
    keep = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name in ("Object_18", "Object_21")]
    im = atlas(key)
    dg = bpy.context.evaluated_depsgraph_get()
    parts = []
    for k in keep:
        me = bpy.data.meshes.new_from_object(k.evaluated_get(dg), depsgraph=dg)
        me.transform(k.matrix_world)
        for m in me.materials:
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image and n.image.name in ("Blade_baseColor", "Sword_baseColor"):
                    n.image = im
        parts.append(bpy.data.objects.new("sword_" + k.name, me))
    for ob in list(bpy.context.scene.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        bpy.context.scene.collection.objects.link(o)
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    path = os.path.join(OUT, "dracoxinia_sword_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True)
    print("[dracoxinia_swords] wrote", path, len(parts[0].data.polygons), "faces")

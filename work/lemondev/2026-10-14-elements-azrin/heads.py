import bpy, numpy as np
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="A:/Python/woa/assets/characters/hero/hero.glb")
body = bpy.data.objects["hero"]
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
arm.data.pose_position = 'REST'
body.data.shape_keys.key_blocks["female"].value = 1.0
bpy.context.view_layer.update()
e = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
h = np.array([e.matrix_world @ v.co for v in e.data.vertices])
bpy.ops.import_scene.gltf(filepath="A:/Python/woa/assets/characters/hero/azrin_body.glb")
az = next(o for o in bpy.context.selected_objects if o.type == 'MESH')
a = np.array([az.matrix_world @ v.co for v in az.data.vertices])
for name, c in (("hero", h), ("azrin", a)):
    hd = c[c[:,2] > 1.56]
    print("HEAD", name, "min", hd.min(0).round(3), "max", hd.max(0).round(3), "centre", ((hd.min(0)+hd.max(0))/2).round(3))
    face = c[(c[:,2] > 1.6) & (c[:,2] < 1.68)]
    print("FACE", name, "front y", face[:,1].min().round(3), "back y", face[:,1].max().round(3))

import bpy, numpy as np
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="A:/Python/woa/assets/characters/hero/hero.glb")
o = bpy.data.objects["hero"]
arm = bpy.data.objects["Armature"]
print("MODS", [(m.type, getattr(m,'object',None)) for m in o.modifiers], "parent", o.parent, "pose_pos", arm.data.pose_position)
print("ACTION", arm.animation_data.action.name if arm.animation_data and arm.animation_data.action else None)
for pos in ['REST', 'POSE']:
    arm.data.pose_position = pos
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    e = o.evaluated_get(dg)
    co = np.array([e.matrix_world @ v.co for v in e.data.vertices])
    i = co[:,0].argmax()
    print(pos, "dims", (co.max(0)-co.min(0)).round(3), "max-x vertex", co[i].round(3), "zmax", co[:,2].max().round(3))
raw = np.array([o.matrix_world @ v.co for v in o.data.vertices])
print("RAW max-x", raw[raw[:,0].argmax()].round(3))

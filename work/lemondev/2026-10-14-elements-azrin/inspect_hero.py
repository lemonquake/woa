import bpy, sys
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="A:/Python/woa/assets/characters/hero/hero.glb")
for o in bpy.data.objects:
    info = [o.name, o.type, tuple(round(x,3) for x in o.dimensions)]
    if o.type == 'MESH':
        sk = o.data.shape_keys
        info += [len(o.data.vertices), [k.name for k in sk.key_blocks][:40] if sk else None, [m.name for m in o.data.materials][:6], len(o.vertex_groups)]
    print("OBJ", info)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for b in arm.data.bones:
    print("BONE", b.name, tuple(round(x,3) for x in (arm.matrix_world @ b.head_local)), tuple(round(x,3) for x in (arm.matrix_world @ b.tail_local)))

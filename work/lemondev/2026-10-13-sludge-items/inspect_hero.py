import bpy, sys
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"A:/Python/woa/assets/characters/hero/hero.glb")
for o in bpy.data.objects:
    print("OBJ", o.type, o.name, tuple(round(x,3) for x in o.dimensions), o.data.name if o.data else "")
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
print("BONES", len(arm.data.bones))
for b in arm.data.bones:
    if b.parent is None or b.name.lower().startswith(("spine","upper","fore","hand","thigh","shin","foot","neck","head","clav","shoulder","pelvis","hips")) or "arm" in b.name.lower() or "leg" in b.name.lower():
        print(" B", b.name, "parent", b.parent.name if b.parent else None, tuple(round(x,3) for x in b.head_local), tuple(round(x,3) for x in b.tail_local))
print("ACTIONS", len(bpy.data.actions), [a.name for a in bpy.data.actions][:20])
for o in bpy.data.objects:
    if o.type=='MESH' and o.data.shape_keys:
        print("SK", o.name, [k.name for k in o.data.shape_keys.key_blocks][:40])

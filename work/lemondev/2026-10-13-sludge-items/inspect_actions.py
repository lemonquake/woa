import bpy, collections
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"A:/Python/woa/assets/characters/hero/hero.glb")
locs=collections.Counter(); scl=collections.Counter()
for a in bpy.data.actions:
    fcs = a.fcurves if hasattr(a,'fcurves') else []
    try:
        fcs = list(a.layers[0].strips[0].channelbags[0].fcurves) if not fcs else fcs
    except Exception as e:
        pass
    for fc in fcs:
        dp=fc.data_path
        if dp.endswith(".location"):
            b=dp.split('"')[1]
            vals=[k.co[1] for k in fc.keyframe_points]
            if max(vals)-min(vals)>1e-4 or abs(vals[0])>1e-4: locs[b]+=1
        if dp.endswith(".scale"):
            vals=[k.co[1] for k in fc.keyframe_points]
            if max(abs(v-1) for v in vals)>1e-4: scl[dp.split('"')[1]]+=1
print("NONZERO_LOC", dict(locs))
print("NONUNIT_SCALE", dict(scl))

# Survey an FBX: objects, armature, materials, images, bounds; render front/side/back previews.
import bpy, sys, math, mathutils
argv = sys.argv[sys.argv.index("--")+1:]
src, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
(bpy.ops.import_scene.gltf(filepath=src) if src.lower().endswith((".glb",".gltf")) else bpy.ops.import_scene.fbx(filepath=src))
mn = mathutils.Vector((1e9,)*3); mx = -mn
for o in bpy.context.scene.objects:
    print("OBJ", o.name, o.type, tuple(round(v,3) for v in o.dimensions), "parent", o.parent.name if o.parent else None)
    if o.type == 'MESH':
        print("  faces", len(o.data.polygons), "verts", len(o.data.vertices), "mats", [m.name for m in o.data.materials if m],
              "vgroups", len(o.vertex_groups), "uv", len(o.data.uv_layers), "colattr", len(o.data.color_attributes))
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
    if o.type == 'ARMATURE':
        print("  bones", len(o.data.bones), [b.name for b in o.data.bones][:80])
    if o.animation_data and o.animation_data.action:
        print("  action", o.animation_data.action.name)
for a in bpy.data.actions: print("ACTION", a.name, a.frame_range[:])
for i in bpy.data.images: print("IMG", i.name, i.size[:], i.packed_file is not None, i.filepath)
print("BOUNDS", tuple(round(v,3) for v in mn), tuple(round(v,3) for v in mx))
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = 700; sc.render.resolution_y = 900
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.5,0.5,0.55,1); w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
c = (mn+mx)/2; size = max(mx-mn)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = size*1.1
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 3; sun.rotation_euler = (0.8, 0.2, 0.6)
for name, ang in (("front", 0), ("side", 90), ("back", 180), ("top", None)):
    if ang is None:
        cam.location = c + mathutils.Vector((0,0,size*2)); cam.rotation_euler = (0,0,0)
    else:
        a = math.radians(ang)
        cam.location = c + mathutils.Vector((math.sin(a)*size*2, -math.cos(a)*size*2, 0))
        cam.rotation_euler = (math.radians(90), 0, a)
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)

# Render a rigged FBX/blend in REST pose, close-ups: front, back, sides, head, hands. Optional colour attribute "paint".
import bpy, sys, math, mathutils, os
argv = sys.argv[sys.argv.index("--")+1:]
src, out = argv[0], argv[1]
only = argv[2] if len(argv) > 2 else ""
if src.endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=src)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=True)
for o in bpy.data.objects:
    if o.type == 'ARMATURE':
        o.data.pose_position = 'REST'
sc = bpy.context.scene
bpy.context.view_layer.update()
meshes = [o for o in sc.objects if o.type == 'MESH']
dg = bpy.context.evaluated_depsgraph_get()
mn = mathutils.Vector((1e9,)*3); mx = -mn
for o in meshes:
    e = o.evaluated_get(dg); me = e.to_mesh()
    for v in me.vertices:
        w = o.matrix_world @ v.co
        mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
    e.to_mesh_clear()
print("REST BOUNDS", tuple(round(v,4) for v in mn), tuple(round(v,4) for v in mx))
engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
RES = int(os.environ.get("RES", 900)); sc.render.resolution_x = RES; sc.render.resolution_y = RES
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.35,0.36,0.4,1); bg.inputs[1].default_value = 1.2
for o in meshes:
    if not o.data.materials or os.environ.get("NOMAT") or os.environ.get("ATTR"):
        m = bpy.data.materials.new("look"); m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = (0.7,0.7,0.7,1); b.inputs["Roughness"].default_value = 0.5
        if os.environ.get("ATTR", "paint") in o.data.color_attributes:
            a = m.node_tree.nodes.new("ShaderNodeAttribute"); a.attribute_name = os.environ.get("ATTR", "paint")
            m.node_tree.links.new(a.outputs["Color"], b.inputs["Base Color"])
        o.data.materials.clear(); o.data.materials.append(m)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'
for i, (rx, rz, e) in enumerate(((0.9, 0.3, 3.0), (0.6, 2.8, 2.0), (1.2, -1.0, 1.5))):
    l = bpy.data.objects.new("l%d" % i, bpy.data.lights.new("l%d" % i, 'SUN')); sc.collection.objects.link(l)
    l.data.energy = e; l.rotation_euler = (rx, 0, rz)
c = (mn + mx) / 2; H = mx.z - mn.z
views = {
 "front": (c, 0, H*1.05), "back": (c, 180, H*1.05), "left": (c, 90, H*1.05), "right": (c, -90, H*1.05),
 "head": (mathutils.Vector((c.x, c.y, mn.z + H*0.88)), 0, H*0.28), "head_back": (mathutils.Vector((c.x, c.y, mn.z + H*0.88)), 180, H*0.28),
 "torso": (mathutils.Vector((c.x, c.y, mn.z + H*0.65)), 0, H*0.45), "torso_back": (mathutils.Vector((c.x, c.y, mn.z + H*0.65)), 180, H*0.45),
 "legs": (mathutils.Vector((c.x, c.y, mn.z + H*0.25)), 0, H*0.5), "head_side": (mathutils.Vector((c.x, c.y, mn.z + H*0.88)), 90, H*0.28),
 "hand_r": (mathutils.Vector((mn.x + (mx.x-mn.x)*0.1, c.y, mn.z + H*0.78)), 0, H*0.25),
}
for name, (p, ang, size) in views.items():
    if only and name not in only.split(","):
        continue
    a = math.radians(ang)
    cam.data.ortho_scale = size
    cam.location = p + mathutils.Vector((math.sin(a)*5, -math.cos(a)*5, 0))
    cam.rotation_euler = (math.radians(90), 0, a)
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)

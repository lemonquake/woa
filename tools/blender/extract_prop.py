"""Cut a held prop (a staff, a sword) out of a fused character mesh and save it as a game weapon.

The prop is everything inside the given capsules and balls (model space, as hero_body.py --rigid); it is decimated,
baked onto its own small texture from the dense mesh, scaled like the hero body (--height of the whole model), and
turned so its grip sits at the origin and it points up +Y in Godot (+Z in Blender), the game's weapon convention.

Run: blender -b --factory-startup --python tools/blender/extract_prop.py -- --src=<model> --out=<weapon.glb>
       --shapes="cap:x1,y1,z1,x2,y2,z2,r;ball:x,y,z,r" --grip=x,y,z --tip=x,y,z --height=<body height, m>
       [--yaw=0] [--faces=4000] [--tex=1024] [--hue=from:to:width[:sat[:val]]]
--tip is a point toward the prop's head: the prop's +Y runs from the grip toward it.
"""
import bpy
import bmesh
import math
import os
import sys
import numpy as np
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import texops  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in args if a.startswith("--") and "=" in a}
SRC, OUT = opt["src"], opt["out"]
SHAPES = opt["shapes"]
GRIP = Vector([float(x) for x in opt["grip"].split(",")])
TIP = Vector([float(x) for x in opt["tip"].split(",")])
HEIGHT = float(opt["height"])
YAW = float(opt.get("yaw", "0"))
FACES = int(opt.get("faces", "4000"))
TEX = int(opt.get("tex", "1024"))
HUE = opt.get("hue", "")                       # as hero_body.py --hue


def log(*a):
    print("[extract_prop]", *a, flush=True)


def seg_dist(p, a, b):
    a = np.array(a[:])
    b = np.array(b[:])
    d = b - a
    t = np.clip(((p - a) @ d) / max(1e-9, d @ d), 0.0, 1.0)
    return np.linalg.norm(p - (a + np.outer(t, d)), axis=1)


bpy.ops.wm.read_factory_settings(use_empty=True)
ext = os.path.splitext(SRC)[1].lower()
if ext == ".fbx":
    bpy.ops.import_scene.fbx(filepath=SRC)
else:
    bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
R = Matrix.Rotation(math.radians(YAW), 4, 'Z')
for o in bpy.context.scene.objects:
    if o.parent is None:
        o.matrix_world = R @ o.matrix_world
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for m in meshes:
    m.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
hi = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = np.empty(len(hi.data.vertices) * 3)
hi.data.vertices.foreach_get("co", co)
co = co.reshape(-1, 3)
zmin, zmax = co[:, 2].min(), co[:, 2].max()
inside = np.zeros(len(co), dtype=bool)
for spec in [x for x in SHAPES.split(";") if x.strip()]:
    kind, nums = spec.split(":")
    v = [float(x) for x in nums.split(",")]
    if kind == "cap":
        inside |= seg_dist(co, Vector(v[0:3]), Vector(v[3:6])) < v[6]
    else:
        inside |= np.linalg.norm(co - np.array(v[0:3]), axis=1) < v[3]
# the prop: a copy of the faces wholly inside
prop = hi.copy()
prop.data = hi.data.copy()
bpy.context.collection.objects.link(prop)
bm = bmesh.new()
bm.from_mesh(prop.data)
bm.verts.ensure_lookup_table()
kill = [f for f in bm.faces if not all(inside[v.index] for v in f.verts)]
bmesh.ops.delete(bm, geom=kill, context='FACES')
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
bm.to_mesh(prop.data)
bm.free()
log("prop: %d faces cut out" % len(prop.data.polygons))
# decimate and unwrap
bpy.ops.object.select_all(action='DESELECT')
prop.select_set(True)
bpy.context.view_layer.objects.active = prop
d = prop.modifiers.new("d", 'DECIMATE')
d.ratio = min(1.0, FACES / max(1, len(prop.data.polygons)))
bpy.ops.object.modifier_apply(modifier="d")
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
while prop.data.uv_layers:
    prop.data.uv_layers.remove(prop.data.uv_layers[0])
prop.data.uv_layers.new(name="UVMap")
bpy.ops.uv.smart_project(angle_limit=math.radians(55.0), island_margin=0.004, scale_to_bounds=True)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.shade_smooth()
# bake colour, roughness, metal and normal from the dense mesh (hi keeps only the faces near the prop, so the
# rays cannot hit the body)
bm = bmesh.new()
bm.from_mesh(hi.data)
bm.verts.ensure_lookup_table()
near = np.zeros(len(co), dtype=bool)
for spec in [x for x in SHAPES.split(";") if x.strip()]:
    kind, nums = spec.split(":")
    v = [float(x) for x in nums.split(",")]
    if kind == "cap":
        near |= seg_dist(co, Vector(v[0:3]), Vector(v[3:6])) < v[6] * 1.3
    else:
        near |= np.linalg.norm(co - np.array(v[0:3]), axis=1) < v[3] * 1.3
bmesh.ops.delete(bm, geom=[f for f in bm.faces if not all(near[v.index] for v in f.verts)], context='FACES')
bm.to_mesh(hi.data)
bm.free()
sc = bpy.context.scene
sc.render.engine = 'CYCLES'
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for dv in prefs.devices:
        dv.use = dv.type == 'OPTIX'
    sc.cycles.device = 'GPU'
except Exception:
    sc.cycles.device = 'CPU'
sc.cycles.samples = 1
sc.render.bake.use_selected_to_active = True
L = (TIP - GRIP).length
sc.render.bake.cage_extrusion = 0.01 * L
sc.render.bake.max_ray_distance = 0.03 * L
sc.render.bake.margin = 6
srcs = []
for slot in hi.material_slots:
    m = slot.material
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL')
    feeds = {k: (bsdf.inputs[k].links[0].from_socket if bsdf.inputs[k].links else bsdf.inputs[k].default_value)
             for k in ("Base Color", "Roughness", "Metallic")}
    srcs.append((nt, bsdf, out, feeds))
name = os.path.splitext(os.path.basename(OUT))[0]
pm = bpy.data.materials.new(name)
pm.use_nodes = True
pnt = pm.node_tree
pb = pnt.nodes["Principled BSDF"]
prop.data.materials.clear()
prop.data.materials.append(pm)
imgs = {}
for key, cs in (("color", 'sRGB'), ("rough", 'Non-Color'), ("metal", 'Non-Color'), ("normal", 'Non-Color')):
    imgs[key] = bpy.data.images.new("%s_%s" % (name, key), TEX, TEX, alpha=False)
    imgs[key].colorspace_settings.name = cs
tn = pnt.nodes.new("ShaderNodeTexImage")
pnt.nodes.active = tn
bpy.ops.object.select_all(action='DESELECT')
hi.select_set(True)
prop.select_set(True)
bpy.context.view_layer.objects.active = prop
for key, sock in (("color", "Base Color"), ("rough", "Roughness"), ("metal", "Metallic")):
    tn.image = imgs[key]
    for nt, bsdf, out, feeds in srcs:
        em = nt.nodes.new("ShaderNodeEmission")
        em.name = "__bake_em"
        vv = feeds[sock]
        if isinstance(vv, bpy.types.NodeSocket):
            nt.links.new(vv, em.inputs["Color"])
        elif hasattr(vv, "__len__"):
            em.inputs["Color"].default_value = (vv[0], vv[1], vv[2], 1.0)
        else:
            em.inputs["Color"].default_value = (vv, vv, vv, 1.0)
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    bpy.ops.object.bake(type='EMIT')
    for nt, bsdf, out, feeds in srcs:
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        for n in [n for n in nt.nodes if n.name.startswith("__bake_em")]:
            nt.nodes.remove(n)
tn.image = imgs["normal"]
bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT')
pnt.nodes.remove(tn)
if HUE:
    # edits made straight after a bake are lost on save: recolour a saved copy
    tmp = os.path.join(os.path.dirname(os.path.abspath(OUT)), "_%s_color.png" % name)
    imgs["color"].filepath_raw = tmp
    imgs["color"].file_format = 'PNG'
    imgs["color"].save()
    src = bpy.data.images.load(tmp, check_existing=False)
    texops.hue_remap(src, HUE, 1.0)
    img2 = bpy.data.images.new(name + "_colour", src.size[0], src.size[1], alpha=False)
    img2.pixels[:] = src.pixels[:]
    img2.pack()
    imgs["color"] = img2
    if os.path.exists(tmp):
        os.remove(tmp)
def tex(img):
    n = pnt.nodes.new("ShaderNodeTexImage")
    n.image = img
    img.pack()
    return n
pnt.links.new(tex(imgs["color"]).outputs["Color"], pb.inputs["Base Color"])
pnt.links.new(tex(imgs["rough"]).outputs["Color"], pb.inputs["Roughness"])
pnt.links.new(tex(imgs["metal"]).outputs["Color"], pb.inputs["Metallic"])
nm = pnt.nodes.new("ShaderNodeNormalMap")
pnt.links.new(tex(imgs["normal"]).outputs["Color"], nm.inputs["Color"])
pnt.links.new(nm.outputs["Normal"], pb.inputs["Normal"])
bpy.data.objects.remove(hi, do_unlink=True)
# grip to the origin, pointing +Z, at the body's game scale
k = HEIGHT / (zmax - zmin)
axis = (TIP - GRIP).normalized()
rot = axis.rotation_difference(Vector((0.0, 0.0, 1.0))).to_matrix().to_4x4()
prop.data.transform(Matrix.Scale(k, 4) @ rot @ Matrix.Translation(-GRIP))
prop.data.update()
bpy.ops.object.select_all(action='DESELECT')
prop.select_set(True)
bpy.context.view_layer.objects.active = prop
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format='GLB', export_yup=True, export_apply=True)
log("wrote %s: %d faces, %.2f m long" % (OUT, len(prop.data.polygons), L * k))

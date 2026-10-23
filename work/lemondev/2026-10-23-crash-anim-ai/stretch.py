# Blender: pose a hero body's left leg in a running stride and list the mesh pieces whose edges stretch the most.
#   blender -b --factory-startup --python stretch.py -- <body.glb> [thigh_deg shin_deg]
import bpy, bmesh, sys, math
from collections import defaultdict
from mathutils import Matrix

args = sys.argv[sys.argv.index("--") + 1:]
src = args[0]
th = float(args[1]) if len(args) > 1 else -35.0
sh = float(args[2]) if len(args) > 2 else 70.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
body = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.find_armature()][0]
rest = [v.co.copy() for v in body.data.vertices]
pb = arm.pose.bones
for side in ("L", "R"):
    s = 1 if side == "L" else -1
    pb["thigh." + side].rotation_mode = "XYZ"
    pb["shin." + side].rotation_mode = "XYZ"
    pb["thigh." + side].rotation_euler = (math.radians(th * s), 0, 0)
    pb["shin." + side].rotation_euler = (math.radians(sh * s), 0, 0)
    s = -s
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
ev = body.evaluated_get(dg)
me = ev.to_mesh()
posed = [v.co.copy() for v in me.vertices]
names = {g.index: g.name for g in body.vertex_groups}
bm = bmesh.new()
bm.from_mesh(body.data)
bm.verts.ensure_lookup_table()
comp_of = [-1] * len(bm.verts)
cid = 0
for v in bm.verts:
    if comp_of[v.index] >= 0:
        continue
    stack = [v]
    comp_of[v.index] = cid
    while stack:
        x = stack.pop()
        for e in x.link_edges:
            o = e.other_vert(x)
            if comp_of[o.index] < 0:
                comp_of[o.index] = cid
                stack.append(o)
    cid += 1
worst = defaultdict(float)
for e in bm.edges:
    a, b = e.verts[0].index, e.verts[1].index
    r = (rest[a] - rest[b]).length
    if r < 1e-4:
        continue
    k = (posed[a] - posed[b]).length / r
    c = comp_of[a]
    worst[c] = max(worst[c], k)
members = defaultdict(list)
for i, c in enumerate(comp_of):
    members[c].append(i)
for c, k in sorted(worst.items(), key=lambda kv: -kv[1])[:25]:
    vs = members[c]
    lo = [min(rest[i][j] for i in vs) for j in range(3)]
    hi = [max(rest[i][j] for i in vs) for j in range(3)]
    ws = defaultdict(float)
    for i in vs:
        for g in body.data.vertices[i].groups:
            ws[names[g.group]] += g.weight
    tot = sum(ws.values()) or 1
    top = " ".join("%s:%.0f%%" % (n, 100 * w / tot) for n, w in sorted(ws.items(), key=lambda kv: -kv[1])[:4])
    print("stretch x%.1f n=%d x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f %s" % (k, len(vs), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], top))

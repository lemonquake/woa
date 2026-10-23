# Blender: list the loose pieces of a hero body GLB with their size and the bones that move them.
#   blender -b --factory-startup --python islands.py -- <body.glb>
import bpy, bmesh, sys
from collections import defaultdict

src = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for ob in bpy.context.scene.objects:
    if ob.type != "MESH":
        continue
    me = ob.data
    names = {g.index: g.name for g in ob.vertex_groups}
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    seen = set()
    comps = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        comp = []
        seen.add(v.index)
        while stack:
            x = stack.pop()
            comp.append(x.index)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
        comps.append(comp)
    print("mesh", ob.name, "verts", len(me.vertices), "pieces", len(comps))
    comps.sort(key=len, reverse=True)
    for ci, comp in enumerate(comps[:60]):
        lo = [1e9] * 3
        hi = [-1e9] * 3
        wsum = defaultdict(float)
        for vi in comp:
            co = ob.matrix_world @ me.vertices[vi].co
            for k in range(3):
                lo[k] = min(lo[k], co[k]); hi[k] = max(hi[k], co[k])
            for g in me.vertices[vi].groups:
                wsum[names[g.group]] += g.weight
        top = sorted(wsum.items(), key=lambda kv: -kv[1])[:4]
        tot = sum(wsum.values()) or 1
        print("  piece %d n=%d x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f  %s" % (ci, len(comp), lo[0], hi[0], lo[1], hi[1],
              lo[2], hi[2], " ".join("%s:%.0f%%" % (n, 100 * w / tot) for n, w in top)))

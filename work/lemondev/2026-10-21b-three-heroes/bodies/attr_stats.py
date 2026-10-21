import bpy, sys, numpy as np
bpy.ops.wm.open_mainfile(filepath=sys.argv[sys.argv.index("--")+1])
o = next(o for o in bpy.data.objects if o.type == 'MESH')
for a in o.data.color_attributes:
    v = np.empty(len(a.data) * 4, np.float32); a.data.foreach_get("color", v); v = v.reshape(-1, 4)
    print("ATTR", a.name, a.domain, [np.round(np.percentile(v[:, i], [1, 50, 99]), 3).tolist() for i in range(4)])

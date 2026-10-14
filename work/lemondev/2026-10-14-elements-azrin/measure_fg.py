import bpy, numpy as np, time
t=time.time()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath="A:/Python/beyond-heroes/models/female_generic.obj")
o = bpy.context.selected_objects[0]
print("IMPORT", round(time.time()-t,1), o.name, len(o.data.vertices), [a.name for a in o.data.attributes][:10], tuple(round(x,3) for x in o.dimensions), tuple(round(x,3) for x in o.rotation_euler))
m = np.array(o.matrix_world)
co = np.empty(len(o.data.vertices)*3, dtype=np.float32); o.data.vertices.foreach_get("co", co); co = co.reshape(-1,3)
co = (np.c_[co, np.ones(len(co))] @ m.T)[:, :3]
print("BBOX min", co.min(0).round(3), "max", co.max(0).round(3))
np.save("A:/Python/woa/work/lemondev/2026-10-14-elements-azrin/fg_co.npy", co)

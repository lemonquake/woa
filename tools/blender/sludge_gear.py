"""Sludge's weapons, modelled in code (all original work):
  assets/weapons/cleaver.glb        butcher's cleaver (right hand)
  assets/weapons/shuriken_hook.glb  the shuriken on its chain, held in the left hand
  assets/weapons/shuriken.glb       the shuriken alone (the flying hook tip)
  assets/weapons/chain_link.glb     one chain link (the hook's chain is built from these)
Weapon convention: the grip is at the origin and the weapon points up +Y in Godot (+Z in Blender before export).

Run: "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/sludge_gear.py
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix

OUT = "A:/Python/woa/assets/weapons/"


def clean():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials):
        for d in list(coll):
            coll.remove(d)


def mat(name, color, metal, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m


def obj_from_bm(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = False
    return o


def prism(outline, depth, z0=0.0):
    """Extrude a 2D outline (x, y) in the XY plane by depth along Z, centred on z0."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z0 - depth / 2)) for x, y in outline]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    top = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=top, vec=(0, 0, depth))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def cylinder(r, h, seg=12, z0=0.0, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2,
                          depth=h, matrix=Matrix.Translation((0, 0, z0 + h / 2)))
    return bm


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def export(o, path):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    # Blender +Z becomes Godot +Y (the weapons point up their grip)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB', export_yup=True,
                              export_apply=True)
    print("[gear] wrote", path, flush=True)


def cleaver():
    steel = mat("CleaverSteel", (0.55, 0.55, 0.57), 0.9, 0.38)
    rust = mat("CleaverRust", (0.36, 0.17, 0.09), 0.4, 0.8)
    wood = mat("CleaverWood", (0.27, 0.16, 0.09), 0.0, 0.75)
    grip = obj_from_bm("grip", cylinder(0.022, 0.24, 10, -0.10), wood)
    pommel = obj_from_bm("pommel", cylinder(0.03, 0.03, 10, -0.13), rust)
    # the blade: a heavy slab offset to one side of the handle, thicker along the spine, a hole near the top
    w, h = 0.24, 0.40
    outline = [(-0.025, 0.14), (w, 0.14), (w + 0.015, 0.20), (w + 0.01, 0.14 + h), (-0.02, 0.14 + h), (-0.03, 0.3)]
    bm = prism(outline, 0.016)
    # bevel the cutting edge thinner: pull the edge-side verts toward the centre plane
    for v in bm.verts:
        if v.co.x > w - 0.02:
            v.co.z *= 0.25
    blade = obj_from_bm("blade", bm, steel)
    spine = obj_from_bm("spine", prism([(-0.03, 0.14), (0.0, 0.14), (0.0, 0.14 + h), (-0.03, 0.14 + h)], 0.026), rust)
    hole = obj_from_bm("hole", cylinder(0.022, 0.03, 12, -0.015), rust)
    hole.location = (0.05, 0.14 + h - 0.05, 0)
    # the blade parts are drawn in the XY plane: stand them up so they rise along +Z like the grip
    for part in (blade, spine, hole):
        part.matrix_world = Matrix.Rotation(math.radians(90), 4, 'X') @ part.matrix_world
    o = join([grip, pommel, blade, spine, hole], "cleaver")
    return o


def _smooth_loop(pts, n=4):
    """Catmull-Rom through a closed outline, n points per segment (smooth curved blades)."""
    out = []
    m = len(pts)
    for i in range(m):
        p0, p1, p2, p3 = (Vector(pts[(i + k) % m]) for k in (-1, 0, 1, 2))
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            out.append((q.x, q.y))
    return out


def shuriken_bm(radius=0.26, thick=0.024):
    """A four-point throwing star: broad blades swept back like a pinwheel, each with a hooked barb behind its tip
    (it bites and holds). The blades thin to sharp edges."""
    prof = [(-45, 0.30), (-30, 0.40), (-14, 0.58), (4, 0.80), (18, 1.0), (21, 0.83), (29, 0.87), (31, 0.66), (39, 0.44)]
    pts = []
    for i in range(4):
        a0 = i * 90.0
        for da, rf in prof:
            a = math.radians(a0 + da)
            pts.append((math.cos(a) * radius * rf, math.sin(a) * radius * rf))
    bm = prism(_smooth_loop(pts, 3), thick)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='BEAUTY')
    for v in bm.verts:
        r = math.hypot(v.co.x, v.co.y)
        if r > radius * 0.5:
            v.co.z *= 0.3
    return bm


def shuriken(name="shuriken"):
    steel = mat("ShurikenSteel", (0.66, 0.67, 0.7), 0.95, 0.25)
    blood = mat("ShurikenBlood", (0.34, 0.03, 0.03), 0.3, 0.4)
    dark = mat("ShurikenHub", (0.1, 0.09, 0.08), 0.8, 0.5)
    o = obj_from_bm(name, shuriken_bm(), steel)
    o.data.materials.append(blood)
    for p in o.data.polygons:
        c = p.center
        a = math.atan2(c.y, c.x)
        if math.hypot(c.x, c.y) > 0.13 and math.sin(a * 2.0 + 0.6) > 0.55:
            p.material_index = 1
    hub = bmesh.new()
    bmesh.ops.create_cone(hub, cap_ends=True, segments=24, radius1=0.06, radius2=0.06, depth=0.046)
    ring = bmesh.new()
    bmesh.ops.create_cone(ring, cap_ends=True, segments=24, radius1=0.026, radius2=0.026, depth=0.05)
    h = obj_from_bm("hub", hub, dark)
    for p in h.data.polygons:
        p.use_smooth = True
    return join([o, h], name)


def chain_link(name="chain_link", r=0.035, t=0.009):
    iron = mat("ChainIron", (0.33, 0.31, 0.3), 0.85, 0.55)
    bm = bmesh.new()
    seg, ring = 14, 6
    verts = []
    for i in range(seg):
        a = i * math.tau / seg
        # a stretched ring (oval link) in the XZ plane, long along Z
        cx, cz = math.cos(a) * r * 0.7, math.sin(a) * r * 1.25
        tan = Vector((-math.sin(a) * 0.7, 0, math.cos(a) * 1.25)).normalized()
        nrm = Vector((cx, 0, cz)).normalized()
        bi = tan.cross(nrm)
        row = []
        for j in range(ring):
            b = j * math.tau / ring
            off = nrm * math.cos(b) * t + bi * math.sin(b) * t
            row.append(bm.verts.new((cx + off.x, off.y, cz + off.z)))
        verts.append(row)
    for i in range(seg):
        for j in range(ring):
            a, b_ = verts[i][j], verts[i][(j + 1) % ring]
            c, d = verts[(i + 1) % seg][(j + 1) % ring], verts[(i + 1) % seg][j]
            bm.faces.new((a, b_, c, d))
    o = obj_from_bm(name, bm, iron)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def shuriken_hook():
    """Held in the left fist: the shuriken gripped by its hub just past the knuckles, its chain running back to the
    wrist (where the coil round the forearm takes over)."""
    iron = mat("HookIron", (0.3, 0.29, 0.28), 0.85, 0.55)
    links = []
    for k in range(3):
        l = chain_link("l%d" % k)
        l.location = (0, 0, -0.02 - k * 0.07)
        l.rotation_euler = (0, 0, (math.pi / 2) * (k % 2))
        links.append(l)
    s = shuriken("hs")
    s.scale = (0.9, 0.9, 0.9)
    s.location = (0, 0, 0.16)
    s.rotation_euler = (math.radians(90), 0, 0)         # its flat side faces the camera when the fist is upright
    o = join(links + [s], "shuriken_hook")
    return o


def main():
    clean()
    export(cleaver(), OUT + "cleaver.glb")
    clean()
    export(shuriken_hook(), OUT + "shuriken_hook.glb")
    clean()
    s = shuriken()
    export(s, OUT + "shuriken.glb")
    clean()
    export(chain_link(), OUT + "chain_link.glb")


main()

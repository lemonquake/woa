"""Warriors of Aether: procedural building models (towers, barracks, ancients, fountains, effigies) for both factions.

Run: "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/buildings.py
Writes assets/buildings/<name>.glb. Metres, Z up in Blender (Y up in glTF), origin at the centre of the footprint on
the ground. Materials are named WOA_<Kind>; the game replaces them with its triplanar stone / metal / crystal shaders,
so no UV unwrapping is needed.
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Vector, Matrix

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "buildings")
os.makedirs(OUT, exist_ok=True)

MATS = {}


def mat(name, color, metallic=0.0, rough=0.7, emit=None):
    key = name
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = 3.0
    MATS[key] = m
    return m


def palette(faction):
    if faction == "dawn":
        return {
            "stone": mat("WOA_StoneLight", (0.78, 0.74, 0.66)),
            "stone2": mat("WOA_StoneWarm", (0.66, 0.58, 0.48)),
            "trim": mat("WOA_Gold", (1.0, 0.76, 0.32), 1.0, 0.32),
            "roof": mat("WOA_RoofBlue", (0.16, 0.32, 0.58), 0.0, 0.55),
            "crystal": mat("WOA_CrystalDawn", (1.0, 0.86, 0.45), 0.0, 0.1, (1.0, 0.82, 0.38)),
            "wood": mat("WOA_Wood", (0.42, 0.28, 0.16)),
            "cloth": mat("WOA_ClothDawn", (0.85, 0.72, 0.38), 0.0, 0.8),
        }
    return {
        "stone": mat("WOA_StoneDark", (0.24, 0.2, 0.22)),
        "stone2": mat("WOA_StoneAsh", (0.36, 0.3, 0.3)),
        "trim": mat("WOA_IronRed", (0.48, 0.12, 0.1), 0.9, 0.38),
        "roof": mat("WOA_RoofDark", (0.18, 0.08, 0.12), 0.0, 0.5),
        "crystal": mat("WOA_CrystalDusk", (0.95, 0.18, 0.22), 0.0, 0.1, (1.0, 0.16, 0.2)),
        "wood": mat("WOA_Bone", (0.78, 0.72, 0.6)),
        "cloth": mat("WOA_ClothDusk", (0.42, 0.08, 0.14), 0.0, 0.8),
    }


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def new_obj(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = False
    return ob


def bevel(ob, width=0.03, segs=2):
    m = ob.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segs
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(35)
    return ob


def cyl(name, r1, r2, h, sides, material, z=0.0, x=0.0, y=0.0, rot=0.0, bev=0.03, cap=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=sides, radius1=r1, radius2=r2, depth=h,
                          matrix=Matrix.Translation((x, y, z + h / 2)) @ Matrix.Rotation(rot, 4, "Z"))
    ob = new_obj(name, bm, material)
    if bev > 0:
        bevel(ob, bev)
    return ob


def box(name, sx, sy, sz, material, x=0.0, y=0.0, z=0.0, rot=0.0, bev=0.03):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=bm.verts)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rot, 3, "Z"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(x, y, z + sz / 2), verts=bm.verts)
    ob = new_obj(name, bm, material)
    if bev > 0:
        bevel(ob, bev)
    return ob


def gem(name, r, h, material, z, x=0.0, y=0.0, sides=6, tilt=0.0):
    """An elongated crystal: two pyramids joined at the girdle."""
    bm = bmesh.new()
    top = bm.verts.new((0, 0, h * 0.62))
    bot = bm.verts.new((0, 0, -h * 0.38))
    ring = [bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0)) for a in [i * math.tau / sides for i in range(sides)]]
    for i in range(sides):
        bm.faces.new((ring[i], ring[(i + 1) % sides], top))
        bm.faces.new((ring[(i + 1) % sides], ring[i], bot))
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(tilt, 3, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(x, y, z), verts=bm.verts)
    return new_obj(name, bm, material)


def spike(name, r, h, material, x, y, z, dir_vec):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=5, radius1=r, radius2=0.0, depth=h,
                          matrix=Matrix.Translation((0, 0, h / 2)))
    d = Vector(dir_vec).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix()
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(x, y, z), verts=bm.verts)
    return new_obj(name, bm, material)


def ring_of(n, radius, z, make, phase=0.0):
    out = []
    for i in range(n):
        a = phase + i * math.tau / n
        out.append(make(i, math.cos(a) * radius, math.sin(a) * radius, z, a))
    return out


def export(name):
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            bpy.context.view_layer.objects.active = ob
            for m in list(ob.modifiers):
                bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.ops.object.select_all(action="SELECT")
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")
    print("wrote", path)


# ---- Towers ---------------------------------------------------------------------------------------------------------

def banner(name, material, x, y, z, w, h, rot):
    """A hanging cloth banner with a swallow-tail end, facing outward (rot = facing angle)."""
    bm = bmesh.new()
    pts = [(-w / 2, 0, 0), (w / 2, 0, 0), (w / 2, 0, -h), (0, 0, -h * 0.82), (-w / 2, 0, -h)]
    vs = [bm.verts.new(p) for p in pts]
    bm.faces.new(vs)
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(rot - math.pi / 2, 3, "Z"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(x, y, z), verts=bm.verts)
    ob = new_obj(name, bm, material)
    m = ob.modifiers.new("solid", "SOLIDIFY")
    m.thickness = 0.03
    return ob


def tower(faction):
    reset()
    P = palette(faction)
    dusk = faction == "dusk"
    sides = 8
    # stepped plinth with a ring of steps
    cyl("plinth", 1.9, 1.8, 0.28, sides, P["stone2"], rot=math.pi / 8, bev=0.05)
    cyl("plinth2", 1.55, 1.48, 0.3, sides, P["stone"], z=0.28, rot=math.pi / 8, bev=0.05)
    cyl("shaft", 1.08, 0.8, 3.9, sides, P["stone"], z=0.58, rot=math.pi / 8, bev=0.04)
    for i, z in enumerate([1.25, 2.35, 3.45]):
        r = 1.08 - (z - 0.58) / 3.9 * 0.28 + 0.05
        cyl("band%d" % i, r, r - 0.01, 0.14, sides, P["trim"] if i == 1 else P["stone2"], z=z, rot=math.pi / 8, bev=0.0, cap=False)
    # four tall buttress fins flaring at the base
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        bm = bmesh.new()
        prof = [(0.0, 0.0), (1.05, 0.0), (0.95, 0.5), (0.45, 1.6), (0.18, 3.6), (0.0, 3.9)]
        t = 0.16
        front = [bm.verts.new((px, -t, pz)) for px, pz in prof]
        back = [bm.verts.new((px, t, pz)) for px, pz in prof]
        bm.faces.new(front)
        bm.faces.new(list(reversed(back)))
        n = len(prof)
        for k in range(n):
            bm.faces.new((front[k], front[(k + 1) % n], back[(k + 1) % n], back[k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(a, 3, "Z"), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(math.cos(a) * 0.72, math.sin(a) * 0.72, 0.58), verts=bm.verts)
        bevel(new_obj("fin%d" % i, bm, P["stone2"]), 0.03)
        if dusk:
            spike("finspike%d" % i, 0.12, 0.9, P["trim"], math.cos(a) * 1.2, math.sin(a) * 1.2, 1.3, (math.cos(a), math.sin(a), 0.9))
    # crown: a wide open ring so the crystal is seen from above
    cyl("crown", 1.25, 1.32, 0.34, sides, P["stone2"], z=4.48, rot=math.pi / 8, bev=0.04)
    cyl("floor", 1.02, 1.02, 0.06, 16, P["stone"], z=4.82, bev=0.0)
    cyl("rim", 0.62, 0.62, 0.08, 16, P["trim"], z=4.84, bev=0.0, cap=False)
    if dusk:
        ring_of(8, 1.18, 4.82, lambda i, x, y, z, a: spike("crownspike%d" % i, 0.16, 1.35 + (i % 2) * 0.5, P["trim"], x, y, z, (x * 0.35, y * 0.35, 1)))
        for i in range(10):
            a = i * math.tau / 10 + 0.2
            zz = 0.9 + (i % 5) * 0.7
            r = 1.08 - (zz - 0.58) / 3.9 * 0.28
            spike("sspike%d" % i, 0.09, 0.55, P["trim"], math.cos(a) * r, math.sin(a) * r, zz, (math.cos(a), math.sin(a), 0.35))
    else:
        ring_of(8, 1.18, 4.82, lambda i, x, y, z, a: box("merlon%d" % i, 0.34, 0.22, 0.42, P["stone"], x, y, z, a + math.pi / 2))
        ring_of(4, 1.2, 5.24, lambda i, x, y, z, a: gem("cgem%d" % i, 0.1, 0.38, P["trim"], z + 0.15, x, y), math.pi / 4)
    gem("crystal", 0.46, 1.5, P["crystal"], 6.1)
    for k, a in enumerate([0.0, math.pi]):
        banner("banner%d" % k, P["cloth"], math.cos(a + 0.4) * 1.22, math.sin(a + 0.4) * 1.22, 4.5, 0.55, 1.4, a + 0.4)
    export("tower_" + faction)


# ---- Barracks -------------------------------------------------------------------------------------------------------

def barracks(faction, kind):
    reset()
    P = palette(faction)
    dusk = faction == "dusk"
    w, d = (3.4, 2.6) if kind == "melee" else (2.8, 2.8)
    box("found", w + 0.6, d + 0.6, 0.3, P["stone2"], bev=0.05)
    if kind == "melee":
        box("hall", w, d, 1.9, P["stone"], z=0.3)
        # pitched roof
        bm = bmesh.new()
        h = 1.25
        vs = [bm.verts.new(v) for v in [(-w / 2 - 0.2, -d / 2 - 0.2, 0), (w / 2 + 0.2, -d / 2 - 0.2, 0), (w / 2 + 0.2, d / 2 + 0.2, 0),
                                         (-w / 2 - 0.2, d / 2 + 0.2, 0), (-w / 2 - 0.2, 0, h), (w / 2 + 0.2, 0, h)]]
        for f in [(0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)]:
            bm.faces.new([vs[k] for k in f])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.translate(bm, vec=(0, 0, 2.2), verts=bm.verts)
        new_obj("roof", bm, P["roof"])
        box("ridge", w + 0.5, 0.14, 0.14, P["trim"], z=3.38)
        for sx in (-1, 1):
            for sy in (-1, 1):
                cyl("corner%d%d" % (sx, sy), 0.3, 0.26, 2.6, 8, P["stone2"], z=0.3, x=sx * w / 2, y=sy * d / 2)
                if dusk:
                    spike("cs%d%d" % (sx, sy), 0.1, 0.8, P["trim"], sx * w / 2, sy * d / 2, 2.9, (sx * 0.3, sy * 0.3, 1))
                else:
                    gem("cg%d%d" % (sx, sy), 0.12, 0.45, P["trim"], 3.05, sx * w / 2, sy * d / 2)
        box("door", 0.9, 0.12, 1.3, P["wood"], y=-d / 2 - 0.02, z=0.3, bev=0.02)
        box("lintel", 1.2, 0.2, 0.18, P["trim"], y=-d / 2 - 0.04, z=1.6)
        box("banner", 0.55, 0.04, 1.0, P["cloth"], y=-d / 2 - 0.05, z=1.85, bev=0.0)
    else:
        cyl("hall", 1.45, 1.3, 2.0, 8, P["stone"], z=0.3, rot=math.pi / 8)
        cyl("band", 1.4, 1.38, 0.18, 8, P["trim"], z=1.6, rot=math.pi / 8, bev=0.0, cap=False)
        if dusk:
            cyl("dome", 1.55, 0.2, 1.7, 8, P["roof"], z=2.6, rot=math.pi / 8, bev=0.0)
            ring_of(8, 1.42, 2.55, lambda i, x, y, z, a: spike("ds%d" % i, 0.1, 0.9, P["trim"], x, y, z, (x, y, 0.8)))
        else:
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1.45)
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -0.01], context="VERTS")
            bmesh.ops.translate(bm, vec=(0, 0, 2.6), verts=bm.verts)
            new_obj("dome", bm, P["roof"])
            gem("top", 0.16, 0.7, P["trim"], 4.25)
        gem("orb", 0.3, 0.8, P["crystal"], 4.9 if not dusk else 4.6)
        box("door", 0.8, 0.12, 1.2, P["wood"], y=-1.33, z=0.3, bev=0.02)
    export("rax_%s_%s" % (kind, faction))


# ---- Ancient --------------------------------------------------------------------------------------------------------

def ancient(faction):
    reset()
    P = palette(faction)
    dusk = faction == "dusk"
    cyl("tier1", 4.6, 4.4, 0.45, 12, P["stone2"], rot=math.pi / 12, bev=0.06)
    cyl("tier2", 3.7, 3.55, 0.45, 12, P["stone"], z=0.45, rot=math.pi / 12, bev=0.05)
    cyl("tier3", 2.75, 2.6, 0.5, 12, P["stone2"], z=0.9, rot=math.pi / 12, bev=0.05)
    cyl("trimring", 2.8, 2.8, 0.12, 12, P["trim"], z=1.36, rot=math.pi / 12, bev=0.0, cap=False)
    # stairs on four sides
    for i in range(4):
        a = i * math.pi / 2
        for k in range(3):
            d = 4.45 - k * 0.45
            box("step%d_%d" % (i, k), 1.6, 0.5, 0.15 + k * 0.15, P["stone"], math.cos(a) * d, math.sin(a) * d, 0.0, a + math.pi / 2, 0.02)
    # pylons around the dais, each topped with a small crystal (Dawn) or a hooked spike (Dusk)
    def mono(i, x, y, z, a):
        h = 3.2 if i % 2 == 0 else 2.5
        box("mono%d" % i, 0.55, 0.42, h, P["stone"], x, y, z, a + math.pi / 2, 0.05)
        box("monocap%d" % i, 0.7, 0.55, 0.16, P["trim"], x, y, z + h, a + math.pi / 2, 0.02)
        if dusk:
            spike("mspike%d" % i, 0.2, 1.3, P["trim"], x, y, z + h + 0.1, (-x * 0.12, -y * 0.12, 1))
        else:
            gem("mgem%d" % i, 0.2, 0.75, P["crystal"], z + h + 0.55, x, y)
    ring_of(8, 3.95, 0.45, mono, math.pi / 8)
    # central pedestal and bowl that cradle the floating heart
    cyl("pedestal", 1.25, 0.95, 1.5, 12, P["stone"], z=1.4, bev=0.04)
    cyl("bowl", 1.45, 1.3, 0.3, 16, P["stone2"], z=2.9, bev=0.03)
    cyl("bowlrim", 1.5, 1.5, 0.1, 16, P["trim"], z=3.12, bev=0.0, cap=False)
    if dusk:
        # claws curling up around the heart
        for i in range(5):
            a = i * math.tau / 5
            for k in range(3):
                r = 1.55 - k * 0.32
                z = 3.3 + k * 1.1
                spike("claw%d_%d" % (i, k), 0.2 - k * 0.04, 1.3, P["stone"] if k < 2 else P["trim"],
                      math.cos(a) * r, math.sin(a) * r, z, (-math.cos(a) * (0.2 + k * 0.35), -math.sin(a) * (0.2 + k * 0.35), 1))
    gem("heart", 1.15, 3.4, P["crystal"], 5.4, sides=8)
    export("ancient_" + faction)


# ---- Fountain and effigy ------------------------------------------------------------------------------------------

def fountain(faction):
    reset()
    P = palette(faction)
    cyl("basin", 3.0, 3.0, 0.55, 16, P["stone2"], bev=0.06)
    cyl("water", 2.7, 2.7, 0.5, 16, mat("WOA_Water", (0.2, 0.55, 0.7), 0.0, 0.05, (0.15, 0.45, 0.6)), z=0.08, bev=0.0)
    cyl("pillar", 0.45, 0.35, 2.8, 8, P["stone"], z=0.5, bev=0.04)
    cyl("bowl", 0.95, 0.4, 0.4, 12, P["trim"], z=3.2, bev=0.03)
    gem("orb", 0.45, 1.2, P["crystal"], 4.2)
    ring_of(6, 2.85, 0.55, lambda i, x, y, z, a: cyl("post%d" % i, 0.16, 0.14, 0.9, 6, P["stone"], z, x, y))
    export("fountain_" + faction)


def effigy(faction):
    reset()
    P = palette(faction)
    box("pedestal", 1.3, 1.3, 0.45, P["stone2"], bev=0.05)
    box("pedestal2", 1.0, 1.0, 0.3, P["stone"], z=0.45, bev=0.04)
    cyl("obelisk", 0.42, 0.24, 3.0, 4, P["stone"], z=0.75, rot=math.pi / 4, bev=0.03)
    if faction == "dusk":
        spike("tip", 0.25, 0.9, P["trim"], 0, 0, 3.75, (0, 0, 1))
        for i in range(4):
            a = i * math.pi / 2 + math.pi / 4
            spike("s%d" % i, 0.08, 0.6, P["trim"], math.cos(a) * 0.3, math.sin(a) * 0.3, 1.6, (math.cos(a), math.sin(a), 0.6))
    else:
        gem("tip", 0.28, 0.9, P["crystal"], 4.2)
    export("effigy_" + faction)


def shop():
    reset()
    P = palette("dawn")
    box("floor", 2.8, 2.2, 0.15, P["wood"], bev=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl("pole%d%d" % (sx, sy), 0.07, 0.07, 2.3, 6, P["wood"], 0.15, sx * 1.25, sy * 0.95, bev=0.0)
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in [(-1.6, -1.3, 0), (1.6, -1.3, 0), (1.6, 1.3, 0), (-1.6, 1.3, 0), (0, 0, 0.9)]]
    for f in [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]:
        bm.faces.new([vs[k] for k in f])
    bmesh.ops.translate(bm, vec=(0, 0, 2.4), verts=bm.verts)
    new_obj("canopy", bm, mat("WOA_ClothShop", (0.75, 0.2, 0.15), 0.0, 0.85))
    box("counter", 2.2, 0.5, 0.9, P["wood"], y=-0.6, z=0.15, bev=0.02)
    for i in range(5):
        box("crate%d" % i, 0.4, 0.4, 0.4, P["wood"], -0.9 + i * 0.45, 0.6, 0.15 + (i % 2) * 0.0, i * 0.3, 0.02)
    export("shop")


if __name__ == "__main__":
    random.seed(7)
    for f in ("dawn", "dusk"):
        tower(f)
        barracks(f, "melee")
        barracks(f, "ranged")
        ancient(f)
        fountain(f)
        effigy(f)
    shop()

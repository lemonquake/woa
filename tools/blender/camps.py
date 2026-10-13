"""Warriors of Aether: neutral camp props, so a camp reads as a camp at a glance: a hide tent, a round hut, a carved
totem with cloth strips, a drying rack with hides, a row of sharpened stakes, a log seat, a cooking spit and sacks.

Run: "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/camps.py
Writes assets/props/camp_<name>.glb. Metres, Z up in Blender (Y up in glTF), origin at the centre of the footprint on
the ground. Materials are named CAMP_<Kind>; the game swaps them for its textured ones (wood grain, hide, cloth tinted
by camp size), so no UV unwrapping is needed.
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Vector, Matrix

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "props")
os.makedirs(OUT, exist_ok=True)
MATS = {}
rng = random.Random(7)


def mat(name, color, rough=0.8):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    MATS[name] = m
    return m


def M(kind):
    return {
        "wood": lambda: mat("CAMP_Wood", (0.36, 0.25, 0.15)),
        "end": lambda: mat("CAMP_WoodEnd", (0.62, 0.48, 0.32)),
        "hide": lambda: mat("CAMP_Hide", (0.5, 0.36, 0.23)),
        "hide2": lambda: mat("CAMP_Hide2", (0.34, 0.24, 0.16)),
        "bone": lambda: mat("CAMP_Bone", (0.86, 0.81, 0.68), 0.6),
        "cloth": lambda: mat("CAMP_Cloth", (0.8, 0.66, 0.26)),
        "rope": lambda: mat("CAMP_Rope", (0.55, 0.47, 0.33)),
        "burlap": lambda: mat("CAMP_Burlap", (0.6, 0.52, 0.37)),
        "meat": lambda: mat("CAMP_Meat", (0.42, 0.14, 0.09), 0.5),
        "stone": lambda: mat("CAMP_Stone", (0.45, 0.43, 0.4), 0.9),
    }[kind]()


def reset():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def new_obj(name, bm, material, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = smooth
    return ob


def pole(name, a, b, r, material, sides=7, taper=1.0, tip=0.0):
    """A round pole from a to b (taper: radius factor at b; tip: a pointed end of this length past b)."""
    a = Vector(a)
    b = Vector(b)
    d = b - a
    length = d.length
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=r, radius2=r * taper,
                          depth=length, matrix=Matrix.Translation((0, 0, length / 2)))
    if tip > 0:
        top = [v for v in bm.verts if v.co.z > length / 2 - 1e-4]
        apex = bm.verts.new((0, 0, length + tip))
        cap = [f for f in bm.faces if all(v in top for v in f.verts)]
        bmesh.ops.delete(bm, geom=cap, context="FACES_ONLY")
        top.sort(key=lambda v: math.atan2(v.co.y, v.co.x))
        for i in range(len(top)):
            bm.faces.new((top[i], top[(i + 1) % len(top)], apex))
    # a little irregularity so poles look cut from branches
    for v in bm.verts:
        v.co.x += rng.uniform(-0.12, 0.12) * r
        v.co.y += rng.uniform(-0.12, 0.12) * r
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(a) @ rot, verts=bm.verts)
    return new_obj(name, bm, material, smooth=True)


def panel(name, corners, nu, nv, material, sag=0.0, jag=0.0, thick=0.03, sag_dir=None):
    """A cloth / hide sheet over four corners (a, b, c, d in order), subdivided, sagging along sag_dir in the middle,
    with a ragged far edge (the c-d side)."""
    a, b, c, d = [Vector(p) for p in corners]
    bm = bmesh.new()
    grid = []
    sd = Vector(sag_dir) if sag_dir else Vector((0, 0, -1))
    for j in range(nv + 1):
        row = []
        for i in range(nu + 1):
            u = i / nu
            v = j / nv
            p = (a.lerp(b, u)).lerp(d.lerp(c, u), v)
            p += sd * sag * math.sin(math.pi * u) * math.sin(math.pi * v)
            if j == nv and jag > 0:
                p += (c - b).normalized() * rng.uniform(-jag, jag * 0.4)
            p += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.01
            row.append(bm.verts.new(p))
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    ob = new_obj(name, bm, material, smooth=True)
    if thick > 0:
        s = ob.modifiers.new("solid", "SOLIDIFY")
        s.thickness = thick
    return ob


def blob(name, r, sx, sy, sz, material, x, y, z, rough=0.08, sub=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-rough, rough)
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
        v.co += Vector((x, y, z))
    return new_obj(name, bm, material, smooth=True)


def ring(name, r, minor, z, material, x=0.0, y=0.0):
    bm = bmesh.new()
    n = 14
    m = 5
    verts = []
    for i in range(n):
        a = i * math.tau / n
        row = []
        for k in range(m):
            b = k * math.tau / m
            rr = r + math.cos(b) * minor
            row.append(bm.verts.new((x + math.cos(a) * rr, y + math.sin(a) * rr, z + math.sin(b) * minor)))
        verts.append(row)
    for i in range(n):
        for k in range(m):
            bm.faces.new((verts[i][k], verts[(i + 1) % n][k], verts[(i + 1) % n][(k + 1) % m], verts[i][(k + 1) % m]))
    return new_obj(name, bm, material, smooth=True)


def export(name):
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            bpy.context.view_layer.objects.active = ob
            for m in list(ob.modifiers):
                bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.ops.object.select_all(action="SELECT")
    path = os.path.join(OUT, "camp_" + name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")
    print("wrote", path)


# ---- Props ----------------------------------------------------------------------------------------------------------

def tent():
    """An A-frame hide tent, 2.6 m long, open at the front (+x) with the flap thrown back."""
    W = M("wood")
    L, H, B = 1.3, 1.75, 1.05
    pole("ridge", (-L - 0.15, 0, H), (L + 0.2, 0, H), 0.045, W)
    for x in (-L, L):
        pole("x1", (x, -B * 0.95, 0), (x, 0.28, H + 0.32), 0.04, W)
        pole("x2", (x, B * 0.95, 0), (x, -0.28, H + 0.32), 0.04, W)
    for s in (-1, 1):
        panel("roof", [(-L - 0.05, 0, H + 0.03), (L + 0.08, 0, H + 0.03), (L + 0.08, s * B, 0.06), (-L - 0.05, s * B, 0.06)],
              8, 6, M("hide"), sag=0.07, jag=0.08, sag_dir=(0, -s * 0.5, -0.8))
        # guy rope to a stake
        pole("rope", (L * 0.6, s * B, 0.1), (L * 0.75, s * (B + 0.55), 0.04), 0.008, M("rope"), sides=4)
        pole("stake", (L * 0.75, s * (B + 0.55), -0.05), (L * 0.75, s * (B + 0.55), 0.12), 0.025, W, tip=0.0)
    # back wall and the front flap thrown open
    panel("back", [(-L, -B, 0.05), (-L, B, 0.05), (-L, 0.0, H), (-L, 0.0, H)], 6, 4, M("hide"), sag=0.04, sag_dir=(1, 0, 0))
    panel("flap", [(L + 0.05, 0.0, H), (L + 0.05, B * 0.9, 0.08), (L + 0.55, B * 1.15, 0.1), (L + 0.35, 0.15, H - 0.2)],
          4, 4, M("hide2"), sag=0.05)
    # a bedroll at the opening
    blob("roll", 0.16, 3.2, 1.0, 0.8, M("burlap"), L * 0.6, -0.35, 0.12)
    export("tent")


def hut():
    """A round hide hut on a cone of poles, 2.4 m wide and 3 m tall, with an opening."""
    W = M("wood")
    n = 9
    R = 1.25
    apex = Vector((0, 0, 2.6))
    for i in range(n):
        a = i * math.tau / n + rng.uniform(-0.08, 0.08)
        base = Vector((math.cos(a) * R, math.sin(a) * R, 0))
        top = apex + (apex - base).normalized() * rng.uniform(0.35, 0.55)
        pole("p", base, top, 0.045, W, taper=0.7)
    bm = bmesh.new()
    seg = 18
    rows = 6
    grid = []
    for j in range(rows + 1):
        v = j / rows
        z = 2.3 * v
        r = R * (1 - v) + 0.18 * v + 0.03
        row = []
        for i in range(seg + 1):
            a = i * math.tau / seg
            if i == seg:
                row.append(row[0])
                continue
            rr = r + rng.uniform(-0.03, 0.03) + 0.04 * math.sin(a * 3 + v * 4)
            zz = z + (rng.uniform(-0.08, 0.03) if j == 0 else 0)
            row.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, max(0.02, zz))))
        grid.append(row)
    for j in range(rows):
        for i in range(seg):
            # the doorway: two segments open low down
            if j < 3 and i in (0, 1):
                continue
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    ob = new_obj("cover", bm, M("hide"), smooth=True)
    ob.modifiers.new("solid", "SOLIDIFY").thickness = 0.03
    for z in (1.4, 2.05):
        r = R * (1 - z / 2.3) + 0.18 * (z / 2.3) + 0.06
        ring("band", r, 0.022, z, M("rope"))
    # a hide hung over the door
    panel("door", [(R * 0.98, 0.05, 1.15), (R * 0.9, 0.55, 1.15), (R * 1.15, 0.6, 0.05), (R * 1.2, 0.0, 0.05)], 3, 4,
          M("hide2"), sag=0.04, jag=0.06)
    export("hut")


def totem():
    """A carved pole with a horned skull, a crossbar with two hanging cloth strips and feathers: the camp's marker."""
    W = M("wood")
    pole("pole", (0, 0, -0.1), (0, 0, 3.0), 0.12, W, sides=8, taper=0.85)
    for z in (0.5, 1.1, 1.75):
        ring("carve", 0.13, 0.03, z, M("end"))
    pole("bar", (-0.75, 0, 2.35), (0.75, 0, 2.35), 0.05, W)
    for x in (-0.68, 0.68):
        pole("tie", (x, 0, 2.38), (x, 0, 2.27), 0.06, M("rope"), sides=6)
        top = 2.3
        panel("strip", [(x - 0.17, 0.03, top), (x + 0.17, 0.03, top), (x + 0.15, 0.06, top - 1.25), (x - 0.15, 0.06, top - 1.25)],
              2, 8, M("cloth"), sag=0.05, jag=0.12, thick=0.012, sag_dir=(0, 1, 0))
    # skull with horns at the top
    blob("skull", 0.2, 1.0, 1.15, 0.9, M("bone"), 0, 0.02, 3.12, rough=0.05)
    blob("jaw", 0.13, 0.9, 1.0, 0.55, M("bone"), 0, 0.12, 2.96, rough=0.05)
    for s in (-1, 1):
        prev = Vector((s * 0.14, 0, 3.2))
        for k in range(4):
            nxt = prev + Vector((s * 0.12, 0, 0.09 - 0.05 * k))
            pole("horn", prev, nxt, 0.055 * (1 - k * 0.22), M("bone"), sides=6, taper=0.75)
            prev = nxt
        blob("eye", 0.045, 1, 1, 1, mat("CAMP_Dark", (0.05, 0.04, 0.04)), s * 0.07, 0.19, 3.15, rough=0.0, sub=1)
    for k in range(3):
        a = k * 0.6 - 0.6
        base = Vector((math.sin(a) * 0.1, math.cos(a) * 0.1, 2.75))
        pole("feather", base, base + Vector((math.sin(a) * 0.25, math.cos(a) * 0.1, -0.35)), 0.025,
             mat("CAMP_Feather", (0.16, 0.13, 0.12)), sides=4, taper=0.2)
    export("totem")


def rack():
    """A drying rack: two A-frames, a crossbar and hides hung over it."""
    W = M("wood")
    for x in (-1.1, 1.1):
        pole("a1", (x, -0.45, 0), (x, 0.04, 1.75), 0.04, W)
        pole("a2", (x, 0.45, 0), (x, -0.04, 1.75), 0.04, W)
    pole("bar", (-1.25, 0, 1.66), (1.25, 0, 1.66), 0.04, W)
    for x0, w, m in ((-0.95, 0.85, "hide"), (0.15, 0.75, "hide2")):
        for s in (-1, 1):
            panel("hang", [(x0, 0.0, 1.68), (x0 + w, 0.0, 1.68), (x0 + w - 0.05, s * 0.22, 0.75 + rng.uniform(0, 0.25)),
                           (x0 + 0.05, s * 0.22, 0.7 + rng.uniform(0, 0.25))], 4, 5, M(m), sag=0.04, jag=0.12, thick=0.02,
                  sag_dir=(0, s, 0))
    export("rack")


def stakes():
    """Six sharpened stakes leaning out, bound with rope: a stretch of palisade 2.6 m wide."""
    W = M("wood")
    for i in range(6):
        x = -1.25 + i * 0.5 + rng.uniform(-0.05, 0.05)
        h = rng.uniform(1.55, 2.0)
        r = rng.uniform(0.085, 0.115)
        lean = rng.uniform(0.15, 0.3)
        pole("stake", (x, 0, -0.15), (x, lean, h), r, W, sides=7, tip=0.32)
    for z, y in ((0.55, 0.06), (1.15, 0.13)):
        pole("rope", (-1.4, y, z), (1.4, y, z), 0.022, M("rope"), sides=5)
    export("stakes")


def log_seat():
    W = M("wood")
    ob = pole("log", (-0.85, 0, 0.22), (0.85, 0, 0.22), 0.2, W, sides=10)
    for x in (-0.86, 0.86):
        pole("end", (x * 0.99, 0, 0.22), (x * 1.01, 0, 0.22), 0.19, M("end"), sides=10)
    pole("stub", (0.3, 0.12, 0.35), (0.42, 0.32, 0.5), 0.045, W, taper=0.5)
    export("log")


def spit():
    """A cooking spit: two forked sticks and a bar with a roast."""
    W = M("wood")
    for x in (-0.65, 0.65):
        pole("stick", (x, 0, -0.1), (x, 0, 0.8), 0.035, W)
        pole("fork1", (x, 0, 0.7), (x, 0.12, 0.92), 0.025, W)
        pole("fork2", (x, 0, 0.7), (x, -0.12, 0.92), 0.025, W)
    pole("bar", (-0.8, 0, 0.84), (0.85, 0, 0.84), 0.022, W)
    blob("roast", 0.18, 1.6, 1.0, 0.95, M("meat"), 0.05, 0, 0.82, rough=0.15)
    pole("handle", (0.85, 0, 0.84), (0.95, 0.15, 0.84), 0.02, W)
    export("spit")


def sacks():
    for x, y, s in ((0.0, 0.0, 1.0), (0.42, 0.12, 0.85), (0.18, -0.36, 0.8), (0.22, 0.0, 0.7)):
        z = 0.22 * s + (0.36 if s == 0.7 else 0.0)
        blob("sack", 0.25 * s, 1.0, 0.95, 1.15, M("burlap"), x, y, z, rough=0.12)
        ring("tie", 0.07 * s, 0.018, z + 0.27 * s, M("rope"), x, y)
        blob("neck", 0.07 * s, 1, 1, 1.4, M("burlap"), x, y, z + 0.33 * s, rough=0.2, sub=1)
    export("sacks")


for f in (tent, hut, totem, rack, stakes, log_seat, spit, sacks):
    reset()
    f()

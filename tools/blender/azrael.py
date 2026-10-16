"""Azrael's scythe and wings, modelled in code (all original work, 2026-10-17):
  assets/weapons/scythe.glb                  the great scythe: a carved dark-wood shaft with leather wraps and old
                                             silver fittings, a long crescent blade with an etched band and a bright
                                             edge, a curled back spike
  assets/characters/hero/azrael_wings.glb    two feathered wings, each three jointed parts (arm, fore, hand) so the
                                             game can spread, fold and beat them; white with a grey-blue base
                                             (vertex colours), primaries, secondaries and three rows of coverts
Weapon convention: the grip is at the origin and the weapon points up +Y in Godot (+Z in Blender before export).
Wings: each wing's root is its shoulder joint; the right wing spreads along +X, the feathers hang toward -Z and
sweep back (+Y in Blender is behind the hero, who faces -Y).

Run: "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/azrael.py
"""
import bpy
import bmesh
import math
import random
from mathutils import Vector, Matrix

ROOT = "A:/Python/woa/"
SCYTHE = ROOT + "assets/weapons/scythe.glb"
WINGS = ROOT + "assets/characters/hero/azrael_wings.glb"


def clean():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials):
        for d in list(coll):
            coll.remove(d)


def mat(name, color, metal, rough, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit[0], 1.0)
        b.inputs["Emission Strength"].default_value = emit[1]
    return m


def obj(name, bm, mats, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = smooth
    return o


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def lathe(profile, seg=20, twist=None, mat_index=0):
    """A surface of revolution round Z from (z, r) pairs; twist(z, a) -> radius factor (carved grooves)."""
    bm = bmesh.new()
    rings = []
    for z, r in profile:
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            f = twist(z, a) if twist else 1.0
            ring.append(bm.verts.new((math.cos(a) * r * f, math.sin(a) * r * f, z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(seg):
            f = bm.faces.new((rings[k][i], rings[k][(i + 1) % seg], rings[k + 1][(i + 1) % seg], rings[k + 1][i]))
            f.material_index = mat_index
    for ring, rev in ((rings[0], True), (rings[-1], False)):
        f = bm.faces.new(list(reversed(ring)) if rev else ring)
        f.material_index = mat_index
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ---- the scythe -----------------------------------------------------------------------------------------------------

def scythe():
    wood = mat("ScytheWood", (0.085, 0.06, 0.045), 0.0, 0.62)
    leather = mat("ScytheLeather", (0.05, 0.035, 0.03), 0.0, 0.8)
    iron = mat("ScytheIron", (0.42, 0.41, 0.45), 0.6, 0.45)
    # metals stay light and only half metallic: the game's dark stages and battlefield have little to reflect, so a
    # mirror steel renders black
    steel = mat("ScytheSteel", (0.78, 0.8, 0.85), 0.55, 0.32)
    etch = mat("ScytheEtch", (0.2, 0.2, 0.24), 0.6, 0.55)
    edge = mat("ScytheEdge", (0.98, 0.99, 1.0), 0.45, 0.18, ((0.85, 0.9, 1.0), 0.6))
    parts = []
    # the shaft: gnarled wood with two spiral grooves running its length, thicker near the head
    prof = []
    n = 80
    for k in range(n + 1):
        z = -0.62 + 1.96 * k / n
        r = 0.022 + 0.004 * math.sin(z * 7.0) + (0.006 if z > 1.1 else 0.0) * min(1.0, (z - 1.1) / 0.15)
        prof.append((z, r))
    groove = lambda z, a: 1.0 - 0.14 * max(0.0, math.sin(2 * a + z * 16.0)) ** 6
    parts.append(obj("shaft", lathe(prof, 18, groove), [wood]))
    # leather wraps where the hands hold it: ridged spirals
    for z0, z1 in ((-0.10, 0.10), (0.42, 0.62)):
        wp = [(z0 + (z1 - z0) * k / 24, 0.0275) for k in range(25)]
        wrap = lambda z, a: 1.0 + 0.09 * abs(math.sin(a * 1.0 + z * 120.0))
        parts.append(obj("wrap", lathe(wp, 18, wrap), [leather]))
    # the butt: an iron cap and a short spike
    parts.append(obj("cap", lathe([(-0.72, 0.001), (-0.66, 0.012), (-0.63, 0.03), (-0.58, 0.031), (-0.55, 0.026)], 16), [iron]))
    # the collar under the blade: rings and a band, a socket block the blade sits in
    col = [(1.18, 0.026), (1.19, 0.036), (1.205, 0.036), (1.215, 0.03), (1.26, 0.03), (1.27, 0.038), (1.285, 0.038),
           (1.295, 0.031), (1.34, 0.031), (1.35, 0.024), (1.37, 0.012), (1.40, 0.001)]
    parts.append(obj("collar", lathe(col, 20), [iron]))
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.12 - 0.02, v.co.y * 0.05, v.co.z * 0.10 + 1.30))
    parts.append(obj("socket", bm, [iron], smooth=False))
    # the blade: a crescent swept on an arc (centre c, radius R) from the socket out to a long falling tip; the inner,
    # concave side is the edge. Cross-section: spine (thick) -> etched band -> polished face -> bright edge.
    c = Vector((-0.42, 0.0, 0.92))
    R = 0.60
    a0, a1 = math.radians(38), math.radians(198)
    segs = 56
    bm = bmesh.new()
    rows = []
    for k in range(segs + 1):
        s = k / segs
        a = a0 + (a1 - a0) * s
        out = Vector((math.cos(a), 0.0, math.sin(a)))
        spine = c + out * (R + 0.02 * math.sin(s * math.pi))
        width = 0.20 * (1.0 - s) ** 0.65 + 0.004
        th = 0.028 * (1.0 - s * 0.85) + 0.003
        prof2 = [(0.0, 0.5), (0.22, 0.5), (0.30, 0.42), (0.75, 0.22), (0.93, 0.06), (1.0, 0.0)]
        ring = []
        for frac, half in prof2:
            p = spine - out * width * frac
            ring.append((p, half * th))
        rows.append(ring)
    top = []
    bot = []
    for ring in rows:
        top.append([bm.verts.new((p.x, h, p.z)) for p, h in ring])
        bot.append([bm.verts.new((p.x, -h, p.z)) for p, h in ring])
    band_mat = [1, 1, 0, 0, 2]          # spine band etched, polished face, bright edge strip
    for k in range(segs):
        for j in range(len(rows[0]) - 1):
            for side, flip in ((top, False), (bot, True)):
                q = (side[k][j], side[k][j + 1], side[k + 1][j + 1], side[k + 1][j])
                f = bm.faces.new(tuple(reversed(q)) if flip else q)
                f.material_index = band_mat[j]
        # the spine face
        f = bm.faces.new((top[k][0], top[k + 1][0], bot[k + 1][0], bot[k][0]))
        f.material_index = 1
    # root cap
    f = bm.faces.new([top[0][j] for j in range(len(rows[0]))] + [bot[0][j] for j in reversed(range(len(rows[0])))])
    f.material_index = 1
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    blade = obj("blade", bm, [steel, etch, edge], smooth=True)
    parts.append(blade)
    # barbs along the spine near the root and a curled back spike above the socket
    for s, l in ((0.12, 0.07), (0.2, 0.055), (0.28, 0.04)):
        a = a0 + (a1 - a0) * s
        out = Vector((math.cos(a), 0.0, math.sin(a)))
        tang = Vector((-math.sin(a), 0.0, math.cos(a)))
        base = c + out * (R + 0.02)
        b2 = bmesh.new()
        p0 = b2.verts.new(base + tang * 0.03 + Vector((0, 0.008, 0)))
        p1 = b2.verts.new(base - tang * 0.03 + Vector((0, 0.008, 0)))
        p2 = b2.verts.new(base + out * l - tang * 0.035)
        p3 = b2.verts.new(base + tang * 0.03 - Vector((0, 0.008, 0)))
        p4 = b2.verts.new(base - tang * 0.03 - Vector((0, 0.008, 0)))
        for fv in ((p0, p1, p2), (p4, p3, p2), (p1, p4, p2), (p3, p0, p2)):
            b2.faces.new(fv)
        bmesh.ops.recalc_face_normals(b2, faces=b2.faces)
        parts.append(obj("barb", b2, [etch], smooth=False))
    # the back spike: a horn curling up and back from the socket
    b3 = bmesh.new()
    ring_prev = None
    m = 14
    for k in range(m + 1):
        t = k / m
        p = Vector((0.04 + 0.16 * t, 0.0, 1.34 + 0.10 * math.sin(t * 2.2)))
        r = 0.018 * (1.0 - t) + 0.001
        ring = [b3.verts.new(p + Vector((0.0, math.cos(2 * math.pi * i / 8) * r, math.sin(2 * math.pi * i / 8) * r)))
                for i in range(8)]
        if ring_prev:
            for i in range(8):
                b3.faces.new((ring_prev[i], ring_prev[(i + 1) % 8], ring[(i + 1) % 8], ring[i]))
        ring_prev = ring
    bmesh.ops.recalc_face_normals(b3, faces=b3.faces)
    parts.append(obj("spike", b3, [iron]))
    o = join(parts, "scythe")
    # the head faces the other way: the blade sweeps toward +X so that, held in her right hand, it points forward
    # with its edge toward her (owner's report 2026-10-17: it faced the opposite direction)
    o.data.transform(Matrix.Scale(-1.0, 4, (1.0, 0.0, 0.0)))
    o.data.flip_normals()
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=SCYTHE, use_selection=True, export_format='GLB', export_yup=True,
                              export_apply=True)
    print("[azrael] wrote", SCYTHE, len(o.data.vertices), "verts", flush=True)


# ---- the wings ------------------------------------------------------------------------------------------------------

def feather(bm, root, direction, length, width, curl, layer_y, col_root, col_tip, cols):
    """One feather: a quill (rachis) from `root` along `direction`, vanes either side, cupped a little and curling
    back at the tip. Vertex colours from root to tip."""
    d = direction.normalized()
    side = Vector((d.z, 0.0, -d.x))                 # in the wing plane (XZ), across the feather
    if side.length < 1e-4:
        side = Vector((1, 0, 0))
    side.normalize()
    steps = 7
    left = []
    mid = []
    right = []
    for k in range(steps + 1):
        t = k / steps
        p = root + d * (length * t) + Vector((0.0, layer_y + curl * t * t, 0.0))
        w = width * math.sin(math.pi * min(1.0, t * 0.92 + 0.08)) ** 0.6 * (1.0 - 0.25 * t)
        cup = 0.01 * width * 10.0
        left.append(bm.verts.new(p - side * w * 0.45 + Vector((0, cup * 0.3, 0))))
        mid.append(bm.verts.new(p))
        right.append(bm.verts.new(p + side * w * 0.55 + Vector((0, cup * 0.3, 0))))
    faces = []
    for k in range(steps):
        faces.append(bm.faces.new((left[k], mid[k], mid[k + 1], left[k + 1])))
        faces.append(bm.faces.new((mid[k], right[k], right[k + 1], mid[k + 1])))
    for f in faces:
        for loop in f.loops:
            t = (loop.vert.co - root).length / max(length, 1e-4)
            cols.append((loop, col_root.lerp(col_tip, min(1.0, t ** 0.7))))


def wing_part(name, feathers_fn, mats):
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")     # before any face: adding a layer later frees the loops
    cols = []
    feathers_fn(bm, cols)
    for loop, c in cols:
        loop[layer] = (c.x, c.y, c.z, 1.0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj(name, bm, mats)


def wings():
    white = mat("WingFeather", (1.0, 1.0, 1.0), 0.0, 0.6)
    base = Vector((0.46, 0.5, 0.62))
    tip = Vector((1.0, 1.0, 1.0))
    rnd = random.Random(7)
    # joint positions (shoulder at the origin): arm 0 -> 0.42, fore 0.42 -> 0.92, hand 0.92 -> 1.32, rising gently
    j1 = Vector((0.42, 0.0, 0.10))
    j2 = Vector((0.92, 0.0, 0.16))
    j3 = Vector((1.32, 0.0, 0.10))

    def bone_pt(a, b, t):
        return a.lerp(b, t)

    def arm(bm, cols):
        # coverts over the arm, three short rows; tertials hanging from its back edge
        for row, (ln, wd, ly) in enumerate(((0.16, 0.07, -0.03), (0.24, 0.08, -0.02), (0.36, 0.09, -0.01))):
            nf = 6
            for i in range(nf):
                t = (i + 0.5) / nf
                r = bone_pt(Vector((0, 0, 0.02)), j1, t) + Vector((0, 0, -0.02 * row))
                d = Vector((0.18 + 0.1 * t, 0.25, -1.0))
                feather(bm, r, d, ln * (0.85 + 0.3 * rnd.random()), wd, 0.02, ly, base, tip, cols)
        for i in range(5):
            t = (i + 0.5) / 5
            r = bone_pt(Vector((0.02, 0, 0)), j1, t)
            feather(bm, r, Vector((0.1, 0.35, -1.0)), 0.52 + 0.05 * rnd.random(), 0.15, 0.05, 0.0, base, tip, cols)

    def fore(bm, cols):
        # secondaries: long, side by side, swept a little outward; two covert rows over them
        nf = 15
        for i in range(nf):
            t = (i + 0.5) / nf
            r = bone_pt(Vector((0, 0, 0)), j2 - j1, t)
            feather(bm, r, Vector((0.25 + 0.25 * t, 0.2, -1.0)), 0.62 + 0.1 * t + 0.04 * rnd.random(), 0.17, 0.06,
                    0.004 * (i % 2), base, tip, cols)
        for row, (ln, wd, ly) in enumerate(((0.2, 0.075, -0.025), (0.32, 0.085, -0.012))):
            for i in range(9):
                t = (i + 0.5) / 9
                r = bone_pt(Vector((0, 0, 0.02)), j2 - j1, t)
                feather(bm, r, Vector((0.3 + 0.2 * t, 0.2, -1.0)), ln * (0.9 + 0.2 * rnd.random()), wd, 0.02, ly,
                        base, tip, cols)

    def hand(bm, cols):
        # primaries: the longest, fanning out from the hand to the wing tip
        nf = 13
        for i in range(nf):
            t = (i + 0.5) / nf
            r = bone_pt(Vector((0, 0, 0)), j3 - j2, t)
            ang = math.radians(-70 + 62 * t)                 # from hanging down to pointing out along the span
            d = Vector((math.cos(ang + math.pi / 2) * -1.0, 0.15, math.sin(ang - math.pi / 2) * -1.0))
            d = Vector((math.sin(math.radians(20 + 60 * t)), 0.12, -math.cos(math.radians(20 + 60 * t))))
            feather(bm, r, d, 0.74 + 0.22 * t + 0.04 * rnd.random(), 0.16, 0.07, 0.004 * (i % 2), base, tip, cols)
        for i in range(7):
            t = (i + 0.5) / 7
            r = bone_pt(Vector((0, 0, 0.02)), j3 - j2, t)
            d = Vector((math.sin(math.radians(25 + 55 * t)), 0.12, -math.cos(math.radians(25 + 55 * t))))
            feather(bm, r, d, 0.3 * (0.9 + 0.2 * rnd.random()), 0.085, 0.02, -0.02, base, tip, cols)

    made = []
    for side in ("r", "l"):
        a = wing_part("wing_%s_arm" % side, arm, [white])
        f = wing_part("wing_%s_fore" % side, fore, [white])
        h = wing_part("wing_%s_hand" % side, hand, [white])
        f.location = j1
        h.location = j2 - j1
        f.parent = a
        h.parent = f
        if side == "l":
            # mirror: rebuild the geometry with x negated (no negative scales in the export)
            for o in (a, f, h):
                me = o.data
                for v in me.vertices:
                    v.co.x = -v.co.x
                me.flip_normals()
            f.location = Vector((-j1.x, j1.y, j1.z))
            h.location = Vector((-(j2 - j1).x, (j2 - j1).y, (j2 - j1).z))
        made += [a, f, h]
    bpy.ops.object.select_all(action='DESELECT')
    for o in made:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=WINGS, use_selection=True, export_format='GLB', export_yup=True,
                              export_apply=False, export_vertex_color='ACTIVE')
    print("[azrael] wrote", WINGS, sum(len(o.data.vertices) for o in made), "verts", flush=True)


clean()
scythe()
clean()
wings()

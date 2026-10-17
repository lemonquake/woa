"""Gear for the five 2026-10-17 heroes, modelled in code (all original work):
  assets/weapons/heavy_greatsword.glb   Ser Emelrich's two-handed sword: a long white-steel blade with a fuller and a
                                        gold inlay line, a wide gold guard with a sun in the middle and quillons that
                                        curve toward the blade, parrying lugs, a long ridged leather grip and a sun
                                        pommel
  assets/weapons/throwing_knife.glb     Feran Mock's throwing knife: a leaf blade with a diamond section, a red and black
                                        cord-wrapped handle and a ring pommel with a small bell
  assets/props/joke_box.glb             his Joke Box: a red and black harlequin-panelled box with brass corners, a crank,
                                        a jester face on the front and a coiled fuse on top (the fuse tip is the child
                                        "fuse_tip" so the game can put a spark there)
Weapon convention (as tools/blender/azrael.py): the grip is at the origin and the weapon points up +Y in Godot (+Z in
Blender before export).

Run: "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/heroes17_gear.py
     [-- --only=sword]
"""
import bpy
import bmesh
import math
import sys
from mathutils import Vector

ROOT = "A:/Python/woa/"
SWORD = ROOT + "assets/weapons/heavy_greatsword.glb"
KNIFE = ROOT + "assets/weapons/throwing_knife.glb"
JOKE_BOX = ROOT + "assets/props/joke_box.glb"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = next((a.split("=", 1)[1] for a in ARGS if a.startswith("--only=")), "")


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
    """A surface of revolution round Z from (z, r) pairs; twist(z, a) -> radius factor."""
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


def section_sweep(rows, mats_per_band, cap_start=True, cap_end=True):
    """A flat, two-faced solid swept along rows. Each row is [(x, z, half_thickness), ...] across the width, edge to
    edge; band j between points j and j+1 takes material index mats_per_band[j]. The two faces sit at +-thickness
    in Y; the outermost points should have thickness 0 (a sharp edge)."""
    bm = bmesh.new()
    front, back = [], []
    for row in rows:
        front.append([bm.verts.new((x, -h, z)) for x, z, h in row])
        back.append([bm.verts.new((x, h, z)) for x, z, h in row])
    n = len(rows[0])
    for k in range(len(rows) - 1):
        for j in range(n - 1):
            f = bm.faces.new((front[k][j], front[k][j + 1], front[k + 1][j + 1], front[k + 1][j]))
            f.material_index = mats_per_band[j]
            f = bm.faces.new((back[k][j + 1], back[k][j], back[k + 1][j], back[k + 1][j + 1]))
            f.material_index = mats_per_band[j]
    for k, take in ((0, cap_start), (len(rows) - 1, cap_end)):
        if take:
            ring = front[k] + list(reversed(back[k]))
            f = bm.faces.new(ring)
            f.material_index = mats_per_band[n // 2]
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def sun_disc(radius, thick, rays, ray_len, mat_disc, mat_ray, seg=24):
    """A gold sun: a domed disc facing +-Y with pointed rays round it (all in the XZ plane)."""
    parts = []
    bm = bmesh.new()
    prof = [(-thick, 0.0), (-thick, radius * 0.55), (-thick * 0.7, radius * 0.9), (-thick * 0.2, radius),
            (thick * 0.2, radius), (thick * 0.7, radius * 0.9), (thick, radius * 0.55), (thick, 0.0)]
    rings = []
    for y, r in prof:
        rings.append([bm.verts.new((math.cos(2 * math.pi * i / seg) * r, y, math.sin(2 * math.pi * i / seg) * r))
                      for i in range(seg)])
    for k in range(len(rings) - 1):
        for i in range(seg):
            bm.faces.new((rings[k][i], rings[k][(i + 1) % seg], rings[k + 1][(i + 1) % seg], rings[k + 1][i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    parts.append(obj("sun_disc", bm, [mat_disc]))
    for i in range(rays):
        a = 2 * math.pi * (i + 0.5) / rays
        out = Vector((math.cos(a), 0.0, math.sin(a)))
        tang = Vector((-math.sin(a), 0.0, math.cos(a)))
        long_ray = ray_len * (1.0 if i % 2 == 0 else 0.62)
        base = out * radius * 0.92
        w = radius * 0.28
        b2 = bmesh.new()
        p = [b2.verts.new(base + tang * w), b2.verts.new(base - tang * w),
             b2.verts.new(out * (radius + long_ray)),
             b2.verts.new(base + Vector((0, thick * 0.55, 0))), b2.verts.new(base - Vector((0, thick * 0.55, 0)))]
        for fv in ((p[0], p[3], p[2]), (p[3], p[1], p[2]), (p[1], p[4], p[2]), (p[4], p[0], p[2])):
            b2.faces.new(fv)
        bmesh.ops.recalc_face_normals(b2, faces=b2.faces)
        parts.append(obj("sun_ray", b2, [mat_ray], smooth=False))
    return parts


# ---- Ser Emelrich's greatsword --------------------------------------------------------------------------------------

def greatsword():
    # metals stay light and only half metallic (the game's stages have little to reflect, mirror steel renders black)
    steel = mat("GSteel", (0.86, 0.87, 0.9), 0.55, 0.28)
    edge = mat("GEdge", (0.97, 0.98, 1.0), 0.5, 0.16)
    fuller = mat("GFuller", (0.62, 0.64, 0.7), 0.6, 0.38)
    gold = mat("GGold", (0.95, 0.72, 0.30), 0.85, 0.3)
    gold_dark = mat("GGoldDark", (0.62, 0.42, 0.14), 0.8, 0.42)
    leather = mat("GLeather", (0.22, 0.12, 0.06), 0.0, 0.72)
    inlay = mat("GInlay", (1.0, 0.82, 0.42), 0.8, 0.25, ((1.0, 0.78, 0.4), 0.35))
    parts = []

    # blade: 1.30 m from the guard, wide at the base, gently tapering, then a long point. Cross-section edge ->
    # bevel -> flat -> fuller wall -> fuller floor (with a gold inlay line on the centre) and back out.
    z0, z1 = 0.10, 1.44
    tip_len = 0.26
    rows = []
    n = 90
    for k in range(n + 1):
        t = k / n
        z = z0 + (z1 - z0) * t
        # width: 0.19 at the base, 0.15 before the point, curving to the tip
        w = 0.19 - 0.04 * t
        w += 0.045 * max(0.0, 1.0 - (z - z0) / 0.06) ** 2      # a flared shoulder where the blade leaves the guard
        if z > z1 - tip_len:
            u = (z - (z1 - tip_len)) / tip_len
            w *= max(0.0, math.cos(u * math.pi * 0.5)) ** 0.85
        hw = w * 0.5 + 0.0005
        fz = min(1.0, max(0.0, (z1 - tip_len * 1.25 - z) / 0.08)) * min(1.0, (z - z0) / 0.05)   # fuller fades in/out
        th = 0.013 * (1.0 - 0.45 * t) + 0.002
        fw = hw * 0.30                         # fuller half width
        cs = [(-hw, 0.0), (-hw * 0.80, th * 0.55), (-fw - hw * 0.08, th), (-fw, th * (1.0 - 0.45 * fz)),
              (-fw * 0.25, th * (1.0 - 0.6 * fz)), (fw * 0.25, th * (1.0 - 0.6 * fz)), (fw, th * (1.0 - 0.45 * fz)),
              (fw + hw * 0.08, th), (hw * 0.80, th * 0.55), (hw, 0.0)]
        rows.append([(x, z, h) for x, h in cs])
    # bands: edge, bevel->flat, flat->fuller wall, wall, floor (inlay), wall, ...
    bands = [1, 0, 0, 2, 6, 2, 0, 0, 1]
    blade = obj("blade", section_sweep(rows, bands, cap_end=False),
                [steel, edge, fuller, gold, gold_dark, leather, inlay])
    parts.append(blade)

    # ricasso: the blunt blade root, wrapped in leather for the second hand, with two parrying lugs above it
    rp = [(0.03 + 0.08 * k / 20, 0.030) for k in range(21)]
    ric_wrap = lambda z, a: (1.0 + 0.08 * abs(math.sin(a + z * 140.0))) * (1.35 if abs(math.cos(a)) > 0.6 else 1.0)
    parts.append(obj("ricasso_wrap", lathe(rp, 16, ric_wrap), [leather]))
    for s in (-1, 1):
        b = bmesh.new()
        pts = [(0.0, 0.0), (0.035, 0.012), (0.055, 0.035), (0.05, 0.05), (0.03, 0.035), (0.0, 0.03)]
        top = [b.verts.new((s * (0.084 + x), -0.012, 0.25 + z)) for x, z in pts]
        bot = [b.verts.new((s * (0.084 + x), 0.012, 0.25 + z)) for x, z in pts]
        b.faces.new(top)
        b.faces.new(list(reversed(bot)))
        for i in range(len(pts)):
            j = (i + 1) % len(pts)
            b.faces.new((top[i], bot[i], bot[j], top[j]))
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        parts.append(obj("lug", b, [gold]))

    # guard: a wide bar, thick in the middle, its quillons sweeping up toward the blade and ending in small suns
    seg = 40
    b = bmesh.new()
    rings = []
    span = 0.31
    for k in range(seg + 1):
        t = -1.0 + 2.0 * k / seg
        x = t * span
        z = 0.035 + 0.095 * abs(t) ** 2.4
        r = 0.033 - 0.016 * abs(t) ** 0.8
        ring = []
        for i in range(10):
            a = 2 * math.pi * i / 10
            ring.append(b.verts.new((x, math.cos(a) * r * 0.75, z + math.sin(a) * r)))
        rings.append(ring)
    for k in range(seg):
        for i in range(10):
            b.faces.new((rings[k][i], rings[k][(i + 1) % 10], rings[k + 1][(i + 1) % 10], rings[k + 1][i]))
    b.faces.new(list(reversed(rings[0])))
    b.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(b, faces=b.faces)
    parts.append(obj("guard", b, [gold]))
    for s in (-1, 1):
        for p in sun_disc(0.022, 0.012, 8, 0.018, gold, gold_dark):
            p.location = (s * (span + 0.014), 0.0, 0.035 + 0.095 + 0.006)
            parts.append(p)
    # the sun in the middle of the guard, both faces
    for p in sun_disc(0.048, 0.026, 12, 0.032, gold, gold_dark):
        p.location = (0.0, 0.0, 0.05)
        parts.append(p)
    # a second, flatter sun set into the blade root, just above the guard
    # gold plates on both faces of the blade root, a pointed arch the sun sits in
    outline = [(-0.088, 0.105), (-0.084, 0.17), (-0.07, 0.24), (-0.045, 0.30), (-0.018, 0.345), (0.0, 0.365)]
    outline = outline + [(-x, z) for x, z in reversed(outline[:-1])]
    for side in (-1, 1):
        b = bmesh.new()
        y0, y1 = side * 0.0125, side * 0.0175
        inner = [b.verts.new((x, y0, z)) for x, z in outline]
        outer = [b.verts.new((x * 0.93, y1, 0.105 + (z - 0.105) * 0.95)) for x, z in outline]
        b.faces.new(outer if side > 0 else list(reversed(outer)))
        for i in range(len(outline)):
            j = (i + 1) % len(outline)
            b.faces.new((inner[i], inner[j], outer[j], outer[i]))
        bmesh.ops.recalc_face_normals(b, faces=b.faces)
        parts.append(obj("langet", b, [gold], smooth=False))
    for p in sun_disc(0.028, 0.026, 12, 0.042, gold, gold_dark):
        p.location = (0.0, 0.0, 0.205)
        parts.append(p)

    # grip: long enough for two hands, ridged leather spiral over a core, a gold ferrule at each end
    gp = [(-0.40 + 0.43 * k / 60, 0.019 + 0.003 * math.sin(math.pi * k / 60)) for k in range(61)]
    ridge = lambda z, a: 1.0 + 0.10 * abs(math.sin(a + z * 95.0))
    parts.append(obj("grip", lathe(gp, 16, ridge), [leather]))
    parts.append(obj("ferrule_top", lathe([(0.02, 0.0225), (0.026, 0.026), (0.034, 0.026), (0.04, 0.022)], 16), [gold]))
    parts.append(obj("ferrule_bot", lathe([(-0.43, 0.021), (-0.415, 0.025), (-0.405, 0.025), (-0.395, 0.021)], 16), [gold]))
    # pommel: a sun disc on a short neck
    parts.append(obj("pommel_neck", lathe([(-0.47, 0.012), (-0.45, 0.018), (-0.43, 0.018)], 14), [gold_dark]))
    for p in sun_disc(0.040, 0.020, 12, 0.026, gold, gold_dark):
        p.location = (0.0, 0.0, -0.515)
        parts.append(p)

    o = join(parts, "heavy_greatsword")
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.export_scene.gltf(filepath=SWORD, use_selection=True, export_format='GLB', export_yup=True,
                              export_apply=True)
    print("[heroes17_gear] wrote", SWORD, len(o.data.vertices), "verts", len(o.data.polygons), "faces", flush=True)


def export_one(o, path):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB', export_yup=True, export_apply=True)
    print("[heroes17_gear] wrote", path, len(o.data.vertices), "verts", len(o.data.polygons), "faces", flush=True)


def torus(center, axis_u, axis_v, R, r, seg=20, seg2=8):
    """A ring in the plane of axis_u / axis_v round center."""
    b = bmesh.new()
    n = axis_u.cross(axis_v).normalized()
    rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        radial = axis_u * math.cos(a) + axis_v * math.sin(a)
        c = center + radial * R
        rings.append([b.verts.new(c + radial * math.cos(2 * math.pi * j / seg2) * r + n * math.sin(2 * math.pi * j / seg2) * r)
                      for j in range(seg2)])
    for i in range(seg):
        for j in range(seg2):
            b.faces.new((rings[i][j], rings[(i + 1) % seg][j], rings[(i + 1) % seg][(j + 1) % seg2], rings[i][(j + 1) % seg2]))
    bmesh.ops.recalc_face_normals(b, faces=b.faces)
    return b


# ---- Feran Mock's throwing knife ------------------------------------------------------------------------------------

def throwing_knife():
    steel = mat("KSteel", (0.8, 0.81, 0.85), 0.55, 0.3)
    edge = mat("KEdge", (0.96, 0.97, 1.0), 0.5, 0.16)
    red = mat("KRed", (0.62, 0.05, 0.06), 0.0, 0.55)
    black = mat("KBlack", (0.04, 0.035, 0.04), 0.0, 0.6)
    brass = mat("KBrass", (0.85, 0.62, 0.25), 0.85, 0.32)
    parts = []
    # leaf blade 0.17 m, widest a third of the way up; diamond section with a bright edge
    rows = []
    n = 30
    for k in range(n + 1):
        t = k / n
        z = 0.02 + 0.17 * t
        w = 0.046 * math.sin(math.pi * (0.1 + 0.9 * t) ** 0.7) ** 0.8 + 0.0005
        th = 0.0045 * (1.0 - t * 0.7) + 0.0006
        hw = w * 0.5
        rows.append([(-hw, z, 0.0), (-hw * 0.7, z, th * 0.4), (0.0, z, th), (hw * 0.7, z, th * 0.4), (hw, z, 0.0)])
    parts.append(obj("kblade", section_sweep(rows, [1, 0, 0, 1], cap_end=False), [steel, edge]))
    # guard: a small brass bar
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * 0.05, v.co.y * 0.012, v.co.z * 0.01 + 0.016))
    parts.append(obj("kguard", bm, [brass], smooth=False))
    # handle: alternating red and black cord bands
    for i in range(6):
        z0 = -0.085 + i * 0.016
        prof = [(z0, 0.0085), (z0 + 0.003, 0.0105), (z0 + 0.013, 0.0105), (z0 + 0.016, 0.0085)]
        parts.append(obj("kband", lathe(prof, 12), [red if i % 2 == 0 else black]))
    # ring pommel with a bell hanging inside it
    parts.append(obj("kring", torus(Vector((0, 0, -0.103)), Vector((1, 0, 0)), Vector((0, 0, 1)), 0.016, 0.0035), [brass]))
    bell = lathe([(-0.116, 0.0), (-0.115, 0.006), (-0.110, 0.0068), (-0.105, 0.0055), (-0.1025, 0.002), (-0.102, 0.0)], 12)
    parts.append(obj("kbell", bell, [brass]))
    export_one(join(parts, "throwing_knife"), KNIFE)


# ---- Feran Mock's Joke Box ------------------------------------------------------------------------------------------

def joke_box():
    red = mat("JRed", (0.6, 0.04, 0.05), 0.0, 0.5)
    black = mat("JBlack", (0.035, 0.03, 0.035), 0.0, 0.55)
    brass = mat("JBrass", (0.86, 0.63, 0.26), 0.85, 0.32)
    cream = mat("JCream", (0.92, 0.88, 0.78), 0.0, 0.45)
    cord = mat("JCord", (0.36, 0.26, 0.15), 0.0, 0.8)
    spark = mat("JSpark", (1.0, 0.6, 0.2), 0.0, 0.4, ((1.0, 0.55, 0.15), 6.0))
    parts = []
    S = 0.26
    h = S * 0.5
    # the box: each side a 4 x 4 grid of cells, each cell four triangles in alternating colours (harlequin diamonds)
    bm = bmesh.new()
    def panel(origin, u, v, n=4):
        for i in range(n):
            for j in range(n):
                p0 = origin + u * (i / n) + v * (j / n)
                c = p0 + u * (0.5 / n) + v * (0.5 / n)
                q = [p0, p0 + u / n, p0 + u / n + v / n, p0 + v / n]
                for k in range(4):
                    f = bm.faces.new((bm.verts.new(q[k]), bm.verts.new(q[(k + 1) % 4]), bm.verts.new(c)))
                    # colour by a checkerboard turned 45 degrees (its lines run along the triangles' diagonal
                    # edges), so the panels read as harlequin diamonds
                    cu = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
                    gu = (cu[k][0] + cu[(k + 1) % 4][0] + i + 0.5) / 3.0
                    gv = (cu[k][1] + cu[(k + 1) % 4][1] + j + 0.5) / 3.0
                    f.material_index = int(math.floor(gu + gv) + math.floor(gu - gv)) % 2
    X, Y, Z = Vector((S, 0, 0)), Vector((0, S, 0)), Vector((0, 0, S))
    o = Vector((-h, -h, 0.0))
    panel(o, X, Z)
    panel(o + Y + X, -X, Z)
    panel(o + X, Y, Z)
    panel(o + Y, -Y, Z)
    panel(o + Z, X, Y)
    panel(o + Y, X, -Y)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    parts.append(obj("box", bm, [red, black], smooth=False))
    # brass corner caps
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (0, 1):
                b2 = bmesh.new()
                bmesh.ops.create_cube(b2, size=0.045)
                for v in b2.verts:
                    v.co += Vector((sx * (h - 0.017), sy * (h - 0.017), sz * S + (0.017 if sz == 0 else -0.017)))
                bmesh.ops.bevel(b2, geom=b2.edges[:], offset=0.006, segments=2, affect='EDGES')
                parts.append(obj("corner", b2, [brass]))
    # the crank on the right side
    c = obj("crank_axle", lathe([(0.0, 0.012), (0.03, 0.012), (0.035, 0.006)], 10), [brass])
    c.rotation_euler = (0.0, math.radians(90), 0.0)
    c.location = (h, 0.0, S * 0.55)
    parts.append(c)
    b3 = bmesh.new()
    bmesh.ops.create_cube(b3, size=1.0)
    for v in b3.verts:
        v.co = Vector((v.co.x * 0.012 + h + 0.035, v.co.y * 0.012, v.co.z * 0.075 + S * 0.55 - 0.03))
    parts.append(obj("crank_arm", b3, [brass], smooth=False))
    k = obj("crank_knob", lathe([(0.0, 0.0), (0.004, 0.012), (0.03, 0.012), (0.034, 0.0)], 10), [black])
    k.rotation_euler = (0.0, math.radians(90), 0.0)
    k.location = (h + 0.04, 0.0, S * 0.55 - 0.065)
    parts.append(k)
    # a grinning jester face on the front: cream disc, black eyes, red smile
    f = obj("face", lathe([(0.0, 0.0), (0.006, 0.06), (0.012, 0.058), (0.014, 0.0)], 24), [cream])
    f.rotation_euler = (math.radians(90), 0.0, 0.0)
    f.location = (0.0, -h + 0.002, S * 0.55)
    parts.append(f)
    for ex in (-0.022, 0.022):
        e = obj("eye", lathe([(0.0, 0.0), (0.004, 0.009), (0.006, 0.0)], 10), [black])
        e.rotation_euler = (math.radians(90), 0.0, 0.0)
        e.location = (ex, -h - 0.011, S * 0.55 + 0.016)
        parts.append(e)
    b4 = bmesh.new()
    prev = None
    for i in range(13):
        a = math.radians(200 + 140 * i / 12)
        p0 = Vector((math.cos(a) * 0.036, -h - 0.0125, S * 0.55 + 0.004 + math.sin(a) * 0.028))
        p1 = Vector((math.cos(a) * 0.026, -h - 0.0125, S * 0.55 + 0.004 + math.sin(a) * 0.018))
        cur = (b4.verts.new(p0), b4.verts.new(p1))
        if prev:
            b4.faces.new((prev[0], cur[0], cur[1], prev[1]))
        prev = cur
    bmesh.ops.recalc_face_normals(b4, faces=b4.faces)
    parts.append(obj("smile", b4, [red], smooth=False))
    # the fuse: a cord coiling up out of a brass socket in the lid
    parts.append(obj("socket", lathe([(S, 0.02), (S + 0.012, 0.02), (S + 0.016, 0.012), (S + 0.02, 0.006)], 12), [brass]))
    b5 = bmesh.new()
    prev = None
    n = 40
    end = None
    for i in range(n + 1):
        t = i / n
        a = t * math.pi * 3.0
        cpt = Vector((math.cos(a) * 0.025 * (1 - t * 0.5), math.sin(a) * 0.025 * (1 - t * 0.5), S + 0.02 + t * 0.09))
        end = cpt
        ring = [b5.verts.new(cpt + Vector((math.cos(2 * math.pi * j / 6) * 0.004, math.sin(2 * math.pi * j / 6) * 0.004, 0)))
                for j in range(6)]
        if prev:
            for j in range(6):
                b5.faces.new((prev[j], prev[(j + 1) % 6], ring[(j + 1) % 6], ring[j]))
        prev = ring
    bmesh.ops.recalc_face_normals(b5, faces=b5.faces)
    parts.append(obj("fuse", b5, [cord]))
    box = join(parts, "joke_box")
    bpy.ops.object.select_all(action='DESELECT')
    box.select_set(True)
    bpy.context.view_layer.objects.active = box
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tip = obj("fuse_tip", lathe([(-0.008, 0.0), (-0.002, 0.009), (0.004, 0.007), (0.008, 0.0)], 8), [spark])
    tip.location = end
    tip.parent = box
    bpy.ops.object.select_all(action='DESELECT')
    box.select_set(True)
    tip.select_set(True)
    bpy.context.view_layer.objects.active = box
    bpy.ops.export_scene.gltf(filepath=JOKE_BOX, use_selection=True, export_format='GLB', export_yup=True, export_apply=True)
    print("[heroes17_gear] wrote", JOKE_BOX, len(box.data.vertices), "verts", flush=True)


def main():
    clean()
    if ONLY in ("", "sword"):
        greatsword()
    if ONLY in ("", "knife"):
        clean()
        throwing_knife()
    if ONLY in ("", "box"):
        clean()
        joke_box()


main()

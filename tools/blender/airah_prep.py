"""Airah's body source (run 2026-10-18 e; the owner: "Since we can't properly animate Airah, use the base_female.glb
and build on that"). The downloaded Airah (airah.glb) is a posed sculpt: a dancer with her hands on her hips and her
scarves fused to her arms, so every clip tore her mesh. This dresses the owner's clean T/A-pose base body
(base_female.glb, a Genesis 8.1 woman) in Airah's own pieces instead:
  * head: her brown hair with the cat ears, the dark hair cap under it, the hair ribbon, clips and the head jewel,
    scaled to the base head and pushed off the skull;
  * the gold collar and the chest crystal;
  * the teal top and the white briefs, laid onto the base torso and shrink-wrapped a few millimetres over the skin;
  * the gold waist belt and the white skirt strips (cut just below the knee), moved with the hips;
  * her tail, moved with the hips and pinned to them (vertex group "pin.hips", kept by hero_body.py).
Left out: her own (posed) skin, the arm scarves that tore, the high-heeled shoes (the base feet are flat), the knee
bands, the lamp.

Writes <out>/airah_src.blend (+ textures). Then:
  blender -b --factory-startup --python tools/blender/hero_body.py -- --src=<out>/airah_src.blend --name=airah
          --body_piece="^airah_body" --height=1.76 --faces=60000 --tex=2048 --split=0 --cloth="^airah_skirt"
          --out=assets/characters/heroes17/airah.glb

Run: blender -b --factory-startup --python tools/blender/airah_prep.py -- [--base=<glb>] [--airah=<glb>]
       [--out=work/airah_src] [--preview=<dir>]
"""
import bpy
import math
import os
import sys
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = "A:/Python/woa/"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0][2:]: (a.split("=", 1)[1] if "=" in a else "1") for a in ARGS if a.startswith("--")}
BASE = OPT.get("base", ROOT + "work/downloads/sf_heroes/base_female.glb")
AIRAH = OPT.get("airah", ROOT + "work/downloads/sf_heroes/airah.glb")
OUT = os.path.abspath(OPT.get("out", ROOT + "work/airah_src"))
PREVIEW = OPT.get("preview", "")
H = 1.76                                     # her height (the same as hero_body's --height: no rescale there)

HEAD = ("Hair_0", "Hair_1", "PS3.face_PS3.face01_2", "kain rambut", "IKAT KUPING", "BESI PERMATA KEPALA", "PERMATA",
        "jepit bulet", "jepit rambut")
NECK = ()                                   # made from the base neck (gen_band): her collar did not fit
TOP = ()                                    # her top and briefs were cut for her sculpt's chest and hips: on the
HIPS_TIGHT = ()                             # base body they left it bare, so both are made from its own skin
HIPS_LOOSE = ("aksesoris pinggang", "kain rok", "buntut", "gelang buntut")
SKIP_EYE = ("Cornea", "EyeMoisture", "Tear")


def log(*a):
    print("[airah_prep]", *a, flush=True)


def coords(o):
    m = np.array(o.matrix_world)
    co = np.array([v.co[:] for v in o.data.vertices])
    return (np.c_[co, np.ones(len(co))] @ m.T)[:, :3]


def select_only(o):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o
    o.select_set(True)


def apply_all(o):
    select_only(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def unparent(o):
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw


def set_coords(o, co):
    for v, c in zip(o.data.vertices, co):
        v.co = Vector(c)
    o.data.update()


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def import_meshes(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    for o in meshes:
        unparent(o)
    for o in [o for o in new if o.type != 'MESH']:
        bpy.data.objects.remove(o, do_unlink=True)
    for o in meshes:
        apply_all(o)
    return meshes


# ---- 1. the base body -----------------------------------------------------------------------------------------------

os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
base = import_meshes(BASE)
for o in list(base):
    if any(k in o.name for k in SKIP_EYE):
        bpy.data.objects.remove(o, do_unlink=True)
        base.remove(o)
co = np.concatenate([coords(o) for o in base])
lo, hi = co.min(0), co.max(0)
s = H / (hi[2] - lo[2])
for o in base:
    c = coords(o)
    set_coords(o, (c - np.array([(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]])) * s)
body = join(base, "airah_body")
bco = coords(body)
log("base body scaled x%.4f to %.2f m, %d vertices" % (s, H, len(bco)))
BV = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())


def band(co_, z0, z1, xlim):
    m = (co_[:, 2] >= z0) & (co_[:, 2] <= z1) & (np.abs(co_[:, 0] - np.median(co_[:, 0])) <= xlim)
    p = co_[m]
    return np.percentile(p, 2, axis=0), np.percentile(p, 98, axis=0)


def push_out(o, off=0.004, reach=0.12):
    """Every vertex of o inside the body or nearer than off to its skin goes to off outside it."""
    n = 0
    for v in o.data.vertices:
        loc, nrm, _, d = BV.find_nearest(v.co)
        if loc is None or d > reach or nrm.length < 0.5:
            continue
        side = (v.co - loc).dot(nrm)
        if side < off:
            v.co = loc + nrm.normalized() * off
            n += 1
    o.data.update()
    log("  %s: %d of %d vertices pushed out of the skin" % (o.name, n, len(o.data.vertices)))


def wrap(o, off):
    """Shrink-wrap o onto the skin (off metres outside it), keeping its own folds' spacing roughly."""
    select_only(o)
    m = o.modifiers.new("wrap", 'SHRINKWRAP')
    m.target = body
    m.wrap_method = 'NEAREST_SURFACEPOINT'
    m.wrap_mode = 'OUTSIDE_SURFACE'
    m.offset = off
    bpy.ops.object.modifier_apply(modifier=m.name)


# ---- 2. Airah's pieces ----------------------------------------------------------------------------------------------

pieces = import_meshes(AIRAH)
by = {o.name: [o] for o in pieces}
want = HEAD + NECK + TOP + HIPS_TIGHT + HIPS_LOOSE + ("kolorz",)
for k, objs in list(by.items()):
    if k not in want and not any(k.startswith(w) for w in want):
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
        del by[k]


def group(names):
    out = []
    for k, objs in by.items():
        if any(k == n or k.startswith(n) for n in names):
            out += objs
    return out


skin_a = None
# her own skin, for her measurements: re-import just body_0
_tmp = import_meshes(AIRAH)
head_top = 0.0
for o in _tmp:
    if o.name.startswith("body_0"):
        skin_a = coords(o)
    if o.name.startswith("PS3.face_PS3.face01_0"):
        head_top = coords(o)[:, 2].max()            # her skin stops at the neck: the face piece holds the head
    bpy.data.objects.remove(o, do_unlink=True)
ha = max(head_top, skin_a[:, 2].max()) - skin_a[:, 2].min()
k_body = H / ha
log("Airah's sculpt %.3f m tall, x%.3f to the base height" % (ha, k_body))


def bbox(objs):
    c = np.concatenate([coords(o) for o in objs])
    return c.min(0), c.max(0)


def remap(objs, src_lo, src_hi, dst_lo, dst_hi, uniform=False, anchor=None):
    """Move objs so the box src maps onto the box dst (per axis, or one scale for all axes about `anchor`, a
    fraction of the box per axis)."""
    src_lo, src_hi, dst_lo, dst_hi = map(np.asarray, (src_lo, src_hi, dst_lo, dst_hi))
    k = (dst_hi - dst_lo) / np.maximum(1e-6, src_hi - src_lo)
    if uniform:
        k = np.full(3, float(np.mean(k[:2])))
    a = np.asarray(anchor if anchor is not None else (0.5, 0.5, 0.5))
    sa = src_lo + (src_hi - src_lo) * a
    da = dst_lo + (dst_hi - dst_lo) * a
    for o in objs:
        set_coords(o, (coords(o) - sa) * k + da)
    return k


# head: her hair cap over the base skull (the cap's top, back and sides onto the skull's, one scale)
skull = bco[bco[:, 2] > 0.86 * H]
sk_lo, sk_hi = np.percentile(skull, 0.5, axis=0), np.percentile(skull, 99.5, axis=0)
cap = by.get("PS3.face_PS3.face01_2", [])
c_lo, c_hi = bbox(cap)
# the cap's front is the forehead line; the skull box includes the nose: its front is moved back to the brow
sk_lo2 = sk_lo.copy()
sk_lo2[1] = sk_lo[1] + 0.025 * H / 1.76
sk_lo2[2] = c_lo[2] * 0 + sk_hi[2] - (c_hi[2] - c_lo[2]) * ((sk_hi[0] - sk_lo[0]) / (c_hi[0] - c_lo[0]))
k = remap(group(HEAD), c_lo, c_hi, sk_lo2, sk_hi + np.array([0, 0.006, 0.008]), uniform=True, anchor=(0.5, 0.6, 1.0))
log("head pieces x%.3f onto the skull" % k[0])
for o in group(HEAD):
    push_out(o, 0.003 if "face01_2" in o.name else 0.006, reach=0.05)


def torso_box(za, zb, src):
    """The base torso's box between the base heights matching Airah's za..zb (her skin's height fractions)."""
    f0 = (za - skin_a[:, 2].min()) / ha
    f1 = (zb - skin_a[:, 2].min()) / ha
    return band(bco, f0 * H, f1 * H, 0.2 * H / 1.76)


# the top, briefs and collar: layers of the base body's own skin, lifted off it (they cover it exactly)
def solid_mat(name, rgb, metal=0.0, rough=0.7):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m


def gen_band(name, near, planes, off, thick, mat):
    """A garment from the base skin: the faces round it (near(co) for any of their vertices) are copied, cut clean
    along `planes` ([(point, normal)], the side the normal points to is kept), pushed out along the normals by off
    and given a thin edge (thick)."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    ok = np.array([near(np.array(v.co[:])) for v in bm.verts])
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not any(ok[v.index] for v in f.verts)], context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    for pc, pn in planes:
        geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(pc), plane_no=Vector(pn), clear_inner=True)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * off
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.clear()
    o.data.materials.append(mat)
    select_only(o)
    so = o.modifiers.new("edge", 'SOLIDIFY')
    so.thickness = thick
    so.offset = 1.0
    bpy.ops.object.modifier_apply(modifier=so.name)
    log("  %s: %d vertices from the skin" % (name, len(o.data.vertices)))
    return o


kk = H / 1.76
torso = bco[(np.abs(bco[:, 0]) < 0.17 * kk) & (bco[:, 2] > 0.66 * H) & (bco[:, 2] < 0.80 * H)]
apex = torso[np.argmin(torso[:, 1])]                    # the bust's most forward point
# the crotch: the lowest point of the trunk on the middle line (the legs stand apart)
mid = bco[(np.abs(bco[:, 0]) < 0.015 * kk) & (bco[:, 2] > 0.35 * H) & (bco[:, 2] < 0.62 * H) & (np.abs(bco[:, 1]) < 0.2 * kk)]
crotch = float(mid[:, 2].min())
neck = bco[(bco[:, 2] > 0.80 * H) & (bco[:, 2] < 0.86 * H) & (np.abs(bco[:, 0]) < 0.07 * kk)]
# the neck's thinnest height
zs = np.arange(0.80 * H, 0.86 * H, 0.004)
widths = [np.ptp(neck[np.abs(neck[:, 2] - z) < 0.003][:, 0]) if (np.abs(neck[:, 2] - z) < 0.003).sum() > 3 else 9 for z in zs]
neck_z = float(zs[int(np.argmin(widths))])
log("bust %.3f m, crotch %.3f m, neck %.3f m" % (apex[2], crotch, neck_z))
teal = solid_mat("airah_top", (0.10, 0.62, 0.58), 0.0, 0.55)
white = solid_mat("airah_cloth", (0.86, 0.86, 0.82), 0.0, 0.8)
gold = solid_mat("airah_gold", (1.0, 0.72, 0.28), 1.0, 0.3)
Z = (0.0, 0.0, 1.0)
top = gen_band("airah_gear_top", lambda c: abs(c[0]) < 0.24 * kk and apex[2] - 0.11 * kk < c[2] < apex[2] + 0.1 * kk,
               [((0, 0, apex[2] - 0.085 * kk), Z), ((0, 0, apex[2] + 0.062 * kk), (0, 0, -1)),
                ((0.17 * kk, 0, 0), (-1, 0, 0)), ((-0.17 * kk, 0, 0), (1, 0, 0))], 0.005, 0.003, teal)
cz = crotch - 0.012 * kk
briefs = gen_band("airah_gear_briefs", lambda c: abs(c[0]) < 0.28 * kk and cz - 0.03 < c[2] < crotch + 0.15 * kk,
                  [((0, 0, crotch + 0.12 * kk), (0, 0, -1)), ((0.03 * kk, 0, cz), (-0.5, 0, 1)),
                   ((-0.03 * kk, 0, cz), (0.5, 0, 1)), ((0.24 * kk, 0, 0), (-1, 0, 0)), ((-0.24 * kk, 0, 0), (1, 0, 0))],
                  0.004, 0.003, white)
collar = gen_band("airah_gear_collar", lambda c: abs(c[2] - neck_z) < 0.02 * kk and abs(c[0]) < 0.09 * kk,
                  [((0, 0, neck_z - 0.011 * kk), Z), ((0, 0, neck_z + 0.011 * kk), (0, 0, -1))], 0.004, 0.004, gold)
# gold bands on the upper arms and wrists (the A-pose arm: hero_body gives them to the arm under them)
for side in (-1, 1):
    arm = bco[(bco[:, 0] * side > 0.22 * kk) & (bco[:, 2] > 0.5 * H)]
    if len(arm) == 0:
        continue
    sh = arm[np.argmax(arm[:, 2])]
    wr = arm[np.argmin(arm[:, 2])]
    for f, nm in ((0.28, "upper"), (0.72, "wrist")):
        c = sh + (wr - sh) * f
        ax = (wr - sh) / np.linalg.norm(wr - sh)
        gen_band("airah_gear_band_%s_%s" % (nm, "L" if side > 0 else "R"),
                 lambda p, c=c: np.linalg.norm(p - c) < 0.09 * kk,
                 [(tuple(c - ax * 0.012 * kk), tuple(ax)), (tuple(c + ax * 0.012 * kk), tuple(-ax))], 0.004, 0.003, gold)
hp_lo = np.array([-0.2 * kk, -0.12 * kk, crotch])
hp_hi = np.array([0.2 * kk, 0.12 * kk, crotch + 0.12 * kk])
b_lo, b_hi = bbox(by["kolorz_0"]) if "kolorz_0" in by else (None, None)
# belt, skirt strips and tail: the hips' move (the briefs' box), one scale so the strips and tail keep their shape
loose = group(HIPS_LOOSE)
ka = float(np.mean((hp_hi - hp_lo)[:2] / (b_hi - b_lo)[:2]))
sa = (b_lo + b_hi) / 2
da = (hp_lo + hp_hi) / 2
bpy.data.objects.remove(by.pop("kolorz_0")[0], do_unlink=True)
for o in loose:
    set_coords(o, (coords(o) - sa) * ka + da)
for o in loose:
    push_out(o, 0.006, reach=0.08)
# the belt's loose bits that do not sit on her (an arm band of the sculpt's raised arm): left out
import bmesh
for o in group(("aksesoris pinggang",)):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    drop = []
    for v0 in bm.verts:
        if v0.index in seen:
            continue
        comp, stack = [], [v0]
        seen.add(v0.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        c = sum((x.co for x in comp), Vector()) / len(comp)
        loc, _, _, d = BV.find_nearest(c)
        if d is None or d > 0.05 * kk or c.z > crotch + 0.25 * kk:
            drop += comp
    bmesh.ops.delete(bm, geom=drop, context='VERTS')
    bm.to_mesh(o.data)
    bm.free()
    log("  belt: %d stray vertices left out" % len(drop))

# names: the skirt strips for --cloth, the tail for --rigid
# the skirt strips end just below the knee: they ride the hips (hero_body --cloth), and longer ones went through the
# floor whenever she crouched or lunged
import bmesh as _bm
for o in group(("kain rok",)):
    bm = _bm.new()
    bm.from_mesh(o.data)
    _bm.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                         plane_co=Vector((0, 0, 0.44 * kk)), plane_no=Vector((0, 0, 1)), clear_inner=True)
    bm.to_mesh(o.data)
    bm.free()
for o in group(("kain rok",)):
    for sl in o.material_slots:
        if sl.material:
            sl.material.name = "airah_skirt"
# the tail is carried raised behind her: hanging to the floor it scraped the ground and swung through her legs in
# lunges. Turned about its root so it leaves her straight back and level, four fifths as long (its curled end hangs
# at her knees, not her ankles), and pinned to the spine: when she drops into a lunge her trunk leans in and lifts
# it behind her (pinned to the hips its end still touched the floor).
tail_objs = group(("buntut", "gelang buntut"))
if tail_objs:
    tc = np.concatenate([coords(o) for o in group(("buntut",))])
    root = tc[np.argmin(tc[:, 1])]
    tip = tc[np.argmax(np.linalg.norm(tc - root, axis=1))]
    v = tip - root
    yaw = math.atan2(v[0], v[1])                       # first swing it straight back (no sideways reach)
    lift = math.radians(0.0) - math.atan2(v[2], math.hypot(v[0], v[1]))
    cz, sz = math.cos(yaw), math.sin(yaw)
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    cx, sx = math.cos(lift), math.sin(lift)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    R = (Rx @ Rz) * 0.8
    for o in tail_objs:
        set_coords(o, (coords(o) - root) @ R.T + root)
    log("tail raised %.0f degrees, turned %.0f degrees to point straight back" % (math.degrees(lift), math.degrees(yaw)))

# pinned (hero_body.py keeps a "pin.<bone>" group's vertices on that bone alone): the belt rides the hips (it sits by
# her hands), the tail and its ring the spine, the hair and its ribbons, clips and jewel the head
def pin(objs, bone):
    for o in objs:
        g = o.vertex_groups.new(name="pin." + bone)
        g.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
    log("pinned to the %s: %s" % (bone, ", ".join(o.name for o in objs)))


pin(group(("aksesoris pinggang",)), "hips")
pin(group(("buntut", "gelang buntut")), "spine")
pin(group(HEAD), "head")

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "airah_src.blend"))
log("saved", os.path.join(OUT, "airah_src.blend"))

if PREVIEW:
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.color_type = 'TEXTURE'
    sc.display.shading.light = 'STUDIO'
    sc.render.resolution_x = 420
    sc.render.resolution_y = 720
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = 'ORTHO'
    os.makedirs(PREVIEW, exist_ok=True)
    for name, scale, z in (("full", 2.0, H * 0.5), ("head", 0.5, H * 0.9), ("torso", 0.8, H * 0.6)):
        cam.data.ortho_scale = scale
        for yaw in (0, 90, 180):
            rr = math.radians(yaw)
            cam.location = Vector((math.sin(rr) * 4, -math.cos(rr) * 4, z))
            cam.rotation_euler = (math.radians(90), 0, rr)
            sc.render.filepath = os.path.join(PREVIEW, "%s_%03d.png" % (name, yaw))
            bpy.ops.render.render(write_still=True)

"""Ghorman's human body source (2026-10-17 f): the owner's "Body builder" model (ghorman_human.zip: a bare, bald,
textured T-pose man) dressed as the Beast King before tools/blender/hero_body.py binds it to the hero skeleton.

Dressing (pieces from the owner's druid_clothes.glb, fitted to his size, and pieces made here):
  * the deer skull with its antlers on his head, over the druid's hood (worn higher than on the druid, so his face
    shows under the snout);
  * the druid's fur collar as a golden lion mane over the leather shoulder cape;
  * the belt with its pouches and strap, a knee-length leather kilt (the druid's coat skirt), bracers and boots;
  * a full dark beard and moustache of fur cards (made here).
Each fitted piece is moved, scaled to his measurements and then pushed out of the body wherever it would sink in.

Writes <out>/ghorman_src.blend (+ textures). Then:
  blender -b --factory-startup --python tools/blender/hero_body.py -- --src=<out>/ghorman_src.blend --name=ghorman
          --body_piece="^ghorman_body" --height=2.05 --faces=60000 --tex=2048 --out=assets/characters/heroes17/ghorman.glb

Run: blender -b --factory-startup --python tools/blender/ghorman_prep.py -- [--body=<fbx>] [--druid=<glb>]
       [--out=work/ghorman_src] [--preview]
"""
import bpy
import bmesh
import math
import os
import random
import sys
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = "A:/Python/woa/"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0][2:]: (a.split("=", 1)[1] if "=" in a else "1") for a in ARGS if a.startswith("--")}
BODY = OPT.get("body", ROOT + "work/downloads/sf_heroes/ghorman_human/source/Body builder.fbx")
TEXDIR = os.path.join(os.path.dirname(os.path.dirname(BODY)), "textures")
DRUID = OPT.get("druid", ROOT + "work/downloads/sf_heroes/druid_clothes.glb")
OUT = os.path.abspath(OPT.get("out", ROOT + "work/ghorman_src"))
PREVIEW = "preview" in OPT
H = 2.05                                     # his height in metres (hero_body.py scales to --height anyway)
random.seed(7)


def log(*a):
    print("[ghorman_prep]", *a, flush=True)


def coords(o):
    m = np.array(o.matrix_world)
    co = np.array([v.co[:] for v in o.data.vertices])
    return (np.c_[co, np.ones(len(co))] @ m.T)[:, :3]


def apply_all(o):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def unparent(o):
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw


def transform_verts(o, fn):
    """fn(np (n,3) world coords) -> new world coords; the object must have identity transform."""
    co = coords(o)
    new = fn(co)
    for v, c in zip(o.data.vertices, new):
        v.co = Vector(c)
    o.data.update()


# ---- 1. the body ---------------------------------------------------------------------------------------------------

os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=BODY)
body = bpy.data.objects["body_low"]
eyes = [o for o in bpy.data.objects if o.name.startswith("Eye")]
for o in [body] + eyes:
    unparent(o)
    apply_all(o)
co = coords(body)
lo, hi = co.min(0), co.max(0)
s = H / (hi[2] - lo[2])
T = Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2])))
for o in [body] + eyes:
    o.matrix_world = T @ o.matrix_world
    apply_all(o)
body.name = "ghorman_body"
body.data.name = "ghorman_body"
log("body scaled x%.4f to %.2f m" % (s, H))

# his skin: the model's own maps (the FBX material has none linked)
skin = bpy.data.materials.new("ghorman_skin")
skin.use_nodes = True
nt = skin.node_tree
bsdf = nt.nodes["Principled BSDF"]
def tex(name, cs, x, y):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(os.path.join(TEXDIR, name))
    n.image.colorspace_settings.name = cs
    n.location = (x, y)
    return n
tc = tex("Body_Base_Color.png", 'sRGB', -600, 300)
nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
tr = tex("Body_Roughness.png", 'Non-Color', -600, 0)
nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
tn = tex("Body_Normal.jpeg", 'Non-Color', -600, -300)
nm = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
body.data.materials.clear()
body.data.materials.append(skin)
# the eyes: keep the eyeballs, drop the clear cornea shells
for e in eyes:
    bm = bmesh.new()
    bm.from_mesh(e.data)
    idx = [i for i, sl in enumerate(e.material_slots) if sl.material and "Trans" in sl.material.name]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in idx], context='FACES')
    bm.to_mesh(e.data)
    bm.free()
    e.name = "ghorman_eye"

co = coords(body)
BV = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())


def ring(z0, z1, xlim=None, side=0):
    m = (co[:, 2] >= z0) & (co[:, 2] <= z1)
    if xlim is not None:
        m &= np.abs(co[:, 0]) <= xlim
    if side:
        m &= co[:, 0] * side > 0
    p = co[m]
    return p.min(0), p.max(0)


# landmarks
head_top = co[:, 2].max()
face = co[(co[:, 2] > 0.86 * H) & (np.abs(co[:, 0]) < 0.03)]
nose = face[np.argmin(face[:, 1])]
hz0, hz1 = ring(0.84 * H, H, xlim=0.16)
log("head box", np.round(hz0, 3), np.round(hz1, 3), "nose", np.round(nose, 3))
# chin: the lowest front point of the face (the most forward points under the nose, before the neck falls back)
neck_lo, neck_hi = ring(0.80 * H, 0.83 * H, xlim=0.12)
chin_z = nose[2] - 0.085 * H / 1.8
waist_lo, waist_hi = ring(0.585 * H, 0.60 * H, xlim=0.30)
hip_lo, hip_hi = ring(0.50 * H, 0.53 * H, xlim=0.40)
log("waist", np.round(waist_lo, 3), np.round(waist_hi, 3), "hips", np.round(hip_lo, 3), np.round(hip_hi, 3))


def push_out(o, off=0.008, max_move=0.25):
    """Every vertex of o that is inside the body or closer than off to its skin goes to off outside it."""
    n_moved = 0
    for v in o.data.vertices:
        p = v.co
        loc, nrm, _, d = BV.find_nearest(p)
        if loc is None or d > 0.2:
            continue
        if not all(math.isfinite(x) for x in nrm) or nrm.length < 0.5:
            continue                             # a zero-area face of the body has no normal (it gave NaN vertices)
        side = (p - loc).dot(nrm)
        if side < off and (off - side) < max_move:
            v.co = loc + nrm.normalized() * off
            n_moved += 1
    o.data.update()
    log("  %s: pushed %d of %d vertices out of the body" % (o.name, n_moved, len(o.data.vertices)))


# ---- 2. the druid pieces --------------------------------------------------------------------------------------------

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=DRUID)
druid = [o for o in bpy.data.objects if o not in before]
for o in druid:
    if o.type == 'MESH':
        unparent(o)
for o in [o for o in druid if o.type != 'MESH']:
    bpy.data.objects.remove(o, do_unlink=True)
druid = {o.name.split("_")[0]: o for o in bpy.data.objects if o not in before and o.type == 'MESH'}
for o in druid.values():
    apply_all(o)
log("druid pieces", sorted(druid))


def split_parts(o):
    """Separate o into its loose parts; returns [(obj, centre, lo, hi, n)]"""
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.mesh.separate(type='LOOSE')
    out = []
    for p in bpy.context.selected_objects:
        c = coords(p)
        out.append((p, c.mean(0), c.min(0), c.max(0), len(c)))
    return out


def join(objs, name):
    objs = [o for o in objs if o is not None]
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


def affine(o, src_c, dst_c, sx, sy, sz):
    transform_verts(o, lambda c: (c - np.array(src_c)) * np.array([sx, sy, sz]) + np.array(dst_c))


def subdivide(o, cuts):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.subdivide(number_cuts=cuts)
    bpy.ops.object.mode_set(mode='OBJECT')


# druid measurements (mm): the head under the hood, the neck, the waist at the belt
D_HEAD_C = np.array([0.0, 37.0, 1608.0])
D_HEAD_H = 234.0                             # hood bottom to hood top
D_NECK = np.array([0.0, 20.0, 1470.0])
D_WAIST_C = np.array([0.0, -14.0, 1008.0])
D_WAIST_W, D_WAIST_D = 354.0, 258.0          # the belt's width and depth

# --- head: skull, antlers and ears over the hood
head_parts = split_parts(druid["Head"])
hood = max([p for p in head_parts if p[3][2] < 1730 and abs(p[1][0]) < 50 and p[4] < 200], key=lambda p: p[4])[0]
skull_bits = [p[0] for p in head_parts if p[0] is not hood]
g_head_h = H - chin_z
k_head = g_head_h / D_HEAD_H * 0.98
g_head_c = np.array([0.0, (hz0[1] + hz1[1]) / 2 + 0.01, (chin_z + H) / 2])
affine(hood, D_HEAD_C, g_head_c, k_head * 1.12, k_head * 1.08, k_head)
skull = join(skull_bits, "gear_skull")
lift = 0.24 * g_head_h
affine(skull, D_HEAD_C, g_head_c + np.array([0.0, 0.015, lift]), k_head * 1.1, k_head * 1.1, k_head * 1.1)
hood.name = "gear_hood"
push_out(hood, 0.012)
log("head: height %.3f, scale %.5f, skull lifted %.3f" % (g_head_h, k_head, lift))

# --- shoulders: the leather cape and the fur collar as a mane
cl_parts = split_parts(druid["Druid"])
def take(pred):
    return [p for p in cl_parts if pred(p)]
cape = take(lambda p: p[4] > 400 and p[2][2] > 1200)
sk = take(lambda p: p[4] > 400 and p[3][2] < 1000 and p[2][2] > 300)
apron = take(lambda p: 40 <= p[4] <= 50 and p[3][2] < 1000)
# the druid's trousers: the coat skirt is slit at the front and sides, and his thighs showed through the slits
pants = take(lambda p: 100 <= p[4] <= 150 and 1000 < p[3][2] < 1030 and 500 < p[2][2] < 600)
bracers = take(lambda p: abs(p[1][0]) > 330 and 1000 < p[1][2] < 1250 and p[4] >= 80)
bracer_bits = take(lambda p: abs(p[1][0]) > 380 and 1000 < p[1][2] < 1250 and p[4] < 80)
boots = take(lambda p: p[3][2] < 460 and p[4] >= 50)
used = set(id(p) for p in cape + sk + apron + pants + bracers + bracer_bits + boots)
for p in cl_parts:
    if id(p) not in used:
        bpy.data.objects.remove(p[0], do_unlink=True)
log("clothes: cape %d, skirt %d, apron %d, trousers %d, bracers %d (+%d bits), boot pieces %d" % (
    len(cape), len(sk), len(apron), len(pants), len(bracers), len(bracer_bits), len(boots)))

sh_lo, sh_hi = ring(0.775 * H, 0.80 * H, xlim=0.32)      # shoulders (T-pose: the arms join the trunk here)
g_neck = np.array([0.0, (neck_lo[1] + neck_hi[1]) / 2, 0.815 * H])
g_sh_w = sh_hi[0] - sh_lo[0]
k_sh = g_sh_w / 520.0                       # the druid's shoulders under the cape, mm
k_z = H / 1780.0
mantle_parts = [join([p[0] for p in cape], "gear_cape")]
fur = druid["Fur"]
fur.name = "gear_mane"
for o in mantle_parts + [fur]:
    affine(o, D_NECK, g_neck, k_sh * 1.05, k_sh * 1.15, k_z * 1.05)
# the mane: fuller and longer than the druid's collar
transform_verts(fur, lambda c: np.c_[(c[:, 0]) * 1.12, g_neck[1] + (c[:, 1] - g_neck[1]) * 1.18,
                                     c[:, 2] + (c[:, 2] - g_neck[2]).clip(-1, 0) * 0.25])
push_out(mantle_parts[0], 0.012)
push_out(fur, 0.03)

# --- waist: belt, pouches and strap; the kilt
gear = druid["Gear"]
# the druid's red-sheathed knife hangs from the belt past the thigh; on him the leg weights stretched it to the floor:
# its pieces (red on the gear sheet) are left out
gimg = next((n.image for sl in gear.material_slots for n in sl.material.node_tree.nodes
             if n.type == 'TEX_IMAGE' and n.image and any(l.to_socket.name == "Base Color" for l in n.outputs[0].links)), None)
if gimg is not None:
    gw, gh = gimg.size
    gpx = np.array(gimg.pixels[:], dtype=np.float32).reshape(gh, gw, 4)
    uvl_ = gear.data.uv_layers.active.data
    bm_ = bmesh.new()
    bm_.from_mesh(gear.data)
    bm_.faces.ensure_lookup_table()
    uv_ = bm_.loops.layers.uv.active
    seen_ = set()
    red_faces = []
    n_parts = 0
    for f in bm_.faces:
        if f.index in seen_:
            continue
        comp, stack = [], [f]
        seen_.add(f.index)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.edges:
                for y in e.link_faces:
                    if y.index not in seen_:
                        seen_.add(y.index)
                        stack.append(y)
        cols = []
        for x in comp:
            for lp in x.loops:
                u, v = lp[uv_].uv
                cols.append(gpx[int((v % 1.0) * (gh - 1)), int((u % 1.0) * (gw - 1)), :3])
        c = np.mean(cols, 0)
        if c[0] > 0.3 and c[0] > 2.2 * c[1] and c[0] > 2.2 * c[2]:
            red_faces += comp
            n_parts += 1
    bmesh.ops.delete(bm_, geom=red_faces, context='FACES')
    bm_.to_mesh(gear.data)
    bm_.free()
    log("belt gear: left out %d red pieces (%d faces)" % (n_parts, len(red_faces)))
g_waist_c = np.array([0.0, (waist_lo[1] + waist_hi[1]) / 2, 0.595 * H])
kx = (waist_hi[0] - waist_lo[0]) * 1.06 / D_WAIST_W
ky = (waist_hi[1] - waist_lo[1]) * 1.10 / D_WAIST_D
affine(gear, D_WAIST_C, g_waist_c, kx, ky, k_z)
gear.name = "gear_belt"
push_out(gear, 0.01)

kilt = join([p[0] for p in sk + apron], "gear_kilt")
knee_z = 0.285 * H
def kilt_fn(c):
    t = (D_WAIST_C[2] - c[:, 2]) / (D_WAIST_C[2] - 397.0)            # 0 at the belt, 1 at the coat's hem
    z = g_waist_c[2] - t * (g_waist_c[2] - knee_z)
    kxx = (hip_hi[0] - hip_lo[0]) * 1.16 / 400.0
    kyy = (hip_hi[1] - hip_lo[1]) * 1.18 / 250.0
    flare = 1.0 + 0.28 * np.clip(t, 0.0, 1.0) ** 1.5    # (above the belt t < 0: no flare)
    return np.c_[c[:, 0] * kxx * flare, g_waist_c[1] + (c[:, 1] - D_WAIST_C[1]) * kyy * flare, z]
transform_verts(kilt, kilt_fn)
# finer mesh first, so the faces between pushed and unpushed vertices do not cut back into the thighs
subdivide(kilt, 2)
push_out(kilt, 0.03)
push_out(kilt, 0.02)
if pants:
    trousers = join([p[0] for p in pants], "gear_trousers")
    transform_verts(trousers, kilt_fn)
    subdivide(trousers, 2)
    push_out(trousers, 0.012)

# --- forearms: the bracers turned from the druid's A-pose onto his level arms
def arm_ring(xc, dx=0.02):
    m = np.abs(co[:, 0] - xc) < dx
    m &= co[:, 2] > 0.7 * H
    p = co[m]
    return p.min(0), p.max(0)


arm_tip = co[:, 0].max()
for side in (1.0, -1.0):
    pieces = [p for p in bracers + bracer_bits if p[1][0] * side > 0]
    if not pieces:
        continue
    br = join([p[0] for p in pieces], "gear_bracer_" + ("L" if side > 0 else "R"))
    c = coords(br)
    cen = c.mean(0)
    _, _, vt = np.linalg.svd(c - cen, full_matrices=False)
    u = vt[0] if vt[0][0] * side > 0 else -vt[0]
    t = (c - cen) @ u
    length = t.max() - t.min()
    # rotate the bracer's axis onto +-X
    R = Vector(u).rotation_difference(Vector((side, 0.0, 0.0))).to_matrix().to_4x4()
    wrist_x = side * (arm_tip - 0.22 * H / 1.8)
    fx = wrist_x - side * 0.5 * length * k_z * 1.15
    a_lo, a_hi = arm_ring(fx, 0.03)
    tgt = np.array([fx, (a_lo[1] + a_hi[1]) / 2, (a_lo[2] + a_hi[2]) / 2])
    rad_src = np.percentile(np.linalg.norm((c - cen) - np.outer(t, u), axis=1), 90)
    rad_dst = max(a_hi[1] - a_lo[1], a_hi[2] - a_lo[2]) / 2
    kr = rad_dst * 1.12 / rad_src
    def fn(c, cen=cen, R=R, tgt=tgt, kr=kr):
        loc = c - cen
        loc = loc @ np.array(R.to_3x3()).T
        return np.c_[loc[:, 0] * k_z * 1.15, loc[:, 1] * kr, loc[:, 2] * kr] + tgt
    transform_verts(br, fn)
    push_out(br, 0.008)

# --- feet: the boots fitted to his feet and calves
for side in (1.0, -1.0):
    pieces = [p for p in boots if p[1][0] * side > 0]
    if not pieces:
        continue
    bt = join([p[0] for p in pieces], "gear_boot_" + ("L" if side > 0 else "R"))
    c = coords(bt)
    b_lo, b_hi = c.min(0), c.max(0)
    f_lo, f_hi = ring(0.0, 0.25 * H, side=int(side))
    def fn(c, b_lo=b_lo, b_hi=b_hi, f_lo=f_lo, f_hi=f_hi):
        t = (c - b_lo) / (b_hi - b_lo)
        pad = np.array([0.012, 0.012, 0.0])
        return (f_lo - pad) + t * ((f_hi + pad) - (f_lo - pad))
    transform_verts(bt, fn)
    subdivide(bt, 1)
    push_out(bt, 0.016)

# ---- 3. the beard and moustache (fur cards) ---------------------------------------------------------------------------

def fur_material(name, src_img, fn):
    w, h = src_img.size
    px = np.array(src_img.pixels[:], dtype=np.float32).reshape(-1, 4)
    px[:, :3] = np.clip(fn(px[:, :3]), 0.0, 1.0)
    # the game sees the fur from afar: its smaller mip levels average the thin strands' alpha under the cut-out
    # threshold and the mane vanishes. Thicker alpha, and the strands' colour under the clear parts (no dark fringe)
    a = px[:, 3].reshape(h, w)
    strong = a > 0.5
    if strong.any():
        mean = px[strong.ravel(), :3].mean(0)
        px[~strong.ravel(), :3] = px[~strong.ravel(), :3] * a.ravel()[~strong.ravel(), None] + mean * (1.0 - a.ravel()[~strong.ravel(), None])
    px[:, 3] = np.clip(px[:, 3] * 2.6, 0.0, 1.0)
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels[:] = px.ravel()
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = 'PNG'
    img.save()
    img.filepath = img.filepath_raw
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    t = m.node_tree
    b = t.nodes["Principled BSDF"]
    n = t.nodes.new("ShaderNodeTexImage")
    n.image = img
    t.links.new(n.outputs["Color"], b.inputs["Base Color"])
    # cut-out, not blended (the glTF exporter writes alpha MASK for a rounded alpha; Godot then sorts it like skin)
    cut = t.nodes.new("ShaderNodeMath")
    cut.operation = 'ROUND'
    t.links.new(n.outputs["Alpha"], cut.inputs[0])
    t.links.new(cut.outputs[0], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 0.85
    try:
        m.surface_render_method = 'DITHERED'
    except Exception:
        pass
    return m


fur_img = None
for sl in fur.material_slots:
    b = next((n for n in sl.material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if b is not None and b.inputs["Base Color"].links:
        fur_img = b.inputs["Base Color"].links[0].from_node.image
log("fur sheet", fur_img.name if fur_img else None)


def golden(rgb):
    lum = rgb @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    # a lion's mane: warm gold, the strands' dark roots kept as tawny brown
    v = np.clip(0.18 + lum * 2.6, 0.0, 1.0)
    return np.stack([v * 1.0, v * 0.70, v * 0.30], 1)


def dark_brown(rgb):
    lum = rgb @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    v = np.clip(lum * 1.15, 0.0, 1.0)
    return np.stack([v * 0.62, v * 0.40, v * 0.24], 1)


mane_mat = fur_material("ghorman_mane", fur_img, golden)
beard_mat = fur_material("ghorman_beard", fur_img, dark_brown)
fur.data.materials.clear()
fur.data.materials.append(mane_mat)

# the cards: a fan of strips hanging from the jaw line, each a tuft from the fur sheet turned upside down
TUFTS = [(0.02, 0.52, 0.19, 0.98), (0.26, 0.52, 0.48, 0.98), (0.0, 0.02, 0.24, 0.5), (0.26, 0.04, 0.48, 0.47)]
bm = bmesh.new()
uvl = bm.loops.layers.uv.new("UVMap")
mouth_z = nose[2] - 0.045 * H / 1.8
def card(root, down, side, width, length, tuft, bend):
    u0, v0, u1, v1 = tuft
    segs = 3
    verts = []
    for i in range(segs + 1):
        f = i / segs
        pt = root + down * (length * f) + Vector((0, -bend * f * f, 0))
        verts.append((bm.verts.new(pt - side * width * 0.5 * (1 - 0.4 * f)), bm.verts.new(pt + side * width * 0.5 * (1 - 0.4 * f))))
    for i in range(segs):
        a, b = verts[i]
        c, d = verts[i + 1]
        fce = bm.faces.new((a, b, d, c))
        for lp, (uu, vv) in zip(fce.loops, ((u0, v1 - (v1 - v0) * i / segs), (u1, v1 - (v1 - v0) * i / segs),
                                            (u1, v1 - (v1 - v0) * (i + 1) / segs), (u0, v1 - (v1 - v0) * (i + 1) / segs))):
            lp[uvl].uv = (uu, vv)
# jaw line: points on the skin from ear to ear around the chin, below the mouth
jaw = []
for a in np.linspace(-1.0, 1.0, 15):
    ang = a * math.radians(80)
    dirv = Vector((math.sin(ang), -math.cos(ang), 0.0))
    z = mouth_z - 0.02 * H / 1.8 - (1 - abs(a)) * 0.012
    zj = z + abs(a) ** 1.5 * 0.05
    org = Vector((0.0, g_head_c[1], zj))
    hit = BV.ray_cast(org + dirv * 0.3, -dirv)
    if hit[0] is None:
        continue
    jaw.append((hit[0] + dirv * 0.004, dirv, a))
for p, dirv, a in jaw:
    for layer in range(2):
        length = (0.20 - 0.10 * abs(a) ** 1.3) * (1.0 - 0.18 * layer) * H / 2.05
        down = Vector((dirv.x * 0.15, -0.30 - 0.1 * layer, -1.0)).normalized()
        side = Vector((math.cos(math.asin(max(-1, min(1, dirv.x)))), dirv.x * 0.3, 0.0)).normalized()
        root = p + dirv * (0.006 + 0.008 * layer) + Vector((0, 0, 0.012 * layer))
        card(root, down, side, 0.05 + 0.01 * random.random(), length, random.choice(TUFTS),
             0.03 + 0.02 * random.random())
# moustache: two drooping cards from under the nose
for sx in (-1.0, 1.0):
    root = Vector((sx * 0.012, nose[1] + 0.012, mouth_z + 0.012))
    hit = BV.ray_cast(root + Vector((0, -0.2, 0)), Vector((0, 1, 0)))
    if hit[0] is not None:
        root = hit[0] + Vector((0, -0.006, 0))
    card(root, Vector((sx * 0.8, -0.2, -0.6)).normalized(), Vector((0, 0, 1)).cross(Vector((sx, 0, 0))).normalized() * -1,
         0.03, 0.075, TUFTS[1], 0.0)
me = bpy.data.meshes.new("gear_beard")
bm.to_mesh(me)
bm.free()
beard = bpy.data.objects.new("gear_beard", me)
bpy.context.scene.collection.objects.link(beard)
me.materials.append(beard_mat)
log("beard: %d cards on %d jaw points" % (len(me.polygons) // 3, len(jaw)))

# drop whatever druid piece is left over (the staff)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and not (o.name.startswith("gear_") or o.name.startswith("ghorman_")):
        log("dropped", o.name)
        bpy.data.objects.remove(o, do_unlink=True)

# one UV layer per piece, all with the same name: joining meshes matches UV layers by name, and the FBX body, the druid
# pieces and the beard name theirs differently (the fur then sampled the clear corner of its sheet and vanished)
for o in bpy.data.objects:
    if o.type != 'MESH' or not o.data.uv_layers:
        continue
    keep = o.data.uv_layers.active or o.data.uv_layers[0]
    for l in [l for l in o.data.uv_layers if l != keep]:
        o.data.uv_layers.remove(l)
    o.data.uv_layers[0].name = "UVMap"

for o in bpy.data.objects:
    if o.type == 'MESH':
        bad = [v.index for v in o.data.vertices if not all(math.isfinite(x) for x in v.co)]
        if bad:
            raise RuntimeError("%s has %d vertices with no position" % (o.name, len(bad)))

path = os.path.join(OUT, "ghorman_src.blend")
bpy.ops.wm.save_as_mainfile(filepath=path)
log("saved", path, [o.name for o in bpy.data.objects])

# ---- 4. preview renders --------------------------------------------------------------------------------------------

if PREVIEW:
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE'
    sc.render.resolution_x, sc.render.resolution_y = 900, 1100
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.36, 0.40, 1)
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 70
    for name, yaw, z, dist, ht in (("front", 0, 1.15, 6.5, 1.15), ("q", 35, 1.15, 6.5, 1.15), ("side", 90, 1.15, 6.5, 1.15),
                                   ("back", 180, 1.15, 6.5, 1.15), ("face", 20, 1.82, 2.2, 1.82)):
        a = math.radians(yaw)
        cam.location = (dist * math.sin(a), -dist * math.cos(a), ht)
        cam.rotation_euler = (math.radians(90), 0, a)
        sc.render.filepath = os.path.join(OUT, "prep_%s.png" % name)
        bpy.ops.render.render(write_still=True)
    log("previews in", OUT)

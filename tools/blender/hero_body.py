"""Turn a downloaded character model into a hero body on the game's hero skeleton.

Input: a GLB/GLTF/FBX/OBJ/BLEND character (rigged or not). Output: assets/characters/heroes17/<name>.glb holding the
24-bone hero armature with all 132 hero clips and the character's mesh skinned to it (the route Sludge's body proved:
the hero bones move to the character's own joints and keep their directions and rolls, so every clip plays on the new
proportions; only the hips carry position keys).

Steps
  1. import the model; drop pieces matched by --drop (weapons and shields become separate props);
  2. find its joints: from its own skeleton (UE, Mixamo and most game rigs are recognised by bone names), from a
     joints file (--joints=<json>, hero bone name -> [head xyz, tail xyz] in the model's imported space, for posed
     sculpts without a rig), or estimated from the mesh (T- or A-pose only);
  3. bind it in its own pose (default, --bind=native): the hero skeleton is fitted to its joints (hero bone
     directions turned onto its limbs, its own bone lengths) and every hero clip is retargeted onto that rest, so
     each frame gives every bone the same orientation it has in the hero clip. Rigid armour then barely deforms in
     the poses the game shows most (arms down). --bind=t instead straightens the model into the hero's T-pose;
  4. scale to --height (head top, feet at z = 0), centre the hips on the origin, face -Y;
  5. skin weights: the model's own bone weights summed into the hero bones (every source bone goes to the nearest
     ancestor that maps to a hero bone), or automatic weights for unrigged models;
  6. join, decimate to --faces (UV seams kept, so the model's own textures still fit), shrink textures to --tex;
  7. move the hero bones onto its joints, bind, export with every hero clip.

Run: "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/hero_body.py --
       --src=<file> --name=<out name> [--height=1.85] [--faces=30000] [--tex=2048] [--yaw=0] [--drop=<regex>]
       [--joints=<json>] [--preview=<dir>] [--bake] [--cut=x0,x1,y0,y1,z0,z1;...] [--bind=native|t]
       [--rigid=bone:cap:x1,y1,z1,x2,y2,z2,r;bone:ball:x,y,z,r] [--cloth=<material regex>] [--hue=from:to:width[:sat[:val]]] [--gray=1.0]
       [--glide=<idle clip>] [--reach=0] [--smooth=4] [--norig] [--move=regex:dx,dy,dz;...] [--body_piece=<regex>] [--capture] [--keep=<regex>] [--posture] [--fist] [--unmix=1] [--split=1] [--sleeve=r,reach]
"""
import bpy
import bmesh
import json
import math
import os
import re
import sys
import time
import numpy as np
from mathutils import Vector, Matrix, Quaternion

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import texops  # noqa: E402

ROOT = "A:/Python/woa"
HERO = ROOT + "/assets/characters/hero/hero.glb"
OUT_DIR = ROOT + "/assets/characters/heroes17"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(name, default):
    for a in ARGS:
        if a == "--" + name and isinstance(default, bool):
            return True
        if a.startswith("--%s=" % name):
            v = a.split("=", 1)[1]
            return type(default)(v) if not isinstance(default, bool) else v not in ("0", "false")
    return default

SRC = arg("src", "")
NAME = arg("name", "body")
HEIGHT = arg("height", 1.85)
FACES = arg("faces", 30000)
TEX = arg("tex", 2048)
YAW = arg("yaw", 0.0)
DROP = arg("drop", "")
KEEP = arg("keep", "")                         # regex of pieces never dropped as helpers (a bone-parented weapon)
JOINTS = arg("joints", "")
PREVIEW = arg("preview", "")
OUT = arg("out", OUT_DIR + "/" + NAME + ".glb")
POSTURE = arg("posture", False)                # keep the model's own spine, neck and head lean under every clip (hunched beasts)
CAPTURE = arg("capture", False)                # every vertex keeps only its nearest bone, its parent and children (posed
                                               # models whose hand rests on a cheek or arm against the chest)
BODY_PIECE = arg("body_piece", "")             # regex of the skin pieces: weights are worked out on them alone, and
                                               # clothes, hair and gear take the weights of the skin under them
MOVE = arg("move", "")                         # "regex:dx,dy,dz;..." shift pieces a bad conversion displaced (model space)
NORIG = arg("norig", False)                    # ignore the model's own skeleton (a broken conversion): take its posed mesh
BAKE = arg("bake", False)                      # dense generated or scanned meshes: bake onto a clean low-poly copy
CUT = arg("cut", "")                           # "x0,x1,y0,y1,z0,z1;cap:x1,y1,z1,x2,y2,z2,r;ball:x,y,z,r" to delete
BIND = arg("bind", "native")
CLOTH = arg("cloth", "")                       # regex of material names the hanging-cloth rule may touch (all: "")
HUE = arg("hue", "")                           # "from:to:width[:sat[:val]]" hue remap (degrees) on the colour maps
GRAY = arg("gray", 1.0)                        # brightness gain for unsaturated texels (steel, bone, white cloth)
SMOOTH = arg("smooth", 4)                      # whole-mesh weight smoothing passes after the reach and cloth rules
REACH_K = arg("reach", 0.0)                   # limb reach limit (x the default reach; 0 = off): frees cloth from a limb it brushes
# how far (m, for a 1.8 m hero) an arm bone's skin reaches from the bone: pauldrons and sleeves are within it, a cape or
# a coat skirt hanging beside the arm is not (run 2026-10-17 f: the coats webbed up with the arms in big swings)
REACH = {"upper_arm": 0.15, "forearm": 0.105, "hand": 0.10}
UNMIX = arg("unmix", True)                     # no vertex mixes a forearm or hand with the hips or legs (split there)
SPLIT = arg("split", True)                     # arm and body split by surfaces and whole pieces (arm_split.py, run
                                               # 2026-10-18 d: hand remnants), after the unmix
SLEEVE = arg("sleeve", "")                     # "radius,reach" (m, 1.8 m body): wide sleeves hanging past the hand go
                                               # with the arm (Azrin)
FIST = arg("fist", False)                      # curl the source rig's fingers into a fist round the weapon (open hands)
GLIDE = arg("glide", "")                       # "<idle clip>": also make "glide_fwd", a floating move pose
RIGID = arg("rigid", "")                       # "bone:cap:x1,y1,z1,x2,y2,z2,r;bone:ball:x,y,z,r" (model space) ride
                                               # one bone only: a staff in a fist, a buckle, a held lantern
PLACE_T = [Matrix.Identity(4)]                 # model space -> game space (set by place())                   # native: bind in the model's own pose, retarget the clips; t: T-pose
TEX_DIR = ROOT + "/work/heroes17_tex"                # baked maps (the GLB embeds them; kept for checks)
T0 = time.time()

HERO_BONES = ["root", "hips", "spine", "chest", "neck", "head",
              "shoulder.L", "upper_arm.L", "forearm.L", "hand.L", "weapon.L",
              "shoulder.R", "upper_arm.R", "forearm.R", "hand.R", "weapon.R",
              "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R", "shin.R", "foot.R", "toe.R"]
DEFORM = [b for b in HERO_BONES if b not in ("root", "weapon.L", "weapon.R")]


def log(*a):
    print("[hero_body %5.1fs]" % (time.time() - T0), *a, flush=True)


def select_only(*objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def world_coords(o, evaluated=False):
    if evaluated:
        dg = bpy.context.evaluated_depsgraph_get()
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        co = np.array([v.co[:] for v in me.vertices]) if len(me.vertices) else np.zeros((0, 3))
        e.to_mesh_clear()
    else:
        co = np.empty(len(o.data.vertices) * 3)
        o.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
    if len(co) == 0:
        return co
    m = np.array(o.matrix_world)
    return (np.c_[co, np.ones(len(co))] @ m.T)[:, :3]


# ---- source bone names -> hero bones ---------------------------------------------------------------------------------

def side_of(n):
    """'L', 'R' or '' from a normalised bone name."""
    if re.search(r"(^|[^a-z])(left|l)([^a-z]|$)", n) or n.startswith("left") or re.search(r"[._ -]l$", n) or n.endswith("_l"):
        return "L"
    if re.search(r"(^|[^a-z])(right|r)([^a-z]|$)", n) or n.startswith("right") or re.search(r"[._ -]r$", n) or n.endswith("_r"):
        return "R"
    if "left" in n:
        return "L"
    if "right" in n:
        return "R"
    return ""


def norm(name):
    n = name.lower()
    n = re.sub(r"^(mixamorig\d*[:_]|def[-_]|bip\d*[ _-]|bone_|b_|cc_base_|rig[:_]|armature[:_])", "", n)
    n = re.sub(r"_\d+$", "", n)                 # Sketchfab's converter numbers every node: upperarm_l_012
    return n


def core_role(name):
    """The hero bone this source bone *is* (not just belongs to), or ''."""
    n = norm(name)
    s = side_of(n)
    base = re.sub(r"(left|right)", "", n)
    base = re.sub(r"([._ -](l|r))$|^(l|r)[._ -]", "", base)
    base = base.replace("_", "").replace(".", "").replace(" ", "").replace("-", "")
    if base in ("pelvis", "hips", "hip", "pelvisbone"):
        return "hips"
    if re.fullmatch(r"(spine|torso|abdomen|stomach)\d*", base) or base in ("spine0", "spine1", "spine01"):
        return "spine*"
    if base.startswith("chest") or base.startswith("upperchest") or base == "ribcage":
        return "chest"
    if re.fullmatch(r"neck(twist)?\d*", base):          # CC rigs name theirs NeckTwist01, NeckTwist02
        return "neck*"
    if base in ("head", "headbone"):
        return "head"
    if not s:
        return ""
    if base in ("clavicle", "shoulder", "collar", "collarbone"):
        return "shoulder." + s
    if base in ("upperarm", "arm", "uparm", "humerus"):
        return "upper_arm." + s
    if base in ("lowerarm", "forearm", "elbow", "lowarm"):
        return "forearm." + s
    if base in ("hand", "wrist", "palm"):
        return "hand." + s
    if base in ("thigh", "upleg", "upperleg", "femur", "hipjoint"):
        return "thigh." + s
    if base in ("calf", "leg", "shin", "lowerleg", "knee", "lowleg", "tibia"):
        return "shin." + s
    if base in ("foot", "ankle"):
        return "foot." + s
    if base in ("ball", "toe", "toes", "toebase", "toe0", "toe1", "toes01"):
        return "toe." + s
    return ""


def map_rig(src_arm):
    """Source bone name -> hero bone, for every source bone (via the nearest mapped ancestor), plus the source bones
    that define each hero joint."""
    bones = src_arm.data.bones
    role = {b.name: core_role(b.name) for b in bones}
    # spine chains: the lowest spine bone is 'spine', the rest 'chest'; with an explicit chest the spines below it are
    # split the same way; several neck bones -> the first is 'neck'
    spines = sorted([b for b in bones if role[b.name] == "spine*"], key=lambda b: b.head_local.z)
    has_chest = any(r == "chest" for r in role.values())
    for i, b in enumerate(spines):
        role[b.name] = "spine" if i == 0 or (not has_chest and i < len(spines) // 2) else "chest"
    if len(spines) == 1 and not has_chest:
        role[spines[0].name] = "spine"
    necks = sorted([b for b in bones if role[b.name] == "neck*"], key=lambda b: b.head_local.z)
    for i, b in enumerate(necks):
        role[b.name] = "neck"
    to_hero = {}
    for b in bones:
        p = b
        while p is not None and not role.get(p.name):
            p = p.parent
        to_hero[b.name] = role[p.name] if p is not None else "hips"
    # the defining bone per hero joint: the lowest-in-chain bone with that role
    defining = {}
    for b in bones:
        r = role[b.name]
        if not r:
            continue
        if r not in defining:
            defining[r] = b
        else:
            # keep the one nearer the root of the hierarchy (first spine, first neck)
            def depth(x):
                d = 0
                while x.parent:
                    x = x.parent
                    d += 1
                return d
            if depth(b) < depth(defining[r]):
                defining[r] = b
    defining = {k: b.name for k, b in defining.items()}
    missing = [h for h in ("hips", "spine", "neck", "head", "upper_arm.L", "forearm.L", "hand.L", "thigh.L", "shin.L",
                           "foot.L", "upper_arm.R", "forearm.R", "hand.R", "thigh.R", "shin.R", "foot.R") if h not in defining]
    return to_hero, defining, missing


# ---- 1. import -------------------------------------------------------------------------------------------------------

def import_src(path):
    before = set(bpy.data.objects)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=True)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".blend":
        with bpy.data.libraries.load(path) as (src, dst):
            dst.objects = src.objects
        for o in dst.objects:
            if o is not None:
                bpy.context.scene.collection.objects.link(o)
    else:
        raise RuntimeError("unknown model type " + ext)
    new = [o for o in bpy.data.objects if o not in before]
    log("imported %d objects from %s" % (len(new), path))
    return new


def tidy(objs):
    """Unparent everything into world space (keeping armature parenting), apply transforms, drop non-mesh helpers and
    pieces matched by --drop."""
    names = [o.name for o in objs]
    arms = [o for o in objs if o.type == 'ARMATURE']
    arm = max(arms, key=lambda a: len(a.data.bones)) if arms else None
    meshes = [o for o in objs if o.type == 'MESH']
    drop = re.compile(DROP, re.I) if DROP else None
    keep = []
    for m in meshes:
        mats = " ".join(s.material.name for s in m.material_slots if s.material)
        if drop and (drop.search(m.name) or drop.search(m.data.name) or drop.search(mats)):
            log("  dropped piece", m.name, "(", mats, ")")
            bpy.data.objects.remove(m, do_unlink=True)
            continue
        if len(m.data.vertices) == 0 or (m.name.startswith("Icosphere") and not any(x.type == 'ARMATURE' for x in m.modifiers)
                                         and not (KEEP and re.search(KEEP, m.name, re.I))):
            log("  dropped helper", m.name) if len(m.data.vertices) else None
            bpy.data.objects.remove(m, do_unlink=True)
            continue
        keep.append(m)
    for name in names:
        o = bpy.data.objects.get(name)
        if o is not None and o not in keep and o != arm:
            if o.type in ('EMPTY', 'CAMERA', 'LIGHT', 'ARMATURE', 'CURVE'):
                # children keep their world transform
                for ch in [c for c in bpy.data.objects if c.parent == o]:
                    mw = ch.matrix_world.copy()
                    ch.parent = None
                    ch.matrix_world = mw
                bpy.data.objects.remove(o, do_unlink=True)
    # with a rig, loose pieces far outside the skinned body are helpers (spheres, cameras' targets): drop them
    if arm:
        skinned = [m for m in keep if any(x.type == 'ARMATURE' for x in m.modifiers)]
        if skinned:
            co = np.vstack([world_coords(m) for m in skinned])
            lo_, hi_ = co.min(0), co.max(0)
            pad = (hi_ - lo_) * 0.15
            for m in [m for m in keep if m not in skinned and not (KEEP and re.search(KEEP, m.name, re.I))]:
                c = world_coords(m)
                if (c.min(0) < lo_ - pad).any() or (c.max(0) > hi_ + pad).any():
                    log("  dropped loose piece outside the body", m.name)
                    keep.remove(m)
                    bpy.data.objects.remove(m, do_unlink=True)
    for m in keep:
        if m.parent and m.parent != arm:
            mw = m.matrix_world.copy()
            m.parent = None
            m.matrix_world = mw
    log("kept %d mesh pieces (%d faces), rig: %s" % (len(keep), sum(len(m.data.polygons) for m in keep),
        "%s (%d bones)" % (arm.name, len(arm.data.bones)) if arm else "none"))
    return arm, keep



def islands(co, edges, keep=None):
    """Connected pieces of a mesh (vertices at the same place count as joined: UV seams split them): a label per
    vertex (-1 where keep is False)."""
    n = len(co)
    span = float(np.ptp(co, axis=0).max()) if n else 1.0
    _u, weld = np.unique(np.round(co / max(span * 1e-6, 1e-12)).astype(np.int64), axis=0, return_inverse=True)
    weld = weld.ravel()
    lab = np.arange(weld.max() + 1 if n else 0)
    e = weld[edges]
    if keep is not None:
        e = e[keep[edges[:, 0]] & keep[edges[:, 1]]]
    while True:
        m_ = np.minimum(lab[e[:, 0]], lab[e[:, 1]])
        new = lab.copy()
        np.minimum.at(new, e[:, 0], m_)
        np.minimum.at(new, e[:, 1], m_)
        new = new[new]
        new = new[new]
        if np.array_equal(new, lab):
            break
        lab = new
    out = lab[weld]
    if keep is not None:
        out = np.where(keep, out, -1)
    return out


def cut_remnants(m, co, kill):
    """Vertices of small pieces the cut broke off a bigger piece (a sliver of a fused staff's shaft left beside the
    fist, a chip of its head, a sword pommel floating by the hand: Azrin and Ezee, run 2026-10-18)."""
    ed = np.empty(len(m.data.edges) * 2, dtype=np.int64)
    m.data.edges.foreach_get("vertices", ed)
    ed = ed.reshape(-1, 2)
    if not len(ed):
        return np.zeros(len(co), dtype=bool)
    keep = ~kill
    before = islands(co, ed)
    after = islands(co, ed, keep)
    total = int(keep.sum())
    out = np.zeros(len(co), dtype=bool)
    ids, counts = np.unique(after[keep], return_counts=True)
    kept_before = {}
    b_ids, b_counts = np.unique(before[keep], return_counts=True)
    kept_before = dict(zip(b_ids.tolist(), b_counts.tolist()))
    for i, c in zip(ids.tolist(), counts.tolist()):
        if c >= 0.02 * total:
            continue
        vs = np.where(after == i)[0]
        b = int(before[vs[0]])
        if c < kept_before.get(b, 0):                # split off a bigger piece by the cut
            out[vs] = True
    return out


def cut_boxes(meshes):
    """Delete the vertices inside the --cut boxes (a weapon fused into a hand, a staff through a sleeve)."""
    if not CUT:
        return
    specs = [c.strip() for c in CUT.split(";") if c.strip()]
    for m in meshes:
        co = world_coords(m)
        kill = np.zeros(len(co), dtype=bool)
        for c in specs:
            if c.startswith("cap:"):
                v = [float(x) for x in c[4:].split(",")]
                kill |= seg_dist(co, Vector(v[0:3]), Vector(v[3:6])) < v[6]
            elif c.startswith("ball:"):
                v = [float(x) for x in c[5:].split(",")]
                kill |= np.linalg.norm(co - np.array(v[0:3]), axis=1) < v[3]
            else:
                x0, x1, y0, y1, z0, z1 = [float(x) for x in c.split(",")]
                kill |= ((co[:, 0] >= x0) & (co[:, 0] <= x1) & (co[:, 1] >= y0) & (co[:, 1] <= y1)
                         & (co[:, 2] >= z0) & (co[:, 2] <= z1))
        if kill.any():
            extra = cut_remnants(m, co, kill)
            if extra.any():
                log("  cut %d more vertices: loose remnants of the cut prop (%s)" % (int(extra.sum()), m.name))
                kill |= extra
            bm = bmesh.new()
            bm.from_mesh(m.data)
            bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[bm.verts[i] for i in np.where(kill)[0]], context='VERTS')
            bm.to_mesh(m.data)
            bm.free()
            log("  cut %d vertices from %s" % (int(kill.sum()), m.name))


def gpu_cycles():
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                if any(d.type == kind for d in prefs.devices):
                    for d in prefs.devices:
                        d.use = d.type == kind
                    sc.cycles.device = 'GPU'
                    return kind
            except TypeError:
                continue
    except Exception:
        pass
    sc.cycles.device = 'CPU'
    return "CPU"


def hue_remap(img):
    """--hue / --gray on one colour map (tools/blender/texops.py)."""
    texops.hue_remap(img, HUE, GRAY)


def bake_low(hi):
    """A clean game mesh from a dense one: collapse-decimate a copy to --faces, unwrap it, and bake the dense
    mesh's colour, roughness, metal and surface detail (normal map) onto it. Returns the low mesh (same pose)."""
    os.makedirs(TEX_DIR, exist_ok=True)
    lo = hi.copy()
    lo.data = hi.data.copy()
    lo.name = NAME
    bpy.context.collection.objects.link(lo)
    for g in list(lo.vertex_groups):
        lo.vertex_groups.remove(g)
    select_only(lo)
    d = lo.modifiers.new("dec", 'DECIMATE')
    d.decimate_type = 'COLLAPSE'
    d.ratio = FACES / max(1, sum(len(p.vertices) - 2 for p in lo.data.polygons))
    bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.delete_loose()
    bpy.ops.mesh.select_all(action='SELECT')
    while lo.data.uv_layers:
        lo.data.uv_layers.remove(lo.data.uv_layers[0])
    lo.data.uv_layers.new(name="UVMap")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55.0), island_margin=0.003, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.002, scale=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.shade_smooth()
    log("low mesh %d triangles, unwrapped" % sum(len(p.vertices) - 2 for p in lo.data.polygons))
    dev = gpu_cycles()
    sc = bpy.context.scene
    sc.cycles.samples = 1
    sc.render.bake.use_selected_to_active = True
    co = world_coords(lo)
    H = co[:, 2].max() - co[:, 2].min()
    sc.render.bake.cage_extrusion = 0.012 * H
    sc.render.bake.max_ray_distance = 0.03 * H
    sc.render.bake.margin = 8
    srcs = []
    for slot in hi.material_slots:
        m = slot.material
        if not m or not m.node_tree:
            continue
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        out = next((n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL'), None)
        if bsdf is None or out is None:
            continue
        feeds = {}
        for k in ("Base Color", "Roughness", "Metallic"):
            sock = bsdf.inputs[k]
            feeds[k] = sock.links[0].from_socket if sock.links else sock.default_value
        srcs.append((m, nt, bsdf, out, feeds))
    lm = bpy.data.materials.new(NAME + "_mat")
    lm.use_nodes = True
    lnt = lm.node_tree
    lbsdf = lnt.nodes["Principled BSDF"]
    lo.data.materials.clear()
    lo.data.materials.append(lm)
    imgs = {}
    for key, cs in (("color", 'sRGB'), ("rough", 'Non-Color'), ("metal", 'Non-Color'), ("normal", 'Non-Color')):
        img = bpy.data.images.new("%s_%s" % (NAME, key), TEX, TEX, alpha=False)
        img.colorspace_settings.name = cs
        imgs[key] = img
    tn = lnt.nodes.new("ShaderNodeTexImage")
    lnt.nodes.active = tn
    select_only(lo, hi)
    hi.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    for key, sock in (("color", "Base Color"), ("rough", "Roughness"), ("metal", "Metallic")):
        tn.image = imgs[key]
        for m, nt, bsdf, out, feeds in srcs:
            em = nt.nodes.new("ShaderNodeEmission")
            em.name = "__bake_em"
            v = feeds[sock]
            if isinstance(v, bpy.types.NodeSocket):
                nt.links.new(v, em.inputs["Color"])
            elif hasattr(v, "__len__"):
                em.inputs["Color"].default_value = (v[0], v[1], v[2], 1.0)
            else:
                em.inputs["Color"].default_value = (v, v, v, 1.0)
            nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        bpy.ops.object.bake(type='EMIT')
        for m, nt, bsdf, out, feeds in srcs:
            nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
            for n in [n for n in nt.nodes if n.name.startswith("__bake_em")]:
                nt.nodes.remove(n)
        log("  baked %s (%s)" % (key, dev))
    tn.image = imgs["normal"]
    bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT')
    log("  baked normal")
    for key, img in imgs.items():
        img.filepath_raw = "%s/%s_%s.png" % (TEX_DIR, NAME, key)
        img.file_format = 'PNG'
        img.save()
    if HUE or GRAY != 1.0:
        # edits made straight after a bake are lost when the image is saved: recolour the saved file instead
        # a baked image or one loaded from a file does not save edited pixels back reliably: the recoloured pixels
        # go into a freshly generated image, which saves as the bakes do
        path = imgs["color"].filepath_raw
        raw = path[:-4] + "_bake.png"
        os.replace(path, raw)
        imgs["color"].filepath_raw = raw
        imgs["color"].filepath = raw
        src = bpy.data.images.load(raw, check_existing=False)
        hue_remap(src)
        w, h = src.size
        img = bpy.data.images.new(NAME + "_colour", w, h, alpha=False)
        img.pixels[:] = src.pixels[:]
        img.filepath_raw = path
        img.file_format = 'PNG'
        img.save()
        bpy.data.images.remove(src)
        imgs["color"] = img
    lnt.nodes.remove(tn)
    def tex(img, x, y):
        n = lnt.nodes.new("ShaderNodeTexImage")
        n.image = img
        n.location = (x, y)
        return n
    lnt.links.new(tex(imgs["color"], -500, 300).outputs["Color"], lbsdf.inputs["Base Color"])
    lnt.links.new(tex(imgs["rough"], -500, 0).outputs["Color"], lbsdf.inputs["Roughness"])
    lnt.links.new(tex(imgs["metal"], -500, -250).outputs["Color"], lbsdf.inputs["Metallic"])
    nm = lnt.nodes.new("ShaderNodeNormalMap")
    lnt.links.new(tex(imgs["normal"], -800, -500).outputs["Color"], nm.inputs["Color"])
    lnt.links.new(nm.outputs["Normal"], lbsdf.inputs["Normal"])
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    return lo


# ---- native bind: the hero skeleton in the model's own pose, clips retargeted ----------------------------------------

def bone_depth(b):
    n = 0
    while b.parent:
        b = b.parent
        n += 1
    return n


def t_rig(arm, J):
    """The hero rig with the model's bone lengths and positions, hero bone directions (the clips' rest)."""
    select_only(arm)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones
    old = {b.name: (b.head.copy(), b.tail.copy()) for b in eb}
    for b in eb:
        b.use_connect = False
    def L(n, lo=0.02):
        return max(lo, (J[n][1] - J[n][0]).length)
    def put(n, head, length):
        d = (old[n][1] - old[n][0]).normalized()
        eb[n].head = head
        eb[n].tail = head + d * length
    hj = J["hips"][0]
    put("root", Vector((0.0, 0.0, 0.0)), max(0.1, hj.z))
    put("hips", Vector((0.0, hj.y, hj.z)), L("hips", 0.05))
    for n in ("spine", "chest", "neck", "head"):
        h = J[n][0]
        put(n, Vector((0.0, h.y, h.z)), L(n, 0.05))
    hero_hand = (old["hand.L"][1] - old["hand.L"][0]).length
    for s in ("L", "R"):
        sh = J["upper_arm." + s][0]
        cl = J["shoulder." + s][0]
        put("shoulder." + s, cl, max(0.02, (sh - cl).length))
        put("upper_arm." + s, sh, L("upper_arm." + s, 0.1))
        put("forearm." + s, eb["upper_arm." + s].tail.copy(), L("forearm." + s, 0.1))
        hand_len = max(0.05, L("hand." + s) * 0.55)
        hh = eb["forearm." + s].tail.copy()
        put("hand." + s, hh, hand_len)
        k = hand_len / hero_hand
        off_h = (old["weapon." + s][0] - old["hand." + s][0]) * k
        off_t = (old["weapon." + s][1] - old["hand." + s][0]) * k
        eb["weapon." + s].head = hh + off_h
        eb["weapon." + s].tail = hh + off_t
        put("thigh." + s, J["thigh." + s][0].copy(), L("thigh." + s, 0.1))
        put("shin." + s, eb["thigh." + s].tail.copy(), L("shin." + s, 0.1))
        put("foot." + s, eb["shin." + s].tail.copy(), L("foot." + s, 0.05))
        put("toe." + s, eb["foot." + s].tail.copy(), L("toe." + s, 0.03))
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.data.pose_position = 'POSE'


def a_rig(t_arm, J):
    """A copy of the T rig turned bone by bone (parents first) onto the model's limb directions, made its rest."""
    a = t_arm.copy()
    a.data = t_arm.data.copy()
    a.name = "HeroRigNative"
    a.animation_data_clear()
    bpy.context.collection.objects.link(a)
    a.data.pose_position = 'POSE'
    select_only(a)
    bpy.ops.object.mode_set(mode='POSE')
    for pb in a.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for pb in sorted(a.pose.bones, key=lambda p: bone_depth(p.bone)):
        if pb.name not in J or pb.name in ("root", "weapon.L", "weapon.R"):
            continue
        want = (J[pb.name][1] - J[pb.name][0])
        cur = pb.tail - pb.head
        if want.length < 1e-6 or cur.length < 1e-6:
            continue
        q = cur.normalized().rotation_difference(want.normalized())
        R = Matrix.Translation(pb.head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-pb.head)
        pb.matrix = R @ pb.matrix
        bpy.context.view_layer.update()
    for s in ("L", "R"):
        if "grip." + s not in J:
            continue
        # the hand turns about its own axis until the weapon bone's axis lies along the fist's grip axis, and the
        # weapon bone moves into the fist (fit_hands)
        pb = a.pose.bones["hand." + s]
        wb = a.pose.bones["weapon." + s]
        hy = (pb.tail - pb.head).normalized()
        wy = (wb.tail - wb.head).normalized()
        g0, g1 = J["grip." + s]
        k = (g1 - g0).normalized()
        wy = (wy - hy * wy.dot(hy)).normalized()
        k = (k - hy * k.dot(hy)).normalized()
        ang = math.atan2(hy.dot(wy.cross(k)), wy.dot(k))
        R = Matrix.Translation(pb.head) @ Matrix.Rotation(ang, 4, hy) @ Matrix.Translation(-pb.head)
        pb.matrix = R @ pb.matrix
        bpy.context.view_layer.update()
        m = wb.matrix.copy()
        m.translation = g0
        wb.matrix = m
        bpy.context.view_layer.update()
        log("  hand.%s rolled %.0f deg to the grip; weapon bone in the fist" % (s, math.degrees(ang)))
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    for n in ("upper_arm.L", "forearm.L", "hand.L", "thigh.L"):
        b = a.data.bones[n]
        log("  native %-12s %s -> %s (model %s)" % (n, tuple(round(x, 3) for x in b.head_local),
            tuple(round(x, 3) for x in b.tail_local), tuple(round(x, 3) for x in J[n][0])))
    return a


# a floating caster moving forward: the chest leans in, the head stays up, the legs trail behind with the knees
# bent and the toes pointed (one leg a little higher), on top of her idle (degrees about each bone's own X axis:
# positive swings a leg forward or tips the trunk forward)
GLIDE_POSE = {"spine": 7.0, "chest": 5.0, "neck": -6.0, "head": -6.0,
              "thigh.L": -14.0, "shin.L": -38.0, "foot.L": -30.0,
              "thigh.R": -24.0, "shin.R": -52.0, "foot.R": -34.0}


def make_glide(arm):
    """glide_fwd: the idle clip with the floating-forward pose laid over it (same length, so it loops the same)."""
    src = bpy.data.actions.get(GLIDE)
    if src is None:
        log("no clip %s for the glide" % GLIDE)
        return
    sc = bpy.context.scene
    arm.animation_data_create()
    arm.data.pose_position = 'POSE'
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    arm.animation_data.action = src
    if hasattr(arm.animation_data, "action_slot") and len(getattr(src, "slots", [])):
        arm.animation_data.action_slot = src.slots[0]
    f0, f1 = int(math.floor(src.frame_range[0])), int(math.ceil(src.frame_range[1]))
    frames = list(range(f0, f1 + 1))
    rec = []
    for f in frames:
        sc.frame_set(f)
        rec.append({pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in arm.pose.bones})
    new = bpy.data.actions.new("glide_fwd")
    arm.animation_data.action = new
    for f, pose in zip(frames, rec):
        for pb in arm.pose.bones:
            q, loc = pose[pb.name]
            if pb.name in GLIDE_POSE:
                q = q @ Quaternion((1.0, 0.0, 0.0), math.radians(GLIDE_POSE[pb.name]))
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            if pb.name in ("root", "hips"):
                pb.location = loc
                pb.keyframe_insert("location", frame=f, group=pb.name)
    arm.animation_data.action = None
    new.use_fake_user = True
    log("made glide_fwd from %s (%d frames)" % (GLIDE, len(frames)))


def retarget(t_arm, a_arm):
    """Every clip on the T rig becomes a clip on the native rig in which every bone has the same orientation in the
    armature's space on every frame (hips and root also keep their positions)."""
    sc = bpy.context.scene
    acts = [x for x in bpy.data.actions]
    order = sorted([b.name for b in a_arm.data.bones], key=lambda n: bone_depth(a_arm.data.bones[n]))
    restA = {n: a_arm.data.bones[n].matrix_local.copy() for n in order}
    parent = {n: (a_arm.data.bones[n].parent.name if a_arm.data.bones[n].parent else None) for n in order}
    relA = {n: (restA[parent[n]].inverted() @ restA[n]) if parent[n] else restA[n] for n in order}
    relA_inv = {n: relA[n].inverted() for n in order}
    # --posture: the trunk keeps its own lean (its rest turn away from the hero's rest) on top of the clip
    lean = {}
    if POSTURE:
        for n in ("spine", "chest", "neck", "head"):
            rt = t_arm.data.bones[n].matrix_local.to_3x3()
            ra = a_arm.data.bones[n].matrix_local.to_3x3()
            lean[n] = (rt.inverted() @ ra).to_4x4()
    t_arm.animation_data_create()
    a_arm.animation_data_create()
    for pb in a_arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    keep_loc = {"root", "hips"}
    t0 = time.time()
    nframes = 0
    for act in acts:
        t_arm.animation_data.action = act
        if hasattr(t_arm.animation_data, "action_slot") and len(getattr(act, "slots", [])):
            t_arm.animation_data.action_slot = act.slots[0]
        f0, f1 = int(math.floor(act.frame_range[0])), int(math.ceil(act.frame_range[1]))
        frames = list(range(f0, f1 + 1))
        keys = {n: [] for n in order}
        for f in frames:
            sc.frame_set(f)
            P = {n: t_arm.pose.bones[n].matrix.copy() for n in order}
            for n, L_ in lean.items():
                tr = P[n].translation.copy()
                P[n] = P[n] @ L_
                P[n].translation = tr
            for n in order:
                if parent[n]:
                    basis = relA_inv[n] @ P[parent[n]].inverted() @ P[n]
                else:
                    basis = relA_inv[n] @ P[n]
                keys[n].append((basis.to_quaternion(), basis.to_translation()))
        name = act.name
        new = bpy.data.actions.new(name + "__native")
        a_arm.animation_data.action = new
        for n in order:
            pb = a_arm.pose.bones[n]
            prev = None
            for f, (q, t) in zip(frames, keys[n]):
                if prev is not None and prev.dot(q) < 0.0:
                    q = -q                              # keep quaternions on one side (no flips when interpolating)
                prev = q
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=f, group=n)
                if n in keep_loc:
                    pb.location = t
                    pb.keyframe_insert("location", frame=f, group=n)
        nframes += len(frames)
        t_arm.animation_data.action = None
        a_arm.animation_data.action = None
        bpy.data.actions.remove(act)
        new.name = name
        new.use_fake_user = True
    log("retargeted %d clips (%d frames) onto the native rest in %.1fs" % (len(acts), nframes, time.time() - t0))


CHAINS = {
    "trunk": ("hips", "spine", "chest", "neck", "head"),
    "arm.L": ("shoulder.L", "upper_arm.L", "forearm.L", "hand.L"),
    "arm.R": ("shoulder.R", "upper_arm.R", "forearm.R", "hand.R"),
    "leg.L": ("thigh.L", "shin.L", "foot.L", "toe.L"),
    "leg.R": ("thigh.R", "shin.R", "foot.R", "toe.R"),
}
CHAIN_OF = {b: c for c, bs in CHAINS.items() for b in bs}


def island_gating(m, J):
    """Rigid pieces (a hip plate, a gauntlet, a buckle) follow only the limb nearest their centre, plus the trunk.
    In a model's own pose a hand often rests against a hip plate, and weights computed on the merged stand-in bleed
    across, so the plate would swing with the arm."""
    co = world_coords(m)
    k = HEIGHT / 1.8
    # pieces by position: vertices split at texture seams are welded first (on a copy)
    bm = bmesh.new()
    bm.from_mesh(m.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005 * k)
    bm.verts.ensure_lookup_table()
    comp = np.full(len(bm.verts), -1, dtype=np.int64)
    n = 0
    for v in bm.verts:
        if comp[v.index] >= 0:
            continue
        stack = [v]
        while stack:
            x = stack.pop()
            if comp[x.index] >= 0:
                continue
            comp[x.index] = n
            stack.extend(e.other_vert(x) for e in x.link_edges if comp[e.other_vert(x).index] < 0)
        n += 1
    from mathutils import kdtree
    kd = kdtree.KDTree(len(bm.verts))
    for v in bm.verts:
        kd.insert(m.matrix_world @ v.co, v.index)
    kd.balance()
    wcomp = comp
    comp = np.array([wcomp[kd.find(c)[1]] for c in co], dtype=np.int64)
    bm.free()
    segs = {b: J[b] for b in CHAIN_OF if b in J}
    names = {g.index: g.name for g in m.vertex_groups}
    groups = {g.name: g for g in m.vertex_groups}
    gated = 0
    for c in range(n):
        idx = np.where(comp == c)[0]
        pts = co[idx]
        diag = np.linalg.norm(pts.max(0) - pts.min(0))
        if diag > 0.35 * k or len(idx) < 3:
            continue                                   # big pieces (the body, a cloak) keep their own weights
        cen = pts.mean(0)
        best, bd = None, 1e9
        for b, (h, t) in segs.items():
            d = float(seg_dist(cen[None, :], h, t)[0])
            if d < bd:
                best, bd = b, d
        allowed = {"trunk", CHAIN_OF[best]}
        changed = False
        for vi in idx:
            v = m.data.vertices[int(vi)]
            keep, drop = [], []
            for g in v.groups:
                nm = names[g.group]
                (keep if CHAIN_OF.get(nm, "trunk") in allowed else drop).append((nm, g.weight))
            if not drop:
                continue
            changed = True
            for nm, _w in drop:
                groups[nm].remove([int(vi)])
            tot = sum(w for _n, w in keep)
            if tot <= 1e-6:
                groups[best].add([int(vi)], 1.0, 'REPLACE')
            else:
                for nm, w in keep:
                    groups[nm].add([int(vi)], w / tot, 'REPLACE')
        gated += changed
    log("  island gating: %d pieces, %d kept to their nearest limb" % (n, gated))



def transfer_by_bone(dst, src, J):
    """Clothes, hair and gear take the weights of the skin under them, but only from skin that belongs to the same
    part of the body (the bone nearest the piece's vertex, its parent or its children): where a posed model rests a
    hand on its cheek or an arm across its belly, the nearest skin can be the wrong limb."""
    from mathutils import kdtree
    sco = world_coords(src)
    kd = kdtree.KDTree(len(sco))
    for i, c in enumerate(sco):
        kd.insert(c, i)
    kd.balance()
    sn = {g.index: g.name for g in src.vertex_groups}
    sw = []
    dom = []
    for v in src.data.vertices:
        ws = [(sn[g.group], g.weight) for g in v.groups if g.weight > 0.0]
        sw.append(ws)
        dom.append(max(ws, key=lambda x: x[1])[0] if ws else "")
    bones = [b for b in J if b in CHAIN_OF]
    near_of = {}
    dco = world_coords(dst)
    d = np.stack([seg_dist(dco, *J[b]) for b in bones], axis=1)
    nearest = np.array(bones)[np.argmin(d, axis=1)]
    family = {}
    hero = {b.name: b for b in bpy.data.objects["HeroRigNative"].data.bones} if "HeroRigNative" in bpy.data.objects else {}
    for b in bones:
        fam = {b}
        hb = hero.get(b)
        if hb is not None:
            if hb.parent:
                fam.add(hb.parent.name)
            fam.update(c.name for c in hb.children)
        family[b] = fam
    # vertices a prep script pinned (vertex group "pin.<bone>", e.g. airah_prep.py's tail) keep that bone alone
    pinned = {}
    for g in dst.vertex_groups:
        if g.name.startswith("pin."):
            for v in dst.data.vertices:
                if any(x.group == g.index and x.weight > 0.5 for x in v.groups):
                    pinned[v.index] = g.name[4:]
    for g in list(dst.vertex_groups):
        dst.vertex_groups.remove(g)
    groups = {g.name: dst.vertex_groups.new(name=g.name) for g in src.vertex_groups}
    for bname in set(pinned.values()):
        if bname not in groups:
            groups[bname] = dst.vertex_groups.new(name=bname)
    adds = {name: {} for name in groups}
    loose = 0
    for vi, c in enumerate(dco):
        if vi in pinned:
            adds.setdefault(pinned[vi], {})[vi] = 1.0
            continue
        fam = family.get(str(nearest[vi]), set())
        hits = kd.find_n(c, 24)
        good = [(si, dist) for _co, si, dist in hits if dom[si] in fam][:4]
        if not good:
            good = [(si, dist) for _co, si, dist in hits[:4]]
            loose += 1
        tot = {}
        wsum = 0.0
        for si, dist in good:
            f = 1.0 / max(dist, 1e-4) ** 2
            wsum += f
            for name, w in sw[si]:
                tot[name] = tot.get(name, 0.0) + w * f
        for name, w in tot.items():
            if w > 0.0:
                adds[name][vi] = w / wsum
    for name, dd in adds.items():
        g = groups[name]
        for vi, w in dd.items():
            g.add([vi], w, 'REPLACE')
    log("  %s: weights from the skin under it (%d of %d vertices had no skin of their own part nearby; %d pinned)"
        % (dst.name, loose, len(dco), len(pinned)))


def native_weights(meshes, a_arm, J=None):
    """Automatic weights on the native rig (through the watertight stand-in when bone heat fails)."""
    for b in a_arm.data.bones:
        b.use_deform = b.name in DEFORM
    for m in meshes:
        strip_shape_keys(m)
        for g in list(m.vertex_groups):
            m.vertex_groups.remove(g)
        select_only(m, a_arm)
        m.select_set(True)
        a_arm.select_set(True)
        bpy.context.view_layer.objects.active = a_arm
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
        w = np.array([any(g.weight > 0.0 for g in v.groups) for v in m.data.vertices])
        log("  %s: automatic weights on %.1f%% of vertices" % (m.name, 100.0 * w.mean()))
        if w.mean() < 0.97:
            proxy_weights(m, a_arm)
        fill_unweighted(m, a_arm)
        if J is not None:
            island_gating(m, J)
        for mod in [x for x in m.modifiers if x.type == 'ARMATURE']:
            m.modifiers.remove(mod)
        mw = m.matrix_world.copy()
        m.parent = None
        m.matrix_world = mw


# ---- 2/3. joints and the T-pose -------------------------------------------------------------------------------------

def rest_pose(arm):
    arm.data.pose_position = 'POSE'
    if arm.animation_data:
        arm.animation_data.action = None
        for t in list(arm.animation_data.nla_tracks):
            arm.animation_data.nla_tracks.remove(t)
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def strip_shape_keys(m):
    if m.data.shape_keys:
        select_only(m)
        bpy.ops.object.shape_key_remove(all=True, apply_mix=False)


def tpose_rigged(arm, defining, meshes):
    """Rotate the source arm bones so upper arm, forearm and hand point straight out along X (legs straight down),
    bake that pose into the meshes and make it the rig's rest."""
    rest_pose(arm)
    mw = arm.matrix_world
    select_only(arm)
    bpy.ops.object.mode_set(mode='POSE')
    def aim(bname, child_head_bname, target_dir):
        pb = arm.pose.bones[bname]
        head = mw @ pb.head
        nxt = mw @ arm.pose.bones[child_head_bname].head if child_head_bname else mw @ pb.tail
        cur = (nxt - head)
        if cur.length < 1e-6:
            return
        q = cur.normalized().rotation_difference(target_dir)
        # rotate the bone's world matrix about its head
        M = (mw @ pb.matrix)
        R = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head)
        pb.matrix = mw.inverted() @ (R @ M)
        bpy.context.view_layer.update()
    for s, sx in (("L", 1.0), ("R", -1.0)):
        out = Vector((sx, 0.0, 0.0))
        chain = [("upper_arm." + s, "forearm." + s), ("forearm." + s, "hand." + s), ("hand." + s, None)]
        for h, nxt in chain:
            if h in defining:
                aim(defining[h], defining[nxt] if nxt and nxt in defining else None, out)
        down = Vector((0.0, 0.0, -1.0))
        for h, nxt in (("thigh." + s, "shin." + s), ("shin." + s, "foot." + s)):
            if h in defining and nxt in defining:
                aim(defining[h], defining[nxt], down)
    bpy.ops.object.mode_set(mode='OBJECT')
    # bake into the meshes (armature modifier applied), then the pose becomes the rest
    for m in meshes:
        mod = next((x for x in m.modifiers if x.type == 'ARMATURE'), None)
        if mod is None:
            continue
        strip_shape_keys(m)
        select_only(m)
        # keep the vertex groups: apply a copy of the modifier, the original stays bound
        bpy.ops.object.modifier_copy(modifier=mod.name)
        bpy.ops.object.modifier_apply(modifier=m.modifiers[-1].name)
    select_only(arm)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    log("posed the model into the T-pose with its own rig")


def joints_from_rig(arm, defining):
    """Hero bone -> (head, tail) world positions from the source rig (in its rest, now the T-pose)."""
    mw = arm.matrix_world
    B = lambda r: arm.data.bones[defining[r]]
    H = lambda r: mw @ B(r).head_local
    J = {}
    chest_h = H("chest") if "chest" in defining else (H("spine") + H("neck")) * 0.5
    J["hips"] = (H("hips"), H("spine"))
    J["spine"] = (H("spine"), chest_h)
    J["chest"] = (chest_h, H("neck"))
    J["neck"] = (H("neck"), H("head"))
    head_top = mw @ B("head").tail_local
    J["head"] = (H("head"), Vector((H("head").x, H("head").y, max(head_top.z, H("head").z + 0.12))))
    for s in ("L", "R"):
        sh = H("upper_arm." + s)
        cl = H("shoulder." + s) if "shoulder." + s in defining else Vector((sh.x * 0.2, sh.y, sh.z))
        J["shoulder." + s] = (cl, sh)
        J["upper_arm." + s] = (sh, H("forearm." + s))
        J["forearm." + s] = (H("forearm." + s), H("hand." + s))
        hb = B("hand." + s)
        tip = mw @ hb.tail_local
        J["hand." + s] = (H("hand." + s), tip)
        J["thigh." + s] = (H("thigh." + s), H("shin." + s))
        J["shin." + s] = (H("shin." + s), H("foot." + s))
        toe = H("toe." + s) if "toe." + s in defining else mw @ B("foot." + s).tail_local
        J["foot." + s] = (H("foot." + s), toe)
        J["toe." + s] = (toe, toe + Vector((0.0, -0.12, 0.0)))
    return J


FINGER_RX = re.compile(r"finger|thumb|index|middle|ring|pinky|little", re.I)
# fist (--fist): how far each finger joint bends toward the palm (degrees, from the knuckle out); the thumb folds less
FIST_CURL = (72.0, 88.0, 70.0)
FIST_THUMB = (25.0, 45.0, 40.0)
FIST_THUMB_SWING = 40.0                         # the thumb first swings across the palm (about the hand's axis)


def bake_pose(arm, meshes):
    """The meshes take the skeleton's current pose as their own shape (their weights stay)."""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    for m in meshes:
        e = m.evaluated_get(dg)
        me = e.to_mesh()
        if len(me.vertices) == len(m.data.vertices):
            co = np.empty(len(me.vertices) * 3)
            me.vertices.foreach_get("co", co)
            old = np.empty(len(me.vertices) * 3)
            m.data.vertices.foreach_get("co", old)
            co, old = co.reshape(-1, 3), old.reshape(-1, 3)
            ed = np.empty(len(m.data.edges) * 2, dtype=np.int64)
            m.data.edges.foreach_get("vertices", ed)
            ed = ed.reshape(-1, 2)
            l0 = np.linalg.norm(old[ed[:, 0]] - old[ed[:, 1]], axis=1)
            l1 = np.linalg.norm(co[ed[:, 0]] - co[ed[:, 1]], axis=1)
            ratio = l1 / np.maximum(l0, 1e-9)
            bad = ed[ratio > 1.6].ravel()
            if len(bad):
                names = {g.index: g.name for g in m.vertex_groups}
                hit = {}
                for vi in set(bad.tolist()):
                    for g in m.data.vertices[vi].groups:
                        if g.weight > 0.05:
                            hit[names[g.group]] = hit.get(names[g.group], 0) + 1
                log("  %s: %d edges stretched over 1.6x by the pose (worst %.1fx); bones: %s" % (
                    m.name, int((ratio > 1.6).sum()), ratio.max(), sorted(hit.items(), key=lambda x: -x[1])[:8]))
                if os.environ.get("HB_DEBUG"):
                    for ei in np.argsort(-ratio)[:6]:
                        a_, b_ = ed[ei]
                        for vi in (a_, b_):
                            log("    v%d %s -> %s %s" % (vi, old[vi].round(2), co[vi].round(2),
                                [(names[g.group], round(g.weight, 2)) for g in m.data.vertices[vi].groups]))
            m.data.vertices.foreach_set("co", co.ravel())
            m.data.update()
        e.to_mesh_clear()


def fit_hands(arm, defining, meshes, J):
    """Hands from the source rig's fingers, not its hand bone's tail (a conversion guesses tails: Azrael's pointed back
    into her wrist, so every clip folded her hands 94 degrees and nothing reached the weapon; run 2026-10-18):
      * the hand points from the wrist to the middle of the finger roots;
      * the grip axis runs from the last finger's root to the index finger's root, across the palm (the weapon bone's
        axis: a held weapon leaves the fist on the index side), stored as J["grip.<side>"] for a_rig;
      * --fist: the fingers curl round that axis into a fist (baked into the mesh before the bind) and the weapon bone
        goes to the middle of the curled fingers, so the shaft runs through the closed hand."""
    mw = arm.matrix_world
    bones = arm.data.bones
    groups = []                                  # per mesh: world coords, {group name: (vertex ids, weights)}
    for m in meshes:
        co = world_coords(m)
        names = {g.index: g.name for g in m.vertex_groups}
        per = {}
        for v in m.data.vertices:
            for g in v.groups:
                if g.weight > 0.5:
                    per.setdefault(names[g.group], []).append(v.index)
        groups.append((m, co, per))

    def verts_of(bnames):
        pts = []
        for _m, co, per in groups:
            for bn in bnames:
                if bn in per:
                    pts.append(co[per[bn]])
        return np.vstack(pts) if pts else np.zeros((0, 3))

    sides = {}
    for s in ("L", "R"):
        hb = bones[defining["hand." + s]]
        chains = []
        for c in hb.children:
            if not FINGER_RX.search(c.name):
                continue
            ch = [c]
            while True:
                nxt = [x for x in ch[-1].children if FINGER_RX.search(x.name)]
                if not nxt:
                    break
                ch.append(nxt[0])
            chains.append(ch)
        if len(chains) < 3:
            log("hand %s: %d finger chains in the rig, hand left as converted" % (s, len(chains)))
            continue
        wrist = mw @ hb.head_local
        roots = [mw @ ch[0].head_local for ch in chains]
        named = [i for i, ch in enumerate(chains) if re.search(r"thumb|finger0($|_|\.)", norm(ch[0].name), re.I)]
        thumb = named[0] if named else min(range(len(chains)), key=lambda i: (roots[i] - wrist).length)
        fingers = [i for i in range(len(chains)) if i != thumb]
        knuck = sum((roots[i] for i in fingers), Vector()) / len(fingers)
        d = (knuck - wrist).normalized()
        index = min(fingers, key=lambda i: (roots[i] - roots[thumb]).length)
        last = max(fingers, key=lambda i: (roots[i] - roots[thumb]).length)
        k = roots[index] - roots[last]
        k = (k - d * k.dot(d)).normalized()
        # the palm side: where the fingertips already curl (a relaxed hand), else toward the body
        side = Vector()
        for i in fingers:
            tip_pts = verts_of([chains[i][-1].name])
            if not len(tip_pts):
                continue
            r = np.array(roots[i][:])
            tip = Vector(tip_pts[np.argmax(np.sum((tip_pts - r) ** 2, axis=1))])
            off = tip - roots[i]
            side += off - d * off.dot(d) - k * off.dot(k)
        if side.length < 1e-6 * HEIGHT:
            side = Vector((-wrist.x, 0.0, 0.0))
            side -= d * side.dot(d) + k * side.dot(k)
        p = side.normalized()
        log("hand %s: %d fingers, hand turned %.0f deg from the converted bone, palm side %s" % (
            s, len(fingers), math.degrees((mw.to_3x3() @ (hb.tail_local - hb.head_local)).angle(d, 0.0)),
            tuple(round(x, 2) for x in p)))
        reach = (knuck - wrist).length
        J["hand." + s] = (wrist.copy(), wrist + d * reach * 1.8)
        sides[s] = (chains, thumb, fingers, d, k, p, wrist)
    if not FIST or not sides:
        for s, (chains, thumb, fingers, d, k, p, wrist) in sides.items():
            c = sum((mw @ chains[i][0].head_local for i in fingers), Vector()) / len(fingers)
            J["grip." + s] = (c, c + k * 0.1 * HEIGHT)
        return
    # palm skin carrying a finger's weight behind its knuckle would swing out with the finger (Azrael's last finger
    # pulled the palm into a 4.8x spike): fade finger weight to the hand from the knuckle back (for the curl only;
    # finger weights go to the hand afterwards anyway)
    moved = 0
    for s, (chains, thumb, fingers, d, k, p, wrist) in sides.items():
        hname = defining["hand." + s]
        for i in fingers:
            ch = chains[i]
            root = mw @ ch[0].head_local
            seg = ((mw @ ch[1].head_local) - root).length if len(ch) > 1 else (root - wrist).length * 0.4
            dn = np.array(d[:])
            for m, co, _per in groups:
                g = m.vertex_groups.get(ch[0].name)
                if g is None:
                    continue
                hg = m.vertex_groups.get(hname) or m.vertex_groups.new(name=hname)
                along = (co - np.array(root[:])) @ dn
                f = np.clip((along + 0.15 * seg) / (0.5 * seg), 0.0, 1.0)
                for vi in np.where(f < 1.0)[0]:
                    try:
                        w = g.weight(int(vi))
                    except RuntimeError:
                        continue
                    if w <= 0.0:
                        continue
                    keep = w * float(f[vi])
                    try:
                        hw = hg.weight(int(vi))
                    except RuntimeError:
                        hw = 0.0
                    g.add([int(vi)], keep, 'REPLACE')
                    hg.add([int(vi)], hw + (w - keep), 'REPLACE')
                    moved += 1
    log("hands: %d palm vertices keep the hand for the curl" % moved)
    select_only(arm)
    bpy.ops.object.mode_set(mode='POSE')
    inv = mw.inverted()
    for s, (chains, thumb, fingers, d, k, p, wrist) in sides.items():
        axis = (inv.to_3x3() @ d.cross(p)).normalized()       # turning d toward p
        for i, ch in enumerate(chains):
            curl = FIST_THUMB if i == thumb else FIST_CURL
            ax = axis
            if i == thumb:
                # swing the thumb over the palm about the hand's axis, then bend it toward the palm about its own
                pb = arm.pose.bones[ch[0].name]
                t = (arm.pose.bones[ch[1].name].head - pb.head) if len(ch) > 1 else (pb.tail - pb.head)
                da = (inv.to_3x3() @ d).normalized()
                pa = (inv.to_3x3() @ p).normalized()
                tp = t - da * t.dot(da)
                sw = da if da.dot(tp.cross(pa)) >= 0.0 else -da
                h = pb.head.copy()
                pb.matrix = (Matrix.Translation(h) @ Matrix.Rotation(math.radians(FIST_THUMB_SWING), 4, sw) @
                             Matrix.Translation(-h)) @ pb.matrix
                bpy.context.view_layer.update()
                t = (arm.pose.bones[ch[1].name].head - pb.head) if len(ch) > 1 else (pb.tail - pb.head)
                ax = t.normalized().cross(pa).normalized()
            for j, b in enumerate(ch):
                pb = arm.pose.bones[b.name]
                ang = math.radians(curl[min(j, len(curl) - 1)])
                h = pb.head.copy()
                R = Matrix.Translation(h) @ Matrix.Rotation(ang, 4, ax) @ Matrix.Translation(-h)
                pb.matrix = R @ pb.matrix
                bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode='OBJECT')
    bake_pose(arm, meshes)
    for s, (chains, thumb, fingers, d, k, p, wrist) in sides.items():
        pts = []
        for m, _co, per in groups:
            co = world_coords(m)                                 # the curled shape
            for i in fingers:
                for b in chains[i]:
                    if b.name in per:
                        pts.append(co[per[b.name]])
        pts = np.vstack(pts)
        c = Vector(pts.mean(0))
        J["grip." + s] = (c, c + k * 0.1 * HEIGHT)
        log("hand %s: fist closed, grip %.3f from the wrist" % (s, (c - wrist).length))
    rest_pose(arm)


def remap_weights(meshes, to_hero):
    """Sum the source bone weights into hero-bone vertex groups (normalised)."""
    for m in meshes:
        names = {g.index: g.name for g in m.vertex_groups}
        targets = {h: m.vertex_groups.new(name="__" + h) for h in DEFORM}
        none = 0
        for v in m.data.vertices:
            sums = {}
            for g in v.groups:
                h = to_hero.get(names.get(g.group, ""), None)
                if h in ("root", None):
                    h = "hips" if h == "root" else None
                if h and g.weight > 0.0:
                    sums[h] = sums.get(h, 0.0) + g.weight
            tot = sum(sums.values())
            if tot <= 0.0:
                none += 1
                continue
            for h, w in sums.items():
                targets[h].add([v.index], w / tot, 'REPLACE')
        for g in list(m.vertex_groups):
            if not g.name.startswith("__"):
                m.vertex_groups.remove(g)
        for g in m.vertex_groups:
            g.name = g.name[2:]
        if none:
            log("  %s: %d vertices had no source weight" % (m.name, none))


def estimate_joints(meshes):
    """Joints from the mesh of a model standing in a T- or A-pose (no rig): limb centre lines at the hero's height
    ratios."""
    co = np.vstack([world_coords(m) for m in meshes])
    H = co[:, 2].max() - co[:, 2].min()
    z0 = co[:, 2].min()
    k = H / 1.8
    def at(zf):
        return z0 + zf * H
    def slice_c(z, side=0, dz=0.012 * k, xmax=None):
        mm = np.abs(co[:, 2] - z) < dz
        if side:
            mm &= (co[:, 0] * side) > 0.01 * k
        if xmax is not None:
            mm &= np.abs(co[:, 0]) <= xmax
        p = co[mm]
        if len(p) == 0:
            return Vector((0.0, 0.0, z))
        return Vector(((p[:, 0].max() + p[:, 0].min()) * 0.5, (p[:, 1].max() + p[:, 1].min()) * 0.5, z))
    J = {}
    trunk = 0.16 * k
    for name, h, t in (("hips", 0.98, 1.08), ("spine", 1.08, 1.26), ("chest", 1.26, 1.48), ("neck", 1.48, 1.6),
                       ("head", 1.6, 1.8)):
        a = slice_c(at(h / 1.8), xmax=trunk)
        b = slice_c(at(min(t, 1.77) / 1.8), xmax=trunk)
        J[name] = (Vector((0.0, a.y, a.z)), Vector((0.0, b.y, at(t / 1.8))))
    sh_z = at(1.44 / 1.8)
    for side, s in (("L", 1.0), ("R", -1.0)):
        sx = 0.19 * k * s
        # arm points: beyond the shoulder, above the crotch, away from the leg line
        mm = (co[:, 0] * s > 0.21 * k) & (co[:, 2] > at(0.5))
        a = co[mm]
        if len(a) < 20:
            raise RuntimeError("could not find the %s arm in the mesh; give --joints" % side)
        # the arm's centre line: its principal direction, then the middle of the arm's cross-sections along it
        cen = a.mean(axis=0)
        _, _, vt = np.linalg.svd(a - cen, full_matrices=False)
        u = vt[0] if vt[0][0] * s > 0 else -vt[0]
        t = (a - cen) @ u
        t0, t1 = np.percentile(t, 1), np.percentile(t, 99.5)
        def centre_at(tt, w=0.02 * k):
            mm = np.abs(t - tt) < w
            p = a[mm]
            if len(p) < 5:
                return Vector((cen + u * tt).tolist())
            return Vector(((p.max(0) + p.min(0)) * 0.5).tolist())
        root = centre_at(t0 + 0.03 * k)
        sh = Vector((sx, root.y, root.z + (sx - root.x) * (u[2] / u[0])))
        L = t1 - ((np.array(sh[:]) - cen) @ u)
        ts = (np.array(sh[:]) - cen) @ u
        el = centre_at(ts + L * (0.28 / 0.64))
        wr = centre_at(ts + L * (0.54 / 0.64))
        tip = Vector((cen + u * t1).tolist())
        sh_z = sh.z
        J["shoulder." + side] = (Vector((0.035 * k * s, sh.y, sh_z)), sh)
        J["upper_arm." + side] = (sh, el)
        J["forearm." + side] = (el, wr)
        J["hand." + side] = (wr, tip)
        kz, az, hz = at(0.51 / 1.8), at(0.08 / 1.8), at(0.94 / 1.8)
        kc, ac = slice_c(kz, int(s)), slice_c(az, int(s), dz=0.008 * k)
        hip = Vector((kc.x, kc.y, hz))
        J["thigh." + side] = (hip, kc)
        J["shin." + side] = (kc, ac)
        foot = co[(co[:, 0] * s > 0.0) & (co[:, 2] < at(0.05))]
        toe_y = foot[:, 1].min() if len(foot) else ac.y - 0.2 * k
        mid = Vector((ac.x, ac.y + (toe_y - ac.y) * 0.48, at(0.025 / 1.8)))
        J["foot." + side] = (ac, mid)
        J["toe." + side] = (mid, Vector((ac.x, toe_y, at(0.015 / 1.8))))
    log("estimated joints from the mesh (height %.3f)" % H)
    return J


def fit_unrigged(meshes, J, hero_arm):
    """Temporary rig on the model's joints -> automatic weights -> pose that rig to the hero's T-pose directions
    (keeping the model's bone lengths) -> bake. Leaves hero-named vertex groups on the meshes."""
    fit = hero_arm.copy()
    fit.data = hero_arm.data.copy()
    fit.name = "FitRig"
    fit.animation_data_clear()
    bpy.context.collection.objects.link(fit)
    fit.data.pose_position = 'POSE'
    select_only(fit)
    bpy.ops.object.mode_set(mode='EDIT')
    for eb in fit.data.edit_bones:
        eb.use_connect = False
    for eb in fit.data.edit_bones:
        if eb.name in J:
            eb.head, eb.tail = J[eb.name]
    bpy.ops.object.mode_set(mode='OBJECT')
    for b in fit.data.bones:
        b.use_deform = b.name in DEFORM
    for m in meshes:
        strip_shape_keys(m)
        for g in list(m.vertex_groups):
            m.vertex_groups.remove(g)
        select_only(m, fit)
        m.select_set(True)
        fit.select_set(True)
        bpy.context.view_layer.objects.active = fit
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
        w = np.zeros(len(m.data.vertices), dtype=bool)
        for v in m.data.vertices:
            if any(g.weight > 0.0 for g in v.groups):
                w[v.index] = True
        log("  %s: automatic weights on %.1f%% of vertices" % (m.name, 100.0 * w.mean()))
        if w.mean() < 0.97:
            proxy_weights(m, fit)
        fill_unweighted(m, fit)
        per = {}
        for v in m.data.vertices:
            if v.groups:
                g = max(v.groups, key=lambda g: g.weight)
                nm = m.vertex_groups[g.group].name
                per[nm] = per.get(nm, 0) + 1
        log("    dominant bone per vertex:", dict(sorted(per.items())))
    # pose: each bone turned to the hero bone's direction about its own head, parents first
    hero_dir = {b.name: (b.tail_local - b.head_local).normalized() for b in hero_arm.data.bones}
    select_only(fit)
    bpy.ops.object.mode_set(mode='POSE')
    def depth(b):
        n = 0
        while b.parent:
            b = b.parent
            n += 1
        return n
    for pb in sorted(fit.pose.bones, key=lambda p: depth(p.bone)):
        if pb.name in ("root", "weapon.L", "weapon.R"):
            continue
        cur = (pb.tail - pb.head)
        if cur.length < 1e-6:
            continue
        q = cur.normalized().rotation_difference(hero_dir[pb.name])
        R = Matrix.Translation(pb.head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-pb.head)
        pb.matrix = R @ pb.matrix
        bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode='OBJECT')
    JT = {pb.name: (pb.head.copy(), pb.tail.copy()) for pb in fit.pose.bones}
    for m in meshes:
        mod = next(x for x in m.modifiers if x.type == 'ARMATURE')
        select_only(m)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mw = m.matrix_world.copy()
        m.parent = None
        m.matrix_world = mw
    bpy.data.objects.remove(fit, do_unlink=True)
    log("posed the model into the T-pose with a fitted rig")
    return JT


def proxy_weights(m, arm):
    """Bone heat fails on meshes made of many loose, overlapping pieces (and on any mesh with small stray islands).
    Weights are worked out on a watertight stand-in instead: a voxel remesh of the whole figure with its stray
    islands removed, coarser on each retry, then copied to the real mesh from the nearest stand-in surface."""
    co = world_coords(m)
    H = co[:, 2].max() - co[:, 2].min()
    proxy = None
    for voxel in (0.010, 0.014, 0.02):
        if proxy:
            bpy.data.objects.remove(proxy, do_unlink=True)
        proxy = m.copy()
        proxy.data = m.data.copy()
        proxy.name = "WeightProxy"
        bpy.context.collection.objects.link(proxy)
        proxy.parent = None
        proxy.matrix_world = m.matrix_world.copy()
        for mod in list(proxy.modifiers):
            proxy.modifiers.remove(mod)
        for g in list(proxy.vertex_groups):
            proxy.vertex_groups.remove(g)
        r = proxy.modifiers.new("remesh", 'REMESH')
        r.mode = 'VOXEL'
        r.voxel_size = H * voxel
        r.adaptivity = 0.0
        select_only(proxy)
        bpy.ops.object.modifier_apply(modifier="remesh")
        # keep only big islands (the body, the cloak); rings and rivets go
        bm = bmesh.new()
        bm.from_mesh(proxy.data)
        bm.verts.ensure_lookup_table()
        seen = set()
        islands = []
        for v in bm.verts:
            if v.index in seen:
                continue
            comp, stack = [], [v]
            while stack:
                x = stack.pop()
                if x.index in seen:
                    continue
                seen.add(x.index)
                comp.append(x)
                stack.extend(e.other_vert(x) for e in x.link_edges)
            islands.append(comp)
        big = max(len(c) for c in islands)
        kill = [v for c in islands if len(c) < big * 0.02 for v in c]
        bmesh.ops.delete(bm, geom=kill, context='VERTS')
        bm.to_mesh(proxy.data)
        bm.free()
        select_only(proxy, arm)
        proxy.select_set(True)
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
        cov = np.mean([any(g.weight > 0 for g in v.groups) for v in proxy.data.vertices])
        log("  weight stand-in (voxel %.1f cm): %d faces, %d islands kept, automatic weights on %.1f%%"
            % (H * voxel * 100, len(proxy.data.polygons), sum(1 for c in islands if len(c) >= big * 0.02), 100.0 * cov))
        per = {}
        for v in proxy.data.vertices:
            if v.groups:
                g = max(v.groups, key=lambda g: g.weight)
                nm = proxy.vertex_groups[g.group].name
                per[nm] = per.get(nm, 0) + 1
        log("    dominant bone per stand-in vertex:", dict(sorted(per.items())))
        if cov > 0.97 and all(per.get(b_, 0) > 0 for b_ in ("forearm.L", "forearm.R", "hand.L", "hand.R", "shin.L", "shin.R")):
            break
    copy_weights_nearest(proxy, m, k=4)
    bpy.data.objects.remove(proxy, do_unlink=True)


def copy_weights_nearest(src, dst, k=4):
    """dst gets src's vertex group weights, blended from its k nearest src vertices (inverse distance)."""
    from mathutils import kdtree
    sco = world_coords(src)
    kd = kdtree.KDTree(len(sco))
    for i, c in enumerate(sco):
        kd.insert(c, i)
    kd.balance()
    sn = {g.index: g.name for g in src.vertex_groups}
    sw = [[(sn[g.group], g.weight) for g in v.groups] for v in src.data.vertices]
    # vertices a prep script pinned (vertex group "pin.<bone>", e.g. airah_prep.py's tail) keep that bone alone
    pinned = {}
    for g in dst.vertex_groups:
        if g.name.startswith("pin."):
            for v in dst.data.vertices:
                if any(x.group == g.index and x.weight > 0.5 for x in v.groups):
                    pinned[v.index] = g.name[4:]
    for g in list(dst.vertex_groups):
        dst.vertex_groups.remove(g)
    groups = {g.name: dst.vertex_groups.new(name=g.name) for g in src.vertex_groups}
    for bname in set(pinned.values()):
        if bname not in groups:
            groups[bname] = dst.vertex_groups.new(name=bname)
    dco = world_coords(dst)
    adds = {name: {} for name in groups}
    for vi, c in enumerate(dco):
        hits = kd.find_n(c, k)
        tot = {}
        wsum = 0.0
        for _co, si, d in hits:
            f = 1.0 / max(d, 1e-4) ** 2
            wsum += f
            for name, w in sw[si]:
                tot[name] = tot.get(name, 0.0) + w * f
        for name, w in tot.items():
            if w > 0.0:
                adds[name][vi] = w / wsum
    for name, d in adds.items():
        g = groups[name]
        for vi, w in d.items():
            g.add([vi], w, 'REPLACE')


def fill_unweighted(m, arm):
    """Vertices bone heat missed (separate armour pieces, cards) take the weights of the nearest weighted vertex, or
    the nearest bone."""
    co = world_coords(m)
    has = np.array([any(g.weight > 0.0 for g in v.groups) for v in m.data.vertices])
    if has.all():
        return
    idx_w = np.where(has)[0]
    names = {g.index: g.name for g in m.vertex_groups}
    groups = {g.name: g for g in m.vertex_groups}
    for vi in np.where(~has)[0]:
        if len(idx_w):
            j = idx_w[np.argmin(np.sum((co[idx_w] - co[vi]) ** 2, axis=1))]
            for g in m.data.vertices[int(j)].groups:
                groups[names[g.group]].add([int(vi)], g.weight, 'REPLACE')
        else:
            best, bd = None, 1e9
            for b in arm.data.bones:
                if not b.use_deform:
                    continue
                a, bb = Vector(b.head_local), Vector(b.tail_local)
                p = Vector(co[vi])
                t = max(0.0, min(1.0, (p - a).dot(bb - a) / max(1e-9, (bb - a).length_squared)))
                d = (a + (bb - a) * t - p).length
                if d < bd:
                    best, bd = b.name, d
            g = groups.get(best) or m.vertex_groups.new(name=best)
            g.add([int(vi)], 1.0, 'REPLACE')


# ---- 4. scale, centre, face -----------------------------------------------------------------------------------------

def place(meshes, J, arm=None, body=None):
    # body: the piece that sets the height (--body_piece: antlers or a tall helm on top do not shrink the hero)
    co = np.vstack([world_coords(m) for m in ([body] if body is not None else meshes)])
    zmin, zmax = co[:, 2].min(), co[:, 2].max()
    hips = J["hips"][0]
    s = HEIGHT / (zmax - zmin)
    T = Matrix.Scale(s, 4) @ Matrix.Translation(Vector((-hips.x, -hips.y, -zmin)))
    for m in meshes:
        m.matrix_world = T @ m.matrix_world
        select_only(m)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    J2 = {k: (T @ a, T @ b) for k, (a, b) in J.items()}
    PLACE_T[0] = T @ PLACE_T[0]
    log("scaled x%.3f to %.3f m" % (s, HEIGHT))
    return J2


def face_front(objs, yaw_deg):
    if abs(yaw_deg) < 1e-6:
        return
    R = Matrix.Rotation(math.radians(yaw_deg), 4, 'Z')
    for o in objs:
        if o.parent is None:
            o.matrix_world = R @ o.matrix_world
    bpy.context.view_layer.update()


# ---- 6. one mesh, a game budget -------------------------------------------------------------------------------------

def finish_mesh(meshes, J):
    for m in meshes:
        for mod in list(m.modifiers):
            m.modifiers.remove(mod)
        m.parent = None
        strip_shape_keys(m)
    select_only(*meshes)
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = body.data.name = NAME
    before = len(body.data.polygons)
    # merge only coincident duplicates; keep separate pieces separate
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00002)
    bm.to_mesh(body.data)
    bm.free()
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    if tris > FACES:
        d = body.modifiers.new("dec", 'DECIMATE')
        d.decimate_type = 'COLLAPSE'
        d.ratio = FACES / tris
        d.delimit = {'UV', 'SEAM', 'MATERIAL'}
        d.use_collapse_triangulate = False
        select_only(body)
        bpy.ops.object.modifier_apply(modifier="dec")
    for p in body.data.polygons:
        p.use_smooth = True
    log("mesh: %d faces -> %d triangles" % (before, sum(len(p.vertices) - 2 for p in body.data.polygons)))
    # textures no larger than TEX
    seen = set()
    for slot in body.material_slots:
        if not slot.material or not slot.material.node_tree:
            continue
        for n in slot.material.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and n.image.name not in seen:
                seen.add(n.image.name)
                w, h = n.image.size
                if max(w, h) > TEX:
                    f = TEX / max(w, h)
                    n.image.scale(int(w * f), int(h * f))
                    n.image.pack()
    reach_gating(body, J)
    cloth_weights(body, J)
    arm_capture(body, J)
    if CAPTURE:
        segment_capture(body, J)
    smooth_all(body)
    smooth_joints(body, J)
    if (HUE or GRAY != 1.0) and not BAKE:
        done = set()
        for slot in body.material_slots:
            m = slot.material
            if not m or not m.node_tree:
                continue
            bsdf = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if bsdf and bsdf.inputs["Base Color"].links:
                n = bsdf.inputs["Base Color"].links[0].from_node
                if n.type == 'TEX_IMAGE' and n.image and n.image.name not in done:
                    done.add(n.image.name)
                    hue_remap(n.image)
                    n.image.pack()
    hand_lock(body)
    unify_coincident(body)
    apply_rigid(body)                            # its split copies must keep different weights
    if UNMIX:
        unmix_arms(body)
    # weights: at most 4 bones per vertex, normalised (what the game's skinning uses)
    select_only(body)
    bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
    bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    if SPLIT:
        # on the finished weights (after the unmix), as tested on the built bodies (run 2026-10-18 d)
        import arm_split
        # the bones as the game has them (the native rig), as tested on the built bodies; else the joints
        nat = bpy.data.objects.get("HeroRigNative")
        if nat is not None:
            mw = nat.matrix_world
            jj = {b.name: (np.array((mw @ b.head_local)[:]), np.array((mw @ b.tail_local)[:])) for b in nat.data.bones}
        else:
            jj = {b: (np.array(h[:], dtype=np.float64), np.array(t[:], dtype=np.float64)) for b, (h, t) in J.items()
                  if b in HERO_BONES}
        sl = tuple(float(x) for x in SLEEVE.split(",")) if SLEEVE else None
        arm_split.split_arms(body, jj, HEIGHT, log=log, sleeve=sl)
        select_only(body)
        bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
        bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
        bpy.ops.object.mode_set(mode='OBJECT')
    return body


def seg_dist(p, a, b):
    """Distances from points p (n x 3) to the segment a-b."""
    a = np.array(a[:])
    b = np.array(b[:])
    d = b - a
    t = np.clip(((p - a) @ d) / max(1e-9, d @ d), 0.0, 1.0)
    return np.linalg.norm(p - (a + np.outer(t, d)), axis=1)


def cloth_weights(body, J):
    """Skirts, tabards and long coats hanging off the hips: a vertex below the hips that is not on a leg follows the
    hips most and the legs only partly (more lower down), so a stride does not split the cloth into a bell."""
    co = world_coords(body)
    k = HEIGHT / 1.8
    hip_z = J["thigh.L"][0].z
    knee_z = (J["shin.L"][0].z + J["shin.R"][0].z) * 0.5
    ankle_z = (J["shin.L"][1].z + J["shin.R"][1].z) * 0.5
    dL = np.minimum(seg_dist(co, *J["thigh.L"]), seg_dist(co, *J["shin.L"]))
    dR = np.minimum(seg_dist(co, *J["thigh.R"]), seg_dist(co, *J["shin.R"]))
    leg_r = np.where(co[:, 2] > knee_z, 0.12 * k, 0.09 * k)
    cloth = (co[:, 2] < hip_z - 0.02 * k) & (co[:, 2] > ankle_z + 0.06 * k) & (np.minimum(dL, dR) > leg_r)
    # hands and forearms hanging beside the hips are not cloth
    for s_ in ("L", "R"):
        for b_ in ("forearm.", "hand."):
            if b_ + s_ in J:
                cloth &= seg_dist(co, *J[b_ + s_]) > 0.11 * k
    if CLOTH:
        rx = re.compile(CLOTH, re.I)
        ok_mat = np.array([bool(s_.material and rx.search(s_.material.name)) for s_ in body.material_slots] or [True])
        on = np.zeros(len(co), dtype=bool)
        for poly in body.data.polygons:
            if ok_mat[min(poly.material_index, len(ok_mat) - 1)]:
                on[list(poly.vertices)] = True
        cloth &= on
    idx = np.where(cloth)[0]
    if len(idx) == 0:
        return
    g = {n: body.vertex_groups.get(n) or body.vertex_groups.new(name=n) for n in DEFORM}
    for vi in idx:
        z = co[vi, 2]
        f = min(1.0, max(0.0, (hip_z - z) / max(0.05, hip_z - knee_z)))
        legs = 0.2 + 0.3 * min(1.0, f)                      # 20% at the hips, 50% at and below the knees
        wl = 1.0 / max(dL[vi], 1e-3) ** 2
        wr = 1.0 / max(dR[vi], 1e-3) ** 2
        sl, sr = wl / (wl + wr), wr / (wl + wr)
        below = z < knee_z
        for n in DEFORM:
            g[n].remove([int(vi)])
        g["hips"].add([int(vi)], 1.0 - legs, 'REPLACE')
        for side, sh in (("L", sl), ("R", sr)):
            if below:
                g["thigh." + side].add([int(vi)], legs * sh * 0.7, 'REPLACE')
                g["shin." + side].add([int(vi)], legs * sh * 0.3, 'REPLACE')
            else:
                g["thigh." + side].add([int(vi)], legs * sh, 'REPLACE')
    log("cloth: %d hanging vertices follow the hips more than the legs" % len(idx))


def apply_rigid(body):
    """Vertices inside the --rigid shapes get one bone at full weight (applied after every other weight pass), and
    the faces wholly inside are split off along their border: on a fused surface (a staff grown into the hand and
    the cloak) the triangles joining the rigid part to its neighbours would otherwise stretch into needles."""
    if not RIGID:
        return
    co = world_coords(body)
    T = PLACE_T[0]
    s_ = T.to_scale()[0]
    inside = np.zeros(len(co), dtype=bool)
    bone_of = {}
    for spec in [x for x in RIGID.split(";") if x.strip()]:
        bone, kind, nums = spec.split(":")
        v = [float(x) for x in nums.split(",")]
        if kind == "cap":
            a = T @ Vector(v[0:3])
            b = T @ Vector(v[3:6])
            hit = seg_dist(co, a, b) < v[6] * s_
        else:
            c = np.array((T @ Vector(v[0:3]))[:])
            hit = np.linalg.norm(co - c, axis=1) < v[3] * s_
        inside |= hit
        for vi in np.where(hit)[0]:
            bone_of[int(vi)] = bone
    if not inside.any():
        return
    for nm in set(bone_of.values()):
        if body.vertex_groups.get(nm) is None:
            body.vertex_groups.new(name=nm)
    gidx = {g.name: g.index for g in body.vertex_groups}
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    dl = bm.verts.layers.deform.verify()
    rigid_face = set(f.index for f in bm.faces if all(inside[v.index] for v in f.verts))
    border = [e for e in bm.edges
              if any(f.index in rigid_face for f in e.link_faces) and any(f.index not in rigid_face for f in e.link_faces)]
    flag = bm.faces.layers.int.new("rigid")
    for f in bm.faces:
        f[flag] = 1 if f.index in rigid_face else 0
    old_bone = {}
    for v in bm.verts:
        if inside[v.index]:
            old_bone[v] = bone_of[v.index]
    bmesh.ops.split_edges(bm, edges=border)
    n_rigid = 0
    for v in bm.verts:
        on_rigid = any(f[flag] for f in v.link_faces)
        if on_rigid:
            bone = old_bone.get(v)
            if bone is None:
                # a copy made by the split: take the bone of the rigid part it touches
                for f in v.link_faces:
                    for w in f.verts:
                        if w in old_bone:
                            bone = old_bone[w]
                            break
                    if bone:
                        break
            if bone is None:
                continue
            v[dl].clear()
            v[dl][gidx[bone]] = 1.0
            n_rigid += 1
    bm.faces.layers.int.remove(flag)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    log("  rigid: %d vertices on %d faces ride their bone only, split off along %d border edges"
        % (n_rigid, len(rigid_face), len(border)))

def reach_gating(body, J):
    """A limb bone moves only the skin within reach of that limb (a cloak brushing a hanging hand stays with the
    body instead of being stretched into a spike when the hand lifts)."""
    if REACH_K <= 0.0:
        return
    co = world_coords(body)
    k = HEIGHT / 1.8
    names = {g.index: g.name for g in body.vertex_groups}
    groups = {g.name: g for g in body.vertex_groups}
    far = {}
    for b, (h, t) in J.items():
        key = b.split(".")[0]
        if key in REACH and b in groups:
            far[b] = seg_dist(co, h, t) > REACH[key] * k * REACH_K
    trunk_d = {b: seg_dist(co, *J[b]) for b in ("hips", "spine", "chest", "neck", "head") if b in J}
    moved = 0
    for v in body.data.vertices:
        drop = [(names[g.group], g.weight) for g in v.groups if names[g.group] in far and far[names[g.group]][v.index]]
        if not drop:
            continue
        moved += 1
        keep = [(names[g.group], g.weight) for g in v.groups if (names[g.group], g.weight) not in drop]
        for nm, _w in drop:
            groups[nm].remove([v.index])
        tot = sum(w for _n, w in keep)
        if tot > 1e-6:
            for nm, w in keep:
                groups[nm].add([v.index], w / tot, 'REPLACE')
        else:
            best = min(trunk_d, key=lambda b: trunk_d[b][v.index])
            groups[best].add([v.index], 1.0, 'REPLACE')
    log("reach: %d vertices freed from limbs too far away" % moved)


def unify_coincident(body):
    """Vertices split at texture seams (glTF stores one vertex per UV) sit at the same place; any weight pass can
    give the two copies different weights, and then the seam cracks open when the limb moves. Copies get the
    average of their weights."""
    co = world_coords(body)
    key = np.round(co / 1e-5).astype(np.int64)
    _, inv, counts = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    inv = inv.ravel()
    multi = np.where(counts[inv] > 1)[0]
    if len(multi) == 0:
        return
    names = {g.index: g.name for g in body.vertex_groups}
    groups = {g.name: g for g in body.vertex_groups}
    by = {}
    for vi in multi:
        by.setdefault(int(inv[vi]), []).append(int(vi))
    for members in by.values():
        acc = {}
        for vi in members:
            for g in body.data.vertices[vi].groups:
                acc[names[g.group]] = acc.get(names[g.group], 0.0) + g.weight / len(members)
        for vi in members:
            for nm in [names[g.group] for g in body.data.vertices[vi].groups]:
                groups[nm].remove([vi])
            for nm, w in acc.items():
                if w > 0.0:
                    groups[nm].add([vi], w, 'REPLACE')
    log("seams: %d split vertices share their weights" % len(multi))


def unmix_arms(body):
    """A hanging arm that touched a coat, a skirt or a thigh in the model's pose leaves vertices weighted partly to the
    arm and partly to the hips, spine or legs; no joint links those, so when the arm lifts they stretch into
    sheets from the hem to the fist (Caziel's coat in his heavy strike, Ezee's roar; run 2026-10-18). Each such vertex
    now goes wholly to the side holding most of it, and the mesh is split where faces of the two sides meet, so the
    arm leaves the coat instead of dragging it."""
    names = {g.index: g.name for g in body.vertex_groups}
    idx = {g.name: g.index for g in body.vertex_groups}
    # the whole arm: an upper arm hanging against a coat's side panel webs it up as badly as a hand does (the
    # shoulder joins the arm to the chest, which is not in `trunk`)
    low = {s_: {idx[n] for n in ("upper_arm." + s_, "forearm." + s_, "hand." + s_) if n in idx} for s_ in ("L", "R")}
    trunk = {idx[n] for n in ("hips", "spine", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R",
                              "toe.L", "toe.R") if n in idx}
    bm = bmesh.new()
    bm.from_mesh(body.data)
    dl = bm.verts.layers.deform.active
    if dl is None:
        bm.free()
        return

    def cls(v):
        dv = v[dl]
        b = sum(w for g, w in dv.items() if g in trunk)
        best, aw = "", 0.0
        for s_ in ("L", "R"):
            a = sum(w for g, w in dv.items() if g in low[s_])
            if a > aw:
                best, aw = s_, a
        if aw <= 0.02 or b <= 0.02:
            return best if aw > 0.02 else ""                    # unmixed: arm side or "" (the rest)
        return best if aw >= b else ""

    vc = {v: cls(v) for v in bm.verts}
    fc = {}
    for f in bm.faces:
        votes = {}
        for v in f.verts:
            votes[vc[v]] = votes.get(vc[v], 0) + 1
        fc[f] = max(votes, key=lambda k: (votes[k], k == ""))
    cut = [e for e in bm.edges if len(e.link_faces) == 2 and fc[e.link_faces[0]] != fc[e.link_faces[1]]
           and "" in (fc[e.link_faces[0]], fc[e.link_faces[1]])
           and any(vc[v] == "" and any(g in trunk for g in v[dl].keys()) for v in e.verts)]
    n_before = len(bm.verts)
    if cut:
        bmesh.ops.split_edges(bm, edges=cut)
    fixed = 0
    for v in bm.verts:
        sides = {fc.get(f, "?") for f in v.link_faces}
        if len(sides) != 1 or "?" in sides:
            continue
        side = sides.pop()
        dv = v[dl]
        if side == "":
            drop = [g for g in dv.keys() if g in low["L"] or g in low["R"]]
            if not drop or not any(g in trunk for g in dv.keys()):
                continue
        else:
            drop = [g for g in dv.keys() if g in trunk]
            if not drop:
                continue
        for g in drop:
            del dv[g]
        tot = sum(dv.values())
        if tot <= 1e-6:
            dv[idx["hips"] if side == "" else idx["hand." + side]] = 1.0
        else:
            for g in list(dv.keys()):
                dv[g] = dv[g] / tot
        fixed += 1
    bm.to_mesh(body.data)
    bm.free()
    log("unmix: %d vertices made wholly arm or body, %d edges split (%d new vertices)" % (
        fixed, len(cut), len(body.data.vertices) - n_before))


def mark_hands(meshes):
    """Remember the vertices the source rig gave to a hand or its fingers (group lock.hand.<side>), for hand_lock."""
    for m in meshes:
        for side in ("L", "R"):
            g = m.vertex_groups.get("hand." + side)
            if g is None:
                continue
            ids = []
            for v in m.data.vertices:
                for gg in v.groups:
                    if gg.group == g.index and gg.weight >= 0.5:
                        ids.append(v.index)
            if ids:
                lk = m.vertex_groups.new(name="lock.hand." + side)
                lk.add(ids, 1.0, 'REPLACE')


def hand_lock(body):
    """The source rig's hand and finger vertices move with their arm only. A closed fist hanging beside the thigh
    (--fist) put Azrael's claw tips within reach of the hip, cloth and smoothing rules; they kept a share of the hips
    and stretched into needles 25 cm long whenever the arm moved (run 2026-10-18)."""
    names = {g.index: g.name for g in body.vertex_groups}
    groups = {g.name: g for g in body.vertex_groups}
    fixed = 0
    for side in ("L", "R"):
        lk = groups.get("lock.hand." + side)
        if lk is None:
            continue
        arm_ = ("upper_arm." + side, "forearm." + side, "hand." + side)
        for v in body.data.vertices:
            if not any(g.group == lk.index and g.weight >= 0.5 for g in v.groups):
                continue
            keep, drop = [], []
            for g in v.groups:
                nm = names[g.group]
                if nm.startswith("lock."):
                    continue
                (keep if nm in arm_ else drop).append((nm, g.weight))
            if not drop:
                continue
            fixed += 1
            for nm, _w in drop:
                groups[nm].remove([v.index])
            tot = sum(w for _n, w in keep)
            if tot <= 1e-6:
                groups["hand." + side].add([v.index], 1.0, 'REPLACE')
            else:
                for nm, w in keep:
                    groups[nm].add([v.index], w / tot, 'REPLACE')
        body.vertex_groups.remove(lk)
    log("hands: %d hand and finger vertices given back to their arm only" % fixed)


def arm_capture(body, J):
    """A vertex whose nearest bone is a forearm or a hand (fingers, a gauntlet) moves with that arm only: a hand
    hanging beside the hips must not keep a share of the hips or a thigh, or it stretches into a plank."""
    co = world_coords(body)
    bones = [b for b in J if b in CHAIN_OF and b not in ("root",)]
    d = np.stack([seg_dist(co, *J[b]) for b in bones], axis=1)
    near = np.array(bones)[np.argmin(d, axis=1)]
    names = {g.index: g.name for g in body.vertex_groups}
    groups = {g.name: g for g in body.vertex_groups}
    fixed = 0
    k = HEIGHT / 1.8
    for vi in np.where(np.isin(near, ["forearm.L", "hand.L", "forearm.R", "hand.R"]))[0]:
        side = str(near[vi])[-1]
        if REACH_K > 0.0 and d[vi].min() > REACH[str(near[vi]).split(".")[0]] * k * REACH_K:
            continue                                 # cloth beside the hand, beyond its reach (reach_gating)
        v = body.data.vertices[int(vi)]
        keep, drop = [], []
        for g in v.groups:
            nm = names[g.group]
            (keep if nm in ("upper_arm." + side, "forearm." + side, "hand." + side) else drop).append((nm, g.weight))
        if not drop:
            continue
        fixed += 1
        for nm, _w in drop:
            groups[nm].remove([int(vi)])
        tot = sum(w for _n, w in keep)
        if tot <= 1e-6:
            groups[str(near[vi])].add([int(vi)], 1.0, 'REPLACE')
        else:
            for nm, w in keep:
                groups[nm].add([int(vi)], w / tot, 'REPLACE')
    log("arms: %d hand and forearm vertices freed from the trunk and legs" % fixed)


def segment_capture(body, J):
    """--capture: each vertex keeps only the weights of the bone nearest it, that bone's parent and its children
    (renormalised); the smoothing passes after blend the seams. For posed models, where bone heat gives a cheek to
    the hand resting on it or a chest to the arm pressed against it."""
    arm = bpy.data.objects.get("HeroRigNative")
    bones = [b for b in J if b in CHAIN_OF]
    family = {}
    for b in bones:
        fam = {b}
        if arm is not None and b in arm.data.bones:
            hb = arm.data.bones[b]
            if hb.parent:
                fam.add(hb.parent.name)
            fam.update(c.name for c in hb.children)
        family[b] = fam
    co = world_coords(body)
    d = np.stack([seg_dist(co, *J[b]) for b in bones], axis=1)
    nearest = np.array(bones)[np.argmin(d, axis=1)]
    names = {g.index: g.name for g in body.vertex_groups}
    groups = {g.name: g for g in body.vertex_groups}
    changed = 0
    for v in body.data.vertices:
        fam = family[str(nearest[v.index])]
        keep, drop = [], []
        for g in v.groups:
            nm = names[g.group]
            (keep if nm in fam else drop).append((nm, g.weight))
        if not drop:
            continue
        changed += 1
        for nm, _w in drop:
            groups[nm].remove([v.index])
        tot = sum(w for _n, w in keep)
        if tot <= 1e-6:
            nb = str(nearest[v.index])
            g = groups.get(nb) or body.vertex_groups.new(name=nb)
            groups[nb] = g
            g.add([v.index], 1.0, 'REPLACE')
        else:
            for nm, w in keep:
                groups[nm].add([v.index], w / tot, 'REPLACE')
    log("capture: %d vertices kept to their nearest bone and its neighbours" % changed)


def smooth_all(body):
    """The reach and cloth rules leave hard seams between neighbouring vertices; a low-poly mesh's long triangles
    tear along them into slabs. A few gentle smoothing passes over every bone group blend them out."""
    if SMOOTH <= 0:
        return
    select_only(body)
    body.data.vertices.foreach_set("select", np.ones(len(body.data.vertices), dtype=bool))
    bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
    body.data.use_paint_mask_vertex = False
    bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=SMOOTH, expand=0.0)
    bpy.ops.object.mode_set(mode='OBJECT')
    log("smoothed all weights (%d passes)" % SMOOTH)


def smooth_joints(body, J):
    """Soften the weights round the shoulders, hips and neck, where an arm or leg turns far from the T-pose: a hard
    border between two bones folds the skin into a crease (linear skinning)."""
    co = world_coords(body)
    H = HEIGHT
    spots = []
    for s in ("L", "R"):
        spots.append((J["upper_arm." + s][0], 0.075 * H, ("shoulder." + s, "upper_arm." + s, "chest")))
        spots.append((J["thigh." + s][0], 0.07 * H, ("hips", "thigh." + s)))
        spots.append((J["forearm." + s][0], 0.035 * H, ("upper_arm." + s, "forearm." + s)))
        spots.append((J["shin." + s][0], 0.04 * H, ("thigh." + s, "shin." + s)))
    spots.append((J["neck"][0], 0.05 * H, ("chest", "neck", "head")))
    select_only(body)
    for centre, r, groups in spots:
        sel = np.linalg.norm(co - np.array(centre[:]), axis=1) < r
        body.data.vertices.foreach_set("select", sel)
        body.data.update()
        bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
        body.data.use_paint_mask_vertex = True
        for g in groups:
            vg = body.vertex_groups.get(g)
            if vg is None:
                continue
            body.vertex_groups.active_index = vg.index
            bpy.ops.object.vertex_group_smooth(group_select_mode='ACTIVE', factor=0.6, repeat=8, expand=0.15)
        body.data.use_paint_mask_vertex = False
        bpy.ops.object.mode_set(mode='OBJECT')
    body.data.vertices.foreach_set("select", np.zeros(len(co), dtype=bool))
    log("smoothed weights at the shoulders, elbows, hips, knees and neck")


# ---- 7. hero skeleton ----------------------------------------------------------------------------------------------

def load_hero():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=HERO)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == 'ARMATURE')
    for o in new:
        if o.type == 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    if arm.animation_data:
        arm.animation_data.action = None
    arm.data.pose_position = 'REST'
    arm.name = "HeroRig"
    log("hero rig with %d clips" % len(bpy.data.actions))
    return arm


def refit(arm, J):
    """Move the hero bones onto the model's joints, keeping every bone's direction and roll (as Sludge)."""
    select_only(arm)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones
    old = {b.name: (b.head.copy(), b.tail.copy()) for b in eb}
    for b in eb:
        b.use_connect = False
    def put(name, head, length=None):
        b = eb[name]
        d = old[name][1] - old[name][0]
        ln = d.length if length is None else length
        b.head = head
        b.tail = head + d.normalized() * ln
    hj = J["hips"][0]
    put("root", Vector((0.0, 0.0, 0.0)), max(0.1, hj.z))
    put("hips", Vector((0.0, hj.y, hj.z)), max(0.05, J["spine"][0].z - hj.z))
    for n in ("spine", "chest", "neck"):
        h, t = J[n]
        put(n, Vector((0.0, h.y, h.z)), max(0.05, t.z - h.z))
    h, t = J["head"]
    put("head", Vector((0.0, h.y, h.z)), max(0.08, t.z - h.z))
    for s in ("L", "R"):
        sh = J["upper_arm." + s][0]
        y, z = sh.y, sh.z
        cx = J["shoulder." + s][0].x
        put("shoulder." + s, Vector((cx, y, z)), max(0.02, abs(sh.x - cx)))
        el = J["forearm." + s][0]
        wr = J["hand." + s][0]
        put("upper_arm." + s, Vector((sh.x, y, z)), abs(el.x - sh.x))
        put("forearm." + s, Vector((el.x, y, z)), abs(wr.x - el.x))
        hand_new = Vector((wr.x, y, z))
        put("hand." + s, hand_new, max(0.05, abs(J["hand." + s][1].x - wr.x) * 0.55))
        off = hand_new - old["hand." + s][0]
        eb["weapon." + s].head = old["weapon." + s][0] + off
        eb["weapon." + s].tail = old["weapon." + s][1] + off
        th, kn = J["thigh." + s]
        an = J["shin." + s][1]
        put("thigh." + s, Vector((th.x, th.y, th.z)), max(0.1, th.z - kn.z))
        put("shin." + s, Vector((th.x, th.y, kn.z)), max(0.1, kn.z - an.z))
        foot_new = Vector((th.x, th.y, an.z))
        fo = old["foot." + s]
        # the foot keeps its slope; its length follows the model's foot
        flen = max(0.06, (J["foot." + s][1] - J["foot." + s][0]).length)
        put("foot." + s, foot_new, flen)
        to = old["toe." + s]
        eb["toe." + s].head = eb["foot." + s].tail.copy()
        eb["toe." + s].tail = eb["foot." + s].tail + (to[1] - to[0]) * max(0.6, flen / (fo[1] - fo[0]).length)
    # bones re-connect where the hero rig had them connected is not needed for skinning; leave disconnected
    bpy.ops.object.mode_set(mode='OBJECT')
    for n in ("hips", "head", "upper_arm.L", "hand.L", "thigh.L", "foot.L"):
        b = arm.data.bones[n]
        log("  %-12s %s -> %s" % (n, tuple(round(x, 3) for x in b.head_local), tuple(round(x, 3) for x in b.tail_local)))


def bind(body, arm):
    body.parent = arm
    body.matrix_parent_inverse = Matrix.Identity(4)
    mod = body.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    for g in list(body.vertex_groups):
        if g.name not in DEFORM:
            body.vertex_groups.remove(g)


def preview(arm, body, folder):
    os.makedirs(folder, exist_ok=True)
    sc = bpy.context.scene
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else 'BLENDER_EEVEE'
    sc.render.resolution_x = 700
    sc.render.resolution_y = 900
    sc.world = bpy.data.worlds.new("W")
    sc.world.color = (0.2, 0.21, 0.25)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    for nm, loc, rot in (("k", (2.5, -3.0, 4.0), None), ("f", (-3.0, -2.0, 1.5), None)):
        l = bpy.data.objects.new(nm, bpy.data.lights.new(nm, 'POINT'))
        l.data.energy = 900 if nm == "k" else 350
        l.location = loc
        sc.collection.objects.link(l)
    arm.data.pose_position = 'POSE'
    arm.animation_data_create()
    for clip, fr in ((None, 0), ("idle", 0.3), ("hero_run", 0.25), ("gs_1", 0.45)) + ((("glide_fwd", 0.3),) if GLIDE else ()):
        if clip is None:
            arm.animation_data.action = None
            for pb in arm.pose.bones:
                pb.matrix_basis = Matrix.Identity(4)
        if clip:
            act = bpy.data.actions.get(clip)
            if act is None:
                continue
            arm.animation_data.action = act
            a, b = act.frame_range
            sc.frame_set(int(a + (b - a) * fr))
        kk = HEIGHT / 1.8
        for nm, loc in (("front", (0.0, -4.2 * kk, 1.1 * kk)), ("side", (4.2 * kk, 0.0, 1.1 * kk))):
            cam.location = loc
            cam.rotation_euler = (Vector((0, 0, 0.95 * kk)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            cam.data.lens = 50
            sc.render.filepath = os.path.join(folder, "%s_%s_%s.png" % (NAME, clip or "rest", nm))
            bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None
    arm.data.pose_position = 'REST'
    log("previews in", folder)


def export(arm, body):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    select_only(arm, body)
    arm.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = arm
    arm.data.pose_position = 'POSE'
    bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format='GLB', export_animations=True,
                              export_animation_mode='ACTIONS', export_skins=True, export_morph=False,
                              export_yup=True, export_apply=False, export_image_format='AUTO')
    log("wrote %s (%.1f MB)" % (OUT, os.path.getsize(OUT) / 1e6))


def main():
    if not SRC:
        raise SystemExit("--src is required")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    hero_arm = load_hero()
    hero_acts = set(bpy.data.actions)
    objs = import_src(SRC)
    for act in [a_ for a_ in bpy.data.actions if a_ not in hero_acts]:
        bpy.data.actions.remove(act)                 # the download's own clips: the body plays the hero clips
    face_front([o for o in objs if o.name in bpy.data.objects], YAW)
    src_arm, meshes = tidy(objs)
    if not meshes:
        raise RuntimeError("no mesh left after --drop")
    def move_pieces():
        for spec in [x for x in MOVE.split(";") if x.strip()]:
            rx, nums = spec.rsplit(":", 1)
            d = Vector([float(x) for x in nums.split(",")])
            for m in meshes:
                if re.search(rx, m.name, re.I):
                    m.matrix_world = Matrix.Translation(d) @ m.matrix_world
                    log("  moved %s by %s" % (m.name, tuple(d)))
    if not src_arm:
        move_pieces()
    cut_boxes(meshes)
    to_hero = None
    if JOINTS or NORIG or not src_arm:
        if src_arm:
            for m in meshes:
                for mod in [x for x in m.modifiers if x.type == 'ARMATURE']:
                    select_only(m)
                    bpy.ops.object.modifier_apply(modifier=mod.name)
                mw = m.matrix_world.copy()           # keep the place the skeleton gave it
                m.parent = None
                m.matrix_world = mw
            bpy.data.objects.remove(src_arm, do_unlink=True)
            src_arm = None
            move_pieces()                            # a skinned piece ignores its own offset until the skin is applied
        if BODY_PIECE:
            skin = [m for m in meshes if re.search(BODY_PIECE, m.name, re.I)]
            rest = [m for m in meshes if m not in skin]
            if not skin:
                raise RuntimeError("--body_piece matched no piece")
            meshes = [join_all(skin)] + ([join_all(rest)] if rest else [])
        else:
            meshes = [join_all(meshes)]
        if BAKE:
            hi = meshes[0]
            lo = bake_low(hi)
            bpy.data.objects.remove(hi, do_unlink=True)
            meshes = [lo]
        if JOINTS:
            J = {k: (Vector(v[0]), Vector(v[1])) for k, v in json.load(open(JOINTS)).items()}
        else:
            J = estimate_joints(meshes[:1] if BODY_PIECE else meshes)
        J = place(meshes, J, body=meshes[0] if BODY_PIECE else None)                     # weights are worked out at game size (bone heat fails on tiny models)
        if BIND == "t":
            J = fit_unrigged(meshes, J, hero_arm)
    else:
        to_hero, defining, missing = map_rig(src_arm)
        if missing:
            log("rig bones not recognised for:", missing)
            log("source bones:", [b.name for b in src_arm.data.bones][:80])
            raise RuntimeError("could not map the source rig; give --joints")
        log("rig map:", dict(sorted(defining.items())))
        skinned = [m for m in meshes if any(x.type == 'ARMATURE' and x.object == src_arm for x in m.modifiers)]
        loose = [m for m in meshes if m not in skinned]
        if BIND == "t":
            tpose_rigged(src_arm, defining, skinned)
        else:
            rest_pose(src_arm)
        J = joints_from_rig(src_arm, defining)
        if BIND != "t":
            fit_hands(src_arm, defining, skinned, J)
        remap_weights(skinned, to_hero)
        mark_hands(skinned)
        for m in skinned:
            for mod in [x for x in m.modifiers if x.type == 'ARMATURE']:
                m.modifiers.remove(mod)
            mw = m.matrix_world.copy()
            m.parent = None
            m.matrix_world = mw
        bpy.data.objects.remove(src_arm, do_unlink=True)
        for m in loose:
            for g in list(m.vertex_groups):
                m.vertex_groups.remove(g)
            transfer_nearest(m, skinned)
        J = place(meshes, J)
    for n in ("hips", "head", "upper_arm.L", "hand.L", "thigh.L", "foot.L"):
        log("  joint %-12s %s -> %s" % (n, tuple(round(x, 3) for x in J[n][0]), tuple(round(x, 3) for x in J[n][1])))
    if BIND == "t":
        body = finish_mesh(meshes, J)
        refit(hero_arm, J)
        rig = hero_arm
    else:
        t_rig(hero_arm, J)
        if GLIDE:
            make_glide(hero_arm)
        rig = a_rig(hero_arm, J)
        if to_hero is None:
            if BODY_PIECE and len(meshes) > 1:
                native_weights(meshes[:1], rig, J)
                for m in meshes[1:]:
                    transfer_by_bone(m, meshes[0], J)
            else:
                native_weights(meshes, rig, J)
        body = finish_mesh(meshes, J)
        retarget(hero_arm, rig)
        bpy.data.objects.remove(hero_arm, do_unlink=True)
        rig.name = "HeroRig"
    bind(body, rig)
    if PREVIEW:
        preview(rig, body, PREVIEW)
    export(rig, body)


def join_all(meshes):
    """One mesh from many loose pieces (rivets, straps, cloth layers), so weights are worked out once."""
    for m in meshes:
        strip_shape_keys(m)
        for mod in list(m.modifiers):
            m.modifiers.remove(mod)
    select_only(*meshes)
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    select_only(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    log("joined %d pieces into one mesh (%d faces)" % (len(meshes), len(o.data.polygons)))
    return o


def transfer_nearest(m, sources):
    """Copy weights from the nearest vertex of the skinned meshes (a rigid buckle, a loose plate)."""
    src_co = []
    src_w = []
    for s in sources:
        names = {g.index: g.name for g in s.vertex_groups}
        co = world_coords(s)
        for v in s.data.vertices:
            src_co.append(co[v.index])
            src_w.append([(names[g.group], g.weight) for g in v.groups])
    if not src_co:
        return
    src_co = np.array(src_co)
    co = world_coords(m)
    groups = {}
    for vi in range(len(co)):
        j = int(np.argmin(np.sum((src_co - co[vi]) ** 2, axis=1)))
        for name, w in src_w[j]:
            g = groups.get(name) or m.vertex_groups.get(name) or m.vertex_groups.new(name=name)
            groups[name] = g
            g.add([vi], w, 'REPLACE')


main()

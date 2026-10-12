"""Build Sludge's body: assets/characters/hero/sludge.glb.

A MakeHuman body (MPFB 2 for Blender; MakeHuman's base mesh and targets are CC0, see docs/ASSET_CREDITS.md), pushed to
an obese, heavily built butcher, posed in a T-pose and bound to the game's hero skeleton (the 24 bones of hero.glb),
so all 132 hero animations play on it. The hero bones are moved to the fat body's joints; their directions (and so
every rotation key) stay as they are. Only the hips carry position keys in those animations, so the new proportions
survive animation.

Run (needs MPFB installed and enabled in Blender 5.2):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python tools/blender/sludge.py [-- --preview=dir]
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.rigservice import RigService
from bl_ext.user_default.mpfb.services.locationservice import LocationService

ROOT = "A:/Python/woa"
HERO = ROOT + "/assets/characters/hero/hero.glb"
OUT = ROOT + "/assets/characters/hero/sludge.glb"
ARM_OUT = 0.11                                 # metres the arms move out from the trunk
HEIGHT = 1.86                                  # metres, head top; the game scales the model up further

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = next((a.split("=", 1)[1] for a in ARGS if a.startswith("--preview=")), "")

# Body shape. Macro sliders 0..1, then MakeHuman targets (name, weight).
MACRO = {"gender": 1.0, "age": 0.72, "muscle": 0.8, "weight": 1.0, "proportions": 0.12, "height": 0.62,
         "cupsize": 0.5, "firmness": 0.5, "race": {"asian": 0.15, "caucasian": 0.55, "african": 0.30}}
TARGETS = [
    # gut: huge, low and soft
    ("stomach-pregnant-incr", 0.9), ("stomach-tone-decr", 1.0), ("stomach-navel-down", 1.0),
    ("measure-waist-circ-incr", 1.4), ("measure-hips-circ-incr", 1.0), ("buttocks-volume-incr", 0.6),
    # trunk: wide and deep, no V shape, heavy back
    ("torso-scale-horiz-incr", 1.0), ("torso-scale-depth-incr", 1.2), ("torso-vshape-decr", 1.0),
    ("measure-shoulder-dist-incr", 0.8), ("torso-muscle-dorsi-incr", 0.8), ("hip-scale-horiz-incr", 0.6),
    ("hip-scale-depth-incr", 0.6),
    # neck and head: fat neck, smallish head sunk forward
    ("neck-double-incr", 1.0), ("measure-neck-circ-incr", 1.4), ("neck-scale-vert-decr", 1.0),
    ("head-fat-incr", 1.0), ("head-scale-vert-decr", 0.35), ("head-trans-forward", 0.5), ("head-trans-down", 0.5),
    # arms: thick and strong, big hands
    ("l-upperarm-fat-incr", 1.0), ("r-upperarm-fat-incr", 1.0), ("l-lowerarm-fat-incr", 1.0), ("r-lowerarm-fat-incr", 1.0),
    ("l-upperarm-scale-horiz-incr", 0.8), ("r-upperarm-scale-horiz-incr", 0.8),
    ("l-upperarm-scale-depth-incr", 0.8), ("r-upperarm-scale-depth-incr", 0.8),
    ("l-lowerarm-scale-horiz-incr", 0.7), ("r-lowerarm-scale-horiz-incr", 0.7),
    ("l-lowerarm-scale-depth-incr", 0.7), ("r-lowerarm-scale-depth-incr", 0.7),
    ("l-upperarm-shoulder-muscle-incr", 1.0), ("r-upperarm-shoulder-muscle-incr", 1.0),
    ("measure-upperarm-circ-incr", 1.0), ("l-hand-scale-incr", 1.0), ("r-hand-scale-incr", 1.0),
    ("l-hand-fingers-diameter-incr", 1.0), ("r-hand-fingers-diameter-incr", 1.0),
    # legs: short, thick pillars
    ("l-upperleg-fat-incr", 1.0), ("r-upperleg-fat-incr", 1.0), ("l-lowerleg-fat-incr", 1.0), ("r-lowerleg-fat-incr", 1.0),
    ("l-upperleg-scale-horiz-incr", 1.0), ("r-upperleg-scale-horiz-incr", 1.0),
    ("l-upperleg-scale-depth-incr", 0.8), ("r-upperleg-scale-depth-incr", 0.8),
    ("l-lowerleg-scale-horiz-incr", 0.9), ("r-lowerleg-scale-horiz-incr", 0.9),
    ("l-lowerleg-scale-depth-incr", 0.7), ("r-lowerleg-scale-depth-incr", 0.7),
    ("measure-thigh-circ-incr", 1.0), ("measure-calf-circ-incr", 1.0), ("measure-knee-circ-incr", 1.0),
    ("upperlegs-height-decr", 0.6), ("lowerlegs-height-decr", 0.4),
]

# MakeHuman game-engine bones -> hero bones (weights are summed into the hero bone).
BONE_MAP = {
    "Root": "hips", "pelvis": "hips", "spine_01": "spine", "spine_02": "chest", "spine_03": "chest",
    "neck_01": "neck", "head": "head",
    "clavicle_l": "shoulder.L", "upperarm_l": "upper_arm.L", "lowerarm_l": "forearm.L", "hand_l": "hand.L",
    "clavicle_r": "shoulder.R", "upperarm_r": "upper_arm.R", "lowerarm_r": "forearm.R", "hand_r": "hand.R",
    "thigh_l": "thigh.L", "calf_l": "shin.L", "foot_l": "foot.L", "ball_l": "foot.L",
    "thigh_r": "thigh.R", "calf_r": "shin.R", "foot_r": "foot.R", "ball_r": "foot.R",
}
for side, s in (("l", "L"), ("r", "R")):
    for f in ("thumb", "index", "middle", "ring", "pinky"):
        for k in ("01", "02", "03"):
            BONE_MAP["%s_%s_%s" % (f, k, side)] = "hand." + s


def log(*a):
    print("[sludge]", *a, flush=True)


def clean_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.actions):
        for d in list(coll):
            coll.remove(d)


def make_body():
    mh = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
                                   feet_on_ground=True, scale=0.1, macro_detail_dict=MACRO)
    for name, wgt in TARGETS:
        path = TargetService.target_full_path(name)
        if path is None:
            log("missing target", name)
            continue
        TargetService.load_target(mh, path, weight=min(1.0, wgt), name=name)
        kb = mh.data.shape_keys.key_blocks.get(name)
        if kb is not None:
            kb.slider_max = 3.0
            kb.value = wgt
    rig = HumanService.add_builtin_rig(mh, "game_engine", import_weights=True)
    # T-pose to match the hero skeleton's rest pose, then make it the rest pose (bakes the targets)
    import json
    tpose = json.load(open(os.path.join(LocationService.get_mpfb_data("poses"), "game_engine_fk", "t-pose.json")))
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='POSE')
    RigService.set_pose_from_dict(rig, tpose)
    bpy.ops.object.mode_set(mode='OBJECT')
    RigService.apply_pose_as_rest_pose(rig)
    return mh, rig


def barrel(mh, J):
    """Make the trunk one barrel-shaped mass (Pudge's silhouette): widen and deepen every trunk vertex around a
    bell curve centred on the gut, more at the front, letting the gut overhang the groin. Weighted by how much each
    vertex follows the pelvis and spine, so arms and legs keep their shape."""
    pel = J["pelvis"][0]
    neck = J["neck_01"][0]
    gz = pel.z + (neck.z - pel.z) * 0.3             # the gut's fullest height
    span = (neck.z - pel.z) * 0.85
    names = {g.index: g.name for g in mh.vertex_groups}
    trunk = {"pelvis", "spine_01", "spine_02", "spine_03", "Root"}
    for v in mh.data.vertices:
        w = sum(g.weight for g in v.groups if names.get(g.group) in trunk)
        if w <= 0.01:
            continue
        w = min(1.0, w)
        co = v.co
        t = (co.z - gz) / span
        bell = math.exp(-t * t * (1.6 if co.z >= gz else 2.4))
        front = min(1.0, max(0.0, (pel.y + 0.04 - co.y) / 0.16))   # 0 at the back, 1 at the front
        sx = 1.0 + 0.34 * bell * w
        sy = 1.0 + (0.16 + 0.34 * front) * bell * w
        co.x = co.x * sx
        co.y = pel.y + (co.y - pel.y) * sy
        if co.z < gz:
            co.z -= 0.06 * front * bell * w * min(1.0, (gz - co.z) / 0.2)   # the lower gut sags
    # broad shoulders: the arms sit further out so they hang clear of the gut in the hero animations
    arm_names = {"upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r"}
    for v in mh.data.vertices:
        wa = 0.0
        wc = 0.0
        for g in v.groups:
            n = names.get(g.group, "")
            if n in arm_names or n.endswith(("_01_l", "_02_l", "_03_l", "_01_r", "_02_r", "_03_r")):
                wa += g.weight
            elif n.startswith("clavicle"):
                wc += g.weight
        k = min(1.0, wa + 0.5 * wc)
        if k > 0.0:
            v.co.x += math.copysign(ARM_OUT * k, v.co.x)
    for n in list(J.keys()):
        if n in arm_names or n.endswith(("_01_l", "_02_l", "_03_l", "_01_r", "_02_r", "_03_r")):
            h, t = J[n]
            d = Vector((math.copysign(ARM_OUT, h.x), 0.0, 0.0))
            J[n] = (h + d, t + d)
    mh.data.update()

def joints(rig):
    out = {}
    for b in rig.data.bones:
        out[b.name] = (rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local)
    return out


def main():
    clean_scene()
    mh, rig = make_body()
    # scale the body to the target height (feet on the ground at z = 0)
    zs = [(mh.matrix_world @ v.co).z for v in mh.data.vertices if True]
    body_group = mh.vertex_groups.get("body")
    body_idx = body_group.index if body_group else -1
    body_z = [(mh.matrix_world @ v.co).z for v in mh.data.vertices
              if body_idx < 0 or any(g.group == body_idx and g.weight > 0.5 for g in v.groups)]
    top = max(body_z)
    k = HEIGHT / top
    log("raw height %.3f, scale %.3f" % (top, k))
    rig.scale = (k, k, k)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    mh.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    J = joints(rig)
    barrel(mh, J)
    # keep the mesh: unparent with its current shape, drop the MakeHuman rig
    bpy.ops.object.select_all(action='DESELECT')
    mh.select_set(True)
    bpy.context.view_layer.objects.active = mh
    for m in list(mh.modifiers):
        if m.type == 'ARMATURE':
            mh.modifiers.remove(m)
    mh.parent = None
    bpy.data.objects.remove(rig, do_unlink=True)
    # delete helper geometry (joint cubes, tights, hair proxy, teeth, tongue); keep the body and the eyes
    keep = set()
    for name in ("body", "helper-l-eye", "helper-r-eye"):
        g = mh.vertex_groups.get(name)
        if g:
            keep.add(g.index)
    bm = bmesh.new()
    bm.from_mesh(mh.data)
    deform = bm.verts.layers.deform.active
    kill = [v for v in bm.verts if not any(gi in keep and w > 0.5 for gi, w in v[deform].items())]
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    bm.to_mesh(mh.data)
    bm.free()
    for m in list(mh.modifiers):
        mh.modifiers.remove(m)
    log("mesh verts", len(mh.data.vertices))

    # hero skeleton and its 132 animations
    bpy.ops.import_scene.gltf(filepath=HERO)
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE' and o != mh)
    for o in list(bpy.context.scene.objects):
        if o.type == 'MESH' and o != mh:
            bpy.data.objects.remove(o, do_unlink=True)
    log("hero bones", [b.name for b in arm.data.bones])
    refit(arm, J)
    remap_weights(mh)
    eye_groups = [mh.vertex_groups.get(n) for n in ("helper-l-eye", "helper-r-eye")]
    finish_mesh(mh, arm, eye_groups)
    gear = make_gear(mh, arm)
    rest_colors([mh] + gear)
    if PREVIEW:
        preview(arm, mh, PREVIEW)
    export(arm, [mh] + gear)


def refit(arm, J):
    """Move the hero bones onto the fat body's joints, keeping every bone's direction and roll."""
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones
    old = {b.name: (b.head.copy(), b.tail.copy()) for b in eb}
    for b in eb:
        b.use_connect = False

    def put(name, head, length=None):
        b = eb[name]
        d = (old[name][1] - old[name][0])
        ln = d.length if length is None else length
        b.head = head
        b.tail = head + d.normalized() * ln

    H = lambda n: J[n][0]
    pel = H("pelvis")
    put("hips", Vector((0.0, pel.y, pel.z)), max(0.06, H("spine_01").z - pel.z))
    put("spine", Vector((0.0, H("spine_01").y, H("spine_01").z)), max(0.08, H("spine_02").z - H("spine_01").z))
    put("chest", Vector((0.0, H("spine_02").y, H("spine_02").z)), max(0.1, H("neck_01").z - H("spine_02").z))
    put("neck", Vector((0.0, H("neck_01").y, H("neck_01").z)), max(0.06, H("head").z - H("neck_01").z))
    put("head", Vector((0.0, H("head").y, H("head").z)))
    if "root" in eb:
        put("root", Vector((0.0, 0.0, 0.0)), pel.z)
    for s, side in (("L", "l"), ("R", "r")):
        sh = H("upperarm_" + side)
        y, z = sh.y, sh.z
        cx = H("clavicle_" + side).x
        put("shoulder." + s, Vector((cx, y, z)), abs(sh.x - cx))
        put("upper_arm." + s, Vector((sh.x, y, z)), abs(H("lowerarm_" + side).x - sh.x))
        put("forearm." + s, Vector((H("lowerarm_" + side).x, y, z)), abs(H("hand_" + side).x - H("lowerarm_" + side).x))
        hand_new = Vector((H("hand_" + side).x, y, z))
        hand_old = old["hand." + s][0]
        put("hand." + s, hand_new)
        th = H("thigh_" + side)
        put("thigh." + s, Vector((th.x, th.y, th.z)), th.z - H("calf_" + side).z)
        put("shin." + s, Vector((th.x, th.y, H("calf_" + side).z)), H("calf_" + side).z - H("foot_" + side).z)
        foot_new = Vector((th.x, th.y, H("foot_" + side).z))
        put("foot." + s, foot_new)
        if "toe." + s in eb:
            fo = old["foot." + s]
            new_tail = foot_new + (fo[1] - fo[0])
            off = new_tail - old["toe." + s][0]
            eb["toe." + s].head = old["toe." + s][0] + off
            eb["toe." + s].tail = old["toe." + s][1] + off
        # anything else hanging off the hand (weapon sockets) moves with it
        for b in eb:
            if b.parent and b.parent.name == "hand." + s and b.name not in old.keys() - {b.name}:
                pass
        for b in eb:
            if b.parent and b.parent.name == "hand." + s:
                off = hand_new - hand_old
                b.head = old[b.name][0] + off
                b.tail = old[b.name][1] + off
    for b in eb:
        log("bone %-12s %s -> %s" % (b.name, tuple(round(x, 3) for x in b.head), tuple(round(x, 3) for x in b.tail)))
    bpy.ops.object.mode_set(mode='OBJECT')


def remap_weights(mh):
    """Sum the MakeHuman bone weights into the hero bones' vertex groups."""
    groups = {g.index: g.name for g in mh.vertex_groups}
    targets = {}
    for hero in set(BONE_MAP.values()):
        targets[hero] = mh.vertex_groups.new(name="__" + hero)
    acc = {}
    for v in mh.data.vertices:
        sums = {}
        for g in v.groups:
            hero = BONE_MAP.get(groups.get(g.group, ""))
            if hero and g.weight > 0.0:
                sums[hero] = sums.get(hero, 0.0) + g.weight
        acc[v.index] = sums
    unweighted = 0
    for vi, sums in acc.items():
        tot = sum(sums.values())
        if tot <= 0.0:
            unweighted += 1
            continue
        for hero, wgt in sums.items():
            targets[hero].add([vi], wgt / tot, 'REPLACE')
    log("vertices with no bone weight:", unweighted)
    keep_eyes = {"helper-l-eye", "helper-r-eye"}
    for g in list(mh.vertex_groups):
        if not g.name.startswith("__") and g.name not in keep_eyes:
            mh.vertex_groups.remove(g)
    for g in mh.vertex_groups:
        if g.name.startswith("__"):
            g.name = g.name[2:]


def finish_mesh(mh, arm, eye_groups):
    mh.name = mh.data.name = "sludge"
    # eyes follow the head bone
    head = mh.vertex_groups.get("head")
    skin = bpy.data.materials.new("SludgeSkin")
    skin.diffuse_color = (0.42, 0.47, 0.36, 1.0)
    eye = bpy.data.materials.new("SludgeEye")
    eye.diffuse_color = (0.85, 0.78, 0.45, 1.0)
    mh.data.materials.clear()
    mh.data.materials.append(skin)
    mh.data.materials.append(eye)
    eye_idx = {g.index for g in eye_groups if g}
    for p in mh.data.polygons:
        p.use_smooth = True
        on_eye = all(any(gg.group in eye_idx and gg.weight > 0.5 for gg in mh.data.vertices[vi].groups) for vi in p.vertices)
        p.material_index = 1 if on_eye else 0
    for vi in range(len(mh.data.vertices)):
        v = mh.data.vertices[vi]
        if any(g.group in eye_idx and g.weight > 0.5 for g in v.groups):
            for g in list(v.groups):
                if g.group not in eye_idx:
                    mh.vertex_groups[g.group].remove([vi])
            head.add([vi], 1.0, 'REPLACE')
    for g in eye_groups:
        if g:
            mh.vertex_groups.remove(g)
    mh.parent = arm
    mod = mh.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm


def preview(arm, mh, folder):
    os.makedirs(folder, exist_ok=True)
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'MATERIAL'
    scn.render.resolution_x = 900
    scn.render.resolution_y = 1000
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 2.3
    cam = bpy.data.objects.new("cam", cam_data)
    scn.collection.objects.link(cam)
    scn.camera = cam
    shots = [("front", (0, -6, 0.95), (math.radians(90), 0, 0)),
             ("side", (6, 0, 0.95), (math.radians(90), 0, math.radians(90)))]
    arm.animation_data_create()
    for clip in [None, "idle", "run"]:
        if clip:
            act = bpy.data.actions.get(clip) or next((a for a in bpy.data.actions if a.name.startswith(clip)), None)
            if act is None:
                continue
            arm.animation_data.action = act
            scn.frame_set(int(act.frame_range[0] + (act.frame_range[1] - act.frame_range[0]) * 0.3))
        for nm, loc, rot in shots:
            cam.location = loc
            cam.rotation_euler = rot
            scn.render.filepath = os.path.join(folder, "sludge_%s_%s.png" % (clip or "rest", nm))
            bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None
    bpy.data.objects.remove(cam, do_unlink=True)


def export(arm, meshes):
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format='GLB', export_animations=True,
                              export_animation_mode='ACTIONS', export_skins=True, export_morph=False,
                              export_yup=True, export_apply=False, export_vertex_color='ACTIVE')
    log("wrote", OUT)


# ---- gear -------------------------------------------------------------------------------------------------------

def _mat(name, color, metal, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*color, 1.0)
    return m


def _surface(body, x, z, front=True):
    """The body's surface point at (x, z), hit by a ray from the front (or the back)."""
    o = Vector((x, -2.0 if front else 2.0, z))
    d = Vector((0, 1.0 if front else -1.0, 0))
    ok, loc, nrm, _ = body.ray_cast(o, d)
    return (loc, nrm) if ok else (None, None)


def _ring_outline(body, z, n=48, center_y=0.0):
    """The body's outline at height z: for n directions around the vertical axis, the farthest surface point."""
    pts = []
    for i in range(n):
        a = i * math.tau / n
        d = Vector((math.cos(a), math.sin(a), 0.0))
        o = Vector((0.0, center_y, z)) + d * 2.0
        ok, loc, nrm, _ = body.ray_cast(o, -d)
        pts.append(loc if ok else Vector((0.0, center_y, z)) + d * 0.3)
    return pts


def _uv_faces(bm, faces_uv):
    uv = bm.loops.layers.uv.new("UVMap")
    for f, uvs in faces_uv:
        for loop, t in zip(f.loops, uvs):
            loop[uv].uv = t


def _band(name, rings, material):
    """A closed band from rows of points (each row a closed loop)."""
    bm = bmesh.new()
    rows = [[bm.verts.new(p) for p in row] for row in rings]
    n = len(rows[0])
    fu = []
    for r in range(len(rows) - 1):
        for i in range(n):
            f = bm.faces.new((rows[r][i], rows[r][(i + 1) % n], rows[r + 1][(i + 1) % n], rows[r + 1][i]))
            fu.append((f, [(i * 0.25, r * 0.5), ((i + 1) * 0.25, r * 0.5), ((i + 1) * 0.25, (r + 1) * 0.5), (i * 0.25, (r + 1) * 0.5)]))
    _uv_faces(bm, fu)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(material)
    return o


def _strip(name, rows, material, closed=False):
    """An open (or closed) strip from rows of points."""
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in row] for row in rows]
    fu = []
    du = 1.0 / max(1, len(vs[0]) - 1)
    dv = 1.0 / max(1, len(vs) - 1)
    for r in range(len(vs) - 1):
        for i in range(len(vs[r]) - (0 if closed else 1)):
            j = (i + 1) % len(vs[r])
            f = bm.faces.new((vs[r][i], vs[r][j], vs[r + 1][j], vs[r + 1][i]))
            fu.append((f, [(i * du, r * dv), ((i + 1) * du, r * dv), ((i + 1) * du, (r + 1) * dv), (i * du, (r + 1) * dv)]))
    _uv_faces(bm, fu)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(material)
    return o


def _solidify(o, t):
    mod = o.modifiers.new("solid", 'SOLIDIFY')
    mod.thickness = t
    mod.offset = 1.0
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)


def _skin_like(o, body, arm, fixed=None):
    """Skin a gear piece: copy the nearest body weights (or fixed {bone: weight}), add the armature."""
    for g in body.vertex_groups:
        o.vertex_groups.new(name=g.name)
    if fixed:
        idx = list(range(len(o.data.vertices)))
        for bone, wgt in fixed.items():
            o.vertex_groups[bone].add(idx, wgt, 'REPLACE')
    else:
        dt = o.modifiers.new("dt", 'DATA_TRANSFER')
        dt.object = body
        dt.use_vert_data = True
        dt.data_types_verts = {'VGROUP_WEIGHTS'}
        dt.vert_mapping = 'POLYINTERP_NEAREST'
        dt.layers_vgroup_select_src = 'ALL'
        dt.layers_vgroup_select_dst = 'NAME'
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=dt.name)
    for p in o.data.polygons:
        p.use_smooth = True
    o.parent = arm
    mod = o.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm


def make_gear(body, arm):
    # cast against the rest pose (the armature modifier would give the animated pose)
    for m in body.modifiers:
        m.show_viewport = False
    if arm.animation_data:
        arm.animation_data.action = None
    bpy.context.view_layer.update()
    # BH_<kind> names: the game gives these its textured leather, cloth and dark iron (src/game/gear_materials.gd)
    leather = _mat("BH_Leather__sludge", (0.03, 0.017, 0.01), 0.0, 0.7)
    cloth = _mat("BH_Leather__sludge_apron", (0.045, 0.022, 0.014), 0.0, 0.75)
    iron = _mat("BH_DarkSteel__sludge", (0.3, 0.28, 0.27), 0.85, 0.55)
    gear = []
    hips = arm.data.bones["hips"].head_local
    # belt: a thick leather band hugging the hips under the gut
    zb = hips.z - 0.06
    rings = []
    for dz in (-0.05, 0.05):
        out = _ring_outline(body, zb + dz, 56, hips.y)
        rings.append([p + (p - Vector((0, hips.y, p.z))).normalized() * 0.018 for p in out])
    belt = _band("belt", rings, leather)
    _solidify(belt, 0.012)
    _skin_like(belt, body, arm, {"hips": 1.0})
    gear.append(belt)
    # buckle and three meat hooks hanging off the belt at the front-left
    # loincloth: one smooth curved panel in front (wide enough to hide the groin under the gut) and one behind,
    # hanging from the belt to mid-thigh
    for side, sign in (("front", -1.0), ("back", 1.0)):
        zt = zb + 0.02
        ok, hit, _, _ = body.ray_cast(Vector((0, hips.y + sign * 2.0, zt - 0.06)), Vector((0, -sign, 0)))
        depth = abs(hit.y - hips.y) + 0.03 if ok else 0.3
        half = 0.27 if side == "front" else 0.22
        width_axis = 0.38
        drop = 0.46 if side == "front" else 0.38
        cols, steps = 14, 7
        rows = []
        for k in range(steps + 1):
            f = k / steps
            row = []
            for c in range(cols + 1):
                x = -half + 2 * half * c / cols
                y = hips.y + sign * depth * math.sqrt(max(0.0, 1.0 - (x / width_axis) ** 2))
                x *= 1.0 - 0.15 * f
                y += sign * 0.05 * f                  # hangs slightly away from the legs
                row.append(Vector((x, y, zt - drop * f)))
            rows.append(row)
        panel = _strip("loincloth_" + side, rows, cloth)
        _solidify(panel, 0.01)
        _skin_like(panel, body, arm, {"hips": 1.0})
        gear.append(panel)
    # chest strap: from the right shoulder across the gut to the left hip, and back round behind
    sh = arm.data.bones["upper_arm.R"].head_local
    a = Vector((sh.x * 0.62, 0.0, sh.z + 0.02))
    b = Vector((0.27, 0.0, zb + 0.08))
    rows_f, rows_b = [], []
    for i in range(25):
        f = i / 24
        x = a.x + (b.x - a.x) * f
        z = a.z + (b.z - a.z) * f
        for front, rows in ((True, rows_f), (False, rows_b)):
            loc, nrm = _surface(body, x, z, front)
            if loc is None:
                continue
            side = Vector((b.x - a.x, 0, b.z - a.z)).normalized().cross(nrm).normalized()
            rows.append([loc + nrm * 0.014 - side * 0.035, loc + nrm * 0.014 + side * 0.035])
    for nm, rows in (("strap_front", rows_f), ("strap_back", rows_b)):
        if len(rows) > 2:
            strap = _strip(nm, rows, leather)
            _solidify(strap, 0.008)
            _skin_like(strap, body, arm)
            gear.append(strap)
    # chain wound round the left forearm (the hook arm): a tight helical coil of iron, four turns
    fa = arm.data.bones["forearm.L"]
    h0, h1 = fa.head_local, fa.tail_local
    turns, n, ring = 4.0, 160, 8
    rows = []
    for i in range(n):
        f = i / (n - 1)
        ang = f * turns * math.tau
        c = h0.lerp(h1, 0.12 + 0.72 * f)
        loc, _ = None, None
        r = 0.0
        # the arm's radius here: cast in from above
        ok, hit, _, _ = body.ray_cast(c + Vector((0, 0, 0.5)), Vector((0, 0, -1)))
        r = (hit - c).length + 0.012 if ok else 0.08
        ctr = c + Vector((0, math.cos(ang) * r, math.sin(ang) * r))
        tan = Vector((h1.x - h0.x, -math.sin(ang) * r * turns * math.tau, math.cos(ang) * r * turns * math.tau)).normalized()
        nrm = (ctr - c).normalized()
        bi = tan.cross(nrm).normalized()
        thick = 0.013 * (0.8 + 0.2 * abs(math.sin(i * 1.7)))      # bumpy: reads as links
        rows.append([ctr + (nrm * math.cos(b) + bi * math.sin(b)) * thick for b in
                     (k * math.tau / ring for k in range(ring))])
    chain = _strip("arm_chain", rows, iron, closed=True)
    _skin_like(chain, body, arm, {"forearm.L": 1.0})
    gear.append(chain)
    for m in body.modifiers:
        m.show_viewport = True
    log("gear", [g.name for g in gear])
    return gear


def rest_colors(objs):
    """Store each vertex's rest position in its colour (r = x/2 + 0.5, g = y/2 + 0.5, b = z/2) so the skin shader can
    paint scars, stitches and blotches that stay on the body while it animates."""
    for o in objs:
        me = o.data
        attr = me.color_attributes.new("rest", 'FLOAT_COLOR', 'POINT')
        for i, v in enumerate(me.vertices):
            c = v.co
            attr.data[i].color = (c.x * 0.5 + 0.5, c.y * 0.5 + 0.5, c.z * 0.5, 1.0)
        me.color_attributes.active_color = attr


main()

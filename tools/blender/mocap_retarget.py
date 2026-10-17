"""Motion-capture clips (Mixamo FBX, "Y Bot", 30 fps, no skin) onto the hero skeleton (run 2026-10-18 d).

The hero rig (assets/characters/hero/hero.glb, 24 bones) and Mixamo's rig both rest in a T-pose facing -Y with almost
the same proportions, so each hero bone takes the armature-space turn of its Mixamo bone away from that bone's rest:
    hero_world(t) = mixamo_world(t) * mixamo_world_rest^-1 * hero_world_rest
(spine <- Spine1, chest <- Spine2; fingers are dropped). The hips keep Mixamo's hip path scaled to the hero's hip
height; `place` decides what happens to its drift across the floor (the game moves the hero, so attacks stay put).
Every hero-skeleton body (the shared hero, Sludge, the heroes17 bodies) stores full local bone turns, so these clips
fit all of them; the game moves the hips track onto each body's own hip height (MocapClips).

Survey (one contact sheet per source file, to choose clips; renders the hero body with a 1.2 m stick in the right hand):
  blender -b --factory-startup --python tools/blender/mocap_retarget.py -- --survey --src=work/downloads/mixamo/raw
      --cells=<dir> [--only=regex] [--frames=6]
Build (the clips named in the spec, written as one GLB of the hero rig with only those clips):
  blender -b --factory-startup --python tools/blender/mocap_retarget.py -- --spec=tools/blender/mocap_clips.json
      --src=work/downloads/mixamo/raw --out=assets/characters/hero/mocap/hero_mocap.glb [--cells=<dir>] [--only=regex]

Spec (tools/blender/mocap_clips.json): {"clip": {"src": "<fbx name without .fbx>" (or a list: played one after the
other), "start": first frame, "end": last frame (from 0), "place": "zero" | "keep" | "loop" | "sway", "mirror": false
(left and right swapped), "loop": false, "lean": degrees forward for the trunk, "hand": R | L | both and "reach" (m)
for finding the blow, "strike": seconds (the blow, given), "kind": "cast" (also writes the release)}}.
  place zero: no drift across the floor (the hips keep only their height and sway, measured from the first frame);
  keep: Mixamo's path as it is; loop: the drift from the first to the last frame is taken out evenly (looping idles).
"""
import bpy
import json
import math
import os
import re
import sys
import time
from mathutils import Matrix, Quaternion, Vector

HERO = r"A:/Python/woa/assets/characters/hero/hero.glb"
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    for a in ARGV:
        if a == "--" + name:
            return True
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    return default


SRC = os.path.abspath(arg("src", "work/downloads/mixamo/raw"))
SPEC = arg("spec", "")
OUT = arg("out", "")
CELLS = os.path.abspath(arg("cells")) if arg("cells") else ""
ONLY = arg("only", "")
SURVEY = bool(arg("survey", False))
NFRAMES = int(arg("frames", 6))
META = {}

# hero bone <- Mixamo bone
MAP = {
    "hips": "Hips", "spine": "Spine1", "chest": "Spine2", "neck": "Neck", "head": "Head",
    "shoulder.L": "LeftShoulder", "upper_arm.L": "LeftArm", "forearm.L": "LeftForeArm", "hand.L": "LeftHand",
    "shoulder.R": "RightShoulder", "upper_arm.R": "RightArm", "forearm.R": "RightForeArm", "hand.R": "RightHand",
    "thigh.L": "LeftUpLeg", "shin.L": "LeftLeg", "foot.L": "LeftFoot", "toe.L": "LeftToeBase",
    "thigh.R": "RightUpLeg", "shin.R": "RightLeg", "foot.R": "RightFoot", "toe.R": "RightToeBase",
}


def log(*a):
    print("[mocap]", *a, flush=True)


def depth(b):
    d = 0
    while b.parent:
        d += 1
        b = b.parent
    return d


def load_hero(keep_mesh):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=HERO)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and not keep_mesh:
            bpy.data.objects.remove(o, do_unlink=True)
    if arm.animation_data:
        arm.animation_data.action = None
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    arm.name = "HeroRig"
    arm.data.pose_position = 'POSE'
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.matrix_basis = Matrix.Identity(4)
    if keep_mesh:
        for o in bpy.data.objects:
            if o.type == 'MESH' and o.data.shape_keys:
                for kb in o.data.shape_keys.key_blocks:
                    kb.value = 0.0
    return arm


def read_source(path):
    """Mixamo clip -> (frames, {mixamo bone: [armature-space 4x4 per frame]}, {bone: rest 4x4}) in Blender world space."""
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False)
    new = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new if o.type == 'ARMATURE')
    act = src.animation_data.action if src.animation_data else None
    if act is None:
        act = next(a for a in bpy.data.actions if a not in acts_before)
        src.animation_data_create()
        src.animation_data.action = act
    f0, f1 = int(round(act.frame_range[0])), int(round(act.frame_range[1]))
    mw = src.matrix_world.copy()
    names = {}
    for b in src.data.bones:
        short = b.name.split(":")[-1]
        names[short] = b.name
    rest = {s: mw @ src.data.bones[n].matrix_local for s, n in names.items()}
    want = sorted(set(MAP.values()))
    seq = {s: [] for s in want}
    sc = bpy.context.scene
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for s in want:
            seq[s].append(mw @ src.pose.bones[names[s]].matrix)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a not in acts_before:
            bpy.data.actions.remove(a)
    return list(range(f0, f1 + 1)), seq, rest


MIR = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))


def mirror_side(s):
    if s.startswith("Left"):
        return "Right" + s[4:]
    if s.startswith("Right"):
        return "Left" + s[5:]
    return s


def mirrored(seq, rest):
    """Left and right swapped (the armature's X flipped)."""
    seq2 = {s: [MIR @ m @ MIR for m in seq[mirror_side(s)]] for s in seq}
    rest2 = {s: MIR @ rest[mirror_side(s)] @ MIR for s in rest if mirror_side(s) in rest}
    return seq2, rest2


def rot3(m):
    return m.to_3x3().normalized()


def retarget_clip(arm, name, frames, seq, rest, opt):
    """Write action `name` on the hero rig."""
    bones = sorted(arm.data.bones, key=depth)
    order = [b.name for b in bones]
    restH = {b.name: b.matrix_local.copy() for b in bones}
    parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
    relH = {n: (restH[parent[n]].inverted() @ restH[n]) if parent[n] else restH[n] for n in order}
    k_hip = restH["hips"].translation.z / max(0.1, rest["Hips"].translation.z)
    s0 = seq["Hips"][0].translation.copy()
    s1 = seq["Hips"][-1].translation.copy()
    n = len(frames)
    place = opt.get("place", "zero")
    lean = math.radians(float(opt.get("lean", 0.0)))
    turns = {}
    for h, s in MAP.items():
        turns[h] = rest[s].to_3x3().normalized().inverted()
    poses = []
    for i in range(n):
        P = {}
        for h in order:
            if h in MAP:
                R = rot3(seq[MAP[h]][i]) @ turns[h] @ restH[h].to_3x3()
                if lean and h in ("spine",):
                    R = Matrix.Rotation(-lean, 3, 'X') @ R
            else:
                R = None
            if h == "hips":
                p = seq["Hips"][i].translation.copy()
                d = (p - rest["Hips"].translation) * k_hip
                if place == "zero":
                    d.x = (p.x - s0.x) * 0.0
                    d.y = (p.y - s0.y) * 0.0
                elif place == "loop":
                    f = i / max(1, n - 1)
                    d.x = (p.x - s0.x - (s1.x - s0.x) * f) * k_hip
                    d.y = (p.y - s0.y - (s1.y - s0.y) * f) * k_hip
                elif place == "sway":
                    # keep the sway round the start, cap it at 12 cm (attacks that step stay near the spot)
                    d.x = max(-0.12, min(0.12, (p.x - s0.x) * k_hip))
                    d.y = max(-0.12, min(0.12, (p.y - s0.y) * k_hip))
                pos = restH["hips"].translation + Vector((d.x, d.y, d.z))
                P[h] = Matrix.Translation(pos) @ R.to_4x4()
            elif parent[h] is None:
                P[h] = restH[h].copy()
            else:
                base = P[parent[h]] @ relH[h]
                if R is None:
                    P[h] = base
                else:
                    P[h] = Matrix.Translation(base.translation) @ R.to_4x4()
        poses.append(P)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    relH_inv = {h: relH[h].inverted() for h in order}
    prev = {}
    for i, f in enumerate(frames):
        P = poses[i]
        for h in order:
            if h in ("root",) or h.startswith("weapon."):
                continue
            pb = arm.pose.bones[h]
            basis = relH_inv[h] @ (P[parent[h]].inverted() @ P[h] if parent[h] else P[h])
            q = basis.to_quaternion()
            if h in prev and prev[h].dot(q) < 0.0:
                q = -q
            prev[h] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f - frames[0], group=h)
            if h == "hips":
                pb.location = basis.to_translation()
                pb.keyframe_insert("location", frame=f - frames[0], group=h)
    arm.animation_data.action = None
    return act, poses


def strike_time(poses, opt):
    """When the blow lands (or the spell leaves): the frame the weapon's tip (a hand, for spells) moves fastest,
    away from the clip's first and last 15%. spec "strike" (seconds) wins; "hand": R, L or both; "reach": the tip's
    distance along the weapon bone (m)."""
    if "strike" in opt:
        return float(opt["strike"])
    hands = {"R": ["R"], "L": ["L"], "both": ["R", "L"]}[opt.get("hand", "R")]
    reach = float(opt.get("reach", 0.9))
    n = len(poses)
    if n < 4:
        return n / 60.0
    speed = [0.0] * n
    for s in hands:
        tip = [(P["weapon." + s] @ Vector((0.0, reach, 0.0, 1.0))).to_3d() if reach > 0 else
               P["hand." + s].translation.copy() for P in poses]
        for i in range(1, n - 1):
            speed[i] = max(speed[i], (tip[i + 1] - tip[i - 1]).length * 15.0)
    a, b = int(n * 0.15), max(int(n * 0.15) + 1, int(n * 0.85))
    i = max(range(a, b), key=lambda j: speed[j])
    return i / 30.0


def stats(seq, rest, frames):
    """Numbers for choosing: hip drift across the floor, hand spacing (two-handed grips), lowest hand."""
    h = [m.translation for m in seq["Hips"]]
    drift = (h[-1] - h[0])
    far = max(((p - h[0]).xy.length for p in h), default=0.0)
    hands = [(seq["LeftHand"][i].translation - seq["RightHand"][i].translation).length for i in range(len(frames))]
    low = min(min(seq["LeftHand"][i].translation.z, seq["RightHand"][i].translation.z) for i in range(len(frames)))
    return "frames %d (%.2fs) drift %.2f m (max %.2f) hands apart %.2f-%.2f m lowest hand %.2f m" % (
        len(frames), len(frames) / 30.0, drift.xy.length, far, min(hands), max(hands), low)


def preview_setup(arm):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.render.resolution_x = 260
    sc.render.resolution_y = 340
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("w") if not sc.world else sc.world
    # a 1.2 m stick along the right weapon bone (a greatsword's reach), a short one on the left
    for side, length in (("R", 1.2), ("L", 0.35)):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.012, depth=length, location=(0, 0, 0))
        st = bpy.context.active_object
        st.name = "stick_" + side
        st.parent = arm
        st.parent_type = 'BONE'
        st.parent_bone = "weapon." + side
        # bone space: +Y along the bone; the cylinder runs along Z; put it from the grip outward along +Y
        st.matrix_parent_inverse = Matrix.Identity(4)
        st.rotation_euler = (math.radians(90), 0, 0)
        b = arm.data.bones["weapon." + side]
        st.location = (0, -b.length + length * 0.5 - 0.15, 0)
        mat = bpy.data.materials.new("stick")
        mat.diffuse_color = (0.9, 0.2, 0.1, 1.0) if side == "R" else (0.1, 0.4, 0.9, 1.0)
        st.data.materials.append(mat)
    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    cam_data.lens = 50
    return cam


def aim_cam(cam, yaw_deg):
    yaw = math.radians(yaw_deg)
    dist = 5.2
    target = Vector((0, 0, 0.95))
    pos = target + Vector((math.sin(yaw) * dist, -math.cos(yaw) * dist, 0.55))
    cam.location = pos
    d = (target - pos).normalized()
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()


def render_cells(arm, cam, act, name, nframes):
    sc = bpy.context.scene
    arm.animation_data.action = act
    if hasattr(arm.animation_data, "action_slot") and len(getattr(act, "slots", [])):
        arm.animation_data.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    os.makedirs(CELLS, exist_ok=True)
    for yi, yaw in enumerate((25, 115)):
        aim_cam(cam, yaw)
        for k in range(nframes):
            f = f0 + (f1 - f0) * k / max(1, nframes - 1)
            sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
            sc.render.filepath = os.path.join(CELLS, "%s__%d_%02d.png" % (name, yi, k))
            bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None


def main():
    t0 = time.time()
    keep_mesh = bool(CELLS)
    arm = load_hero(keep_mesh)
    cam = preview_setup(arm) if CELLS else None
    if SURVEY:
        files = sorted(f[:-4] for f in os.listdir(SRC) if f.endswith(".fbx"))
        jobs = [(f, {"src": f, "place": "keep"}) for f in files]
    else:
        spec = json.load(open(SPEC))
        jobs = [(k, v) for k, v in spec.items() if not k.startswith("_")]
    if ONLY:
        jobs = [(k, v) for k, v in jobs if re.search(ONLY, k)]
    report = []
    for name, opt in jobs:
        srcs = opt["src"] if isinstance(opt["src"], list) else [opt["src"]]
        paths = [os.path.join(SRC, x + ".fbx") for x in srcs]
        if not all(os.path.exists(x) for x in paths):
            log("MISSING", paths)
            continue
        frames, seq, rest = read_source(paths[0])
        for extra in paths[1:]:
            # "src": [a, b]: b's frames follow a's (a draw, then the release)
            f2, s2, _r2 = read_source(extra)
            frames = list(range(len(frames) + len(f2)))
            seq = {k: seq[k] + s2[k] for k in seq}
        frames = [f - frames[0] for f in frames]
        if opt.get("mirror"):
            seq, rest = mirrored(seq, rest)
        a, b = int(opt.get("start", frames[0])), int(opt.get("end", frames[-1]))
        keep = [i for i, f in enumerate(frames) if a <= f <= b]
        frames = [frames[i] for i in keep]
        seq = {s: [v[i] for i in keep] for s, v in seq.items()}
        line = "%-34s %s" % (name, stats(seq, rest, frames))
        report.append(line)
        log(line)
        act, poses = retarget_clip(arm, name, frames, seq, rest, opt)
        if not SURVEY:
            st = strike_time(poses, opt)
            m = {"length": round((len(frames) - 1) / 30.0, 4), "loop": bool(opt.get("loop", False))}
            if not m["loop"]:
                m["hits"] = [[round(max(0.0, st - 1 / 30.0), 4), round(st + 1 / 30.0, 4)]]
                if opt.get("kind") == "cast":
                    m["release"] = round(st, 4)
            META[name] = m
            log("  %s: %.2fs, strike %.2fs" % (name, m["length"], st))
        if CELLS:
            render_cells(arm, cam, act, name, NFRAMES)
        if SURVEY and not OUT:
            bpy.data.actions.remove(act)
    if CELLS:
        with open(os.path.join(CELLS, "report.txt"), "w") as f:
            f.write("\n".join(report) + "\n")
    if OUT and META:
        with open(os.path.join(os.path.dirname(os.path.abspath(OUT)), "mocap_meta.json"), "w") as f:
            json.dump({"fps": 30, "generator": "tools/blender/mocap_retarget.py", "animations": META}, f, indent=1)
    if OUT:
        for o in list(bpy.data.objects):
            if o != arm:
                bpy.data.objects.remove(o, do_unlink=True)
        os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
        for pb in arm.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        bpy.ops.object.select_all(action='DESELECT')
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format='GLB', export_animations=True,
                                  export_animation_mode='ACTIONS', export_skins=True, export_morph=False,
                                  export_yup=True, export_apply=False, export_force_sampling=True,
                                  export_frame_step=1)
        log("wrote %s with %d clips (%.1f KB)" % (OUT, len(bpy.data.actions), os.path.getsize(OUT) / 1024.0))
    log("done in %.1fs" % (time.time() - t0))


main()

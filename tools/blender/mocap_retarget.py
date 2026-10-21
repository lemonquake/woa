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
for finding the blow, "strike": seconds (the blow, given), "kind": "cast" (also writes the release), "run": true (writes
"ground_speed": the capture's own speed across the floor, m/s on the hero, so the game plays it without the feet
sliding), "seam": frames (a loop's last frames are eased into its first so it joins without a jump; loops default to
6), "airborne": [take-off, landing] seconds or "auto" (both feet off the floor; written to the timings, for Leap
Strike), "flat": true (the hips never rise above standing: the game lifts the hero itself)}}.
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


def rig_tables(arm):
    bones = sorted(arm.data.bones, key=depth)
    order = [b.name for b in bones]
    restH = {b.name: b.matrix_local.copy() for b in bones}
    parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
    relH = {n: (restH[parent[n]].inverted() @ restH[n]) if parent[n] else restH[n] for n in order}
    return order, restH, parent, relH


def to_local(P, order, parent, relH):
    """Armature-space pose -> each bone's turn and place against its rest under its parent."""
    return {h: relH[h].inverted() @ (P[parent[h]].inverted() @ P[h] if parent[h] else P[h]) for h in order}


def from_local(L, order, parent, relH):
    P = {}
    for h in order:
        P[h] = (P[parent[h]] @ relH[h] @ L[h]) if parent[h] else (relH[h] @ L[h])
    return P


UPPER = ("spine", "chest", "neck", "head", "shoulder.L", "upper_arm.L", "forearm.L", "hand.L", "shoulder.R",
         "upper_arm.R", "forearm.R", "hand.R")
ARMS = ("shoulder.L", "upper_arm.L", "forearm.L", "hand.L", "shoulder.R", "upper_arm.R", "forearm.R", "hand.R")


def bone_set(v):
    if isinstance(v, list):
        return tuple(v)
    return {"upper": UPPER, "arms": ARMS, "trunk": ("spine", "chest", "neck", "head"),
            "chest_up": UPPER[1:]}.get(v, UPPER)


def turn(q_local, deg):
    """A local turn of `deg` [x, y, z] degrees (bone axes) laid on q_local."""
    e = Matrix.Rotation(math.radians(deg[2]), 3, 'Z') @ Matrix.Rotation(math.radians(deg[1]), 3, 'Y') @ \
        Matrix.Rotation(math.radians(deg[0]), 3, 'X')
    return q_local @ e.to_quaternion()


def curve_at(curve, t):
    pts = sorted(curve)
    if t <= pts[0][0]:
        return pts[0][1]
    if t >= pts[-1][0]:
        return pts[-1][1]
    for (ta, wa), (tb, wb) in zip(pts, pts[1:]):
        if ta <= t <= tb:
            u = (t - ta) / max(1e-6, tb - ta)
            u = u * u * (3 - 2 * u)
            return wa + (wb - wa) * u
    return 1.0


def stylize(poses, opt, order, parent, relH, upper=None):
    """A hero's own way of moving, laid over the capture (run 2026-10-21 b), all in each bone's local turn:
      "upper": another clip's poses (`upper` here) for the bones in "upper_bones" (default the trunk and both arms;
        "arms", "trunk", "chest_up" or a list), blended by "upper_mix" (1 = all of it): a run's legs under a weapon
        stance;
      "amp": {bone or "all": factor}: how far each bone moves away from the clip's average turn (1.2 = bolder,
        0.7 = calmer);
      "pose": {bone: [x, y, z] degrees}: a constant offset in the bone's own axes (the hero's stance: chest out, head
        low, elbows wide); "pose_curve": [[t, w], ...] (seconds): how much of "pose" applies over time."""
    if not (upper or opt.get("amp") or opt.get("pose")):
        return poses
    locs = [to_local(P, order, parent, relH) for P in poses]
    n = len(locs)
    if upper:
        ub = bone_set(opt.get("upper_bones", "upper"))
        w = float(opt.get("upper_mix", 1.0))
        ul = [to_local(P, order, parent, relH) for P in upper]
        for i in range(n):
            U = ul[i % len(ul)]
            for h in ub:
                qa = locs[i][h].to_quaternion()
                qb = U[h].to_quaternion()
                if qa.dot(qb) < 0:
                    qb = -qb
                locs[i][h] = Matrix.Translation(locs[i][h].translation) @ qa.slerp(qb, w).to_matrix().to_4x4()
    amp = opt.get("amp")
    if amp:
        for h in order:
            k = float(amp.get(h, amp.get("all", 1.0)))
            if abs(k - 1.0) < 1e-4 or h == "root" or h.startswith("weapon."):
                continue
            qs = [L[h].to_quaternion() for L in locs]
            acc = Quaternion((0.0, 0.0, 0.0, 0.0))
            for q in qs:
                acc = acc + (q if q.dot(qs[0]) >= 0 else -q)
            avg = acc.normalized()
            for i, q in enumerate(qs):
                if q.dot(avg) < 0:
                    q = -q
                ax, ang = avg.rotation_difference(q).to_axis_angle()
                q2 = avg @ Quaternion(ax, ang * k)
                locs[i][h] = Matrix.Translation(locs[i][h].translation) @ q2.to_matrix().to_4x4()
    pose = opt.get("pose")
    if pose:
        curve = opt.get("pose_curve")
        for i in range(n):
            w = curve_at(curve, i / 30.0) if curve else 1.0
            for h, deg in pose.items():
                q2 = turn(locs[i][h].to_quaternion(), [d * w for d in deg])
                locs[i][h] = Matrix.Translation(locs[i][h].translation) @ q2.to_matrix().to_4x4()
    return [from_local(L, order, parent, relH) for L in locs]


def resample(frames, seq, factor):
    """Play a capture `factor` times as fast (1.25 = quicker), at 30 fps: each bone's turn slerped, place lerped."""
    n = len(frames)
    m = max(2, int(round((n - 1) / factor)) + 1)
    out = {s: [] for s in seq}
    for j in range(m):
        x = j * (n - 1) / (m - 1)
        i = min(n - 2, int(math.floor(x)))
        u = x - i
        for s, v in seq.items():
            a, b = v[i], v[i + 1]
            qa, qb = a.to_quaternion(), b.to_quaternion()
            if qa.dot(qb) < 0:
                qb = -qb
            t = a.translation.lerp(b.translation, u)
            out[s].append(Matrix.LocRotScale(t, qa.slerp(qb, u), a.to_scale().lerp(b.to_scale(), u)))
    return list(range(m)), out


def compute_poses(arm, frames, seq, rest, opt):
    """Each frame's armature-space pose of the hero rig for a Mixamo capture (no keys written). "crouch" (m) lowers
    the hips for a lower stance; "hip_drop" scales the capture's own hip rise and fall."""
    order, restH, parent, relH = rig_tables(arm)
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
                if opt.get("flat") and d.z > 0.0:
                    d.z = 0.0                    # the game lifts the hero itself (Leap Strike's arc): no own jump height
                d.z = d.z * float(opt.get("hip_drop", 1.0)) - float(opt.get("crouch", 0.0))
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
    return poses


def retarget_clip(arm, name, frames, seq, rest, opt, upper=None):
    """Write action `name` on the hero rig."""
    order, restH, parent, relH = rig_tables(arm)
    n = len(frames)
    poses = stylize(compute_poses(arm, frames, seq, rest, opt), opt, order, parent, relH, upper)
    seam = int(opt.get("seam", 6 if opt.get("loop") else 0))
    if seam > 0 and n > 3 * seam:
        # ease the last `seam` frames into the first frame's pose (each bone's armature-space turn and the hips'
        # place), so the loop's wrap from its last frame to its first is an ordinary step
        for j in range(seam):
            i = n - seam + j
            w = ((j + 1) / seam) ** 2 * (3 - 2 * (j + 1) / seam)        # smoothstep to 1 at the last frame
            P, F = poses[i], poses[0]
            for h in P:
                qa = P[h].to_quaternion()
                qb = F[h].to_quaternion()
                if qa.dot(qb) < 0:
                    qb = -qb
                q = qa.slerp(qb, w)
                t = P[h].translation.lerp(F[h].translation, w)
                P[h] = Matrix.Translation(t) @ q.to_matrix().to_4x4()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    relH_inv = {h: relH[h].inverted() for h in order}
    keys = {}
    locs = []
    for i, f in enumerate(frames):
        P = poses[i]
        for h in order:
            if h in ("root",) or h.startswith("weapon."):
                continue
            basis = relH_inv[h] @ (P[parent[h]].inverted() @ P[h] if parent[h] else P[h])
            q = basis.to_quaternion()
            seq_h = keys.setdefault(h, [])
            if seq_h and seq_h[-1].dot(q) < 0.0:
                q = -q
            seq_h.append(q)
            if h == "hips":
                locs.append(basis.to_translation())
    fixed = clean_turns(keys)
    if fixed:
        log("  %s: %s" % (name, ", ".join("%s %d" % (k, v) for k, v in sorted(fixed.items()))))
    for h, qs in keys.items():
        pb = arm.pose.bones[h]
        for i, q in enumerate(qs):
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frames[i] - frames[0], group=h)
    pb = arm.pose.bones["hips"]
    for i, t in enumerate(locs):
        pb.location = t
        pb.keyframe_insert("location", frame=frames[i] - frames[0], group="hips")
    arm.animation_data.action = None
    return act, poses


TOE_MAX = math.radians(60.0)                 # a toe bends at most this far from its rest, either way
TOE_MIN = math.radians(-50.0)
TOE_RATE = math.radians(25.0)                # per frame
SPIKE = math.radians(35.0)                   # a single frame this far off both neighbours is a capture glitch


def clean_turns(keys):
    """Capture glitches out of each bone's turns (in place); returns {kind: frames fixed}.
      * toes: a hinge, bent about the bone's X axis only and within TOE_MIN..TOE_MAX (Mixamo's toes curl to 145
        degrees in some falls, then wrap round and swap the way they bend in one frame);
      * spikes: a frame that jumps more than SPIKE away from the frame before it and comes back (the frames either
        side of it are close) is set halfway between them."""
    fixed = {}
    for h, qs in keys.items():
        if h.startswith("toe."):
            # a toe is a hinge: only its bend about the bone's X axis is kept, within TOE_MIN..TOE_MAX, and it bends
            # at most TOE_RATE a frame (eased both ways through the clip)
            bends = []
            for i, q in enumerate(qs):
                q = q if q.w >= 0 else -q
                bend = 2.0 * math.atan2(q.x, q.w)
                c = max(TOE_MIN, min(TOE_MAX, bend))
                if abs(c - bend) > 1e-3 or abs(q.y) + abs(q.z) > 0.02:
                    fixed["toe hinge"] = fixed.get("toe hinge", 0) + 1
                bends.append(c)
            for rng in (range(1, len(bends)), range(len(bends) - 2, -1, -1)):
                for i in rng:
                    j = i - 1 if rng.step > 0 else i + 1
                    d = bends[i] - bends[j]
                    if abs(d) > TOE_RATE:
                        bends[i] = bends[j] + math.copysign(TOE_RATE, d)
            for i, c in enumerate(bends):
                qs[i] = Quaternion((1.0, 0.0, 0.0), c)
        for i in range(1, len(qs) - 1):
            a, b, c = qs[i - 1], qs[i], qs[i + 1]
            if a.rotation_difference(b).angle > SPIKE and a.rotation_difference(c).angle < 0.5 * a.rotation_difference(b).angle:
                qs[i] = a.slerp(c, 0.5)
                fixed["spike " + h] = fixed.get("spike " + h, 0) + 1
        for i in range(1, len(qs)):
            if qs[i - 1].dot(qs[i]) < 0.0:
                qs[i] = -qs[i]
    return fixed


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
        if abs(float(opt.get("speed", 1.0)) - 1.0) > 1e-4:
            frames, seq = resample(frames, seq, float(opt["speed"]))
        upper = None
        if opt.get("upper"):
            # the upper body from another capture (its own start, end, speed, mirror), looped under these frames
            uo = opt["upper"] if isinstance(opt["upper"], dict) else {"src": opt["upper"]}
            uf, us, ur = read_source(os.path.join(SRC, uo["src"] + ".fbx"))
            uf = [f - uf[0] for f in uf]
            if uo.get("mirror"):
                us, ur = mirrored(us, ur)
            ua, ub = int(uo.get("start", uf[0])), int(uo.get("end", uf[-1]))
            ukeep = [i for i, f in enumerate(uf) if ua <= f <= ub]
            uf = [uf[i] for i in ukeep]
            us = {s: [v[i] for i in ukeep] for s, v in us.items()}
            if abs(float(uo.get("speed", 1.0)) - 1.0) > 1e-4:
                uf, us = resample(uf, us, float(uo["speed"]))
            if uo.get("fit", True) and len(uf) != len(frames) and len(uf) > 1:
                # stretch the upper clip over this one's length (a looping stance under a looping run)
                uf, us = resample(uf, us, (len(uf) - 1) / max(1, len(frames) - 1))
            upper = compute_poses(arm, uf, us, ur, dict(uo, place="zero"))
        line = "%-34s %s" % (name, stats(seq, rest, frames))
        report.append(line)
        log(line)
        act, poses = retarget_clip(arm, name, frames, seq, rest, opt, upper)
        if arg("speeds"):
            # the right weapon tip's speed each frame (m/s), to find where a combo's blows fall ("start"/"end")
            tip = [(P["weapon.R"] @ Vector((0.0, float(opt.get("reach", 0.9)), 0.0, 1.0))).to_3d() for P in poses]
            sp = [0.0] + [(tip[i + 1] - tip[i - 1]).length * 15.0 for i in range(1, len(tip) - 1)] + [0.0]
            log("  speeds %s: %s" % (name, " ".join("%d:%.0f" % (i, v) for i, v in enumerate(sp) if i % 2 == 0)))
        if not SURVEY:
            st = strike_time(poses, opt)
            m = {"length": round((len(frames) - 1) / 30.0, 4), "loop": bool(opt.get("loop", False))}
            if opt.get("run"):
                k_hip = arm.data.bones["hips"].matrix_local.translation.z / max(0.1, rest["Hips"].translation.z)
                d = (seq["Hips"][-1].translation - seq["Hips"][0].translation).xy.length * k_hip
                m["ground_speed"] = round(d / max(1e-3, (len(frames) - 1) / 30.0), 3)
                log("  %s: ground speed %.2f m/s" % (name, m["ground_speed"]))
            if opt.get("airborne") == "auto":
                # the longest stretch with both feet off the floor (toes 8 cm above their lowest point)
                lowz = min(min(seq["LeftToeBase"][i].translation.z, seq["RightToeBase"][i].translation.z)
                           for i in range(len(frames)))
                up = [min(seq["LeftToeBase"][i].translation.z, seq["RightToeBase"][i].translation.z) > lowz + 0.08
                      for i in range(len(frames))]
                best, cur = (0, 0), None
                for i, u in enumerate(up + [False]):
                    if u and cur is None:
                        cur = i
                    elif not u and cur is not None:
                        if i - cur > best[1] - best[0]:
                            best = (cur, i)
                        cur = None
                m["airborne"] = [round(best[0] / 30.0, 4), round(best[1] / 30.0, 4)]
                log("  %s: airborne %.2f-%.2f s" % (name, m["airborne"][0], m["airborne"][1]))
            elif "airborne" in opt:
                m["airborne"] = opt["airborne"]
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

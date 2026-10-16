"""Build Roydo's, the Anomaly form's and Blau's bodies and Blau's turret: assets/characters/heroes16/*.glb.

Sources (all CC0, Quaternius, see docs/ASSET_CREDITS.md; downloaded into work/downloads/q_*):
  * Universal Base Characters (Superhero_Male): the body and head of both heroes.
  * Modular Character Outfits - Fantasy (Male_Ranger): Blau's coat, hood, bracers, belts and boots (recoloured here);
    Roydo wears its bracers, belts and boots reworked into dark armour.
  * Universal Animation Library 1 and 2: 86 clips on the same rig; renamed to the game's clip names below, and Blau's
    gun clips re-solved so his left hand holds the rifle's fore-end (two-handed grip).
  * Sci-Fi Essentials Kit: Gun_Sniper (Blau's rifle) and Enemy_QuadShell (the turret, with its own clips).

What this script makes (no hand edits; run again after any change):
  * roydo.glb: the body with a longer, ridged alien skull, no brows, glowing eyes (material "RoydoEyes"), the skin as
    material "RoydoSkin" (the game draws it with src/game/roydo_skin.gdshader: a moving night sky), dark armour pieces
    ("RoydoArmor").
  * anomaly.glb: the same body pushed into a hulking monster (thick arms and shoulders, big hands, hunched), crystal
    spikes along the spine, shoulders and forearms ("AnomalyCrystal"), skin "AnomalySkin".
  * blau.glb: the body with the recoloured ranger outfit (navy coat, charcoal leather, gold buckles, a cyan glowing trim
    in an emissive map), a short beard, the rifle in his right hand ("BlauRifle"), a "muzzle" bone at the barrel's tip.
  * blau_turret.glb: the QuadShell walker, scaled, with its clips renamed (idle, attack, hit, death, charge).
Run:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/heroes16.py
      [-- --only=blau,roydo,anomaly,turret] [--preview=dir] [--clips=a,b] [--frames=0.2,0.5]
"""
import bpy
import bmesh
import colorsys
import math
import os
import sys
from mathutils import Vector, Matrix

ROOT = "A:/Python/woa"
DL = ROOT + "/work/downloads"
UBC = DL + "/q_ubc/x/Universal Base Characters[Standard]"
OUTFITS = DL + "/q_outfits/x/Modular Character Outfits - Fantasy[Standard]"
UAL1 = DL + "/q_ual1/x/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
UAL2 = DL + "/q_ual2/x/Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb"
SCIFI = DL + "/q_scifi_essentials/x/glTF"
OUT = ROOT + "/assets/characters/heroes16"
TEX = ROOT + "/work/heroes16_tex"          # intermediate textures (packed into the GLBs)
META = OUT + "/heroes16_meta.json"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def _arg(name, default=""):
    return next((a.split("=", 1)[1] for a in ARGS if a.startswith("--" + name + "=")), default)
ONLY = [s for s in _arg("only", "blau,roydo,anomaly,turret").split(",") if s]
PREVIEW = _arg("preview")
PREVIEW_CLIPS = [s for s in _arg("clips").split(",") if s]
PREVIEW_FRAMES = [float(s) for s in _arg("frames", "0.0,0.33,0.66").split(",")]

# Clips each hero keeps: game name -> library clip. Loops are named *_loop by the library; the game sets loop modes.
COMMON = {
    "death": "Death01", "knockback": "Hit_Knockback", "hit_heavy": "Hit_Chest", "hit_head": "Hit_Head",
    "getup": "LayToIdle", "victory": "Dance_Loop", "idle_talk": "Idle_Talking_Loop", "roll": "Roll",
}
ROYDO_CLIPS = dict(COMMON, **{
    "idle": "Idle_Loop", "idle_fold": "Idle_FoldArms_Loop", "run": "Jog_Fwd_Loop", "sprint": "Sprint_Loop",
    "walk": "Walk_Formal_Loop", "punch_jab": "Punch_Jab", "punch_cross": "Punch_Cross", "punch_hook": "Melee_Hook",
    "cast_shoot": "Spell_Simple_Shoot", "cast_enter": "Spell_Simple_Enter", "cast_hold": "Spell_Simple_Idle_Loop",
    "cast_exit": "Spell_Simple_Exit", "cast_throw": "OverhandThrow", "cast_slam": "Shield_OneShot",
    "jump_start": "NinjaJump_Start", "jump_land": "NinjaJump_Land",
})
ANOMALY_CLIPS = dict(COMMON, **{
    "idle": "Zombie_Idle_Loop", "idle_tall": "Idle_Loop", "run": "Sprint_Loop", "walk": "Zombie_Walk_Fwd_Loop",
    "blast": "Spell_Simple_Shoot", "blast_throw": "OverhandThrow", "smash": "Zombie_Scratch",
    "punch_hook": "Melee_Hook", "cast_shoot": "Spell_Simple_Shoot", "cast_slam": "Shield_OneShot",
    "roar": "Idle_Shield_Break",
})
BLAU_CLIPS = dict(COMMON, **{
    "idle": "Pistol_Idle_Loop", "idle_plain": "Idle_Loop", "aim": "Pistol_Aim_Neutral", "aim_up": "Pistol_Aim_Up",
    "aim_down": "Pistol_Aim_Down", "shoot": "Pistol_Shoot", "reload": "Pistol_Reload", "sprint": "Sprint_Loop",
    "cast_shoot": "Spell_Simple_Shoot", "cast_throw": "OverhandThrow", "kneel_fix": "Fixing_Kneeling",
    "interact": "Interact", "jump_start": "NinjaJump_Start", "jump_air": "NinjaJump_Idle_Loop",
    "jump_land": "NinjaJump_Land", "drive": "Driving_Loop", "idle_fold": "Idle_FoldArms_Loop",
})
# Blau's clips where both hands hold the rifle: the left hand is moved onto the fore-end
BLAU_TWO_HANDED = ["idle", "aim", "aim_up", "aim_down", "shoot", "run_rifle"]
ARM_BONES = ["clavicle", "upperarm", "lowerarm", "hand", "thumb_01", "thumb_02", "thumb_03", "index_01", "index_02",
             "index_03", "middle_01", "middle_02", "middle_03", "ring_01", "ring_02", "ring_03", "pinky_01", "pinky_02",
             "pinky_03"]


# ---- Scene helpers ------------------------------------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30


def import_gltf(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == 'MESH' and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o, do_unlink=True)
            new.remove(o)
    return new


def armature_of(objs):
    return next(o for o in objs if o.type == 'ARMATURE')


def meshes_of(objs):
    return [o for o in objs if o.type == 'MESH']


def set_active(o):
    for s in bpy.context.selected_objects:
        s.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def fcurves(act):
    """The action's F-curves (Blender 5 layered actions keep them in a channel bag per slot)."""
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def assign(arm, act):
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    if act.slots and arm.animation_data.action_slot is None:
        arm.animation_data.action_slot = act.slots[0]


def library_actions():
    """Import both animation libraries; keep their actions (fake user), drop their objects."""
    acts = {}
    for path in [UAL1, UAL2]:
        before = set(bpy.data.actions)
        objs = import_gltf(path)
        for a in bpy.data.actions:
            if a not in before:
                name = a.name.split(".")[0]
                if name not in acts:
                    acts[name] = a
                    a.use_fake_user = True
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
    return acts


# clips every unit model shares by name (the game plays them by these names); everything else gets the model's prefix
GENERIC = ("death", "knockback", "hit_heavy", "getup", "launch", "wall_impact")


def keep_clips(arm, lib, table, extra=None, prefix=""):
    """Copies of the library clips under the game's names (prefixed unless generic); every other action is removed."""
    keep = {}
    for game, src in table.items():
        a = lib[src].copy()
        a.name = game if game in GENERIC or not prefix else prefix + game
        a.use_fake_user = True
        keep[game] = a
    for game, a in (extra or {}).items():
        a.name = game
        a.use_fake_user = True
        keep[game] = a
    return keep


def rename_prefixed(keep, prefix):
    for game, a in keep.items():
        a.name = game if game in GENERIC else prefix + game


# measured values the automatic estimate gets wrong (in-place library clips: the stance foot test overshoots; spell
# clips whose fastest frame is not the release), checked on frame strips in work/lemondev/2026-10-16-roydo-blau/
META_OVERRIDES = {
 "roydo_run": {
  "ground_speed": 3.6
 },
 "blau_run_rifle": {
  "ground_speed": 3.6
 },
 "roydo_sprint": {
  "ground_speed": 6.2
 },
 "blau_sprint": {
  "ground_speed": 6.2
 },
 "anomaly_run": {
  "ground_speed": 6.2
 },
 "roydo_walk": {
  "ground_speed": 1.45
 },
 "anomaly_walk": {
  "ground_speed": 1.2
 },
 "blau_kneel_fix": {
  "release": 0.6,
  "length": 1.5
 },
 "roydo_cast_shoot": {
  "release": 0.25
 },
 "anomaly_blast": {
  "release": 0.12
 },
 "anomaly_cast_shoot": {
  "release": 0.12
 },
 "blau_cast_shoot": {
  "release": 0.2
 },
 "blau_shoot": {
  "release": 0.04
 },
 "turret_attack": {
  "release": 0.08
 }
}


def clip_meta(arm, keep, prefix, active_hand="hand_r"):
    """Timing data per clip for the game (ModelCatalog.clip): length; the strike moment of attacks and casts (the
    peak speed of the striking hand); runs' ground speed (how fast a planted foot slides back)."""
    import json
    out = {}
    fps = bpy.context.scene.render.fps
    for game, a in keep.items():
        f0, f1 = frame_range(a)
        name = a.name
        m = {"length": round((f1 - f0) / fps, 3), "loop": game.endswith(("idle", "run", "walk", "sprint", "hold", "fold",
             "drive", "plain", "tall", "talk", "jump_air", "run_rifle", "look"))}
        assign(arm, a)
        hands = []
        feet = []
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            P = arm.pose.bones
            mw = arm.matrix_world
            hands.append([mw @ P[h].head for h in ("hand_r", "hand_l")] if "hand_r" in P else [])
            feet.append([mw @ P[x].head for x in ("foot_l", "foot_r")] if "foot_l" in P else [])
        if hands and hands[0] and len(hands) > 2:
            best, bt = 0.0, (f1 - f0) * 0.5
            for i in range(1, len(hands)):
                for k in range(2):
                    sp = (hands[i][k] - hands[i - 1][k]).length * fps
                    if sp > best:
                        best, bt = sp, i
            m["release"] = round(bt / fps, 3)
        if feet and feet[0] and ("run" in game or "walk" in game or "sprint" in game):
            speeds = []
            for i in range(1, len(feet)):
                for k in range(2):
                    if feet[i][k].z < min(fe[k].z for fe in feet) + 0.04:
                        d = feet[i][k] - feet[i - 1][k]
                        speeds.append(Vector((d.x, d.y)).length * fps)
            if speeds:
                speeds.sort()
                m["ground_speed"] = round(speeds[len(speeds) // 2], 3)
        out[name] = m
    data = {}
    if os.path.exists(META):
        data = json.load(open(META))
    anims = data.get("animations", {})
    anims = {k: v for k, v in anims.items() if not (k.startswith(prefix) and prefix)}
    for k, v in META_OVERRIDES.items():
        if k in out:
            out[k].update(v)
    anims.update(out)
    data["animations"] = anims
    json.dump(data, open(META, "w"), indent=1, sort_keys=True)


def despike(arm, keep, limit_deg=80.0):
    """Smooth the rare one-frame snaps in the library clips: wherever a joint turns more than `limit_deg` between two
    frames (relative to its parent), the frame is re-keyed halfway between its neighbours (slerp). Checked by
    tests/tools/anim_pops16.gd."""
    import mathutils
    fixed = 0
    for name, act in keep.items():
        f0, f1 = frame_range(act)
        if f1 - f0 < 3:
            continue
        assign(arm, act)
        frames = {}
        for f in range(f0, f1 + 1):
            bpy.context.scene.frame_set(f)
            frames[f] = {pb.name: pb.rotation_quaternion.copy() for pb in arm.pose.bones}
        for pb in arm.pose.bones:
            if "leaf" in pb.name:
                continue
            for f in range(f0 + 1, f1):
                q0, q1, q2 = frames[f - 1][pb.name], frames[f][pb.name], frames[f + 1][pb.name]
                if math.degrees(q0.rotation_difference(q1).angle) > limit_deg:
                    mid = q0.slerp(q2, 0.5)
                    frames[f][pb.name] = mid
                    bpy.context.scene.frame_set(f)
                    pb.rotation_mode = 'QUATERNION'
                    pb.rotation_quaternion = mid
                    pb.keyframe_insert("rotation_quaternion", frame=f)
                    fixed += 1
    print("despike: %d joint frames smoothed" % fixed)


def purge_actions(keep):
    keep_set = set(keep.values())
    for a in list(bpy.data.actions):
        if a not in keep_set:
            bpy.data.actions.remove(a)


def frame_range(act):
    f0, f1 = act.frame_range
    return int(round(f0)), int(round(f1))


def pose_at(arm, act, frame):
    assign(arm, act)
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()


def shrink_images(limit=1024):
    for img in bpy.data.images:
        if img.size[0] > limit or img.size[1] > limit:
            img.scale(min(limit, img.size[0]), min(limit, img.size[1]))


def export(arm, meshes, path, keep):
    shrink_images()
    for s in bpy.context.selected_objects:
        s.select_set(False)
    arm.select_set(True)
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = arm
    # each kept action becomes one glTF animation
    for a in keep.values():
        a.use_fake_user = True
    # the exporter only looks for actions on an armature that has animation data; give every clip its slot
    for a in keep.values():
        assign(arm, a)
    assign(arm, keep.get("idle", next(iter(keep.values()))))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_animations=True,
                              export_animation_mode='ACTIONS', export_force_sampling=True, export_optimize_animation_size=True,
                              export_def_bones=False, export_reset_pose_bones=True, export_image_format='AUTO',
                              export_yup=True, export_apply=False, export_skins=True, export_morph=False)
    print("WROTE", path, os.path.getsize(path))


# ---- Images -------------------------------------------------------------------------------------------------------------

def load_image(path):
    return bpy.data.images.load(path, check_existing=True)


def px(img):
    import numpy as np
    a = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], img.channels)
    return a


def write_image(arr, name, path):
    import numpy as np
    h, w, c = arr.shape
    if c == 3:
        arr = np.concatenate([arr, np.ones((h, w, 1), np.float32)], axis=2)
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels = arr.reshape(-1).tolist()
    img.filepath_raw = path
    img.file_format = 'PNG'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save()
    return img


def recolor_ranger(src_path, orm_path, out_base, out_emit):
    """Blau's coat: green cloth -> navy and steel blue, brown leather -> charcoal leather, the linen shirt -> slate,
    metal (the ORM map's metallic channel) -> gold; an emissive map with a thin cyan glow along the cloth's seams."""
    import numpy as np
    a = px(load_image(src_path))[:, :, :3]
    orm = px(load_image(orm_path))[:, :, :3]
    step = max(1, a.shape[0] // 1024)
    a = a[::step, ::step, :].copy()
    step2 = max(1, orm.shape[0] // a.shape[0])
    metal_ch = orm[::step2, ::step2, 2][:a.shape[0], :a.shape[1]]
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    v = mx
    s = np.where(mx > 1e-5, (mx - mn) / np.maximum(mx, 1e-5), 0.0)
    d = np.maximum(mx - mn, 1e-5)
    h = np.where(mx == r, ((g - b) / d) % 6.0, np.where(mx == g, (b - r) / d + 2.0, (r - g) / d + 4.0)) * 60.0
    metal = metal_ch > 0.5
    green = (h > 70) & (h < 165) & (s > 0.25) & ~metal
    leather = (h >= 5) & (h <= 50) & (s > 0.3) & ~green & ~metal
    linen = ~green & ~leather & ~metal & (v > 0.3)
    out = a.copy()

    def hsv_to_rgb(hh, ss, vv):
        hh = (hh % 360.0) / 60.0
        c = vv * ss
        x = c * (1 - np.abs(hh % 2 - 1))
        m = vv - c
        z = np.zeros_like(hh)
        rr = np.select([hh < 1, hh < 2, hh < 3, hh < 4, hh < 5], [c, x, z, z, x], c)
        gg = np.select([hh < 1, hh < 2, hh < 3, hh < 4, hh < 5], [x, c, c, x, z], z)
        bb = np.select([hh < 1, hh < 2, hh < 3, hh < 4, hh < 5], [z, z, x, c, c], x)
        return np.stack([rr + m, gg + m, bb + m], axis=2)

    navy = hsv_to_rgb(np.full_like(h, 222.0), np.clip(s * 0.85, 0.35, 0.8), np.clip(v * 0.82, 0.02, 1.0))
    out[green] = navy[green]
    leath = hsv_to_rgb(np.full_like(h, 24.0), np.clip(s * 0.35, 0.05, 0.3), np.clip(v * 0.55, 0.02, 1.0))
    out[leather] = leath[leather]
    slate = hsv_to_rgb(np.full_like(h, 214.0), np.full_like(h, 0.16), np.clip(v * 0.55, 0.02, 1.0))
    out[linen] = slate[linen]
    gold = hsv_to_rgb(np.full_like(h, 42.0), np.full_like(h, 0.62), np.clip(0.35 + v * 0.65, 0.0, 1.0))
    out[metal] = gold[metal]
    m = green.astype(np.float32)
    edge = np.zeros_like(m)
    for dy, dx in [(-2, 0), (2, 0), (0, -2), (0, 2), (-1, -1), (1, 1)]:
        edge = np.maximum(edge, np.abs(np.roll(np.roll(m, dy, 0), dx, 1) - m))
    edge *= m
    emit = np.zeros_like(out)
    emit[:, :, 0] = edge * 0.15
    emit[:, :, 1] = edge * 0.85
    emit[:, :, 2] = edge * 1.0
    write_image(np.clip(out, 0.0, 1.0), "BlauCoat", out_base)
    write_image(emit, "BlauCoatGlow", out_emit)
    return out_base, out_emit


def armor_texture(src_path, out_path):
    """Roydo's armour pieces (ranger bracers, belts, boots): obsidian with violet sheen, metal parts pale silver."""
    import numpy as np
    img = load_image(src_path)
    a = px(img)[:, :, :3]
    step = max(1, a.shape[0] // 1024)
    a = a[::step, ::step, :].copy()
    lum = a @ np.array([0.3, 0.55, 0.15], np.float32)
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    s = np.where(mx > 1e-5, (mx - mn) / np.maximum(mx, 1e-5), 0.0)
    metal = (s < 0.18) & (mx > 0.55)
    out = np.stack([lum * 0.32 + 0.02, lum * 0.24 + 0.015, lum * 0.5 + 0.04], axis=2)
    silver = np.stack([lum * 0.9 + 0.1, lum * 0.92 + 0.1, lum + 0.12], axis=2)
    out[metal] = silver[metal]
    write_image(np.clip(out, 0, 1), "RoydoArmor", out_path)
    return out_path


def material(name, base=None, color=(1, 1, 1, 1), emit=None, emit_strength=1.0, rough=0.6, metal=0.0, normal=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if base:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = load_image(base)
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if normal:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = load_image(normal)
        t.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emit:
        if isinstance(emit, str):
            t = nt.nodes.new("ShaderNodeTexImage")
            t.image = load_image(emit)
            nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
        else:
            bsdf.inputs["Emission Color"].default_value = emit
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    return m


def set_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


# ---- Mesh helpers -------------------------------------------------------------------------------------------------------

def bone_world(arm, name, tail=False):
    b = arm.data.bones[name]
    return arm.matrix_world @ (b.tail_local if tail else b.head_local)


def delete_verts(obj, pred):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    kill = [v for v in bm.verts if pred(obj.matrix_world @ v.co, v)]
    bmesh.ops.delete(bm, geom=kill, context='VERTS')
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def weights(obj, v_index):
    out = {}
    for g in obj.data.vertices[v_index].groups:
        out[obj.vertex_groups[g.group].name] = g.weight
    return out


def drop_skin_faces(obj, keep_bones):
    """Remove faces using a bare-skin material ("MI_Regular_*") unless their vertices belong mostly to `keep_bones`."""
    skin_slots = {i for i, sl in enumerate(obj.material_slots) if sl.material and sl.material.name.startswith("MI_Regular")}
    if not skin_slots:
        return
    names = {g.index: g.name for g in obj.vertex_groups}
    def kept(v):
        best, bw = "", 0.0
        for g in v.groups:
            if g.weight > bw:
                best, bw = names.get(g.group, ""), g.weight
        return best.startswith(keep_bones)
    keep_v = [kept(v) for v in obj.data.vertices]
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    kill = [f for f in bm.faces if f.material_index in skin_slots and not all(keep_v[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def bind_rigid(obj, arm, bone):
    """Skin every vertex of `obj` fully to one bone (a rigid prop that follows it)."""
    obj.vertex_groups.clear()
    vg = obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    obj.parent = arm


def rebind(obj, arm):
    for mod in obj.modifiers:
        if mod.type == 'ARMATURE':
            mod.object = arm
    mw = obj.matrix_world.copy()
    obj.parent = arm
    obj.matrix_world = mw


def add_bone(arm, name, parent, head, tail):
    set_active(arm)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones.new(name)
    inv = arm.matrix_world.inverted()
    eb.head = inv @ head
    eb.tail = inv @ tail
    eb.parent = arm.data.edit_bones[parent]
    eb.use_deform = False
    bpy.ops.object.mode_set(mode='OBJECT')


# ---- Blau ---------------------------------------------------------------------------------------------------------------

def build_blau(lib):
    body = import_gltf(UBC + "/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf")
    arm = armature_of(body)
    outfit = import_gltf(OUTFITS + "/Exports/glTF (Godot-Unreal)/Outfits/Male_Ranger.gltf")
    oarm = armature_of(outfit)
    pieces = meshes_of(outfit)
    for p in pieces:
        rebind(p, arm)
    bpy.data.objects.remove(oarm, do_unlink=True)
    beard = import_gltf(UBC + "/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Beard.gltf")
    barm = [o for o in beard if o.type == 'ARMATURE']
    bmeshes = meshes_of(beard)
    for p in bmeshes:
        rebind(p, arm)
    for o in barm:
        bpy.data.objects.remove(o, do_unlink=True)
    skin = next(o for o in body if o.type == 'MESH' and o.name.startswith("SuperHero"))
    # the sleeves carry bare-skin faces at the shoulders (under the vest in the pack's own body); keep only the hands
    for p in pieces:
        drop_skin_faces(p, keep_bones=("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_", "lowerarm_"))
    # the outfit covers everything below the jaw: keep the head and neck only (no skin pokes through the coat)
    names = {g.index: g.name for g in skin.vertex_groups}
    def head_part(v):
        w = sum(g.weight for g in v.groups if names.get(g.group, "") in ("Head", "neck_01"))
        return w >= 0.5
    keep_v = [head_part(v) for v in skin.data.vertices]
    delete_verts(skin, lambda co, v: not keep_v[v.index])
    # coat textures
    base, glow = recolor_ranger(OUTFITS + "/Textures/Ranger/T_Ranger_BaseColor.png",
                                OUTFITS + "/Textures/Ranger/T_Ranger_ORM.png", TEX + "/blau_coat.png",
                                TEX + "/blau_coat_glow.png")
    # a dark brown beard and brows (the pack's hair texture is grey-blond)
    for p in bmeshes + [o for o in body if o.type == 'MESH' and o.name.startswith("Eyebrows")]:
        for slot in p.material_slots:
            if slot.material and slot.material.node_tree:
                bs = slot.material.node_tree.nodes.get("Principled BSDF")
                if bs:
                    for l in list(bs.inputs["Base Color"].links):
                        slot.material.node_tree.links.remove(l)
                    bs.inputs["Base Color"].default_value = (0.09, 0.055, 0.035, 1.0)
    coat = material("BlauCoat", base=base, emit=glow, emit_strength=2.5, rough=0.75,
                    normal=OUTFITS + "/Textures/Ranger/T_Ranger_Normal.png")
    for p in pieces:
        for i, slot in enumerate(p.material_slots):
            if slot.material and slot.material.name.startswith("MI_Ranger"):
                p.material_slots[i].material = coat
    # the rifle: scaled to 1.15 m, grip in the right palm, barrel along the aim of the pistol clips
    rifle = meshes_of(import_gltf(SCIFI + "/Gun_Sniper.gltf"))[0]
    rifle.name = "BlauRifle"
    for slot in rifle.material_slots:
        if slot.material:
            slot.material.name = "BlauRifle"
    s = 1.15 / 1.72
    rifle.scale = (s, s, s)
    bpy.context.view_layer.update()
    keep = keep_clips(arm, lib, BLAU_CLIPS)
    # where the rifle sits: measured in the aiming pose, then fixed to the right hand
    aim = keep["aim"]
    f0, f1 = frame_range(aim)
    pose_at(arm, aim, (f0 + f1) // 2)
    pb = arm.pose.bones["hand_r"]
    hand_m = arm.matrix_world @ pb.matrix
    mid = arm.matrix_world @ arm.pose.bones["middle_01_r"].head
    palm = (arm.matrix_world @ pb.head).lerp(mid, 0.55)
    # aim direction: forward (Blender -Y) levelled; up: world Z
    fwd = Vector((0.0, -1.0, 0.0))
    chest = arm.matrix_world @ arm.pose.bones["spine_03"].head
    lh = arm.matrix_world @ arm.pose.bones["hand_l"].head
    side = fwd.cross(Vector((0, 0, 1))).normalized()
    # rifle local frame (glTF import): barrel along -X, up +Z (Blender: glTF y-up becomes z-up)
    rot = Matrix((
        (-fwd.x, side.x, 0.0),
        (-fwd.y, side.y, 0.0),
        (-fwd.z, side.z, 1.0))).to_4x4()
    # columns: local x -> -fwd, local y -> side, local z -> up
    rot = Matrix.Identity(4)
    rot.col[0].xyz = -fwd
    rot.col[1].xyz = Vector((0, 0, 1)).cross(-fwd)
    rot.col[2].xyz = Vector((0, 0, 1))
    world = Matrix.Translation(palm + Vector((0, 0, -0.02))) @ rot @ Matrix.Diagonal((s, s, s, 1.0))
    local = hand_m.inverted() @ world
    # rest-pose placement for the skinned prop: the same offset from the hand's rest matrix
    rest_hand = arm.matrix_world @ arm.data.bones["hand_r"].matrix_local
    rifle.matrix_world = rest_hand @ local
    bpy.context.view_layer.update()
    # the barrel's tip and the fore-end grip, in the hand's frame (for the muzzle bone and the left-hand target)
    # (rifle mesh axes in Blender: x along the barrel, tip at -x; y toward his right; z up)
    tip_local = Vector((-1.276, 0.0, 0.03))
    # the left wrist's target: behind and below the fore-end, so the palm (not the wrist) sits under it
    fore_local = Vector((-0.62 + 0.12 / s, -0.02 / s, -0.09 / s))
    rifle_m = rifle.matrix_world.copy()
    tip_rest = rifle_m @ tip_local
    fore_rest = rifle_m @ fore_local
    bind_rigid(rifle, arm, "hand_r")
    add_bone(arm, "muzzle", "hand_r", tip_rest, tip_rest + (rifle_m.to_3x3() @ Vector((-0.1, 0, 0))))
    add_bone(arm, "weapon.R", "hand_r", rest_hand.translation, rest_hand.translation + Vector((0, 0, 0.1)))
    add_bone(arm, "weapon.L", "hand_l", bone_world(arm, "hand_l"), bone_world(arm, "hand_l") + Vector((0, 0, 0.1)))
    add_bone(arm, "fore_grip", "hand_r", fore_rest, fore_rest + Vector((0, 0, 0.08)))
    # a rifle-carrying run: legs and torso of the jog, arms of the gun idle
    run = make_layered(arm, lib["Jog_Fwd_Loop"], lib["Pistol_Idle_Loop"], "run_rifle")
    keep["run_rifle"] = run
    for name in BLAU_TWO_HANDED:
        keep[name] = two_hand(arm, keep[name])
    meshes = [skin] + [o for o in body if o.type == 'MESH' and o != skin] + pieces + bmeshes + [rifle]
    purge_actions(keep)
    despike(arm, keep)
    rename_prefixed(keep, "blau_")
    clip_meta(arm, keep, "blau_")
    export(arm, meshes, OUT + "/blau.glb", keep)
    return arm, meshes, keep


def make_layered(arm, legs_act, arms_act, name):
    """A new clip: every bone from `legs_act`, the arm bones (both sides) from `arms_act` (looped to fit)."""
    import copy
    f0, f1 = frame_range(legs_act)
    a0, a1 = frame_range(arms_act)
    arm_bones = set(b + s for b in ARM_BONES for s in ["_l", "_r"])
    # sample both into a dict of pose matrices (local), then key a new action
    poses = []
    for f in range(f0, f1 + 1):
        pose_at(arm, legs_act, f)
        legs = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in arm.pose.bones}
        fa = a0 + (f - f0) % max(1, a1 - a0)
        pose_at(arm, arms_act, fa)
        for pb in arm.pose.bones:
            if pb.name in arm_bones:
                legs[pb.name] = (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy())
        poses.append(legs)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    assign(arm, act)
    for i, p in enumerate(poses):
        for pb in arm.pose.bones:
            if pb.name not in p:
                continue
            loc, rot, sc = p[pb.name]
            pb.rotation_mode = 'QUATERNION'
            pb.location = loc
            pb.rotation_quaternion = rot
            pb.scale = sc
            pb.keyframe_insert("location", frame=f0 + i)
            pb.keyframe_insert("rotation_quaternion", frame=f0 + i)
            pb.keyframe_insert("scale", frame=f0 + i)
    return act


FINGER_CURL = {"index": (60, 70, 40), "middle": (62, 72, 40), "ring": (64, 72, 40), "pinky": (66, 70, 40),
               "thumb": (20, 30, 25)}
CURL_SIGN = float(_arg("curl_sign", "-1"))


def curl(arm, f0, f1, side="l"):
    """Bend the fingers of one hand into a grip on every frame (keys the joints)."""
    P = arm.pose.bones
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        hand = P["hand_" + side]
        mw = arm.matrix_world
        idx = mw @ P["index_01_" + side].head
        pnk = mw @ P["pinky_01_" + side].head
        mid = mw @ P["middle_01_" + side].head
        wrist = mw @ hand.head
        n = (idx - pnk).cross(mid - wrist).normalized() * CURL_SIGN
        if side == "l":
            n = -n
        # turn the hand about the forearm so the palm faces up into the rifle's fore-end
        fore = (wrist - (mw @ P["lowerarm_" + side].head)).normalized()
        want = Vector((0, 0, 1))
        a_cur = (n - fore * n.dot(fore)).normalized()
        a_want = (want - fore * want.dot(fore)).normalized()
        ang = math.atan2(a_cur.cross(a_want).dot(fore), a_cur.dot(a_want))
        ang = max(-2.6, min(2.6, ang))
        R = Matrix.Rotation(ang, 4, fore)
        m = mw @ hand.matrix
        t = m.translation.copy()
        hand.matrix = mw.inverted() @ (Matrix.Translation(t) @ R @ Matrix.Translation(-t) @ m)
        bpy.context.view_layer.update()
        hand.rotation_mode = 'QUATERNION'
        hand.keyframe_insert("rotation_quaternion", frame=f)
        n = (R.to_3x3() @ n).normalized()
        for finger, angles in FINGER_CURL.items():
            for j, ang in enumerate(angles):
                pb = P["%s_%02d_%s" % (finger, j + 1, side)]
                d = ((mw @ pb.tail) - (mw @ pb.head)).normalized()
                axis = d.cross(n).normalized()
                if axis.length < 0.5:
                    continue
                R = Matrix.Rotation(math.radians(ang), 4, axis)
                m = mw @ pb.matrix
                t = m.translation.copy()
                m = Matrix.Translation(t) @ R @ Matrix.Translation(-t) @ m
                pb.matrix = mw.inverted() @ m
                bpy.context.view_layer.update()
                pb.rotation_mode = 'QUATERNION'
                pb.keyframe_insert("rotation_quaternion", frame=f)


def two_hand(arm, act):
    """Re-solve the left arm so the hand holds the rifle's fore-end (IK, two bones, baked to keys)."""
    f0, f1 = frame_range(act)
    assign(arm, act)
    set_active(arm)
    bpy.ops.object.mode_set(mode='POSE')
    lower = arm.pose.bones["lowerarm_l"]
    ik = lower.constraints.new('IK')
    ik.target = arm
    ik.subtarget = "fore_grip"
    ik.chain_count = 2
    ik.use_tail = True
    # pole: the elbow points down and out to the left, as when holding a rifle
    pole_name = "elbow_pole_l"
    bpy.ops.object.mode_set(mode='OBJECT')
    if pole_name not in arm.data.bones:
        sp = bone_world(arm, "spine_03")
        p = sp + Vector((0.55, 0.15, -0.45))
        add_bone(arm, pole_name, "spine_03", p, p + Vector((0, 0, 0.05)))
    set_active(arm)
    bpy.ops.object.mode_set(mode='POSE')
    ik.pole_target = arm
    ik.pole_subtarget = pole_name
    ik.pole_angle = math.radians(-90)
    # hand: keep it turned to the grip (copy the right hand's roll so the palm faces up under the stock)
    for pb in arm.pose.bones:
        sel = pb.name in ("upperarm_l", "lowerarm_l", "hand_l")
        if hasattr(pb, "select"):
            pb.select = sel
        else:
            pb.bone.select = sel
    bpy.ops.nla.bake(frame_start=f0, frame_end=f1, step=1, only_selected=True, visual_keying=True,
                     clear_constraints=False, use_current_action=True, bake_types={'POSE'})
    lower.constraints.remove(ik)
    # the left fingers close round the fore-end: each joint bends toward the palm
    curl(arm, f0, f1)
    bpy.ops.object.mode_set(mode='OBJECT')
    return act


# ---- Roydo and the Anomaly --------------------------------------------------------------------------------------------

def alien_head(skin, arm):
    """A longer skull swept back and up, a ridge over the brow, narrow chin, no ears to speak of."""
    head = arm.data.bones["Head"]
    hm = arm.matrix_world @ head.matrix_local
    origin = hm.translation
    up = (hm.to_3x3() @ Vector((0, 1, 0))).normalized()             # bone axis: up the head
    back = Vector((0, 1, 0))                                         # Blender +Y is behind the character
    gi = skin.vertex_groups["Head"].index if "Head" in skin.vertex_groups else -1
    for v in skin.data.vertices:
        w = 0.0
        for g in v.groups:
            if g.group == gi:
                w = g.weight
        if w <= 0.0:
            continue
        co = skin.matrix_world @ v.co
        rel = co - origin
        h = rel.dot(up)                                              # height above the head bone's root
        if h > 0.09:
            # cranium: grows up and back, more the higher it is
            t = min(1.0, (h - 0.09) / 0.14)
            co = co + up * (0.05 * t * t) * w + back * (0.07 * t * t) * w
            # a little narrower at the temples
            co.x = origin.x + (co.x - origin.x) * (1.0 - 0.08 * t * w)
        if -0.02 < h < 0.08 and abs(co.x - origin.x) > 0.062:
            # ears: pulled flat against the skull (a smooth, earless alien profile)
            k = (abs(co.x - origin.x) - 0.062) * w
            co.x -= math.copysign(k * 0.85, co.x - origin.x)
        if h < 0.02:
            # jaw and chin: narrower and longer
            t = min(1.0, (0.02 - h) / 0.1)
            co.x = origin.x + (co.x - origin.x) * (1.0 - 0.18 * t * w)
            co = co - up * 0.012 * t * w
        v.co = skin.matrix_world.inverted() @ co


def bulk(skin, arm, factors):
    """Thicken the body around its bones: each vertex moves away from the axis of the bones it is weighted to by
    (factor - 1) of its distance, blended by the weights (the rig stays valid, no bone moves)."""
    axes = {}
    for b in arm.data.bones:
        h = arm.matrix_world @ b.head_local
        t = arm.matrix_world @ b.tail_local
        axes[b.name] = (h, t)
    names = {g.index: g.name for g in skin.vertex_groups}
    for v in skin.data.vertices:
        co = skin.matrix_world @ v.co
        disp = Vector((0, 0, 0))
        for g in v.groups:
            n = names.get(g.group)
            f = factors.get(n)
            if f is None or n not in axes:
                continue
            h, t = axes[n]
            seg = t - h
            L2 = max(seg.length_squared, 1e-8)
            k = max(0.0, min(1.0, (co - h).dot(seg) / L2))
            p = h + seg * k
            disp += (co - p) * (f - 1.0) * g.weight
        v.co = skin.matrix_world.inverted() @ (co + disp)


def crystal(at, direction, length, radius, sides=5):
    """A faceted crystal spike (a pointed prism) from `at` along `direction`."""
    bm = bmesh.new()
    d = direction.normalized()
    side = d.orthogonal().normalized()
    other = d.cross(side)
    ring0 = []
    ring1 = []
    for i in range(sides):
        a = 2 * math.pi * i / sides
        o = side * math.cos(a) + other * math.sin(a)
        ring0.append(bm.verts.new(at + o * radius))
        ring1.append(bm.verts.new(at + o * radius * 0.82 + d * length * 0.55))
    tip = bm.verts.new(at + d * length)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new([ring0[i], ring0[j], ring1[j], ring1[i]])
        bm.faces.new([ring1[i], ring1[j], tip])
    bm.faces.new(list(reversed(ring0)))
    me = bpy.data.meshes.new("crystal")
    bm.to_mesh(me)
    bm.free()
    return me


def add_crystals(arm, spots, mat):
    """Join crystals into one mesh, each crystal skinned rigidly to its bone."""
    bm_all = bmesh.new()
    obj_me = bpy.data.meshes.new("AnomalyCrystals")
    groups = []
    for (bone, offset, direction, length, radius) in spots:
        b = arm.data.bones[bone]
        m = arm.matrix_world @ b.matrix_local
        at = m @ Vector(offset)
        dirw = (m.to_3x3() @ Vector(direction)).normalized()
        me = crystal(at, dirw, length, radius)
        n0 = len(bm_all.verts)
        bm_all.from_mesh(me)
        bpy.data.meshes.remove(me)
        groups.append((bone, list(range(n0, len(bm_all.verts)))))
    bm_all.to_mesh(obj_me)
    bm_all.free()
    obj = bpy.data.objects.new("AnomalyCrystals", obj_me)
    bpy.context.scene.collection.objects.link(obj)
    for bone, idx in groups:
        vg = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
        vg.add(idx, 1.0, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    obj.parent = arm
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = False
    return obj


def roydo_body(lib, monster):
    body = import_gltf(UBC + "/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf")
    arm = armature_of(body)
    skin = next(o for o in body if o.type == 'MESH' and o.name.startswith("SuperHero"))
    brows = next((o for o in body if o.type == 'MESH' and o.name.startswith("Eyebrows")), None)
    eyes = next((o for o in body if o.type == 'MESH' and o.name.startswith("Eyes")), None)
    if brows:
        bpy.data.objects.remove(brows, do_unlink=True)
    alien_head(skin, arm)
    skin_name = "AnomalySkin" if monster else "RoydoSkin"
    set_material(skin, material(skin_name, color=(0.08, 0.05, 0.18, 1.0), rough=0.35, emit=(0.25, 0.15, 0.6, 1.0),
                                emit_strength=0.4))
    if eyes:
        set_material(eyes, material("RoydoEyes", color=(0.7, 0.95, 1.0, 1.0), emit=(0.55, 0.9, 1.0, 1.0),
                                    emit_strength=6.0))
    # armour: the ranger's bracers, belts and boots in obsidian and silver
    outfit = import_gltf(OUTFITS + "/Exports/glTF (Godot-Unreal)/Outfits/Male_Ranger.gltf")
    oarm = armature_of(outfit)
    keep_parts = ("Arms_Bracer", "Belt_1", "Feet_Boots", "Acc_Pauldron")
    tex = armor_texture(OUTFITS + "/Textures/Ranger/T_Ranger_BaseColor.png", TEX + "/roydo_armor.png")
    amat = material("RoydoArmor", base=tex, rough=0.28, metal=0.65,
                    normal=OUTFITS + "/Textures/Ranger/T_Ranger_Normal.png", emit=(0.35, 0.2, 0.9, 1.0),
                    emit_strength=0.15)
    parts = []
    for p in meshes_of(outfit):
        if any(k in p.name for k in keep_parts):
            rebind(p, arm)
            for i in range(len(p.material_slots)):
                p.material_slots[i].material = amat
            parts.append(p)
        else:
            bpy.data.objects.remove(p, do_unlink=True)
    bpy.data.objects.remove(oarm, do_unlink=True)
    extra = []
    if monster:
        f = {"upperarm_l": 1.55, "upperarm_r": 1.55, "lowerarm_l": 1.6, "lowerarm_r": 1.6, "hand_l": 1.35,
             "hand_r": 1.35, "clavicle_l": 1.35, "clavicle_r": 1.35, "spine_03": 1.28, "spine_02": 1.18,
             "neck_01": 1.45, "thigh_l": 1.22, "thigh_r": 1.22, "calf_l": 1.25, "calf_r": 1.25, "pelvis": 1.1}
        for o in [skin] + parts:
            bulk(o, arm, f)
        cmat = material("AnomalyCrystal", color=(0.32, 0.12, 0.55, 1.0), rough=0.12, metal=0.35,
                        emit=(0.85, 0.25, 1.0, 1.0), emit_strength=1.1)
        Y = (0, 1, 0)
        spots = []
        # along the spine, pointing back and up
        for i, (bn, z) in enumerate([("spine_01", 0.05), ("spine_02", 0.05), ("spine_03", 0.04), ("spine_03", 0.16),
                                     ("neck_01", 0.03)]):
            spots.append((bn, (0.0, z, 0.11), (0.0, 0.45, 1.0), 0.16 + 0.05 * (i % 2), 0.035))
        for s in ("l", "r"):
            sx = 1.0 if s == "l" else -1.0
            # shoulders: a cluster of three
            spots.append(("clavicle_" + s, (0.0, 0.14, 0.04), (0.2 * sx, 0.6, 1.0), 0.26, 0.05))
            spots.append(("clavicle_" + s, (0.0, 0.10, -0.03), (0.6 * sx, 0.3, 1.0), 0.18, 0.04))
            spots.append(("upperarm_" + s, (0.0, 0.05, 0.05), (0.1 * sx, -0.2, 1.0), 0.15, 0.035))
            # forearms: ridge of spikes
            for k in range(3):
                spots.append(("lowerarm_" + s, (0.0, 0.06 + 0.07 * k, 0.05), (0.0, 0.4, 1.0), 0.12 + 0.03 * k, 0.03))
            # knees
            spots.append(("calf_" + s, (0.0, 0.03, -0.06), (0.0, -0.3, -1.0), 0.1, 0.03))
        # horns sweeping back from the skull
        spots.append(("Head", (0.05, 0.16, 0.02), (0.4, 0.7, 0.9), 0.2, 0.03))
        spots.append(("Head", (-0.05, 0.16, 0.02), (-0.4, 0.7, 0.9), 0.2, 0.03))
        extra.append(add_crystals(arm, spots, cmat))
    keep = keep_clips(arm, lib, ANOMALY_CLIPS if monster else ROYDO_CLIPS)
    meshes = [skin] + ([eyes] if eyes else []) + parts + extra
    add_bone(arm, "weapon.R", "hand_r", bone_world(arm, "hand_r"), bone_world(arm, "hand_r") + Vector((0, 0, 0.1)))
    add_bone(arm, "weapon.L", "hand_l", bone_world(arm, "hand_l"), bone_world(arm, "hand_l") + Vector((0, 0, 0.1)))
    purge_actions(keep)
    despike(arm, keep)
    pre = "anomaly_" if monster else "roydo_"
    rename_prefixed(keep, pre)
    clip_meta(arm, keep, pre)
    export(arm, meshes, OUT + ("/anomaly.glb" if monster else "/roydo.glb"), keep)
    return arm, meshes, keep


# ---- Turret -------------------------------------------------------------------------------------------------------------

def build_turret():
    objs = import_gltf(SCIFI + "/Enemy_QuadShell.gltf")
    arm = armature_of(objs)
    names = {"Idle": "idle", "Attack": "attack", "Hit": "hit", "TurnOff": "death", "Charge": "charge", "Look": "look",
             "Walk": "walk"}
    keep = {}
    for a in list(bpy.data.actions):
        n = a.name.split("|")[-1].split(".")[0]
        if n in names and names[n] not in keep:
            keep[names[n]] = a
    rename_prefixed(keep, "turret_")
    for m in meshes_of(objs):
        for slot in m.material_slots:
            if slot.material:
                slot.material.name = "TurretShell"
    purge_actions(keep)
    clip_meta(arm, keep, "turret_")
    export(arm, meshes_of(objs), OUT + "/blau_turret.glb", keep)
    return arm, meshes_of(objs), keep


# ---- Preview ------------------------------------------------------------------------------------------------------------

def preview(arm, meshes, keep, tag):
    """Frame sheets: each clip at a few points, from the front-left and the side."""
    os.makedirs(PREVIEW, exist_ok=True)
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_EEVEE'
    scn.render.resolution_x = 360
    scn.render.resolution_y = 420
    if scn.world is None:
        scn.world = bpy.data.worlds.new("w")
    scn.world.use_nodes = True
    scn.world.node_tree.nodes['Background'].inputs[0].default_value = (0.25, 0.26, 0.3, 1)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scn.collection.objects.link(cam)
    cam.data.lens = 55
    scn.camera = cam
    for k, (loc, e) in enumerate([((3, -4, 5), 1200), ((-4, 3, 3), 600)]):
        L = bpy.data.objects.new("l%d" % k, bpy.data.lights.new("l%d" % k, 'AREA'))
        L.data.energy = e
        L.data.size = 4
        L.location = Vector(loc)
        L.rotation_euler = (Vector((0, 0, 1)) - L.location).to_track_quat('-Z', 'Y').to_euler()
        scn.collection.objects.link(L)
    clips = PREVIEW_CLIPS or list(keep.keys())
    for c in clips:
        if c not in keep:
            continue
        a = keep[c]
        f0, f1 = frame_range(a)
        for fi, frac in enumerate(PREVIEW_FRAMES):
            pose_at(arm, a, int(f0 + (f1 - f0) * frac))
            for yaw in (25, 100):
                ang = math.radians(yaw)
                cam.location = Vector((math.sin(ang) * -4.2, -math.cos(ang) * 4.2, 1.5))
                cam.rotation_euler = (Vector((0, 0, 1.0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
                scn.render.filepath = "%s/%s_%s_%d_%d.png" % (PREVIEW, tag, c, fi, yaw)
                bpy.ops.render.render(write_still=True)


def main():
    for what in ONLY:
        reset()
        lib = library_actions() if what != "turret" else {}
        if what == "blau":
            res = build_blau(lib)
        elif what == "roydo":
            res = roydo_body(lib, False)
        elif what == "anomaly":
            res = roydo_body(lib, True)
        elif what == "turret":
            res = build_turret()
        else:
            continue
        if PREVIEW:
            preview(*res, what)


main()

"""Build Azrin's body: assets/characters/hero/azrin_body.glb.

The owner's female_generic model (A:/Python/beyond-heroes/models/female_generic.obj: a 2-million-face scan-like mesh,
colour per vertex, T-pose, facing -Y) made into a game body on the hero skeleton:
  1. scaled to the hero's height, decimated to a game budget and unwrapped;
  2. her vertex colours baked from the full mesh into a 2048 texture (keeps the face sharp);
  3. fitted to the hero skeleton: a copy of the hero rig is moved onto her own joints (found from the mesh), she is
     skinned to it, then that rig is posed onto the hero rig's rest, so her limbs line up with the hero bones;
  4. bound to the hero armature (same 24 bones) and exported without animations. The game puts this mesh on the
     hero model's skeleton in place of its body, so every hero animation, hair style, outfit piece and dye works on
     her as on Blood Ranger.

Run: "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/azrin_body.py
     [-- --faces=30000 --tex=2048 --preview=dir]
"""
import bpy
import bmesh
import math
import os
import sys
import time
import numpy as np
from mathutils import Vector, Matrix

ROOT = "A:/Python/woa"
HERO = ROOT + "/assets/characters/hero/hero.glb"
SRC = "A:/Python/beyond-heroes/models/female_generic.obj"
OUT = ROOT + "/assets/characters/hero/azrin_body.glb"
TEX = ROOT + "/assets/characters/hero/azrin_body.png"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(name, default):
    for a in ARGS:
        if a.startswith("--%s=" % name):
            return type(default)(a.split("=", 1)[1])
    return default
FACES = arg("faces", 30000)
HEAD_FROM = 0.82                               # faces above this fraction of her height count as head and neck
HEAD_DENSITY = 2.5
TEXSIZE = arg("tex", 2048)
PREVIEW = arg("preview", "")
T0 = time.time()

def log(*a):
    print("[azrin_body %5.1fs]" % (time.time() - T0), *a, flush=True)

def select_only(*objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]

def coords(o):
    co = np.empty(len(o.data.vertices) * 3, dtype=np.float64)
    o.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    m = np.array(o.matrix_world)
    return (np.c_[co, np.ones(len(co))] @ m.T)[:, :3]

# ---- 1. hero rig and the female hero body (the height and proportions she is fitted to) -----------------------------

def load_hero():
    bpy.ops.import_scene.gltf(filepath=HERO)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    body = bpy.data.objects["hero"]
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o != body:
            bpy.data.objects.remove(o)
    if arm.animation_data:
        arm.animation_data.action = None
    arm.data.pose_position = 'REST'
    body.data.shape_keys.key_blocks["female"].value = 1.0
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    e = body.evaluated_get(dg)
    hco = np.array([e.matrix_world @ v.co for v in e.data.vertices])
    log("hero female height %.3f span %.3f" % (hco[:, 2].max(), hco[:, 0].max() - hco[:, 0].min()))
    return arm, body, hco

# ---- 2. her mesh: import, scale, decimate, unwrap, bake ---------------------------------------------------------------

def load_her(height):
    bpy.ops.wm.obj_import(filepath=SRC)
    hi = bpy.context.selected_objects[0]
    hi.name = "AzrinHigh"
    select_only(hi)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    co = coords(hi)
    s = height / (co[:, 2].max() - co[:, 2].min())
    hi.scale = (s, s, s)
    hi.location = (-(co[:, 0].max() + co[:, 0].min()) * 0.5 * s, -(co[:, 1].max() + co[:, 1].min()) * 0.5 * s, -co[:, 2].min() * s)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    log("her mesh: %d verts, %d faces, scaled x%.3f to %.3f m" % (len(hi.data.vertices), len(hi.data.polygons), s, height))
    return hi

def make_low(hi):
    lo = hi.copy()
    lo.data = hi.data.copy()
    lo.name = "AzrinBody"
    bpy.context.collection.objects.link(lo)
    select_only(lo)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0002)
    bpy.ops.object.mode_set(mode='OBJECT')
    d = lo.modifiers.new("dec", 'DECIMATE')
    d.decimate_type = 'COLLAPSE'
    d.ratio = min(1.0, FACES / max(1, len(lo.data.polygons)))
    d.use_symmetry = True
    d.symmetry_axis = 'X'
    bpy.ops.object.modifier_apply(modifier="dec")
    # tidy: smooth shading, no loose bits
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.delete_loose()
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=0.004, area_weight=0.0, scale_to_bounds=True)
    # the head and neck get HEAD_DENSITY times the texture space of the rest (the face is what players look at)
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.average_islands_scale()
    from bpy_extras import bmesh_utils
    bm = bmesh.from_edit_mesh(lo.data)
    uv = bm.loops.layers.uv.active
    head_z = HEAD_FROM * lo.dimensions.z
    grown = 0
    for island in bmesh_utils.bmesh_linked_uv_islands(bm, uv):
        zc = sum(f.calc_center_median().z for f in island) / len(island)
        if zc <= head_z:
            continue
        loops = [l for f in island for l in f.loops]
        c = sum((l[uv].uv for l in loops), Vector((0.0, 0.0))) / len(loops)
        for l in loops:
            l[uv].uv = c + (l[uv].uv - c) * HEAD_DENSITY
        grown += 1
    bmesh.update_edit_mesh(lo.data)
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.pack_islands(rotate=True, margin=0.003, scale=True)
    log("uv: %d head islands given %.1fx the texture space" % (grown, HEAD_DENSITY))
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.shade_smooth()
    for a in list(lo.data.color_attributes):
        lo.data.color_attributes.remove(a)
    log("low mesh: %d verts, %d faces" % (len(lo.data.vertices), len(lo.data.polygons)))
    return lo

def bake(hi, lo):
    img = bpy.data.images.new("AzrinBodyTex", TEXSIZE, TEXSIZE, alpha=False)
    img.colorspace_settings.name = 'sRGB'
    # the full mesh shows its vertex colours as emission; the game mesh gets them baked into its texture
    hm = bpy.data.materials.new("AzrinHighMat")
    hm.use_nodes = True
    nt = hm.node_tree
    nt.nodes.clear()
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = hi.data.color_attributes[0].name
    em = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(attr.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    hi.data.materials.clear()
    hi.data.materials.append(hm)
    lm = bpy.data.materials.new("AzrinSkin")
    lm.use_nodes = True
    tex = lm.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    bsdf = lm.node_tree.nodes["Principled BSDF"]
    lm.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    lm.node_tree.nodes.active = tex
    lo.data.materials.clear()
    lo.data.materials.append(lm)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 1
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.02
    sc.render.bake.max_ray_distance = 0.06
    sc.render.bake.margin = 6
    select_only(lo, hi)
    hi.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type='EMIT')
    img.filepath_raw = TEX
    img.file_format = 'PNG'
    img.save()
    log("baked %dx%d -> %s" % (TEXSIZE, TEXSIZE, TEX))
    return lm

# ---- 3. her joints, found from the mesh ------------------------------------------------------------------------------

def her_joints(lo, hero_arm, hco):
    """Hero bone name -> (head, tail) on her body. Limb joints sit on her limbs' centre lines at the hero's height
    ratios; trunk bones sit as far in front of or behind her body's centre as the hero's sit from the hero body's
    centre, so her head ends up where hair and helmets expect a head."""
    co = coords(lo)
    H = co[:, 2].max()
    hb = {b.name: (Vector(b.head_local), Vector(b.tail_local)) for b in hero_arm.data.bones}
    HH = 1.8                                     # the hero rig's height (head top)
    J = {}
    def slice_c(z, side=0, dz=0.012, xmin=None, xmax=None):
        m = np.abs(co[:, 2] - z) < dz
        if side:
            m &= (co[:, 0] * side) > 0.005
        if xmin is not None:
            m &= np.abs(co[:, 0]) >= xmin
        if xmax is not None:
            m &= np.abs(co[:, 0]) <= xmax
        p = co[m]
        if len(p) == 0:
            return None
        return Vector(((p[:, 0].max() + p[:, 0].min()) * 0.5, (p[:, 1].max() + p[:, 1].min()) * 0.5, z))
    k = H / HH
    def hero_c(z):
        m = (np.abs(hco[:, 2] - z) < 0.012) & (np.abs(hco[:, 0]) <= 0.16)
        p = hco[m]
        return (p[:, 1].max() + p[:, 1].min()) * 0.5 if len(p) else 0.0
    # trunk: the hero's heights scaled to hers; front to back, the hero's offset from its body's centre
    for name in ("hips", "spine", "chest", "neck", "head"):
        h, t = hb[name]
        ch = slice_c(h.z * k, xmax=0.16) or Vector((0, 0, h.z * k))
        zt = min(t.z * k, H - 0.03)
        ct = slice_c(zt, xmax=0.16) or Vector((0, 0, t.z * k))
        oh = h.y - hero_c(min(h.z, HH - 0.03))
        ot = t.y - hero_c(min(t.z, HH - 0.03))
        J[name] = (Vector((0.0, ch.y + oh, h.z * k)), Vector((0.0, ct.y + ot, t.z * k)))
    log("head bone: %s -> %s (hero head centre offset %.3f)" % (tuple(round(x, 3) for x in J["head"][0]),
        tuple(round(x, 3) for x in J["head"][1]), hb["head"][0].y - hero_c(hb["head"][0].z)))
    J["root"] = (Vector((0, 0, 0)), Vector((0, 0, hb["root"][1].z * k)))
    # arms: her arm's centre line per side (points beyond the shoulders), the hero's joints placed along it by the
    # ratio of her reach to the hero's
    for side, s in (("L", 1.0), ("R", -1.0)):
        a = co[(co[:, 0] * s > 0.24 * k * 1.0) & (co[:, 2] > 0.7 * H)]
        xs = np.abs(a[:, 0])
        tip = xs.max()
        reach = tip / 0.844                     # hero fingertip x at rest
        # centre line by bins
        bins = np.linspace(0.22 * k, tip - 0.01, 14)
        cz, cy, cx = [], [], []
        for i in range(len(bins) - 1):
            mm = (xs >= bins[i]) & (xs < bins[i + 1])
            if mm.sum() < 5:
                continue
            cx.append((bins[i] + bins[i + 1]) * 0.5)
            cz.append((a[mm, 2].max() + a[mm, 2].min()) * 0.5)
            cy.append((a[mm, 1].max() + a[mm, 1].min()) * 0.5)
        fz = np.polyfit(cx, cz, 1)
        fy = np.polyfit(cx, cy, 1)
        def on_arm(x):
            return Vector((s * x, float(np.polyval(fy, x)), float(np.polyval(fz, x))))
        for name in ("upper_arm", "forearm", "hand"):
            h, t = hb["%s.%s" % (name, side)]
            J["%s.%s" % (name, side)] = (on_arm(abs(h.x) * reach), on_arm(abs(t.x) * reach))
        sh, st = hb["shoulder." + side]
        J["shoulder." + side] = (Vector((s * abs(sh.x) * reach, 0.0, J["upper_arm." + side][0].z)), J["upper_arm." + side][0].copy())
        wh, wt = hb["weapon." + side]
        hand_end = J["hand." + side][1]
        J["weapon." + side] = (hand_end + Vector((0, 0, -0.018 * k)), hand_end + Vector((0, -0.077 * k, -0.018 * k)))
    # legs: her leg's centre at the hero's knee and ankle heights; the hip joint above the knee, in line with her thigh
    crotch = None
    for z in np.arange(0.3 * H, 0.65 * H, 0.004):
        m = (np.abs(co[:, 2] - z) < 0.003) & (np.abs(co[:, 0]) < 0.012)
        if m.sum() > 0:
            crotch = z
            break
    for side, s in (("L", 1.0), ("R", -1.0)):
        knee_z = hb["shin." + side][0].z * k
        ankle_z = hb["shin." + side][1].z * k
        hip_z = hb["thigh." + side][0].z * k
        kc = slice_c(knee_z, int(s))
        ac = slice_c(ankle_z, int(s), dz=0.008)
        up = slice_c((crotch or hip_z) - 0.04, int(s))
        d = (up - kc)
        hip = kc + d * ((hip_z - kc.z) / max(1e-4, d.z))
        J["thigh." + side] = (hip, kc)
        J["shin." + side] = (kc, ac)
        fh, ft = hb["foot." + side]
        th, tt = hb["toe." + side]
        foot_m = co[(co[:, 0] * s > 0.0) & (co[:, 2] < 0.05 * H)]
        toe_y = foot_m[:, 1].min()
        J["foot." + side] = (ac.copy(), Vector((ac.x, ac.y + (toe_y - ac.y) * 0.48, ft.z * k)))
        J["toe." + side] = (J["foot." + side][1].copy(), Vector((ac.x, toe_y, tt.z * k)))
    log("crotch at %.3f, hips at %.3f" % (crotch or -1, J["thigh.L"][0].z))
    for n in ("upper_arm.L", "hand.L", "thigh.L", "shin.L", "shin.R"):
        log("  %-12s head %s tail %s" % (n, tuple(round(x, 3) for x in J[n][0]), tuple(round(x, 3) for x in J[n][1])))
    return J

# ---- 4. fit: skin her to a rig on her joints, pose that rig onto the hero's rest ------------------------------------

def fit(lo, hero_arm, J):
    fit_arm = hero_arm.copy()
    fit_arm.data = hero_arm.data.copy()
    fit_arm.name = "FitRig"
    fit_arm.data.pose_position = 'POSE'          # the hero rig shows its rest; this one must show its pose
    bpy.context.collection.objects.link(fit_arm)
    select_only(fit_arm)
    bpy.ops.object.mode_set(mode='EDIT')
    for eb in fit_arm.data.edit_bones:
        eb.use_connect = False
    for eb in fit_arm.data.edit_bones:
        if eb.name in J:
            eb.head, eb.tail = J[eb.name]
    bpy.ops.object.mode_set(mode='OBJECT')
    for b in fit_arm.data.bones:
        b.use_deform = b.name not in ("root", "weapon.L", "weapon.R")
    lo.parent = None
    select_only(lo, fit_arm)
    lo.select_set(True)
    fit_arm.select_set(True)
    bpy.context.view_layer.objects.active = fit_arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    groups = {g.name for g in lo.vertex_groups}
    weighted = np.zeros(len(lo.data.vertices), dtype=bool)
    for v in lo.data.vertices:
        if len(v.groups) > 0 and max(g.weight for g in v.groups) > 0.0:
            weighted[v.index] = True
    log("automatic weights: %d groups, %d of %d vertices weighted" % (len(groups), int(weighted.sum()), len(weighted)))
    if weighted.mean() < 0.97:
        raise RuntimeError("bone heat weighting left %.1f%% of vertices unweighted" % (100.0 * (1.0 - weighted.mean())))
    # pose the fit rig onto the hero rig's rest and keep the deformed shape
    hero_rest = {b.name: b.matrix_local.copy() for b in hero_arm.data.bones}
    select_only(fit_arm)
    bpy.ops.object.mode_set(mode='POSE')
    for pb in fit_arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    def depth(b):
        n = 0
        while b.parent:
            b = b.parent
            n += 1
        return n
    for pb in sorted(fit_arm.pose.bones, key=lambda p: depth(p.bone)):
        pb.matrix = hero_rest[pb.name]
        bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode='OBJECT')
    for n in ("head", "neck", "upper_arm.L"):
        pb = fit_arm.pose.bones[n]
        log("  posed %-11s head %s (hero %s)" % (n, tuple(round(x, 3) for x in (fit_arm.matrix_world @ pb.head)),
            tuple(round(x, 3) for x in hero_rest[n].translation)))
    select_only(lo)
    mod = next(m for m in lo.modifiers if m.type == 'ARMATURE')
    bpy.ops.object.modifier_apply(modifier=mod.name)
    lo.parent = None
    bpy.data.objects.remove(fit_arm)
    # the rest pose for the game's clothing cut-outs (as on the hero body): UV2 = (x, 1 - z) in metres
    rest = lo.data.uv_layers.new(name="Rest")
    for loop in lo.data.loops:
        p = lo.data.vertices[loop.vertex_index].co
        rest.data[loop.index].uv = (p.x, 1.0 - p.z)
    lo.data.uv_layers.active_index = 0
    # bind to the real hero rig with the same weights
    lo.matrix_world = Matrix.Identity(4)
    lo.parent = hero_arm
    am = lo.modifiers.new("Armature", 'ARMATURE')
    am.object = hero_arm
    log("fitted onto the hero skeleton")

def preview(lo, hero_arm, folder):
    os.makedirs(folder, exist_ok=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
    sc.render.resolution_x = 900
    sc.render.resolution_y = 1100
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    sc.world = bpy.data.worlds.new("W")
    sc.world.color = (0.25, 0.25, 0.28)
    for name, loc in (("front", (0, -3.4, 1.0)), ("side", (3.4, 0, 1.0)), ("face", (0, -0.75, 1.62))):
        cam.location = loc
        d = Vector((0, 0, loc[2] if name != "face" else 1.62)) - Vector(loc)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        cam.data.lens = 50 if name != "face" else 70
        sc.render.filepath = os.path.join(folder, "azrin_body_%s.png" % name)
        bpy.ops.render.render(write_still=True)
    log("previews in", folder)

def export(hero_arm, lo):
    select_only(hero_arm, lo)
    hero_arm.select_set(True)
    lo.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format='GLB', export_animations=False,
        export_skins=True, export_morph=False, export_texcoords=True, export_normals=True, export_materials='EXPORT',
        export_image_format='AUTO', export_yup=True)
    log("exported", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global HCO
    hero_arm, hero_body, hco = load_hero()
    HCO = hco
    height = float(hco[:, 2].max())
    bpy.data.objects.remove(hero_body)
    hi = load_her(height)
    lo = make_low(hi)
    bake(hi, lo)
    bpy.data.objects.remove(hi)
    J = her_joints(lo, hero_arm, HCO)
    fit(lo, hero_arm, J)
    if PREVIEW:
        preview(lo, hero_arm, PREVIEW)
    export(hero_arm, lo)

main()

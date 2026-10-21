"""Paint an untextured rigged sculpt (run 2026-10-21 b: Lord Kaileh, Dracoxinia) so hero_body.py --bake can bake it.

The owner's Tripo models came as FBX with a Mixamo rig and no UVs or textures. This tool works on the rest pose:
  1. per-vertex features: relief (how far a vertex stands out of a smoothed copy, along its normal, at two scales),
     convexity (edges), bumpiness (normal noise: fur, torn cloth), nearest source bone and the radius from it, height;
  2. a per-hero rule set (paint_rules_<name>.py next to the output, or --rules=<py>) turns them into material weights
     stored as colour attributes "m0" (RGBA) and "m1" (RGBA): one channel per material;
  3. an ambient-occlusion bake into the colour attribute "ao" (Cycles, on the dense mesh);
  4. a material whose Base Color, Roughness and Metallic mix procedural materials (brushed steel, gold, leather,
     cloth, skin, fur, scales...) by those weights, darkened by "ao" and lit on convex edges (wear). hero_body's bake
     turns that into textures on the game mesh.
Writes <out>.blend (the source for hero_body.py --src) and <out>_feat.npz; --look renders the weights.

Run: blender -b --factory-startup --python tools/blender/paint_prep.py -- --src=<fbx> --out=<dir>/<name>_painted
       --rules=<rules.py> [--subdiv=1] [--ao=1] [--look=<png prefix>]
"""
import bpy
import bmesh
import math
import os
import runpy
import sys
import time
import numpy as np
from mathutils import Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    for a in ARGV:
        if a == "--" + name:
            return True
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    return default


SRC = arg("src")
OUT = arg("out")
RULES = arg("rules")
SUBDIV = int(arg("subdiv", 1))
AO = int(arg("ao", 1))
LOOK = arg("look", "")
LOW = int(arg("low", 0))                       # >0: bake onto a rigged low mesh of this many triangles (UVs, textures)
TEX = int(arg("tex", 2048))
T0 = time.time()


def log(*a):
    print("[paint_prep %5.1fs]" % (time.time() - T0), *a, flush=True)


def neighbours(me):
    n = len(me.vertices)
    e = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", e)
    e = e.reshape(-1, 2)
    return n, e


def smooth(co, e, n, iters, lam=0.6):
    """Laplacian-smoothed copy of the vertex positions (umbrella operator)."""
    deg = np.bincount(e.ravel(), minlength=n).astype(float)
    deg[deg == 0] = 1
    p = co.copy()
    for _ in range(iters):
        s = np.zeros_like(p)
        np.add.at(s, e[:, 0], p[e[:, 1]])
        np.add.at(s, e[:, 1], p[e[:, 0]])
        p = p + lam * (s / deg[:, None] - p)
    return p


def vertex_normals(me):
    nr = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("normal", nr)
    return nr.reshape(-1, 3)


def spread(val, e, n, iters):
    deg = np.bincount(e.ravel(), minlength=n).astype(float)
    deg[deg == 0] = 1
    v = val.copy()
    for _ in range(iters):
        s = np.zeros_like(v)
        np.add.at(s, e[:, 0], v[e[:, 1]])
        np.add.at(s, e[:, 1], v[e[:, 0]])
        v = 0.5 * v + 0.5 * s / (deg[:, None] if v.ndim > 1 else deg)
    return v


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
    q = a + t[:, None] * ab
    return np.linalg.norm(p - q, axis=1), t


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=SRC, automatic_bone_orientation=True)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    body = next(o for o in bpy.data.objects if o.type == 'MESH')
    arm.data.pose_position = 'REST'
    if arm.animation_data:
        arm.animation_data.action = None
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    bpy.context.view_layer.update()
    if SUBDIV:
        bpy.context.view_layer.objects.active = body
        m = body.modifiers.new("sub", 'SUBSURF')
        m.subdivision_type = 'SIMPLE'
        m.levels = SUBDIV
        m.render_levels = SUBDIV
        # the subdivision must sit before the armature modifier to be applied on the bind mesh
        while body.modifiers[0].name != "sub":
            bpy.ops.object.modifier_move_up(modifier="sub")
        bpy.ops.object.modifier_apply(modifier="sub")
    me = body.data
    log("mesh %d vertices, %d faces" % (len(me.vertices), len(me.polygons)))
    n, e = neighbours(me)
    mw = np.array(body.matrix_world)
    co_l = np.empty(n * 3)
    me.vertices.foreach_get("co", co_l)
    co_l = co_l.reshape(-1, 3)
    co = (np.c_[co_l, np.ones(n)] @ mw.T)[:, :3]
    nr = vertex_normals(me) @ np.array(body.matrix_world.to_3x3().inverted().transposed())
    nr /= np.linalg.norm(nr, axis=1, keepdims=True) + 1e-12
    H = co[:, 2].max() - co[:, 2].min()
    z0 = co[:, 2].min()
    # relief at two scales (fraction of height), positive = stands out
    s1 = smooth(co, e, n, 6 * (1 + SUBDIV))
    s2 = smooth(co, e, n, 40 * (1 + SUBDIV))
    r1 = np.einsum("ij,ij->i", co - s1, nr) / H
    r2 = np.einsum("ij,ij->i", co - s2, nr) / H
    # convexity: mean of neighbour normal changes signed by direction (edges positive, creases negative)
    d = co[e[:, 1]] - co[e[:, 0]]
    dn = nr[e[:, 1]] - nr[e[:, 0]]
    conv_e = np.einsum("ij,ij->i", d, dn) / (np.einsum("ij,ij->i", d, d) + 1e-12) * H * 0.01
    conv = np.zeros(n)
    cnt = np.zeros(n)
    np.add.at(conv, e[:, 0], conv_e)
    np.add.at(conv, e[:, 1], conv_e)
    np.add.at(cnt, e.ravel(), 1)
    conv /= np.maximum(cnt, 1)
    # bumpiness: how much normals disagree with their smoothed field
    ns = spread(nr, e, n, 8)
    ns /= np.linalg.norm(ns, axis=1, keepdims=True) + 1e-12
    bump = 1.0 - np.einsum("ij,ij->i", nr, ns)
    bump = spread(bump, e, n, 4)
    # nearest source bone (deform bones) and radius from it
    bones = [b for b in arm.data.bones if b.use_deform]
    am = np.array(arm.matrix_world)
    best = np.full(n, 1e9)
    bone_i = np.zeros(n, dtype=int)
    tt = np.zeros(n)
    for i, b in enumerate(bones):
        a = (am @ np.r_[np.array(b.head_local), 1.0])[:3]
        c = (am @ np.r_[np.array(b.tail_local), 1.0])[:3]
        dd, t = seg_dist(co, a, c)
        m = dd < best
        best[m] = dd[m]
        bone_i[m] = i
        tt[m] = t[m]
    names = [b.name.replace("mixamorig:", "") for b in bones]
    bone_pos = {nm: ((am @ np.r_[np.array(b.head_local), 1.0])[:3], (am @ np.r_[np.array(b.tail_local), 1.0])[:3])
                for nm, b in zip(names, bones)}
    F = {"co": co, "nr": nr, "h": (co[:, 2] - z0) / H, "H": H, "r1": r1, "r2": r2, "conv": conv, "bump": bump,
         "bone": np.array(names)[bone_i], "brad": best / H, "bt": tt, "bone_pos": bone_pos, "e": e, "n": n,
         "spread": lambda v, it: spread(v, e, n, it), "x": co[:, 0], "y": co[:, 1]}
    for k in ("r1", "r2", "conv", "bump", "brad"):
        v = F[k]
        log("  %-5s p5 %.4f p50 %.4f p95 %.4f" % (k, *np.percentile(v, [5, 50, 95])))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    np.savez_compressed(OUT + "_feat.npz", **{k: F[k] for k in ("co", "nr", "h", "r1", "r2", "conv", "bump", "brad", "bt")},
                        bone=F["bone"], e=e)
    rules = runpy.run_path(RULES)
    W, mats = rules["weights"](F, np)        # W: (n, k) material weights, mats: list of material names (k <= 8)
    W = np.clip(W, 0, None)
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-6)
    k = W.shape[1]
    Wp = np.zeros((n, 8))
    Wp[:, :k] = W
    for ai, nm in enumerate(("m0", "m1")):
        at = me.color_attributes.new(nm, 'FLOAT_COLOR', 'POINT')
        at.data.foreach_set("color", Wp[:, ai * 4:ai * 4 + 4].ravel().astype(np.float32))
    for nm, v in (("feat", np.c_[np.clip(conv * 0.25 + 0.5, 0, 1), np.clip(r1 * 400 + 0.5, 0, 1),
                                 np.clip(bump * 20, 0, 1), np.ones(n)]),):
        at = me.color_attributes.new(nm, 'FLOAT_COLOR', 'POINT')
        at.data.foreach_set("color", v.ravel().astype(np.float32))
    log("weights: " + ", ".join("%s %.1f%%" % (m, 100 * W[:, i].mean()) for i, m in enumerate(mats)))
    # preview colour (for --look)
    pal = np.array(rules.get("preview", [[0.5, 0.5, 0.5]] * k))[:k]
    pv = W @ pal
    at = me.color_attributes.new("paint", 'FLOAT_COLOR', 'POINT')
    at.data.foreach_set("color", np.c_[pv, np.ones(n)].ravel().astype(np.float32))
    if AO:
        bake_ao(body)
    build_material(body, rules, mats)
    if LOW:
        bake_low(body, arm)
    bpy.ops.wm.save_as_mainfile(filepath=OUT + ".blend")
    log("wrote " + OUT + ".blend")


def bake_low(hi, arm):
    """A rigged game mesh: decimate a copy to --low triangles, unwrap it, bake the painted dense mesh's colour,
    roughness, metal and surface detail onto it, copy the skin weights across, and drop the dense mesh. hero_body.py
    then keeps these UVs (no further decimation when --faces is not below --low)."""
    tex_dir = os.path.dirname(OUT)
    name = os.path.basename(OUT).replace("_painted", "")
    lo = hi.copy()
    lo.data = hi.data.copy()
    lo.name = name
    bpy.context.collection.objects.link(lo)
    for mod in list(lo.modifiers):
        lo.modifiers.remove(mod)
    bpy.ops.object.select_all(action='DESELECT')
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    d = lo.modifiers.new("dec", 'DECIMATE')
    d.decimate_type = 'COLLAPSE'
    d.ratio = LOW / max(1, sum(len(p.vertices) - 2 for p in lo.data.polygons))
    bpy.ops.object.modifier_apply(modifier="dec")
    for g in list(lo.vertex_groups):
        lo.vertex_groups.remove(g)
    for a in list(lo.data.color_attributes):
        lo.data.color_attributes.remove(a)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.quads_convert_to_tris()
    while lo.data.uv_layers:
        lo.data.uv_layers.remove(lo.data.uv_layers[0])
    lo.data.uv_layers.new(name="UVMap")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55.0), island_margin=0.003, area_weight=0.0, scale_to_bounds=True)
    bpy.ops.uv.pack_islands(rotate=True, margin=0.002, scale=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.shade_smooth()
    log("low mesh %d triangles, unwrapped" % sum(len(p.vertices) - 2 for p in lo.data.polygons))
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 1
    sc.render.bake.target = 'IMAGE_TEXTURES'
    sc.render.bake.use_selected_to_active = True
    H = max(v[2] for v in lo.bound_box) - min(v[2] for v in lo.bound_box)
    sc.render.bake.cage_extrusion = 0.02 * H
    sc.render.bake.max_ray_distance = 0.05 * H
    sc.render.bake.margin = 16
    m = hi.data.materials[0]
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL')
    lm = bpy.data.materials.new(name + "_mat")
    lm.use_nodes = True
    lnt = lm.node_tree
    lbsdf = lnt.nodes["Principled BSDF"]
    lo.data.materials.clear()
    lo.data.materials.append(lm)
    imgs = {}
    for key, cs in (("color", 'sRGB'), ("rough", 'Non-Color'), ("metal", 'Non-Color'), ("normal", 'Non-Color')):
        img = bpy.data.images.new("%s_%s" % (name, key), TEX, TEX, alpha=False)
        img.colorspace_settings.name = cs
        imgs[key] = img
    tn = lnt.nodes.new("ShaderNodeTexImage")
    lnt.nodes.active = tn
    bpy.ops.object.select_all(action='DESELECT')
    hi.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    for key, sock in (("color", "Base Color"), ("rough", "Roughness"), ("metal", "Metallic")):
        tn.image = imgs[key]
        em = nt.nodes.new("ShaderNodeEmission")
        src = bsdf.inputs[sock].links[0].from_socket
        nt.links.new(src, em.inputs["Color"])
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        bpy.ops.object.bake(type='EMIT')
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        nt.nodes.remove(em)
        log("  baked " + key)
    tn.image = imgs["normal"]
    bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT')
    log("  baked normal")
    for key, img in imgs.items():
        img.filepath_raw = "%s/%s_%s.png" % (tex_dir, name, key)
        img.file_format = 'PNG'
        img.save()
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
    # skin weights from the dense mesh (nearest face, interpolated)
    for g in hi.vertex_groups:
        lo.vertex_groups.new(name=g.name)
    dt = lo.modifiers.new("dt", 'DATA_TRANSFER')
    dt.object = hi
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    dt.layers_vgroup_select_src = 'ALL'
    dt.layers_vgroup_select_dst = 'NAME'
    bpy.ops.object.select_all(action='DESELECT')
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.modifier_apply(modifier="dt")
    mw = lo.matrix_world.copy()
    lo.parent = arm
    lo.matrix_world = mw
    am = lo.modifiers.new("Armature", 'ARMATURE')
    am.object = arm
    bpy.data.objects.remove(hi, do_unlink=True)
    log("weights copied; dense mesh dropped")


def bake_ao(body):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for dv in prefs.devices:
            dv.use = dv.type == "OPTIX"
        sc.cycles.device = 'GPU'
    except Exception:
        sc.cycles.device = 'CPU'
    sc.cycles.samples = 64
    me = body.data
    at = me.color_attributes.new("ao", 'FLOAT_COLOR', 'POINT')
    me.color_attributes.active_color = at
    m = bpy.data.materials.new("ao_tmp")
    m.use_nodes = True
    body.data.materials.clear()
    body.data.materials.append(m)
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.render.bake.target = 'VERTEX_COLORS'
    sc.render.bake.use_selected_to_active = False
    bpy.ops.object.bake(type='AO')
    log("baked ao into vertex colours")


def build_material(body, rules, mats):
    """Base Color / Roughness / Metallic = sum over materials of weight x procedural material, then ambient occlusion,
    cavity dirt and edge wear. A rule set's MATS: [{"name", "c1", "c2" (colours mixed by noise), "scale" (noise
    scale), "stretch" (xyz squash: brushed or grain), "rough": [a, b], "metal", "wear" (edge brightening), "dirt",
    "emit" (optional glow colour)}] in the weights' order."""
    spec = {m["name"]: m for m in rules["MATS"]}
    m = bpy.data.materials.new(body.name + "_painted")
    m.use_nodes = True
    nt = m.node_tree
    N = nt.nodes
    L = nt.links.new
    for nd in list(N):
        if nd.type != 'OUTPUT_MATERIAL':
            N.remove(nd)
    out = next(nd for nd in N if nd.type == 'OUTPUT_MATERIAL')
    bsdf = N.new("ShaderNodeBsdfPrincipled")
    L(bsdf.outputs["BSDF"], out.inputs["Surface"])
    def attr(name):
        a = N.new("ShaderNodeAttribute")
        a.attribute_name = name
        return a
    def sep(sock):
        s_ = N.new("ShaderNodeSeparateColor")
        L(sock, s_.inputs["Color"])
        return s_
    m0, m1, feat, ao = sep(attr("m0").outputs["Color"]), sep(attr("m1").outputs["Color"]), sep(attr("feat").outputs["Color"]), attr("ao")
    w = [m0.outputs[0], m0.outputs[1], m0.outputs[2], attr("m0").outputs["Alpha"],
         m1.outputs[0], m1.outputs[1], m1.outputs[2], attr("m1").outputs["Alpha"]]
    tc = N.new("ShaderNodeTexCoord")
    def maprange(sock, a, b, c=0.0, d=1.0):
        r = N.new("ShaderNodeMapRange")
        r.clamp = True
        r.interpolation_type = 'SMOOTHSTEP'
        L(sock, r.inputs["Value"])
        r.inputs["From Min"].default_value, r.inputs["From Max"].default_value = a, b
        r.inputs["To Min"].default_value, r.inputs["To Max"].default_value = c, d
        return r.outputs["Result"]
    wear = maprange(feat.outputs[0], 0.6, 0.9)
    dirt = maprange(feat.outputs[0], 0.45, 0.15)
    def vmath(op, a, b=None, f=None):
        v = N.new("ShaderNodeVectorMath")
        v.operation = op
        L(a, v.inputs[0]) if not isinstance(a, (tuple, list)) else v.inputs[0].__setattr__("default_value", a)
        if b is not None:
            L(b, v.inputs[1]) if not isinstance(b, (tuple, list)) else v.inputs[1].__setattr__("default_value", b)
        if f is not None:
            L(f, v.inputs["Scale"]) if not isinstance(f, (int, float)) else v.inputs["Scale"].__setattr__("default_value", f)
        return v.outputs["Vector"]
    def math_(op, a, b):
        v = N.new("ShaderNodeMath")
        v.operation = op
        for i, x in enumerate((a, b)):
            if isinstance(x, (int, float)):
                v.inputs[i].default_value = x
            else:
                L(x, v.inputs[i])
        return v.outputs["Value"]
    col_sum = rough_sum = metal_sum = emit_sum = None
    for i, name in enumerate(mats):
        sp = spec[name]
        mapn = N.new("ShaderNodeMapping")
        L(tc.outputs["Object"], mapn.inputs["Vector"])
        mapn.inputs["Scale"].default_value = sp.get("stretch", (1, 1, 1))
        nz = N.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = sp.get("scale", 60.0)
        nz.inputs["Detail"].default_value = sp.get("detail", 6.0)
        L(mapn.outputs["Vector"], nz.inputs["Vector"])
        mix = N.new("ShaderNodeMix")
        mix.data_type = 'RGBA'
        fac = maprange(nz.outputs["Fac"], 0.3, 0.7)
        if sp.get("pattern") == "scales":
            # dragon scales: Voronoi cells, darker at the cell borders, the noise still varies the tone
            vo = N.new("ShaderNodeTexVoronoi")
            vo.feature = 'DISTANCE_TO_EDGE'
            vo.inputs["Scale"].default_value = sp.get("scale_cells", 300.0)
            L(mapn.outputs["Vector"], vo.inputs["Vector"])
            fac = math_('MULTIPLY', maprange(vo.outputs["Distance"], 0.0, 0.12), maprange(nz.outputs["Fac"], 0.2, 0.8, 0.6, 1.0))
        L(fac, mix.inputs["Factor"])
        mix.inputs["A"].default_value = (*sp["c1"], 1)
        mix.inputs["B"].default_value = (*sp["c2"], 1)
        c = mix.outputs["Result"]
        # edge wear (lighter, polished) and cavity dirt (darker)
        c = vmath('ADD', c, vmath('SCALE', c, f=math_('MULTIPLY', wear, sp.get("wear", 0.3))))
        c = vmath('SUBTRACT', c, vmath('SCALE', c, f=math_('MULTIPLY', dirt, sp.get("dirt", 0.4))))
        r0, r1 = sp.get("rough", (0.5, 0.5))
        rough = math_('ADD', r0, math_('MULTIPLY', nz.outputs["Fac"], r1 - r0))
        rough = math_('SUBTRACT', rough, math_('MULTIPLY', wear, sp.get("wear_rough", 0.1)))
        wc = vmath('SCALE', c, f=w[i])
        col_sum = wc if col_sum is None else vmath('ADD', col_sum, wc)
        wr = math_('MULTIPLY', rough, w[i])
        rough_sum = wr if rough_sum is None else math_('ADD', rough_sum, wr)
        wm = math_('MULTIPLY', sp.get("metal", 0.0), w[i])
        metal_sum = wm if metal_sum is None else math_('ADD', metal_sum, wm)
        if sp.get("emit"):
            we = vmath('SCALE', tuple(sp["emit"]), f=w[i])
            emit_sum = we if emit_sum is None else vmath('ADD', emit_sum, we)
    aof = maprange(ao.outputs["Fac"] if "Fac" in ao.outputs else ao.outputs["Color"], 0.0, 1.0, 1.0 - rules.get("AO", 0.8), 1.0)
    col = vmath('SCALE', col_sum, f=aof)
    L(col, bsdf.inputs["Base Color"])
    L(rough_sum, bsdf.inputs["Roughness"])
    L(metal_sum, bsdf.inputs["Metallic"])
    body.data.materials.clear()
    body.data.materials.append(m)


main()

"""Arm and body split for bodies bound in their own pose (run 2026-10-18 d; the owner: "remnants of hands when
animating").

A model sculpted with its arms hanging has hands, gauntlets and sleeves touching hip plates, coats and skirts, often
in one fused surface. Distance rules alone decide each vertex on its own, so pieces of a gauntlet were left at the hip
when the arm rose (Ezee), coat strips went with the hand and stretched into shards (Caziel), and sleeves tore (Azrin).

split_arms() decides, for every vertex that is in contest between an arm and the lower trunk (hips, spine, legs),
which side it belongs to, and then makes whole pieces agree:
  1. each bone gets a thickness profile measured from the mesh (its skin's distance from the bone along its length;
     arm bones measure their outer side, where nothing else is);
  2. a contested vertex goes to the side whose surface it is nearest (distance to the bone minus its thickness);
  3. the mesh is welded by position and every connected patch of one side that is cut off from the rest of that side
     (a shard of coat on a hand, a chip of gauntlet on a hip) goes to the side it is attached to;
  4. faces of the two sides are split apart, and each vertex keeps only its side's weights (an arm vertex left with no
     arm weight takes the arm bone nearest it).
Run inside hero_body.py (the last weight step), or on a built body:
  blender -b --factory-startup --python tools/blender/arm_split.py -- --glb=in.glb --out=out.glb
"""
import math
import os
import sys

import bmesh
import numpy as np

ARMS = {s: ("upper_arm." + s, "forearm." + s, "hand." + s) for s in ("L", "R")}
LOWER = ("hips", "spine", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R", "toe.L", "toe.R")
FINGERS = 0.9          # the hand's reach past its bone (fingers, a fist), times the hand bone's length
RATIO = 0.6            # a vertex changes side only when it is this much nearer the other side's bones
PATCH = 0.025          # the largest cut-off piece moved to the side it touches (share of the mesh's vertices)
PAST = 0.12            # how far past the fingertips an arm's skin may reach (m, 1.8 m body; sleeve zones excepted)
BLEND = 0.07           # the elbow and wrist blend of weights given to an arm (m either side, for a 1.8 m body)


def seg_param(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(1e-12, float(ab @ ab)), 0.0, 1.0)
    d = np.linalg.norm(p - (a + t[:, None] * ab), axis=1)
    return d, t


def thickness(co, d, t, mask, bins=6, pct=70.0, floor=0.02, ceil=0.4):
    """Per-bin thickness of a bone's skin: the pct-th percentile distance of its own vertices, smoothed."""
    prof = np.full(bins, np.nan)
    for i in range(bins):
        sel = mask & (t >= i / bins) & (t <= (i + 1) / bins)
        if sel.sum() >= 8:
            prof[i] = np.percentile(d[sel], pct)
    if np.all(np.isnan(prof)):
        prof[:] = floor * 2
    idx = np.arange(bins)
    ok = ~np.isnan(prof)
    prof = np.interp(idx, idx[ok], prof[ok])
    prof = np.convolve(np.pad(prof, 1, mode="edge"), [0.25, 0.5, 0.25], mode="valid")
    return np.clip(prof, floor, ceil)


def at_profile(prof, t):
    bins = len(prof)
    x = np.clip(t * bins - 0.5, 0, bins - 1)
    return np.interp(x, np.arange(bins), prof)


def split_arms(obj, J, height, log=print, sleeve=None):
    """obj: a mesh bound to the hero skeleton (vertex groups named after the bones); J: bone -> (head, tail) in the
    mesh's world space (numpy arrays). sleeve: (radius, reach) in metres for a 1.8 m body, or None: wide sleeves
    (Azrin's) hang past the hand beside the skirt; everything within `radius` of the forearm and hand, carried on
    `reach` past the hand, goes with the arm unless its surface faces the arm like a skirt's. Returns a dict of counts."""
    k = height / 1.8
    me = obj.data
    mw = np.array(obj.matrix_world)
    co_l = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co_l)
    co = co_l.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
    n = len(co)
    nl = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("normal", nl)
    nrm = nl.reshape(-1, 3) @ mw[:3, :3].T
    nrm /= np.maximum(1e-9, np.linalg.norm(nrm, axis=1))[:, None]
    gidx = {g.name: g.index for g in obj.vertex_groups}
    gname = {g.index: g.name for g in obj.vertex_groups}
    # weights as a dense matrix over the bones that matter
    bones = [b for b in J if b in gidx]
    col = {b: i for i, b in enumerate(bones)}
    W = np.zeros((n, len(bones)), dtype=np.float64)
    for v in me.vertices:
        for g in v.groups:
            nm = gname.get(g.group)
            if nm in col:
                W[v.index, col[nm]] = g.weight
    # segments: the hand reaches over its fingers
    seg = {}
    for b in bones:
        if b.startswith("weapon.") or b == "root":
            continue
        h, t = np.array(J[b][0], dtype=np.float64), np.array(J[b][1], dtype=np.float64)
        if b.startswith("hand."):
            t = t + (t - h) * FINGERS
        seg[b] = (h, t)
    D, T = {}, {}
    for b, (h, t) in seg.items():
        D[b], T[b] = seg_param(co, h, t)
    names = list(seg)
    Dm = np.stack([D[b] for b in names], axis=1)
    nearest = np.array(names)[np.argmin(Dm, axis=1)]
    # thickness profiles
    mid = (np.array(J["hips"][0]) + np.array(J["chest"][1])) * 0.5 if "chest" in J else np.array(J["hips"][0])
    prof = {}
    for b in names:
        mask = nearest == b
        if b.split(".")[0] in ("upper_arm", "forearm", "hand"):
            h, t = seg[b]
            foot = h + T[b][:, None] * (t - h)
            radial = co - foot
            out = foot - mid
            out[:, 2] = 0.0
            out /= np.maximum(1e-9, np.linalg.norm(out, axis=1))[:, None]
            rn = radial / np.maximum(1e-9, np.linalg.norm(radial, axis=1))[:, None]
            mask = mask & ((rn * out).sum(1) > 0.3)          # the outer side of the arm: nothing else is there
            prof[b] = thickness(co, D[b], T[b], mask, pct=85.0, floor=0.02 * k, ceil=0.3 * k)
        else:
            prof[b] = thickness(co, D[b], T[b], mask, pct=60.0, floor=0.04 * k, ceil=0.45 * k)
    surf = {b: D[b] - at_profile(prof[b], T[b]) for b in names}
    lower = [b for b in LOWER if b in surf]
    low_s = np.min(np.stack([surf[b] for b in lower], axis=1), axis=1)
    low_c = np.array([col[b] for b in LOWER if b in col])
    # labels: 0 trunk, 1 left arm, 2 right arm. A vertex keeps the side most of its weight is on, unless it is
    # clearly nearer the other one (its distance to that side's nearest bone under RATIO of the distance to its own
    # side's): a chip of gauntlet weighted to the hip goes back to the hand, a strip of coat weighted to the hand goes
    # back to the coat; skin between the two (a waist beside a hanging forearm) stays as it is.
    label = np.zeros(n, dtype=np.int8)
    low_d = np.min(np.stack([D[b] for b in lower], axis=1), axis=1)
    lw = W[:, low_c].sum(1) if len(low_c) else np.zeros(n)
    for si, s in enumerate(("L", "R")):
        ab = [b for b in ARMS[s] if b in D]
        arm_d = np.min(np.stack([D[b] for b in ab], axis=1), axis=1)
        arm_in = np.min(np.stack([surf[b] for b in ab], axis=1), axis=1) < 0.015 * k     # inside the arm's skin
        aw = W[:, [col[b] for b in ARMS[s] if b in col]].sum(1)
        mine = (aw > 0.02) & (aw >= lw)
        to_arm = ~mine & (arm_d < RATIO * low_d) & arm_in & (aw + lw > 0.0)
        to_body = mine & (low_d < RATIO * arm_d)
        # where two surfaces touch (a sleeve against a skirt), each faces away from its own bone: the sleeve's side
        # facing the body points away from the arm and towards the leg, the skirt's side facing the arm the other way
        ab_near = np.array(ab)[np.argmin(np.stack([D[b] for b in ab], axis=1), axis=1)]
        foot_a = np.zeros_like(co)
        for b in ab:
            m_ = ab_near == b
            h, t = seg[b]
            foot_a[m_] = h + T[b][m_][:, None] * (t - h)
        low_near = np.array(lower)[np.argmin(np.stack([D[b] for b in lower], axis=1), axis=1)]
        foot_l = np.zeros_like(co)
        for b in lower:
            m_ = low_near == b
            h, t = seg[b]
            foot_l[m_] = h + T[b][m_][:, None] * (t - h)
        ra = co - foot_a
        ra /= np.maximum(1e-9, np.linalg.norm(ra, axis=1))[:, None]
        rl = co - foot_l
        rl /= np.maximum(1e-9, np.linalg.norm(rl, axis=1))[:, None]
        fa, fl_ = (nrm * ra).sum(1), (nrm * rl).sum(1)
        near_both = (arm_d < 1.6 * low_d) & (low_d < 1.6 * arm_d) & (arm_d < 0.35 * k)
        face_arm = near_both & (fa > 0.25) & (fl_ < -0.25)
        face_body = near_both & (fl_ > 0.25) & (fa < -0.25)
        zone = np.zeros(n, dtype=bool)
        if sleeve:
            fa_h = np.array(J["forearm." + s][0], dtype=np.float64)
            hd_t = np.array(J["hand." + s][1], dtype=np.float64)
            dirn = (hd_t - fa_h) / max(1e-9, np.linalg.norm(hd_t - fa_h))
            zd, _zt = seg_param(co, fa_h, hd_t + dirn * sleeve[1] * k)
            zone = (zd < sleeve[0] * k) & (arm_d < 1.15 * low_d)
        # nothing on an arm hangs far past the fingertips (a coat's front edge the hand touched), sleeves excepted
        hh, ht = seg["hand." + s]
        dh, th = seg_param(co, hh, ht)
        past = (th >= 0.999) & (np.linalg.norm(co - ht, axis=1) > PAST * k) & ~zone
        label[((mine & ~to_body) | to_arm | face_arm | zone) & ~face_body & ~past] = si + 1
    # weld by position for the patch graph
    me.vertices.ensure_lookup_table() if hasattr(me.vertices, "ensure_lookup_table") else None
    key = np.round(co / (2e-4 * k)).astype(np.int64)
    _, canon = np.unique(key, axis=0, return_inverse=True)
    canon = canon.ravel()
    ed = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ed)
    ed = canon[ed.reshape(-1, 2)]
    ed = ed[ed[:, 0] != ed[:, 1]]
    nc = canon.max() + 1
    # a welded vertex takes the label most of its copies have
    lab_c = np.zeros(nc, dtype=np.int8)
    for lv in (1, 2):
        cnt = np.bincount(canon[label == lv], minlength=nc)
        tot = np.bincount(canon, minlength=nc)
        lab_c[cnt * 2 > tot] = lv
    # patches: connected same-label pieces; a piece cut off from its side's main body goes to the side it touches
    moved = 0
    for _ in range(3):
        same = lab_c[ed[:, 0]] == lab_c[ed[:, 1]]
        parent = np.arange(nc)

        def find(x):
            r = x
            while parent[r] != r:
                r = parent[r]
            while parent[x] != r:
                parent[x], x = r, parent[x]
            return r
        for a, b in ed[same]:
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[ra] = rb
        roots = np.array([find(x) for x in range(nc)])
        size = np.bincount(roots, minlength=nc)
        main = {}
        for lv in (0, 1, 2):
            rs = roots[lab_c == lv]
            if len(rs):
                main[lv] = np.bincount(rs).argmax()
        # neighbour labels of each patch across the cut
        diff = ed[~same]
        changed = 0
        if len(diff):
            touch = {}
            for a, b in diff:
                ra = roots[a]
                touch.setdefault(ra, {}).setdefault(int(lab_c[b]), 0)
                touch[ra][int(lab_c[b])] += 1
                rb = roots[b]
                touch.setdefault(rb, {}).setdefault(int(lab_c[a]), 0)
                touch[rb][int(lab_c[a])] += 1
            for r, nb in touch.items():
                lv = int(lab_c[r])
                if main.get(lv) == r:
                    continue
                if size[r] > 0.3 * max(1, (lab_c == lv).sum()) or size[r] > PATCH * nc:
                    continue                                    # a big piece of its own (a sleeve, a coat panel, a dress)
                other = max(nb, key=nb.get)
                if other != lv:
                    lab_c[roots == r] = other
                    changed += int(size[r])
        moved += changed
        if not changed:
            break
    label = lab_c[canon]
    # faces take their vertices' majority label; split the edges between arm and trunk faces
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    fl = {}
    for f in bm.faces:
        c = np.bincount([label[v.index] for v in f.verts], minlength=3)
        fl[f.index] = int(np.argmax(c)) if c.max() * 2 > len(f.verts) else 0
    cut = [e for e in bm.edges if len(e.link_faces) >= 2 and len({fl[f.index] for f in e.link_faces}) > 1]
    nv0 = len(bm.verts)
    if cut:
        bmesh.ops.split_edges(bm, edges=cut)
    bm.verts.ensure_lookup_table()
    vlab = np.zeros(len(bm.verts), dtype=np.int8)
    src = np.zeros(len(bm.verts), dtype=np.int64)
    dl = bm.verts.layers.deform.active
    for v in bm.verts:
        ls = [fl[f.index] for f in v.link_faces] if v.link_faces else [int(label[min(v.index, n - 1)])]
        vlab[v.index] = max(set(ls), key=ls.count)
    def chain_blend(p, s):
        """Weights for a vertex given to arm `s` that had none of it: along the arm (projected on the chain), blended
        over BLEND either side of the elbow and the wrist, so a sleeve given to the arm bends instead of tearing."""
        sh, el = np.array(J["upper_arm." + s][0]), np.array(J["forearm." + s][0])
        wr, kn = np.array(J["hand." + s][0]), np.array(J["hand." + s][1])
        pts = [sh, el, wr, kn + (kn - wr) * FINGERS]
        best, bu = 1e9, 0.0
        acc = 0.0
        for i in range(3):
            a, b = pts[i], pts[i + 1]
            d, t = seg_param(p[None, :], a, b)
            if d[0] < best:
                best, bu = d[0], acc + t[0] * np.linalg.norm(b - a)
            acc += np.linalg.norm(b - a)
        ue = np.linalg.norm(el - sh)
        uw = ue + np.linalg.norm(wr - el)
        bl = BLEND * k
        up = float(np.clip((ue + bl - bu) / (2 * bl), 0.0, 1.0))
        hd = float(np.clip((bu - (uw - bl)) / (2 * bl), 0.0, 1.0))
        fo = max(0.0, 1.0 - up - hd)
        return {"upper_arm." + s: up, "forearm." + s: fo, "hand." + s: hd}

    # rewrite weights by side
    arm_cols = {s: [gidx[b] for b in ARMS[s] if b in gidx] for s in ("L", "R")}
    all_arm = set(arm_cols["L"]) | set(arm_cols["R"])
    low_g = {gidx[b] for b in LOWER if b in gidx}
    fixed = 0
    co_b = np.array([v.co[:] for v in bm.verts]) @ mw[:3, :3].T + mw[:3, 3]
    for v in bm.verts:
        if dl is None:
            break
        dv = v[dl]
        lv = int(vlab[v.index])
        if lv == 0:
            drop = [g for g in dv.keys() if g in all_arm]
            if not drop:
                continue
            for g in drop:
                del dv[g]
            if sum(dv.values()) <= 1e-6:
                p = co_b[v.index][None, :]
                best = min((b for b in seg if b not in ARMS["L"] + ARMS["R"] and b in gidx),
                           key=lambda b: seg_param(p, *seg[b])[0][0])
                dv[gidx[best]] = 1.0
        else:
            s = "L" if lv == 1 else "R"
            drop = [g for g in dv.keys() if g in low_g or (g in all_arm and g not in arm_cols[s])]
            if not drop and sum(dv[g] for g in dv.keys() if g in arm_cols[s]) > 0.0:
                continue
            for g in drop:
                del dv[g]
            if sum(dv.get(g, 0.0) for g in arm_cols[s]) <= 1e-6:
                for g in list(dv.keys()):
                    del dv[g]
                for b, w in chain_blend(co_b[v.index], s).items():
                    if b in gidx and w > 0.0:
                        dv[gidx[b]] = w
        tot = sum(dv.values())
        for g in list(dv.keys()):
            dv[g] = dv[g] / tot
        fixed += 1
    bm.to_mesh(me)
    bm.free()
    me.update()
    out = {"arm_left": int((vlab == 1).sum()), "arm_right": int((vlab == 2).sum()), "patches_moved": int(moved),
           "edges_split": len(cut), "new_vertices": len(me.vertices) - nv0, "reweighted": fixed}
    log("arm split: %s" % out)
    return out


def _main():
    import bpy
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in argv if "=" in a}
    glb, out = os.path.abspath(opt["glb"]), os.path.abspath(opt["out"])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    if arm.animation_data:
        arm.animation_data.action = None
    mw = arm.matrix_world
    J = {b.name: (np.array(mw @ b.head_local), np.array(mw @ b.tail_local)) for b in arm.data.bones}
    height = float(opt.get("height", max(1.0, J["head"][1][2])))
    sl = tuple(float(x) for x in opt["sleeve"].split(",")) if "sleeve" in opt else None
    for o in bpy.data.objects:
        if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers) and len(o.data.vertices) > 2000:
            split_arms(o, J, height, sleeve=sl)
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format='GLB', export_animations=True,
                              export_animation_mode='ACTIONS', export_skins=True, export_morph=False,
                              export_yup=True, export_apply=False, export_image_format='AUTO')
    print("wrote", out)


if __name__ == "__main__":
    _main()

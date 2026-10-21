p = 'A:/Python/woa/tools/blender/hero_body.py'
s = open(p).read()


def rep(a, b):
    global s
    assert a in s, a[:80]
    s = s.replace(a, b)


rep('''       [--glide=<idle clip>] [--reach=0] [--smooth=4] [--norig] [--move=regex:dx,dy,dz;...] [--body_piece=<regex>] [--capture] [--keep=<regex>] [--posture] [--fist] [--unmix=1] [--split=1] [--sleeve=r,reach]''',
'''       [--glide=<idle clip>] [--reach=0] [--smooth=4] [--norig] [--move=regex:dx,dy,dz;...] [--body_piece=<regex>] [--capture] [--keep=<regex>] [--posture] [--fist] [--unmix=1] [--split=1] [--sleeve=r,reach]
       [--extra_bones=<json>] [--cloth_legs=0.5]

Extra bones (run 2026-10-21 b: Thyrandael's wings, Gancho's branches): --extra_bones=<json> {"bones": [{"name":
"wing.L", "parent": "chest" (a hero bone or an earlier extra bone), "head": [x, y, z], "tail": [x, y, z] (model space,
like --rigid), "chain": "wing.L" (bones of one chain share their region's vertices; default its own name),
"regions": ["ball:x,y,z,r", "cap:x1,y1,z1,x2,y2,z2,r", "box:x0,x1,y0,y1,z0,z1"] (model space; a chain's regions are
pooled), "root_blend": m (metres on a 1.8 m hero along the chain's first bone over which the parent's weight fades
out; 0 = none), "roll": degrees}]}. Region vertices are weighted to the chain's bones by inverse distance (smooth
across the chain's joints) and blended into the parent at the root; the clips leave the extra bones at rest, so the
game can sway or flap them.''')
rep('''RIGID = arg("rigid", "")''', '''EXTRA = arg("extra_bones", "")                 # json file of extra bones (see the docstring)
CLOTH_LEGS = arg("cloth_legs", 0.5)            # most a hanging cloth vertex follows the legs (stiff armour panels: less)
RIGID = arg("rigid", "")''')
rep("        legs = 0.2 + 0.3 * min(1.0, f)                      # 20% at the hips, 50% at and below the knees",
    "        legs = min(0.2, CLOTH_LEGS) + max(0.0, CLOTH_LEGS - 0.2) * min(1.0, f)   # 20% at the hips, 50% (--cloth_legs) below the knees")
rep('''    apply_rigid(body)                            # its split copies must keep different weights
''', '''    apply_rigid(body)                            # its split copies must keep different weights
    apply_extra(body)
''')
rep('''    for g in list(body.vertex_groups):
        if g.name not in DEFORM:
            body.vertex_groups.remove(g)''', '''    keep = set(DEFORM) | set(b["name"] for b in extra_spec())
    for g in list(body.vertex_groups):
        if g.name not in keep:
            body.vertex_groups.remove(g)''')
rep('''    bind(body, rig)
    if PREVIEW:''', '''    add_extra_bones(rig)
    bind(body, rig)
    if PREVIEW:''')
rep('''def reach_gating(body, J):''', '''_EXTRA = []


def extra_spec():
    if EXTRA and not _EXTRA:
        _EXTRA.extend(json.load(open(EXTRA))["bones"])
    return _EXTRA


def region_hits(co, spec, T, s_):
    kind, nums = spec.split(":", 1)
    v = [float(x) for x in nums.split(",")]
    if kind == "cap":
        return seg_dist(co, T @ Vector(v[0:3]), T @ Vector(v[3:6])) < v[6] * s_
    if kind == "box":
        lo = np.array((T @ Vector((v[0], v[2], v[4])))[:])
        hi = np.array((T @ Vector((v[1], v[3], v[5])))[:])
        a, b = np.minimum(lo, hi), np.maximum(lo, hi)
        return np.all((co >= a) & (co <= b), axis=1)
    c = np.array((T @ Vector(v[0:3]))[:])
    return np.linalg.norm(co - c, axis=1) < v[3] * s_


def apply_extra(body):
    """--extra_bones: each chain's region vertices go to its bones (inverse-distance weights, smooth across the
    chain's joints), blended into the chain's parent over root_blend at the root. Runs after --rigid."""
    bones = extra_spec()
    if not bones:
        return
    co = world_coords(body)
    T = PLACE_T[0]
    s_ = T.to_scale()[0]
    chains = {}
    for b in bones:
        chains.setdefault(b.get("chain", b["name"]), []).append(b)
    for nm in set(b["name"] for b in bones):
        if body.vertex_groups.get(nm) is None:
            body.vertex_groups.new(name=nm)
    claimed = np.zeros(len(co), dtype=bool)
    for cname, cb in chains.items():
        hit = np.zeros(len(co), dtype=bool)
        for b in cb:
            for spec in b.get("regions", []):
                hit |= region_hits(co, spec, T, s_)
        hit &= ~claimed
        claimed |= hit
        idx = np.where(hit)[0]
        if len(idx) == 0:
            log("  extra bones: chain %s has no vertices" % cname)
            continue
        p = co[idx]
        segs = [(np.array((T @ Vector(b["head"]))[:]), np.array((T @ Vector(b["tail"]))[:])) for b in cb]
        d = np.stack([seg_dist(p, a, c) for a, c in segs], axis=1)
        w = 1.0 / (d + 0.01 * HEIGHT) ** 4
        w /= w.sum(axis=1, keepdims=True)
        parent = cb[0]["parent"]
        if body.vertex_groups.get(parent) is None:
            body.vertex_groups.new(name=parent)
        gidx = {g.name: g.index for g in body.vertex_groups}
        rb = float(cb[0].get("root_blend", 0.0)) * HEIGHT / 1.8
        a, c = segs[0]
        ab = c - a
        t = ((p - a) @ ab) / max(float(np.linalg.norm(ab)), 1e-9)
        u = np.clip(t / rb, 0.0, 1.0) if rb > 0 else np.ones(len(idx))
        pw = 1.0 - u * u * (3 - 2 * u)
        dv = body.data.vertices
        for k, vi in enumerate(idx):
            vi = int(vi)
            for g in list(dv[vi].groups):
                body.vertex_groups[g.group].remove([vi])
            if pw[k] > 1e-3:
                body.vertex_groups[gidx[parent]].add([vi], float(pw[k]), 'REPLACE')
            for j, b in enumerate(cb):
                ww = float(w[k, j] * (1.0 - pw[k]))
                if ww > 1e-3:
                    body.vertex_groups[gidx[b["name"]]].add([vi], ww, 'REPLACE')
        log("  extra bones: chain %s (%s) holds %d vertices, %d blended into %s at the root"
            % (cname, ", ".join(b["name"] for b in cb), len(idx), int((pw > 1e-3).sum()), parent))


def add_extra_bones(rig):
    """The --extra_bones bones on the finished rig (rest only: the clips never key them)."""
    bones = extra_spec()
    if not bones:
        return
    T = PLACE_T[0]
    select_only(rig)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    inv = rig.matrix_world.inverted()
    for b in bones:
        e = eb.new(b["name"])
        e.head = inv @ (T @ Vector(b["head"]))
        e.tail = inv @ (T @ Vector(b["tail"]))
        e.roll = math.radians(float(b.get("roll", 0.0)))
        e.parent = eb[b["parent"]]
        e.use_deform = True
    bpy.ops.object.mode_set(mode='OBJECT')
    for b in bones:
        bb = rig.data.bones[b["name"]]
        m = rig.matrix_world @ bb.matrix_local
        log("  extra bone %s (parent %s): head %s tail %s; axes x %s y %s z %s (Blender game space: z up, faces -y)" % (
            b["name"], b["parent"], tuple(round(x, 3) for x in (rig.matrix_world @ bb.head_local)),
            tuple(round(x, 3) for x in (rig.matrix_world @ bb.tail_local)),
            tuple(round(x, 2) for x in m.col[0][:3]), tuple(round(x, 2) for x in m.col[1][:3]),
            tuple(round(x, 2) for x in m.col[2][:3])))


def reach_gating(body, J):''')
open(p, 'w', newline='\n').write(s)
print("patched")

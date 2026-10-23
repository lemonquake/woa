extends RefCounted
## The pose solver behind the hand-made hero clips (run 2026-10-23; the owner: "make it by yourself, a perfect run,
## no clipping, no weird twists"). A pose is a few readable controls in model space (the hero faces +Z, its left is +X,
## metres) and this turns them into every bone's local turn on the hero skeleton:
##   hips      Vector3   the hips' offset from rest
##   pelvis    Vector3   degrees (pitch about X: lean forward, yaw about Y: turn to its left, roll about Z: tilt right)
##   spine, chest, neck, head, clav.L, clav.R   Vector3 degrees, each turned in its parent's turned frame
##   leg.L / leg.R  {ankle: Vector3 (model space), pole: Vector3 (where the knee points), foot: Vector3 degrees
##                   (the foot's turn from flat, in model axes), toe: float degrees (bend up)}
##   arm.L / arm.R  {hand: Vector3 wrist target, pole: Vector3 (where the elbow points), rot: Basis (the hand's
##                   model-space turn; optional), wrist: Vector3 degrees (else: the hand's turn from the forearm),
##                   chest: true (hand, pole and rot are given in the chest's rest frame, so they ride the torso)}
##   sword     {grip: Vector3, blade: Vector3, edge: Vector3, pole: Vector3, chest: bool, hand: "R"}: the hand that
##             holds the sword, aimed by the blade (the weapon bone's +Y) and the cutting edge (its +X)
##   grip2     {gap: float, pole: Vector3, w: float}: the other hand on the same grip, `gap` metres along the blade below
##             the first (w: 0 the hand is where arm.L / arm.R puts it, 1 on the handle, between: on its way)
## Limbs are two-bone IK whose elbow and knee turn only about the rig's own hinge axes (read from the motion-capture
## clips, work/lemondev/2026-10-23-crash-anim-ai/hinges.gd), so a joint never bends sideways; the forearm takes half the
## wrist's twist, as a real forearm does, so the wrist never wrings.

const HINGE := {"forearm.L": Vector3(-0.154, 0.0, -0.988), "forearm.R": Vector3(-0.076, 0.0, 0.988),
	"shin.L": Vector3(-0.999, 0.0, -0.039), "shin.R": Vector3(-0.999, 0.0, -0.052)}
const REF_HIPS := 0.98                       # the motion-capture library's resting hip height (hips_rest)

var sk: Skeleton3D
var names: Array = []
var idx := {}
var parent := PackedInt32Array()
var lrest: Array = []                        # local rest Transform3D per bone
var grest: Array = []                        # global rest Transform3D per bone
var leg_k := 1.0                             # this body's hip height over the library's
var last_edge := {}                          # hand -> the sword edge chosen last frame (cleared for each clip)
var last_pole := {}                          # hand -> the elbow pole chosen last frame (cleared for each clip)
var shapes = null                            # BodyShapes of this body (tests/tools/body_shapes.gd), when the builder fits them
var _obst: Array = []                        # this pose's trunk and leg shapes: [name, frame, centre, radius]
var _wpts := {}                              # side -> a few of the held weapon's points (weapon bone space)
var _chest_basis := Basis()
var grip_prior = null                        # the idle's sword hand against its forearm (Quaternion): every other clip leans to it
const PRIOR_W := 0.6                         # how hard (per radian away from it)

func setup(p_sk: Skeleton3D) -> void:
	sk = p_sk
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
		idx[sk.get_bone_name(i)] = i
		parent.append(sk.get_bone_parent(i))
		lrest.append(sk.get_bone_rest(i))
		grest.append(sk.get_bone_global_rest(i))
	leg_k = clampf(grest[idx.hips].origin.y / REF_HIPS, 0.5, 1.6)

func rest_pos(bone: String) -> Vector3:
	return (grest[idx[bone]] as Transform3D).origin

static func eul(v: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z)))

## Orthonormal frame [a, b', a x b'] with b made perpendicular to a.
static func frame(a: Vector3, b: Vector3) -> Basis:
	var x := a.normalized()
	var y := (b - x * b.dot(x)).normalized()
	return Basis(x, y, x.cross(y))

## The pose: bone name -> local Transform3D (and "_g": the global transforms, for checks).
func solve(c: Dictionary) -> Dictionary:
	var g := {}
	var d := {}                               # bone -> model-space delta turn of the trunk chain
	var out := {}
	# hips
	var hi: int = idx.hips
	var rp := eul(c.get("pelvis", Vector3.ZERO))
	d["hips"] = rp
	g["hips"] = Transform3D(rp * (grest[hi] as Transform3D).basis, (grest[hi] as Transform3D).origin + c.get("hips", Vector3.ZERO))
	for b in ["spine", "chest", "neck", "head"]:
		var pb := names[parent[idx[b]]] as String
		d[b] = (d[pb] as Basis) * eul(c.get(b, Vector3.ZERO))
		_place(g, b, (d[b] as Basis) * (grest[idx[b]] as Transform3D).basis)
	for s: String in ["L", "R"]:
		var cl: String = "shoulder." + s
		d[cl] = (d["chest"] as Basis) * eul(c.get("clav." + s, Vector3.ZERO))
		_place(g, cl, (d[cl] as Basis) * (grest[idx[cl]] as Transform3D).basis)
	# the chest's rest-to-posed transform (arm targets "in the chest" ride it)
	var chest_xf: Transform3D = (g["chest"] as Transform3D) * (grest[idx.chest] as Transform3D).affine_inverse()
	# legs
	for s: String in ["L", "R"]:
		var leg: Dictionary = c.get("leg." + s, {})
		var ankle: Vector3 = leg.get("ankle", rest_pos("foot." + s))
		_two_bone(g, "thigh." + s, "shin." + s, "foot." + s, ankle, leg.get("pole", Vector3(0, 0, 1)))
		var fb := eul(leg.get("foot", Vector3.ZERO)) * (grest[idx["foot." + s]] as Transform3D).basis
		_place(g, "foot." + s, fb)
		var lmiss := ((g["foot." + s] as Transform3D).origin - ankle).length()
		if lmiss > float(g.get("_miss", 0.0)):
			g["_miss"] = lmiss
			g["_miss_at"] = "foot." + s
		var tb := (g["foot." + s] as Transform3D).basis * (lrest[idx["toe." + s]] as Transform3D).basis \
			* Basis(Vector3.RIGHT, deg_to_rad(-float(leg.get("toe", 0.0))))
		_place(g, "toe." + s, tb)
	_chest_basis = (g["chest"] as Transform3D).basis.orthonormalized()
	_obstacles(g)
	# arms: a sword hand first (the other hand may hold the same grip)
	var sw: Dictionary = c.get("sword", {})
	var arms := {"L": c.get("arm.L", {}), "R": c.get("arm.R", {})}
	var wb := {}
	if not sw.is_empty():
		var hs := String(sw.get("hand", "R"))
		var grip: Vector3 = sw.grip
		var blade: Vector3 = sw.blade
		var edge: Vector3 = sw.edge
		if bool(sw.get("chest", false)):
			grip = chest_xf * grip
			blade = chest_xf.basis * blade
			edge = chest_xf.basis * edge
		# the weapon bone: +Y along the blade, +X the cutting edge. The edge asked for is only a wish: the hand turns
		# about the blade, and the elbow swings round the shoulder-wrist line, to where the wrist is most at ease (bend
		# hurts most: a wrist bends about 75 degrees at most; twist goes half into the forearm). A whole clip picks its
		# grips together (HandClips: grip_costs for every frame, then the smoothest cheap path), so they never jump;
		# a single pose searches on its own, kept close to the last frame's.
		var by := blade.normalized()
		var e0 := (edge - by * edge.dot(by)).normalized()
		var lw: Transform3D = lrest[idx["weapon." + hs]]
		var pole0: Vector3 = sw.get("pole", Vector3(0.6, -0.5, -0.6))
		var g2s: Dictionary = c.get("grip2", {})
		var os := "L" if hs == "R" else "R"
		var w2 := float(g2s.get("w", 1.0)) if not g2s.is_empty() else 0.0
		var gpole0: Vector3 = g2s.get("pole", Vector3(-0.6, -0.5, -0.6))
		var gap := float(g2s.get("gap", 0.16))
		var bx := e0
		var bpole := pole0
		var bpole2 := gpole0
		if c.has("_grip"):
			# chosen for the whole clip: a turn from the blade-carried reference, and the elbows' swings
			var gc: Dictionary = c._grip
			var ref: Vector3 = gc.ref
			ref = (ref - by * ref.dot(by)).normalized()
			bx = ref.rotated(by, TAU * float(gc.k) / NR)
			var e1 := _grip_eval(g, hs, os, bx, by, grip, lw, pole0, gpole0, w2, gap, int(gc.j1), int(gc.j2), e0)
			bpole = e1.pole1
			bpole2 = e1.pole2
		elif c.has("_costs"):
			# every grip this frame could take, for the whole-clip choice (index: k * NS * NS + j1 * NS + j2)
			var ref2: Vector3 = c._costs.ref
			ref2 = (ref2 - by * ref2.dot(by)).normalized()
			var out_c: PackedFloat32Array = c._costs.out
			out_c.resize(NR * NS * NS)
			for k in NR:
				var cand := ref2.rotated(by, TAU * k / NR)
				for j1 in NS:
					for j2 in (NS if w2 > 0.01 else 1):
						var ev := _grip_eval(g, hs, os, cand, by, grip, lw, pole0, gpole0, w2, gap, j1, j2, e0)
						out_c[k * NS * NS + j1 * NS + j2] = float(ev.cost)
					if w2 <= 0.01:
						for j2 in range(1, NS):
							out_c[k * NS * NS + j1 * NS + j2] = out_c[k * NS * NS + j1 * NS]
			c._costs.out = out_c
			c._costs["by"] = by
			return {}
		else:
			var best := INF
			for k in NR:
				var cand := e0.rotated(by, TAU * k / NR)
				for j1 in NS:
					var ev := _grip_eval(g, hs, os, cand, by, grip, lw, pole0, gpole0, w2, gap, j1, 2, e0)
					var cost := float(ev.cost)
					if last_edge.has(hs):
						cost += 0.8 * cand.angle_to(last_edge[hs])
					if cost < best:
						best = cost
						bx = cand
						bpole = ev.pole1
						bpole2 = ev.pole2
		last_edge[hs] = bx
		last_pole[hs] = bpole
		if w2 > 0.01:
			last_pole[os] = bpole2
		var wbas := Basis(bx, by, bx.cross(by))
		var hand_b := wbas * lw.basis.inverse()
		var hand_o := grip - hand_b * lw.origin
		arms[hs] = {"hand": hand_o, "rot": hand_b, "pole": bpole}
		wb[hs] = Transform3D(wbas, grip)
		var g2: Dictionary = c.get("grip2", {})
		if not g2.is_empty() and float(g2.get("w", 1.0)) > 0.001:
			var o := "L" if hs == "R" else "R"
			var ob2 := _second_hand(wbas, grip, o, float(g2.get("gap", 0.16)))
			var w := clampf(float(g2.get("w", 1.0)), 0.0, 1.0)
			var gpole: Vector3 = g2.get("pole", Vector3(-0.6, -0.5, -0.6))
			if w >= 0.999:
				arms[o] = {"hand": ob2.origin, "rot": ob2.basis, "pole": gpole}
			else:
				# on its way to the handle: from where the free hand is toward the grip
				var free: Dictionary = arms[o]
				var ft: Vector3 = free.get("hand", rest_pos("hand." + o))
				var fp: Vector3 = free.get("pole", Vector3(0, -0.3, -1))
				if bool(free.get("chest", false)):
					ft = chest_xf * ft
					fp = chest_xf.basis * fp
				_two_bone(g, "upper_arm." + o, "forearm." + o, "hand." + o, ft, fp)
				var fb := (g["forearm." + o] as Transform3D).basis * (lrest[idx["hand." + o]] as Transform3D).basis \
					* eul(free.get("wrist", Vector3.ZERO))
				var q := fb.orthonormalized().get_rotation_quaternion().slerp(ob2.basis.get_rotation_quaternion(), w)
				arms[o] = {"hand": ft.lerp(ob2.origin, w), "rot": Basis(q), "pole": fp.lerp(gpole, w).normalized()}
	for s: String in ["L", "R"]:
		var arm: Dictionary = arms[s]
		var cl: String = "shoulder." + s
		var ua: String = "upper_arm." + s
		var fa: String = "forearm." + s
		var ha: String = "hand." + s
		var target: Vector3 = arm.get("hand", rest_pos(ha))
		var pole: Vector3 = arm.get("pole", Vector3(0, -0.3, -1))
		var rot = arm.get("rot", null)
		if bool(arm.get("chest", false)):
			target = chest_xf * target
			pole = chest_xf.basis * pole
			if rot != null:
				rot = chest_xf.basis * (rot as Basis)
		_two_bone(g, ua, fa, ha, target, pole)
		if bool(c.get("_capture_prior", false)) and rot != null and s == String(sw.get("hand", "R")) and not sw.is_empty():
			grip_prior = _wrist_q(g, s, (rot as Basis).orthonormalized())
		var hb: Basis
		if rot != null:
			hb = (rot as Basis).orthonormalized()
		else:
			hb = (g[fa] as Transform3D).basis * (lrest[idx[ha]] as Transform3D).basis * eul(arm.get("wrist", Vector3.ZERO))
		# half the wrist's twist goes up the forearm
		var tang := _wrist(g, s, hb).x
		var fb: Basis = (g[fa] as Transform3D).basis * Basis(Vector3.UP, tang * 0.5)
		_place(g, fa, fb)
		_place(g, ha, hb)
		var miss := ((g[ha] as Transform3D).origin - target).length()
		if miss > float(g.get("_miss", 0.0)):
			g["_miss"] = miss
			g["_miss_at"] = ha
		var wn: String = "weapon." + s
		_place(g, wn, (g[ha] as Transform3D).basis * (lrest[idx[wn]] as Transform3D).basis)
	# root and everything as local turns
	g["root"] = grest[idx.root]
	for i in names.size():
		var n := names[i] as String
		if not g.has(n) or not (g[n] is Transform3D):
			continue
		var pt: Transform3D = Transform3D() if parent[i] < 0 else g[names[parent[i]]]
		out[n] = pt.affine_inverse() * (g[n] as Transform3D)
	out["_g"] = g
	return out

const SAME_GRIP := true                     # the other hand closes round the handle turned as the first
const NR := 24                               # grip turns about the blade tried (15 degrees apart)
const NS := 5                                # elbow swings tried for each hand
const SWING := [-40.0, -20.0, 0.0, 20.0, 40.0]

## One grip: the sword hand's edge `cand` and its elbow swing `j1` (the other hand's `j2` when both hold it). Returns its
## cost (wrist bend most, then twist, the swing from the natural elbow, the edge from the one asked for) and the poles.
func _grip_eval(g: Dictionary, hs: String, os: String, cand: Vector3, by: Vector3, grip: Vector3, lw: Transform3D,
		pole0: Vector3, gpole0: Vector3, w2: float, gap: float, j1: int, j2: int, e0: Vector3) -> Dictionary:
	var wb0 := Basis(cand, by, cand.cross(by))
	var hb0 := wb0 * lw.basis.inverse()
	var a1 := _arm_cost(g, hs, grip - hb0 * lw.origin, hb0, pole0, deg_to_rad(SWING[j1]))
	var cost := float(a1.cost) + 0.3 * cand.angle_to(e0)
	if grip_prior != null:
		# one way of holding the sword for every move (the idle's hand against its forearm), so moves blend without the
		# forearm wringing round
		cost += PRIOR_W * (grip_prior as Quaternion).angle_to(_wrist_q(g, hs, hb0))
	var p2 := gpole0
	if w2 > 0.01:
		var ob := _second_hand(wb0, grip, os, gap)
		var a2 := _arm_cost(g, os, ob.origin, ob.basis, gpole0, deg_to_rad(SWING[j2]))
		cost += w2 * float(a2.cost)
		p2 = a2.pole
	return {"cost": cost, "pole1": a1.pole, "pole2": p2}

## One arm reaching `target` with the hand turned `hb`, its elbow swung `a` radians round the shoulder-wrist line from
## `pole`: {cost, pole}.
func _arm_cost(g: Dictionary, s: String, target: Vector3, hb: Basis, pole: Vector3, a: float) -> Dictionary:
	var sh: Vector3 = (g["shoulder." + s] as Transform3D) * (lrest[idx["upper_arm." + s]] as Transform3D).origin
	var ax := (target - sh).normalized()
	var p := pole.rotated(ax, a) if absf(a) > 0.0001 and ax.length() > 0.5 else pole
	_two_bone(g, "upper_arm." + s, "forearm." + s, "hand." + s, target, p)
	var ws := _wrist(g, s, hb)
	var bend := absf(ws.y)
	var tw := absf(ws.x)
	var cost := 0.35 * bend + 2.5 * maxf(0.0, bend - 1.05) + 0.25 * tw + 1.0 * maxf(0.0, tw - 1.5) + 0.2 * absf(a)
	var reach: Vector3 = (g["forearm." + s] as Transform3D) * (lrest[idx["hand." + s]] as Transform3D).origin
	cost += 3.0 * reach.distance_to(target)
	# the elbow where elbows go (down, a little out and back, as tests/tools/anim_audit.gd judges it)
	var el: Vector3 = (g["forearm." + s] as Transform3D).origin
	var off := el - sh
	off = off - ax * off.dot(ax)
	if off.length() > 0.02:
		var ang := off.angle_to(natural_elbow(ax, s))
		cost += 0.15 * ang + 2.0 * maxf(0.0, ang - deg_to_rad(105.0))
	# arms and the weapon kept out of the body
	cost += 12.0 * _inside(g, s, hb)
	return {"cost": cost, "pole": p}

## Where an elbow naturally points for an arm along `ax` (the audit's reference: down, a little out and back in the
## chest's frame, square to the arm).
func natural_elbow(ax: Vector3, s: String) -> Vector3:
	var side := 1.0 if s == "L" else -1.0
	var r1 := _chest_basis * Vector3(side * 0.35, -1.0, -0.25).normalized()
	r1 = r1 - ax * r1.dot(ax)
	var r2 := _chest_basis * Vector3(0.0, 0.0, -1.0)
	r2 = r2 - ax * r2.dot(ax)
	var r := r1 + r2 * 0.35
	return r.normalized() if r.length() > 1e-4 else r2.normalized()

## The trunk and leg shapes at this pose (BodyShapes), for the arm search.
func _obstacles(g: Dictionary) -> void:
	_obst.clear()
	if shapes == null:
		return
	var pose := {}
	for n in g:
		if g[n] is Transform3D and idx.has(n):
			pose[int(idx[n])] = g[n]
	for name in ["hips", "spine", "chest", "neck", "head", "thigh.L", "thigh.R"]:
		if not shapes.shapes.has(name) or not pose.has(int(shapes.shapes[name].bone)):
			continue
		var f: Transform3D = shapes.frame_of(name, pose)
		var bd: Array = shapes.bound(name, f)
		_obst.append([name, f, bd[0], float(bd[1])])

## How deep (metres, summed) the arm `s` as posed in `g`, its hand turned `hb`, and the weapon it holds sit inside the
## body.
func _inside(g: Dictionary, s: String, hb: Basis) -> float:
	if _obst.is_empty():
		return 0.0
	var pts: Array = []
	var ua: Transform3D = g["upper_arm." + s]
	var fa: Transform3D = g["forearm." + s]
	var wr: Vector3 = fa * (lrest[idx["hand." + s]] as Transform3D).origin
	pts.append([ua.origin.lerp(fa.origin, 0.6), 0.045])
	pts.append([fa.origin, 0.045])
	pts.append([fa.origin.lerp(wr, 0.5), 0.04])
	pts.append([wr, 0.035])
	var wl: Transform3D = lrest[idx["weapon." + s]]
	var wxf := Transform3D(hb * wl.basis, wr + hb * wl.origin)
	for wp in _wpts.get(s, []):
		pts.append([wxf * (wp as Vector3), 0.02])
	var depth := 0.0
	for o in _obst:
		var c: Vector3 = o[2]
		var rr: float = o[3]
		for pr in pts:
			var p: Vector3 = pr[0]
			if p.distance_to(c) > rr + 0.1:
				continue
			depth += shapes.push(String(o[0]), o[1], p, float(pr[1])).length()
	return depth

## The arm reaching `target` with the hand turned `hb`: the elbow's swing round the shoulder-wrist line that leaves the
## wrist most at ease, from `pole` swung up to 60 degrees either way. Returns {pole, cost}.
func _best_swivel(g: Dictionary, s: String, target: Vector3, hb: Basis, pole: Vector3) -> Dictionary:
	var sh: Vector3 = (g["shoulder." + s] as Transform3D) * (lrest[idx["upper_arm." + s]] as Transform3D).origin
	var ax := (target - sh).normalized()
	var best := INF
	var bp := pole
	for k in 7:
		var a := deg_to_rad(-60.0 + 20.0 * k)
		var p := pole.rotated(ax, a) if ax.length() > 0.5 else pole
		_two_bone(g, "upper_arm." + s, "forearm." + s, "hand." + s, target, p)
		var ws := _wrist(g, s, hb)
		var bend := absf(ws.y)
		var tw := absf(ws.x)
		var cost := 0.35 * bend + 2.0 * maxf(0.0, bend - 1.1) + 0.25 * tw + 1.0 * maxf(0.0, tw - 1.5) + 0.12 * absf(a)
		var reach: Vector3 = (g["forearm." + s] as Transform3D) * (lrest[idx["hand." + s]] as Transform3D).origin
		cost += 3.0 * reach.distance_to(target)
		if last_pole.has(s):
			cost += 0.5 * p.angle_to(last_pole[s])
		if cost < best:
			best = cost
			bp = p
	return {"pole": bp, "cost": best}

## The other hand on a two-handed grip: `gap` metres down the handle from the first, its weapon bone along the blade
## with the edge mirrored (the hands close round the handle from opposite sides). Returns the hand bone's transform.
func _second_hand(wbas: Basis, grip: Vector3, o: String, gap: float) -> Transform3D:
	var w2 := Basis(wbas.x, wbas.y, wbas.z) if SAME_GRIP else Basis(-wbas.x, wbas.y, -wbas.z)
	var lw2: Transform3D = lrest[idx["weapon." + o]]
	var hb2 := w2 * lw2.basis.inverse()
	var gp2 := grip - wbas.y * gap
	return Transform3D(hb2, gp2 - hb2 * lw2.origin)

## The hand's turn against its (untwisted) forearm as a quaternion.
func _wrist_q(g: Dictionary, s: String, hb: Basis) -> Quaternion:
	var fl := ((g["forearm." + s] as Transform3D).basis * (lrest[idx["hand." + s]] as Transform3D).basis).inverse() * hb
	var q := fl.orthonormalized().get_rotation_quaternion()
	return -q if q.w < 0.0 else q

## The hand's turn against its forearm: x its twist about the forearm (radians, -PI..PI), y the bend left over.
func _wrist(g: Dictionary, s: String, hb: Basis) -> Vector2:
	var fl := ((g["forearm." + s] as Transform3D).basis * (lrest[idx["hand." + s]] as Transform3D).basis).inverse() * hb
	var q := fl.orthonormalized().get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var tw := Quaternion(0.0, q.y, 0.0, q.w).normalized()
	var tang := wrapf(2.0 * atan2(tw.y, tw.w), -PI, PI)
	var swing := tw.inverse() * q
	return Vector2(tang, swing.get_angle())

## A bone's global transform from its parent's (already placed) and the given model-space basis.
func _place(g: Dictionary, bone: String, b: Basis) -> void:
	var i: int = idx[bone]
	var pt: Transform3D = g[names[parent[i]]]
	g[bone] = Transform3D(b.orthonormalized(), pt * (lrest[i] as Transform3D).origin)

## Two-bone IK: `up` and `lo` reach `target` (where `end` begins), the middle joint toward `pole`, the lower bone
## turned about the rig's hinge only.
func _two_bone(g: Dictionary, up: String, lo: String, end: String, target: Vector3, pole: Vector3) -> void:
	var iu: int = idx[up]
	var il: int = idx[lo]
	var ie: int = idx[end]
	var pt: Transform3D = g[names[parent[iu]]]
	var a: Vector3 = pt * (lrest[iu] as Transform3D).origin
	var l1 := (lrest[il] as Transform3D).origin.length()
	var l2 := (lrest[ie] as Transform3D).origin.length()
	var to := target - a
	var dist := clampf(to.length(), absf(l1 - l2) + 0.01, (l1 + l2) * 0.9985)
	var dc := to.normalized()
	var pp := pole - dc * pole.dot(dc)
	if pp.length() < 0.001:
		pp = Vector3(0, 0, 1) - dc * dc.z
	pp = pp.normalized()
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var b := a + dc * l1 * ca + pp * l1 * sqrt(1.0 - ca * ca)
	var c := a + dc * dist
	var d1 := (b - a).normalized()
	var d2 := (c - b).normalized()
	var n := d1.cross(d2)
	if n.length() < 0.0001:
		n = d1.cross(pp)
	n = n.normalized()
	var h: Vector3 = (HINGE[lo] as Vector3).normalized()
	var lr: Basis = (lrest[il] as Transform3D).basis
	var hu := lr * h
	var f_local := frame(Vector3.UP, hu)
	var f_world := frame(d1, n)
	var gu := f_world * f_local.transposed()
	_place(g, up, gu)
	# the lower bone: about the hinge until it points at the target
	var base := gu * lr
	var want := base.inverse() * d2
	var y := Vector3.UP
	var py := (y - h * y.dot(h)).normalized()
	var pw := (want - h * want.dot(h)).normalized()
	var th := atan2(h.dot(py.cross(pw)), py.dot(pw))
	_place(g, lo, base * Basis(h, th))

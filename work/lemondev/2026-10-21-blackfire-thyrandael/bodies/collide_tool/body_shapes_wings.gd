extends RefCounted
## Collision shapes of a hero or unit model, fitted to its own mesh (run 2026-10-18: "nothing may pass through
## anything"). Used by tests/tools/body_collide.gd to measure and remove interpenetration in every clip.
##
##   * Body: one solid capsule per bone with an elliptic cross-section (the torso is wider than it is deep), fitted to
##     the skin each bone carries in the rest pose: the vertices whose largest weight is that bone, between its joint and
##     the next. It is centred on that skin (a chest swells in front of the spine) and spans its 7th to 93rd
##     percentile across (a loose flap does not swell it), scaled by SHRINK, so a touch is not a hit.
##   * Weapons: the held weapon's own vertices, thinned to one point per GRID cube, each a small sphere.
##   * Movers (what is pushed out): points along the distal upper arm, the forearm and the hand, and the weapon points.
##     Obstacles: the torso, neck, head, thighs, shins, feet, the other arm, and the floor.
##
## Everything is in skeleton space; a shape stores its frame in its bone's space, so a pose moves it with the bone.

const SHRINK := 0.9
const GRID := 0.035                       # metres between weapon sample points
const TRUNK := ["hips", "spine", "chest", "neck", "head"]
const LEGS := ["thigh", "shin", "foot"]
const ARM := ["upper_arm", "forearm", "hand"]
const NEXT := {"hips": "spine", "spine": "chest", "chest": "neck", "neck": "head", "upper_arm": "forearm",
	"forearm": "hand", "thigh": "shin", "shin": "foot", "foot": "toe"}

## Unreal-style names (Roydo's and Blau's rigs) for the hero skeleton's bones
const ALIAS := {"hips": "pelvis", "spine": "spine_01", "chest": "spine_03", "neck": "neck_01", "head": "Head",
	"shoulder.L": "clavicle_l", "upper_arm.L": "upperarm_l", "forearm.L": "lowerarm_l", "hand.L": "hand_l",
	"thigh.L": "thigh_l", "shin.L": "calf_l", "foot.L": "foot_l", "toe.L": "ball_l",
	"shoulder.R": "clavicle_r", "upper_arm.R": "upperarm_r", "forearm.R": "lowerarm_r", "hand.R": "hand_r",
	"thigh.R": "thigh_r", "shin.R": "calf_r", "foot.R": "foot_r", "toe.R": "ball_r"}

## A hero skeleton bone's index on this rig (its own name, else its Unreal-style name), -1 when missing.
static func find(p_sk: Skeleton3D, name: String) -> int:
	var i := p_sk.find_bone(name)
	if i < 0 and ALIAS.has(name):
		i = p_sk.find_bone(String(ALIAS[name]))
	return i

## bone name -> {bone: index, xf: Transform3D (shape frame in the bone's space; +Y along the bone), y0, y1, rx, rz}
var shapes := {}
## side -> PackedVector3Array of weapon points in the weapon bone's space ([] when it holds nothing)
var weapon_pts := {"L": PackedVector3Array(), "R": PackedVector3Array()}
var weapon_r := GRID * 0.5
var sk: Skeleton3D
var height := 1.8

## Fit the body shapes of `model` (an instanced scene holding a Skeleton3D and skinned meshes).
func fit(model: Node, p_sk: Skeleton3D) -> void:
	sk = p_sk
	var verts := PackedVector3Array()
	var owner_bone := PackedInt32Array()
	var inv := sk.global_transform.affine_inverse()
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.skin == null:
			continue
		var skin := mi.skin
		var bind_bone := PackedInt32Array()
		for b in skin.get_bind_count():
			var bb := skin.get_bind_bone(b)
			if bb < 0:
				bb = sk.find_bone(String(skin.get_bind_name(b)))
			bind_bone.append(bb)
		var to_sk := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var ws = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or ws == null or vs.is_empty():
				continue
			var per := int(bones.size() / vs.size())
			for i in vs.size():
				var best := -1
				var bw := 0.0
				for k in per:
					var w := float(ws[i * per + k])
					if w > bw:
						bw = w
						best = int(bones[i * per + k])
				if best < 0 or best >= bind_bone.size():
					continue
				verts.append(to_sk * vs[i])
				owner_bone.append(bind_bone[best])
	# a finger, a twist bone or a middle spine bone counts for its nearest ancestor that gets a shape
	var shaped := {}
	for b in TRUNK:
		shaped[find(sk, b)] = true
	for side in ["L", "R"]:
		for b in ARM + LEGS:
			shaped[find(sk, b + "." + side)] = true
	var up := {}
	for i in sk.get_bone_count():
		var j := i
		while j >= 0 and not shaped.has(j):
			j = sk.get_bone_parent(j)
		up[i] = j
	for i in owner_bone.size():
		owner_bone[i] = int(up.get(owner_bone[i], owner_bone[i]))
	var top := -1e9
	var bottom := 1e9
	for v in verts:
		top = maxf(top, v.y)
		bottom = minf(bottom, v.y)
	height = maxf(0.5, top - bottom)
	var names := []
	for b in TRUNK:
		names.append(b)
	for s in ["L", "R"]:
		for b in ARM + LEGS:
			names.append(b + "." + s)
	for name in names:
		var bi := find(sk, name)
		if bi < 0:
			continue
		var base := String(name).get_slice(".", 0)
		var side := ("." + String(name).get_slice(".", 1)) if String(name).contains(".") else ""
		var g := sk.get_bone_global_rest(bi)
		var a := g.origin
		var pts := PackedVector3Array()
		for i in verts.size():
			if owner_bone[i] == bi:
				pts.append(verts[i])
		if pts.size() < 8:
			continue
		var b: Vector3
		var nxt := String(NEXT.get(base, ""))
		var ni := find(sk, nxt + side) if nxt != "" else -1
		if nxt == "head":
			ni = find(sk, "head")
		if ni >= 0:
			b = sk.get_bone_global_rest(ni).origin
		else:
			# the head and the hands end where their skin ends, along the bone
			var dir := (g.basis.y).normalized()
			var far := 0.0
			for p in pts:
				far = maxf(far, (p - a).dot(dir))
			b = a + dir * maxf(far, 0.05)
		var axis := b - a
		if axis.length() < 0.01:
			continue
		axis = axis.normalized()
		# the shape's frame: +Y along the bone, X as close to the bone's own X as can be
		var x := g.basis.x.normalized()
		x = (x - axis * x.dot(axis))
		if x.length() < 1e-3:
			x = axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT)
		x = x.normalized()
		var z := x.cross(axis).normalized()
		var frame := Transform3D(Basis(x, axis, z), a)
		var finv := frame.affine_inverse()
		var L := a.distance_to(b)
		# the hips bone is short (to the spine) and the pelvis hangs below its joint
		var below := 0.24 * height / 1.8 if base == "hips" else 0.1 * L
		var ts := PackedFloat32Array()
		var xs := PackedFloat32Array()
		var zs := PackedFloat32Array()
		for p in pts:
			var q := finv * p
			if q.y < -below or q.y > 1.1 * L:
				continue
			# wings riding the chest (run 2026-10-21): the trunk is what lies near its bone line
			if base in TRUNK and (absf(q.x) > 0.30 * height / 1.8 or absf(q.z) > 0.17 * height / 1.8):
				continue
			ts.append(q.y)
			xs.append(q.x)
			zs.append(q.z)
		if ts.size() < 8:
			continue
		# the skin's own middle, not the bone's line: a spine runs near the back, a chest swells in front of it
		var x0 := _pct(xs, 0.07)
		var x1 := _pct(xs, 0.93)
		var z0 := _pct(zs, 0.07)
		var z1 := _pct(zs, 0.93)
		var rx := (x1 - x0) * 0.5 * SHRINK
		var rz := (z1 - z0) * 0.5 * SHRINK
		var y0 := maxf(_pct(ts, 0.03), 0.0 if base != "hips" else -below)
		var y1 := minf(_pct(ts, 0.97), L)
		var centred := frame * Transform3D(Basis(), Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5))
		shapes[name] = {"bone": bi, "xf": g.affine_inverse() * centred, "y0": y0, "y1": y1,
			"rx": maxf(rx, 0.015), "rz": maxf(rz, 0.015), "name": name}

## The weapon held on `side`: its mesh points in the weapon bone's space (prop_transform applied).
func fit_weapon(side: String, scene: PackedScene, prop: Transform3D) -> void:
	if scene == null:
		return
	var w: Node3D = scene.instantiate()
	var seen := {}
	var out := PackedVector3Array()
	for mi: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		# the node's place inside the weapon scene
		var xf := Transform3D()
		var n: Node = mi
		while n != null and n != w:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		xf = prop * xf
		for s in mi.mesh.get_surface_count():
			var vs: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in vs:
				var p := xf * v
				var key := Vector3i(floori(p.x / GRID), floori(p.y / GRID), floori(p.z / GRID))
				if seen.has(key):
					continue
				seen[key] = true
				out.append(p)
	w.free()
	weapon_pts[side] = out

static func _pct(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(q * (s.size() - 1)), 0, s.size() - 1)]

## The shape's world frame for a pose ({bone index: global pose}).
func frame_of(name: String, pose: Dictionary) -> Transform3D:
	var sh: Dictionary = shapes[name]
	return (pose[int(sh.bone)] as Transform3D) * (sh.xf as Transform3D)

## How far point p (with radius r) is inside shape `name` at this pose: the push that takes it out (zero outside).
func push(name: String, frame: Transform3D, p: Vector3, r: float) -> Vector3:
	var sh: Dictionary = shapes[name]
	var q := frame.affine_inverse() * p
	var y0 := float(sh.y0)
	var y1 := float(sh.y1)
	var rx := float(sh.rx) + r
	var rz := float(sh.rz) + r
	var rc := minf(rx, rz)
	var c := clampf(q.y, y0, y1)
	var d := Vector3(q.x / rx, (q.y - c) / rc, q.z / rz)
	var e := d.length()
	if e >= 1.0:
		return Vector3.ZERO
	if e < 1e-4:
		d = Vector3(0, 0, 1)
		e = 1e-4
	# out along the scaled direction, to the surface
	var surf := Vector3(d.x / e * rx, c + d.y / e * rc, d.z / e * rz)
	var out_local := surf - q
	return frame.basis * out_local

## A bounding sphere of a shape (for a quick reject): centre, radius.
func bound(name: String, frame: Transform3D) -> Array:
	var sh: Dictionary = shapes[name]
	var c := frame * Vector3(0, (float(sh.y0) + float(sh.y1)) * 0.5, 0)
	var r := (float(sh.y1) - float(sh.y0)) * 0.5 + maxf(float(sh.rx), float(sh.rz))
	return [c, r]

## The obstacles for side `s`'s arm, hand and weapon.
func obstacles_for(s: String) -> Array:
	var o := "R" if s == "L" else "L"
	var out: Array = []
	for b in TRUNK:
		if shapes.has(b):
			out.append(b)
	for side in ["L", "R"]:
		for b in LEGS:
			if shapes.has(b + "." + side):
				out.append(b + "." + side)
	for b in ARM:
		if shapes.has(b + "." + o):
			out.append(b + "." + o)
	return out

## The radius of a mover point on arm bone `b` (its own fitted size).
func arm_radius(b: String) -> float:
	if not shapes.has(b):
		return 0.04 * height / 1.8
	var sh: Dictionary = shapes[b]
	return minf(float(sh.rx), float(sh.rz)) * 0.85

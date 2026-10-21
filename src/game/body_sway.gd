class_name BodySway
extends SkeletonModifier3D
## A hero's own moving parts that the clips do not carry (run 2026-10-21 b; the owner: every hero has some of its own
## animation and rigging): wings that beat, open and fold; and bone chains (branches, cloth) that swing with the body
## through a SpringBoneSimulator3D, colliding with the legs so they never pass through them.
##
## ModelCatalog entry "sway":
##   "wings": {"L": bone, "R": bone, "tips": [boneL, boneR] (optional), "axis": Vector3 (local axis a wing opens
##     about; the right wing turns the other way), "open": degrees at rest, "beat": degrees of a beat, "rate": beats
##     a second while moving}
##   "chains": [{"root": bone, "end": bone, "stiffness": 0..4, "drag": 0..1, "gravity": m/s2, "radius": m,
##     "collide": [{"bone": name, "radius": m, "height": m}]}]
## UnitView sets `moving` (0..1, how fast it travels), `airborne` (gliding or flying) and `dead` each frame.

var moving := 0.0
var airborne := false
var dead := false
var _cfg := {}
var _wing := {}                                      # "L"/"R" -> [bone, tip bone or -1]
var _axis := Vector3.FORWARD
var _open := 0.0
var _beat := 0.0
var _rate := 1.0
var _t := 0.0
var _phase := 0.0
var _fold := 0.0                                     # 0 open .. 1 folded (eased)

## Add the sway parts a catalog entry asks for to a model's skeleton (once per model).
static func attach(sk: Skeleton3D, cfg: Dictionary) -> BodySway:
	var sw: Dictionary = cfg.get("sway", {})
	if sk == null or sw.is_empty():
		return null
	for c in (sw.get("chains", []) as Array):
		_chain(sk, c)
	if not sw.has("wings"):
		return null
	var m := BodySway.new()
	m.name = "BodySway"
	m._cfg = sw.wings
	sk.add_child(m)
	m._setup(sk)
	return m

static func _chain(sk: Skeleton3D, c: Dictionary) -> void:
	var root := sk.find_bone(String(c.root))
	var end := sk.find_bone(String(c.end))
	if root < 0 or end < 0:
		return
	var sim := SpringBoneSimulator3D.new()
	sim.name = "Sway_" + String(c.root)
	sk.add_child(sim)
	sim.setting_count = 1
	sim.set_root_bone(0, root)
	sim.set_end_bone(0, end)
	sim.set_extend_end_bone(0, true)
	sim.set_end_bone_length(0, float(c.get("tip", 0.12)))
	sim.set_radius(0, float(c.get("radius", 0.06)))
	sim.set_stiffness(0, float(c.get("stiffness", 1.2)))
	sim.set_drag(0, float(c.get("drag", 0.45)))
	sim.set_gravity(0, float(c.get("gravity", 0.4)))
	sim.set_enable_all_child_collisions(0, true)
	for col in (c.get("collide", []) as Array):
		var b := sk.find_bone(String(col.bone))
		if b < 0:
			continue
		var cap := SpringBoneCollisionCapsule3D.new()
		sim.add_child(cap)
		cap.set_bone(b)
		cap.radius = float(col.get("radius", 0.08))
		cap.height = float(col.get("height", 0.4))
		# the capsule runs along the bone (Godot bones point along +Y), centred half way down it
		cap.position_offset = Vector3(0, float(col.get("height", 0.4)) * 0.5, 0)
		cap.rotation_offset = Quaternion.IDENTITY

func _setup(sk: Skeleton3D) -> void:
	_axis = (_cfg.get("axis", Vector3.FORWARD) as Vector3).normalized()
	_open = deg_to_rad(float(_cfg.get("open", 0.0)))
	_beat = deg_to_rad(float(_cfg.get("beat", 35.0)))
	_rate = float(_cfg.get("rate", 1.6))
	var tips: Array = _cfg.get("tips", ["", ""])
	for i in 2:
		var side := ["L", "R"][i] as String
		var b := sk.find_bone(String(_cfg.get(side, "")))
		if b >= 0:
			_wing[side] = [b, sk.find_bone(String(tips[i])) if i < tips.size() else -1]
	_phase = randf() * TAU

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _wing.is_empty():
		return
	# beats come faster and deeper the faster he moves; at rest a slow breath; dead: folded
	var speed := clampf(moving, 0.0, 1.0)
	var rate := _rate * (0.35 + 0.65 * speed) * (1.15 if airborne else 1.0)
	_t += delta * rate * TAU
	_fold = move_toward(_fold, 1.0 if dead else 0.0, delta * 1.5)
	var depth := _beat * (0.25 + 0.75 * speed)
	# a beat: a fast down stroke and a slower up stroke (the sine skewed), the tips lagging the roots
	var s := sin(_t + _phase)
	var stroke := s * (0.75 + 0.25 * signf(s))
	var lag := sin(_t + _phase - 0.9)
	for side in _wing:
		var sign := -1.0 if side == "R" else 1.0
		var pair: Array = _wing[side]
		var b := int(pair[0])
		var ang := lerpf(_open + stroke * depth, -0.6, _fold)
		sk.set_bone_pose_rotation(b, sk.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(_axis * sign, ang))
		var tip := int(pair[1])
		if tip >= 0:
			var ta := lerpf(lag * depth * 0.6, -0.4, _fold)
			sk.set_bone_pose_rotation(tip, sk.get_bone_rest(tip).basis.get_rotation_quaternion() * Quaternion(_axis * sign, ta))

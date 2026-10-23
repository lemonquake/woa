extends SceneTree
## Builds the hand-made hero clips (run 2026-10-23) into assets/characters/hero/hand/hero_hand.res and hand_meta.json.
## Each hero's set is a script in tools/anim/ (clips_<hero>.gd) that describes poses with HandRig controls: key poses
## eased into each other, or a function of time (the run, whose feet stay planted on the ground). Every clip is solved
## on that hero's own skeleton, 30 frames a second, so the feet and grips land where they are written.
##   godot --headless --path . -s tools/anim/hand_clips.gd -- [--heroes=dracoxinia,emelrich] [--clips=a,b]
## Unlike the motion-capture library (Mixamo's, kept out of git), these clips are ours and are committed.

const Rig := preload("res://tools/anim/hand_rig.gd")
const Shapes := preload("res://tests/tools/body_shapes.gd")
const DIR := "res://assets/characters/hero/hand/"
const LIB := DIR + "hero_hand.res"
const META := DIR + "hand_meta.json"
const FPS := 30.0
const SETS := {"dracoxinia": "res://tools/anim/clips_dracoxinia.gd", "emelrich": "res://tools/anim/clips_emelrich.gd"}

var _heroes: Array = []
var _only: Array = []

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--heroes="):
			_heroes = Array(a.substr(9).split(",", false))
		elif a.begins_with("--clips="):
			_only = Array(a.substr(8).split(",", false))
	if _heroes.is_empty():
		_heroes = SETS.keys()
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var lib: AnimationLibrary = load(LIB) if ResourceLoader.exists(LIB) else AnimationLibrary.new()
	lib = lib.duplicate(true) if lib != null else AnimationLibrary.new()
	var meta := {"fps": FPS, "generator": "tools/anim/hand_clips.gd", "animations": {}}
	if FileAccess.file_exists(META):
		var old = JSON.parse_string(FileAccess.get_file_as_string(META))
		if old is Dictionary and old.has("animations"):
			meta.animations = old.animations
	for hero in _heroes:
		var set_script: GDScript = load(String(SETS[hero]))
		var cs = set_script.new()
		var body: Node = (load(String(cs.BODY)) as PackedScene).instantiate()
		root.add_child(body)
		var sk: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
		var rig = Rig.new()
		rig.setup(sk)
		# the body's own shapes and its weapon, so the grips keep arms and blade out of the body
		var shp = Shapes.new()
		shp.fit(body, sk)
		var wname: String = cs.WEAPON
		if wname != "":
			shp.fit_weapon("R", ModelCatalog.weapon(wname), ModelCatalog.prop_transform(ModelCatalog.MODELS.get("hero_" + hero, {}), "R"))
			var all: PackedVector3Array = shp.weapon_pts["R"]
			var few: Array = []
			var step := maxi(1, all.size() / 14)
			for i in range(0, all.size(), step):
				few.append(all[i])
			rig._wpts["R"] = few
		rig.shapes = shp
		cs.rig = rig
		var clips: Dictionary = cs.clips()
		rig.grip_prior = null
		for name in clips:
			if not _only.is_empty() and not (name in _only):
				continue
			var spec: Dictionary = clips[name]
			var a := _bake(rig, spec)
			if rig.grip_prior == null and bool(spec.get("loop", false)) and String(name).ends_with("_idle"):
				# the idle's grip (frame 0, the hand against its forearm) is the one the other clips lean to
				var c0 := _with_grip(rig, spec)
				c0["_capture_prior"] = true
				rig.solve(c0)
			if lib.has_animation(name):
				lib.remove_animation(name)
			lib.add_animation(name, a)
			var m := {"length": snappedf(a.length, 0.0001), "loop": bool(spec.get("loop", false))}
			for k in ["hits", "release", "airborne"]:
				if spec.has(k):
					m[k] = spec[k]
			if spec.has("ground_speed"):
				# the view scales a clip's ground speed by the body's leg length (MocapClips.leg_scale): store it for
				# the library's reference legs, so this body's feet stay planted
				m["ground_speed"] = snappedf(float(spec.ground_speed) / rig.leg_k, 0.001)
			meta.animations[name] = m
			print("%s: %s %.2f s %s" % [hero, name, a.length, str(m)])
		body.queue_free()
	lib.set_meta("hips_rest", Vector3(0, Rig.REF_HIPS, 0))
	var err := ResourceSaver.save(lib, LIB, ResourceSaver.FLAG_COMPRESS)
	var f := FileAccess.open(META, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t", true))
	f.close()
	print("saved ", LIB, " (", lib.get_animation_list().size(), " clips) err ", err)
	quit(0 if err == OK else 1)

## Samples a clip spec: {length, loop, pose: Callable(t) -> controls}, at 30 frames a second.
func _bake(rig, spec: Dictionary) -> Animation:
	var length := float(spec.length)
	var loop := bool(spec.get("loop", false))
	var n := int(round(length * FPS))
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracks := {}
	var pos_t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pos_t, NodePath("Skeleton3D:hips"))
	var bones: Array = []
	for b in rig.names:
		if b == "root" or String(b).begins_with("weapon"):
			continue
		bones.append(b)
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:" + String(b)))
		tracks[b] = t
	var prev := {}
	var worst := 0.0
	var worst_at := ""
	var pose: Callable = spec.pose
	rig.last_edge.clear()
	rig.last_pole.clear()
	if bool(spec.get("loop", false)):
		rig.solve(pose.call(maxf(0.0, length - 1.0 / FPS)))   # a loop's first frame follows on from its last
	var grips := _plan_grips(rig, pose, length, loop, n)
	for i in n + 1:
		var tt := minf(float(i) / FPS, length)
		var c: Dictionary = pose.call(tt if not (loop and i == n) else 0.0)
		if not grips.is_empty():
			c["_grip"] = grips[0 if (loop and i == n) else i]
		var p: Dictionary = rig.solve(c)
		var miss := float((p._g as Dictionary).get("_miss", 0.0))
		if miss > worst:
			worst = miss
			worst_at = "%s at %.2f s" % [(p._g as Dictionary).get("_miss_at", ""), tt]
		var hips_off: Vector3 = (p.hips as Transform3D).origin - (rig.lrest[rig.idx.hips] as Transform3D).origin
		a.position_track_insert_key(pos_t, tt, hips_off / rig.leg_k)
		for b in bones:
			var q := (p[b] as Transform3D).basis.get_rotation_quaternion()
			if prev.has(b) and (prev[b] as Quaternion).dot(q) < 0.0:
				q = -q                              # keep the shortest way between keys
			prev[b] = q
			a.rotation_track_insert_key(tracks[b], tt, q)
	if worst > 0.01:
		print("  out of reach by %.1f cm: %s" % [worst * 100.0, worst_at])
	return a

## The sword grips of a whole clip, chosen together: every frame scores each grip it could take (the turn of the hand
## about the blade, measured from a reference carried along with the blade so "the same turn" means the same from frame
## to frame, and each elbow's swing: HandRig.grip_costs), then the path through the frames with the least cost plus
## the least change between frames wins (dynamic programming), so a grip never jumps. A loop is planned over two rounds
## and takes the second, so its end runs into its start. [] for a clip without a sword.
func _plan_grips(rig, pose: Callable, length: float, loop: bool, n: int) -> Array:
	var c0: Dictionary = pose.call(0.0)
	if not c0.has("sword"):
		return []
	var nr: int = rig.NR
	var ns: int = rig.NS
	var count := n if loop else n + 1
	var times: Array = []
	for r in (2 if loop else 1):
		for i in count:
			times.append(minf(float(i) / FPS, length))
	var refs: Array = []
	var costs: Array = []
	var ref := Vector3.ZERO
	for t in times:
		var c: Dictionary = pose.call(t)
		var probe := {"ref": ref if ref != Vector3.ZERO else Vector3(0.3, 0.9, 0.3), "out": PackedFloat32Array()}
		c["_costs"] = probe
		rig.solve(c)
		var by: Vector3 = probe.by
		var r0: Vector3 = probe.ref
		if absf(r0.normalized().dot(by)) > 0.98:
			r0 = Vector3.RIGHT if absf(by.x) < 0.9 else Vector3.FORWARD
		ref = (r0 - by * r0.dot(by)).normalized()
		refs.append(ref)
		costs.append(probe.out)
	var size := nr * ns * ns
	var step_k := 2.0 * TAU / nr                 # the cost of turning the grip one step between two frames
	var step_j := 1.0 * deg_to_rad(20.0)          # and of swinging an elbow one step
	var d: PackedFloat32Array = costs[0]
	var back: Array = []                         # per frame: [arg over k, arg over j1, arg over j2]
	for f in range(1, costs.size()):
		var m1 := PackedFloat32Array()
		m1.resize(size)
		var a1 := PackedInt32Array()
		a1.resize(size)
		for j in ns * ns:
			for k in nr:
				var best := INF
				var arg := 0
				for k2 in nr:
					var dk := absi(k - k2)
					dk = mini(dk, nr - dk)
					var v := d[k2 * ns * ns + j] + step_k * dk
					if v < best:
						best = v
						arg = k2
				m1[k * ns * ns + j] = best
				a1[k * ns * ns + j] = arg
		var m2 := PackedFloat32Array()
		m2.resize(size)
		var a2 := PackedInt32Array()
		a2.resize(size)
		for k in nr:
			for j2 in ns:
				for j1 in ns:
					var best2 := INF
					var arg2 := 0
					for j1b in ns:
						var v2 := m1[k * ns * ns + j1b * ns + j2] + step_j * absi(j1 - j1b)
						if v2 < best2:
							best2 = v2
							arg2 = j1b
					m2[k * ns * ns + j1 * ns + j2] = best2
					a2[k * ns * ns + j1 * ns + j2] = arg2
		var m3 := PackedFloat32Array()
		m3.resize(size)
		var a3 := PackedInt32Array()
		a3.resize(size)
		var cf: PackedFloat32Array = costs[f]
		for k in nr:
			for j1 in ns:
				for j2 in ns:
					var best3 := INF
					var arg3 := 0
					for j2b in ns:
						var v3 := m2[k * ns * ns + j1 * ns + j2b] + step_j * absi(j2 - j2b)
						if v3 < best3:
							best3 = v3
							arg3 = j2b
					m3[k * ns * ns + j1 * ns + j2] = best3 + cf[k * ns * ns + j1 * ns + j2]
					a3[k * ns * ns + j1 * ns + j2] = arg3
		back.append([a1, a2, a3])
		d = m3
	# the cheapest end, then back through the frames
	var s_best := 0
	for i in size:
		if d[i] < d[s_best]:
			s_best = i
	var path := PackedInt32Array()
	path.resize(costs.size())
	path[costs.size() - 1] = s_best
	for f in range(costs.size() - 1, 0, -1):
		var st := path[f]
		var k := st / (ns * ns)
		var j1 := (st / ns) % ns
		var j2 := st % ns
		var bk: Array = back[f - 1]
		var j2p: int = (bk[2] as PackedInt32Array)[k * ns * ns + j1 * ns + j2]
		var j1p: int = (bk[1] as PackedInt32Array)[k * ns * ns + j1 * ns + j2p]
		var kp: int = (bk[0] as PackedInt32Array)[k * ns * ns + j1p * ns + j2p]
		path[f - 1] = kp * ns * ns + j1p * ns + j2p
	var out: Array = []
	var start := count if loop else 0
	for i in count:
		var st2 := path[start + i]
		out.append({"ref": refs[start + i], "k": st2 / (ns * ns), "j1": (st2 / ns) % ns, "j2": st2 % ns})
	if not loop:
		return out
	return out

## A clip's first pose with the grip its whole-clip plan chose for it (to read the idle's grip back).
func _with_grip(rig, spec: Dictionary) -> Dictionary:
	var pose: Callable = spec.pose
	var n := int(round(float(spec.length) * FPS))
	var plan := _plan_grips(rig, pose, float(spec.length), bool(spec.get("loop", false)), n)
	var c: Dictionary = pose.call(0.0)
	if not plan.is_empty():
		c["_grip"] = plan[0]
	return c

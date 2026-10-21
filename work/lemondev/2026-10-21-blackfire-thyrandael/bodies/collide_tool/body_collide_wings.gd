## Run 2026-10-21 copy of tests/tools/body_collide.gd for winged bodies: it uses body_shapes_wings.gd (trunk shapes
## ignore skin far out from the bone line: Thyrandael's wings ride the chest and swelled it to 1.2 m).
extends SceneTree
## Body collision for every clip a hero uses (run 2026-10-18, the owner: "body parts or anything they hold should never
## go through anything"). Shapes come from each model's own mesh (tests/tools/body_shapes.gd): solid capsules for the
## torso, head, legs and arms, sphere clouds for the weapons. Every clip is played at 30 frames a second and every
## frame is tested: the upper arm, forearm, hand and the held weapon against the torso, neck, head, legs, the other
## arm and the floor.
##
##   godot --headless --path . -s tests/tools/body_collide.gd -- --heroes=azrael,ezee [--fix] [--clips=a,b] [--report=f]
##     (no --heroes: every hero; --units: every humanoid unit model instead; --fix writes the corrected clip set and
##     checks again; --applied measures the clips as the game plays them, with the saved set laid over)
##
## The fix re-solves each arm wherever something is inside something, frame by frame:
##   * a hand or forearm inside: the wrist target moves out along the push (two-bone IK from the shoulder, the elbow on
##     its own side of the arm, the bones keeping their twist);
##   * a weapon inside: the hand turns about the wrist until the weapon clears (the push's turning moment);
##   * an elbow inside: the elbow swings round the shoulder-wrist line, away from the body;
##   * two hands on one weapon move and turn together, so the grip holds;
##   * the corrections are spread over the neighbouring frames (held 2 frames either side, then blurred), so an arm
##     eases out instead of popping, then each frame is checked and nudged again.
## The corrected upper arm, forearm and hand tracks go to <model dir>/anim_fixed/<model>_collide.res, which
## RepairedClips lays over the clips after the arm repair.

const FPS := 30.0
const Shapes := preload("res://work/lemondev/2026-10-21-blackfire-thyrandael/bodies/collide_tool/body_shapes_wings.gd")
const ITER := 16
const ROUNDS := 5
const TOL := 0.004                         # metres: deeper than this is a hit
const HIT_CM := 1.0                        # the report counts frames deeper than this (cm)

var _heroes: Array = []
var _clips_only: Array = []
var _fix := false
var _report := ""
var _lines: Array = []
var _units := false
var _applied := false                      # measure the clips as the game plays them (with the collision set)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--heroes="):
			_heroes = Array(a.substr(9).split(",", false))
		elif a.begins_with("--clips="):
			_clips_only = Array(a.substr(8).split(",", false))
		elif a == "--fix":
			_fix = true
		elif a.begins_with("--report="):
			_report = a.substr(9)
		elif a == "--units":
			_units = true
		elif a == "--applied":
			_applied = true
	if _heroes.is_empty() and not _units:
		_heroes = Array(GameSettings.HEROES)
	_run.call_deferred()

func _say(s: String) -> void:
	print(s)
	_lines.append(s)

## model scene -> {clip: {R: weapon id, L: weapon id}} for the heroes asked for (a shared body gathers all its heroes'
## clips; a clip two heroes use with different weapons keeps the longer one)
func _plan() -> Dictionary:
	var plan := {}
	for id in _heroes:
		var cfg := ModelCatalog.info(String(SimData.unit(id).model))
		var own := String(id) in GameSettings.OWN_BODY
		var scene := String(cfg.scene) if own else HeroLook.MODEL
		if not plan.has(scene):
			plan[scene] = {"clips": {}, "float": float(cfg.get("float", 0.0)) if own else 0.0, "heroes": []}
		plan[scene].heroes.append(id)
		var clips: Array = [String(cfg.get("idle", "idle")), String(cfg.get("run", "run")), String(cfg.get("death", "death")),
			String(cfg.get("cast", ""))]
		for c in cfg.get("attack", []):
			clips.append(String(c))
		for c in [String(HeroStage.IDLE.get(id, "")), String(HeroStage.FLOURISH.get(id, "")), String(cfg.get("glide_clip", ""))]:
			clips.append(c)
		for aid in SimData.unit(id).abilities:
			clips.append(String(SimData.ability(String(aid)).get("anim", "")))
		# pushes, stuns and hit reactions (UnitView plays these for every hero; run 2026-10-18 e: they were never checked)
		clips.append_array(["knockback", "getup", "launch", "wall_impact", "hit_heavy", "hit_light", "hit_front", "idle_hurt",
			"leap_slam", "blink", "dodge_step"])
		# the motion-capture stand-ins (ModelCatalog.MOCAP), and the old clips they stand in for (kept fixed for a game
		# without the mocap library)
		var base := ModelCatalog.MODELS.get(String(SimData.unit(id).model), {}) as Dictionary
		for c in clips.duplicate():
			clips.append(ModelCatalog.anim(cfg, String(c)))
		for c in [String(base.get("idle", "")), String(base.get("death", "")), String(base.get("cast", ""))]:
			clips.append(c)
		for c in base.get("attack", []):
			clips.append(String(c))
		for c in cfg.get("deaths", []):
			clips.append(String(c))
		for c in clips:
			if c == "" or (not _clips_only.is_empty() and not (c in _clips_only)):
				continue
			var w := {"R": String(cfg.get("R", "")), "L": String(cfg.get("L", ""))}
			if plan[scene].clips.has(c):
				var old: Dictionary = plan[scene].clips[c]
				for s in ["R", "L"]:
					if String(old[s]) != "" and String(w[s]) == "":
						w[s] = old[s]
			plan[scene].clips[c] = w
	return plan

## Every humanoid unit model with the clips and weapons of the catalog entries that use it (--units).
func _unit_plan() -> Dictionary:
	var plan := {}
	for scene in RepairedClips.unit_models():
		for key in ModelCatalog.MODELS:
			var cfg: Dictionary = ModelCatalog.MODELS[key]
			if String(cfg.scene) != scene and String(cfg.get("scene_dusk", "")) != scene:
				continue
			if not plan.has(scene):
				plan[scene] = {"clips": {}, "float": 0.0, "heroes": []}
			plan[scene].heroes.append(key)
			var clips: Array = [String(cfg.get("idle", "idle")), String(cfg.get("run", "run")), String(cfg.get("death", "death")),
				String(cfg.get("cast", ""))]
			for c in cfg.get("attack", []):
				clips.append(String(c))
			for c in clips:
				if c != "" and (_clips_only.is_empty() or c in _clips_only):
					plan[scene].clips[c] = {"R": String(cfg.get("R", "")), "L": String(cfg.get("L", ""))}
	return plan

func _run() -> void:
	var plan := _unit_plan() if _units else _plan()
	for scene in plan:
		await _model(String(scene), plan[scene])
	if _report != "":
		var f := FileAccess.open(_report, FileAccess.WRITE)
		f.store_string("\n".join(_lines) + "\n")
	quit()

func _model(scene: String, info: Dictionary) -> void:
	RepairedClips.collide_disabled = not _applied
	RepairedClips._sets.clear()
	var m: Node3D = (load(scene) as PackedScene).instantiate()
	RepairedClips.patch(m)
	root.add_child(m)
	await process_frame
	var sks := m.find_children("*", "Skeleton3D", true, false)
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	if sks.is_empty() or aps.is_empty():
		_say("== %s: no skeleton or no clips, skipped" % scene.get_file())
		m.queue_free()
		RepairedClips.collide_disabled = false
		return
	var sk: Skeleton3D = sks[0]
	var ap: AnimationPlayer = aps[0]
	for b in ["chest", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R", "shoulder.L", "shoulder.R"]:
		if Shapes.find(sk, b) < 0:
			_say("== %s: no %s bone, skipped" % [scene.get_file(), b])
			m.queue_free()
			RepairedClips.collide_disabled = false
			return
	if Shapes.find(sk, "weapon.L") < 0 or Shapes.find(sk, "weapon.R") < 0:
		_say("   (no weapon bones: weapons not checked)")
	sk.reset_bone_poses()
	var sh := Shapes.new()
	sh.fit(m, sk)
	var names: Array = sh.shapes.keys()
	_say("== %s (%s): %d shapes, height %.2f m" % [scene.get_file(), ", ".join(info.heroes), names.size(), sh.height])
	for n in ["hips", "chest", "head", "forearm.L", "thigh.L"]:
		if sh.shapes.has(n):
			var d: Dictionary = sh.shapes[n]
			_say("   %-10s %.2f-%.2f m along, %.3f x %.3f" % [n, float(d.y0), float(d.y1), float(d.rx), float(d.rz)])
	var lib := AnimationLibrary.new()
	var worst_before := 0.0
	var worst_after := 0.0
	for clip in info.clips:
		if not ap.has_animation(clip):
			continue
		var w: Dictionary = info.clips[clip]
		for s in ["R", "L"]:
			sh.weapon_pts[s] = PackedVector3Array()
			var ps := ModelCatalog.weapon(String(w[s]))
			if ps:
				var cfg := _cfg_with_weapon(String(w[s]), s)
				sh.fit_weapon(s, ps, ModelCatalog.prop_transform(cfg, s))
		var solver := Solver.new(sh, sk, ap, String(clip), -float(info.float))
		solver.read()
		var before := solver.measure()
		worst_before = maxf(worst_before, float(before.worst))
		var line := "  %-18s before: worst %4.1f cm (%s), %d/%d frames over %.0f cm" % [clip, float(before.worst) * 100.0,
			before.where, int(before.bad), int(before.frames), HIT_CM]
		if _fix:
			var anim := solver.solve()
			lib.add_animation(clip, anim)
			var after := solver.measure()
			worst_after = maxf(worst_after, float(after.worst))
			line += " | after: worst %4.1f cm (%s), %d frames" % [float(after.worst) * 100.0, after.where, int(after.bad)]
		_say(line)
	if _fix:
		# the motion-capture clips' fixes go beside the mocap library (git leaves that folder out), the rest as before
		var mlib := AnimationLibrary.new()
		var mo := MocapClips.library()
		for clip in lib.get_animation_list():
			if mo and mo.has_animation(clip):
				mlib.add_animation(clip, lib.get_animation(clip))
		for clip in mlib.get_animation_list():
			lib.remove_animation(clip)
		var out := RepairedClips.collide_path(scene)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
		var err := ResourceSaver.save(lib, out)
		_say("  wrote %s (%s); worst %.1f cm -> %.1f cm" % [out, error_string(err), worst_before * 100.0, worst_after * 100.0])
		if not mlib.get_animation_list().is_empty():
			var mout := MocapClips.collide_path(scene)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(mout.get_base_dir()))
			err = ResourceSaver.save(mlib, mout)
			_say("  wrote %s (%s): %d mocap clips" % [mout, error_string(err), mlib.get_animation_list().size()])
	else:
		_say("  worst %.1f cm" % (worst_before * 100.0))
	m.queue_free()
	await process_frame
	RepairedClips.collide_disabled = false

## The catalog entry that holds this weapon on this side (for its prop transform).
func _cfg_with_weapon(wid: String, s: String) -> Dictionary:
	for key in ModelCatalog.MODELS:
		var cfg: Dictionary = ModelCatalog.MODELS[key]
		if String(cfg.get(s, "")) == wid:
			return cfg
	return {}


## One clip on one model: its frames, the hits, and the fix.
class Solver:
	var sh
	var sk: Skeleton3D
	var ap: AnimationPlayer
	var clip: String
	var floor_y := 0.0
	var a: Animation
	var n := 0
	var bi := {}
	var frames: Array = []                 # per frame: {bone index: global pose}
	var L1 := {}
	var L2 := {}
	var pair_dist := 0.3
	var paths := {}

	func _init(p_sh, p_sk: Skeleton3D, p_ap: AnimationPlayer, p_clip: String, p_floor: float) -> void:
		sh = p_sh
		sk = p_sk
		ap = p_ap
		clip = p_clip
		floor_y = p_floor
		a = ap.get_animation(clip)
		n = maxi(1, int(round(a.length * FPS)))
		for b in ["chest", "shoulder.L", "shoulder.R", "upper_arm.L", "forearm.L", "hand.L", "weapon.L",
				"upper_arm.R", "forearm.R", "hand.R", "weapon.R"]:
			bi[b] = Shapes.find(sk, b)
		for s in ["L", "R"]:
			var u := sk.get_bone_global_rest(int(bi["upper_arm." + s])).origin
			var f := sk.get_bone_global_rest(int(bi["forearm." + s])).origin
			var h := sk.get_bone_global_rest(int(bi["hand." + s])).origin
			L1[s] = u.distance_to(f)
			L2[s] = f.distance_to(h)
		pair_dist = 0.3 * float(sh.height) / 1.8
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				paths[String(a.track_get_path(t)).get_slice(":", 1)] = a.track_get_path(t)

	func read() -> void:
		ap.play(clip)
		ap.pause()
		frames.clear()
		for f in n + 1:
			ap.seek(minf(a.length, f / FPS), true)
			var fr := {}
			for i in sk.get_bone_count():
				fr[i] = sk.get_bone_global_pose(i)
			frames.append(fr)

	## Mover points of side s at a pose: [point, radius, group]
	func movers(fr: Dictionary, s: String) -> Array:
		var out: Array = []
		var U: Transform3D = fr[int(bi["upper_arm." + s])]
		var F: Transform3D = fr[int(bi["forearm." + s])]
		var H: Transform3D = fr[int(bi["hand." + s])]
		var ru: float = sh.arm_radius("upper_arm." + s)
		var rf: float = sh.arm_radius("forearm." + s)
		var rh: float = sh.arm_radius("hand." + s)
		for t in [0.55, 0.8]:
			out.append([U.origin.lerp(F.origin, t), ru, "elbow"])
		out.append([F.origin, rf, "elbow"])
		for t in [0.35, 0.65]:
			out.append([F.origin.lerp(H.origin, t), rf, "fore"])
		out.append([H.origin, rf, "fore"])
		var hname := "hand." + s
		if sh.shapes.has(hname):
			var fx: Transform3D = sh.frame_of(hname, fr)
			var d: Dictionary = sh.shapes[hname]
			for t in [0.5, 1.0]:
				out.append([fx * Vector3(0, lerpf(float(d.y0), float(d.y1), t), 0), rh, "hand"])
		else:
			out.append([H.origin + H.basis.y.normalized() * 0.08, rh, "hand"])
		var wp: PackedVector3Array = sh.weapon_pts[s]
		if not wp.is_empty() and int(bi["weapon." + s]) >= 0:
			var W: Transform3D = fr[int(bi["weapon." + s])]
			for p in wp:
				out.append([W * p, float(sh.weapon_r), "weapon"])
		return out

	## The pushes on side s's movers at a pose: [[point, push, group], ...] (only the ones inside)
	func hits(fr: Dictionary, s: String) -> Array:
		var o := "R" if s == "L" else "L"
		var out: Array = []
		var mv := movers(fr, s)
		var obs: Array = sh.obstacles_for(s)
		var two := _paired(fr)
		var frames_of := {}
		var bounds := {}
		for name in obs:
			var fx: Transform3D = sh.frame_of(String(name), fr)
			frames_of[name] = fx
			bounds[name] = sh.bound(String(name), fx)
		for m in mv:
			var p: Vector3 = m[0]
			var r: float = m[1]
			var g: String = m[2]
			var best := Vector3.ZERO
			var what := ""
			for name in obs:
				# a weapon held in both hands passes through the other hand and forearm, and the two gripping hands and
				# forearms touch
				if two and g != "elbow" and String(name).ends_with("." + o) and not String(name).begins_with("upper_arm"):
					continue
				var bd: Array = bounds[name]
				if p.distance_to(bd[0]) > float(bd[1]) + r:
					continue
				var v: Vector3 = sh.push(String(name), frames_of[name], p, r)
				if v.length() > best.length():
					best = v
					what = String(name)
			if g == "weapon" or g == "hand":
				var under := floor_y + r - p.y
				if under > best.length():
					best = Vector3(0, under, 0)
					what = "floor"
			if best.length() > TOL:
				out.append([p, best, g, what])
		return out

	func _paired(fr: Dictionary) -> bool:
		var hl: Transform3D = fr[int(bi["hand.L"])]
		var hr: Transform3D = fr[int(bi["hand.R"])]
		return hl.origin.distance_to(hr.origin) < pair_dist

	func measure(use: Array = []) -> Dictionary:
		var src: Array = frames if use.is_empty() else use
		var worst := 0.0
		var where := "-"
		var bad := 0
		for f in src.size():
			var fr: Dictionary = src[f]
			var fw := 0.0
			for s in ["L", "R"]:
				for h in hits(fr, s):
					var d: float = (h[1] as Vector3).length()
					if d > fw:
						fw = d
					if d > worst:
						worst = d
						where = "%s.%s in %s f%d" % [h[2], s, h[3], f]
			if fw > HIT_CM / 100.0:
				bad += 1
		return {"worst": worst, "where": where, "bad": bad, "frames": src.size()}

	## The arm of side s posed from a wrist target, a hand turn, and an elbow swing (radians round the shoulder-wrist
	## line), starting from the clip's frame; writes the new globals into fr2.
	func pose_arm(fr0: Dictionary, fr2: Dictionary, s: String, W: Vector3, Hb: Basis, swing: float) -> void:
		var iu := int(bi["upper_arm." + s])
		var i_f := int(bi["forearm." + s])
		var ih := int(bi["hand." + s])
		var iw := int(bi["weapon." + s])
		var U0: Transform3D = fr0[iu]
		var F0: Transform3D = fr0[i_f]
		var H0: Transform3D = fr0[ih]
		var S := U0.origin
		var l1: float = L1[s]
		var l2: float = L2[s]
		var d := W - S
		var D := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.002)
		var ax0 := (H0.origin - S).normalized()
		var ax := d.normalized() if d.length() > 1e-5 else ax0
		W = S + ax * D
		var pole0 := (F0.origin - S) - ax0 * (F0.origin - S).dot(ax0)
		var pole := pole0 - ax * pole0.dot(ax)
		if pole.length() < 1e-4:
			pole = (fr0[int(bi["chest"])] as Transform3D).basis.z.normalized()
			pole = pole - ax * pole.dot(ax)
		pole = pole.normalized().rotated(ax, swing)
		var x := (l1 * l1 - l2 * l2 + D * D) / (2.0 * D)
		var h := sqrt(maxf(0.0, l1 * l1 - x * x))
		var E := S + ax * x + pole * h
		var Ub := Basis(Quaternion((F0.origin - S).normalized(), (E - S).normalized())) * U0.basis.orthonormalized()
		var Fb := Basis(Quaternion((H0.origin - F0.origin).normalized(), (W - E).normalized())) * F0.basis.orthonormalized()
		fr2[iu] = Transform3D(Ub, S)
		fr2[i_f] = Transform3D(Fb, E)
		fr2[ih] = Transform3D(Hb, W)
		if iw >= 0:
			var wl: Transform3D = H0.affine_inverse() * (fr0[iw] as Transform3D)
			fr2[iw] = Transform3D(Hb, W) * wl

	## One frame's correction for both arms, from a starting correction c = {s: [dW, rot(axis*angle), swing]}:
	## pushes are turned into wrist moves, hand turns and elbow swings until nothing is inside (or ITER tries).
	func correct(f: int, c: Dictionary, iters: int) -> Dictionary:
		var fr0: Dictionary = frames[f]
		var c2 := {"L": (c.L as Array).duplicate(), "R": (c.R as Array).duplicate()}
		var two := _paired(fr0)
		for it in iters:
			var fr2 := apply(f, c2)
			var any := false
			var dW := {"L": Vector3.ZERO, "R": Vector3.ZERO}
			var tq := {"L": Vector3.ZERO, "R": Vector3.ZERO}
			var dsw := {"L": 0.0, "R": 0.0}
			for s in ["L", "R"]:
				var hs := hits(fr2, s)
				if hs.is_empty():
					continue
				any = true
				var Wp: Vector3 = (fr2[int(bi["hand." + s])] as Transform3D).origin
				var Sp: Vector3 = (fr2[int(bi["upper_arm." + s])] as Transform3D).origin
				var Ep: Vector3 = (fr2[int(bi["forearm." + s])] as Transform3D).origin
				var ax := (Wp - Sp).normalized()
				for h in hs:
					var p: Vector3 = h[0]
					var v: Vector3 = h[1]
					var g: String = h[2]
					if g == "hand" or g == "fore" or (g == "weapon" and p.distance_to(Wp) < 0.12):
						if v.length() > (dW[s] as Vector3).length():
							dW[s] = v
					elif g == "weapon":
						var arm := p - Wp
						var t := arm.cross(v) / maxf(arm.length_squared(), 1e-4)
						if t.length() > (tq[s] as Vector3).length():
							tq[s] = t
					else:
						var c0 := Sp + ax * (Ep - Sp).dot(ax)
						var rad := Ep - c0
						if rad.length() > 1e-3:
							var tang := ax.cross(rad.normalized())
							var dd := v.dot(tang) / rad.length()
							if absf(dd) > absf(float(dsw[s])):
								dsw[s] = dd
						# an arm across the chest: the whole arm turns out about the shoulder (the wrist moves as much
						# further as it is from the shoulder)
						var lever := clampf((Wp - Sp).length() / maxf((p - Sp).length(), 0.05), 1.0, 2.5)
						if v.length() * lever > (dW[s] as Vector3).length():
							dW[s] = v * lever
			if not any:
				break
			if two:
				# one weapon in both hands: one move, one turn for both (about the weapon hand's wrist)
				var big: Vector3 = dW.L if (dW.L as Vector3).length() > (dW.R as Vector3).length() else dW.R
				var tb: Vector3 = tq.L if (tq.L as Vector3).length() > (tq.R as Vector3).length() else tq.R
				dW = {"L": big, "R": big}
				tq = {"L": tb, "R": tb}
			for s in ["L", "R"]:
				var cs: Array = c2[s]
				cs[0] = (cs[0] as Vector3) + (dW[s] as Vector3) * 1.15
				var t: Vector3 = tq[s]
				var ang := minf(t.length() * 1.15, deg_to_rad(25.0))
				if ang > 1e-4:
					var r0: Vector3 = cs[1]
					var q := Quaternion(t.normalized(), ang) * _rv_quat(r0)
					cs[1] = _quat_rv(q)
				cs[2] = clampf(float(cs[2]) + clampf(float(dsw[s]) * 1.15, -0.3, 0.3), -1.6, 1.6)
		return c2

	## The frame's globals with correction c applied to both arms.
	func apply(f: int, c: Dictionary) -> Dictionary:
		var fr0: Dictionary = frames[f]
		var fr2 := fr0.duplicate()
		var two := _paired(fr0)
		# two hands on one weapon turn about the hand that carries it
		var ws := "L" if (sh.weapon_pts["R"] as PackedVector3Array).is_empty() and not (sh.weapon_pts["L"] as PackedVector3Array).is_empty() else "R"
		var pivot: Vector3 = (fr0[int(bi["hand." + ws])] as Transform3D).origin
		for s in ["L", "R"]:
			var cs: Array = c[s]
			var H0: Transform3D = fr0[int(bi["hand." + s])]
			var q := _rv_quat(cs[1])
			var Hb := Basis(q) * H0.basis.orthonormalized()
			var W: Vector3 = H0.origin
			if two:
				W = pivot + Basis(q) * (W - pivot)
			W += cs[0] as Vector3
			pose_arm(fr0, fr2, s, W, Hb, float(cs[2]))
		return fr2

	static func _rv_quat(v: Vector3) -> Quaternion:
		var ang := v.length()
		return Quaternion() if ang < 1e-6 else Quaternion(v / ang, ang)

	static func _quat_rv(q: Quaternion) -> Vector3:
		q = q.normalized()
		if q.w < 0.0:
			q = -q
		var ang := q.get_angle()
		return Vector3.ZERO if ang < 1e-6 else q.get_axis() * ang

	## The fix: raw corrections per frame, spread over time, checked and nudged again; returns the corrected tracks
	## and leaves the corrected frames in place of the clip's (for measure()).
	func solve() -> Animation:
		var loop := a.loop_mode != Animation.LOOP_NONE
		var cur: Array = []
		for f in frames.size():
			cur.append({"L": [Vector3.ZERO, Vector3.ZERO, 0.0], "R": [Vector3.ZERO, Vector3.ZERO, 0.0]})
		# rounds: what is still inside after a round is corrected again and spread again
		for round in ROUNDS:
			var delta: Array = []
			var left := 0
			for f in frames.size():
				var c := correct(f, cur[f], ITER)
				var d := {}
				for s in ["L", "R"]:
					var c0: Array = cur[f][s]
					var c1: Array = c[s]
					d[s] = [(c1[0] as Vector3) - (c0[0] as Vector3), (c1[1] as Vector3) - (c0[1] as Vector3),
						float(c1[2]) - float(c0[2])]
					if (d[s][0] as Vector3).length() > 1e-4 or (d[s][1] as Vector3).length() > 1e-4 or absf(float(d[s][2])) > 1e-4:
						left += 1
				delta.append(d)
			if left == 0:
				break
			var sm := _spread(delta, loop)
			for f in frames.size():
				for s in ["L", "R"]:
					var c0: Array = cur[f][s]
					var dd: Array = sm[f][s]
					cur[f][s] = [(c0[0] as Vector3) + (dd[0] as Vector3), (c0[1] as Vector3) + (dd[1] as Vector3),
						float(c0[2]) + float(dd[2])]
		var out_frames: Array = []
		for f in frames.size():
			out_frames.append(apply(f, correct(f, cur[f], ITER)))
		# tracks: the arm bones' local turns
		var anim := Animation.new()
		anim.length = a.length
		anim.loop_mode = a.loop_mode
		for s in ["L", "R"]:
			var ish := int(bi["shoulder." + s])
			for b in ["upper_arm", "forearm", "hand"]:
				var bone := "%s.%s" % [b, s]
				var real := sk.get_bone_name(int(bi[bone]))         # the rig's own name (upperarm_l on Unreal rigs)
				if not paths.has(real):
					continue
				var parent := ish if b == "upper_arm" else int(bi[("upper_arm." if b == "forearm" else "forearm.") + s])
				var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
				anim.track_set_path(tr, paths[real])
				anim.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
				var prev := Quaternion()
				for f in out_frames.size():
					var fr: Dictionary = out_frames[f]
					var P: Transform3D = fr[parent]
					var G: Transform3D = fr[int(bi[bone])]
					var q := (P.basis.orthonormalized().inverse() * G.basis.orthonormalized()).get_rotation_quaternion()
					if f > 0 and prev.dot(q) < 0.0:
						q = -q
					prev = q
					anim.rotation_track_insert_key(tr, minf(a.length, f / FPS), q)
		frames = out_frames
		return anim

	## Corrections held over 2 frames either side (the largest), then blurred, so an arm eases in and out.
	func _spread(raw: Array, loop: bool) -> Array:
		var m := raw.size()
		var held: Array = []
		for f in m:
			var c := {}
			for s in ["L", "R"]:
				var best: Array = (raw[f][s] as Array).duplicate()
				for k in range(-2, 3):
					var g := f + k
					if loop:
						g = posmod(g, m)
					elif g < 0 or g >= m:
						continue
					var o: Array = raw[g][s]
					if (o[0] as Vector3).length() > (best[0] as Vector3).length():
						best[0] = o[0]
					if (o[1] as Vector3).length() > (best[1] as Vector3).length():
						best[1] = o[1]
					if absf(float(o[2])) > absf(float(best[2])):
						best[2] = o[2]
				c[s] = best
			held.append(c)
		var wts := [1.0, 2.0, 3.0, 2.0, 1.0]
		var out: Array = []
		for f in m:
			var c := {}
			for s in ["L", "R"]:
				var v0 := Vector3.ZERO
				var v1 := Vector3.ZERO
				var v2 := 0.0
				var tot := 0.0
				for k in range(-2, 3):
					var g := f + k
					if loop:
						g = posmod(g, m)
					elif g < 0 or g >= m:
						continue
					var w: float = wts[k + 2]
					var o: Array = held[g][s]
					v0 += (o[0] as Vector3) * w
					v1 += (o[1] as Vector3) * w
					v2 += float(o[2]) * w
					tot += w
				c[s] = [v0 / tot, v1 / tot, v2 / tot]
			out.append(c)
		return out

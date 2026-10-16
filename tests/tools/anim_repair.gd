extends SceneTree
## Repairs the arms of every clip of a model on the shared skeleton (run 2026-10-15 g) and writes them to a library
## that RepairedClips lays over the clips built into the model.
##   godot --headless --path . -s tests/tools/anim_repair.gd [-- --clips=a,b]     the hero body
##   godot --headless --path . -s tests/tools/anim_repair.gd -- --body=sludge     Sludge's own set
##   godot --headless --path . -s tests/tools/anim_repair.gd -- --units           every humanoid unit model
##   godot --headless --path . -s tests/tools/anim_repair.gd -- --model=res://assets/characters/units/knight.glb
## The body kept clear of hands and blades is measured from each rig (its shoulder width and height), and a unit's
## blade is the weapon it holds in the game (ModelCatalog), for all of its clips.
##
## The clips come from the procedural library of the beyond-heroes project, whose hand IK can flip an elbow to the
## other side of the arm, or spin the forearm's twist by more than 100 degrees, between two frames 1/30 s apart, and
## bends wrists up to 150 degrees (tests/tools/anim_audit.gd measures all of it). Here each arm is solved again, frame
## by frame, from what the clip wants: where the hand is and where the weapon points.
##   * The hand keeps its path (two-bone IK from the shoulder; out-of-reach targets are pulled in).
##   * The elbow's swivel is read from the clip, made continuous (no flip to the other side), kept within a natural
##     range (it never points up past the shoulder line or in toward the chest) and smoothed.
##   * The elbow is a hinge: the upper arm turns so the forearm bends in its own plane, never backward or sideways.
##   * The hand's twist goes into the forearm (where a real arm turns: up to 85 degrees), a little into the wrist
##     (20); the wrist bends at most 70 degrees. The weapon follows the hand, so its direction may change a little
##     where the clip asked for the impossible.
##   * Snaps are taken out: the clips move a hand from overhead to the floor, or flip it round, in one or two frames.
##     The hand's path (an arc round its shoulder, as an arm swings) and turn are speed-limited (both directions in
##     time, averaged, so nothing lags), and so is every arm bone at the end; a move keeps its timing to within a
##     frame or two.
##   * Hands are kept out of the body (a pair gripping one weapon moves together), and a blade that would pass
##     through the torso, head or legs is turned away at the wrist.

const FPS := 30.0
const OUT := "res://assets/characters/hero/hero_anims_fixed.res"
const SWIVEL_MAX := 105.0                  # degrees either side of the natural elbow direction
const SWIVEL_STEP := 28.0                  # largest swivel change per frame
const FORE_TWIST := 85.0
const WRIST_TWIST := 20.0
const WRIST_BEND := 70.0
static var wrist_twist := WRIST_TWIST      # looser for a model whose weapon is part of its hand (an ogre's club):
static var wrist_bend := WRIST_BEND        # turning that hand would turn the weapon
static var pair_dist := 0.3                # two hands this close hold one weapon (scaled with the rig)
const ARM := ["upper_arm", "forearm", "hand"]
const HAND_STEP := 0.16                    # meters the hand may travel in one frame (4.8 m/s)
const TURN_STEP := 18.0                    # degrees the hand may turn in one frame (relative to the chest)
const BONE_STEP := 20.0                    # degrees any arm bone may turn in one frame, at the end
## The body the hands and blades must stay out of (meters; a plated hero, so the slim ones have room to spare):
## the torso as an elliptic cylinder from the hips to the neck (half width, half depth), the head, thighs, shins.
const TORSO := Vector2(0.20, 0.145)
static var torso := TORSO                  # --body=sludge: his belly (0.30 x 0.28); units: from their rig
static var head_r := 0.12
static var thigh_r := 0.09
static var shin_r := 0.065
static var margin := 0.025
static var hand_step := HAND_STEP          # scaled with the rig's height
static var blade_all = null                # a unit's one weapon for every clip ([] = none); null: by clip family
## The blade segment of each weapon a unit may hold (from the grip along the weapon's +Y).
const UNIT_BLADES := {"sword": [0.14, 0.88], "sword_aether": [0.14, 0.88], "axe": [0.0, 0.6], "dagger": [0.06, 0.32],
	"staff": [-0.9, 0.8], "staff_aether": [-0.9, 0.8], "wand": [0.0, 0.26], "spear": [-0.8, 1.2]}
## Blade segments (from the grip along the weapon's +Y) for the clip families, by the weapon their heroes hold.
const BLADES := {"sword": [0.14, 0.88], "gs": [0.2, 1.3], "dual": [0.06, 0.32], "dagger": [0.06, 0.32],
	"staff": [-0.9, 0.8], "wand": [0.0, 0.26], "axe": [0.0, 0.6], "idle_knight": [0.14, 0.88], "idle_shield": [0.14, 0.88],
	"idle_1h": [0.14, 0.88], "idle_2h": [0.2, 1.3], "idle_shadowblade": [0.06, 0.32], "idle_dual": [0.06, 0.32],
	"idle_staff": [-0.9, 0.8], "idle_wand": [0.0, 0.26], "cast_area": [-0.9, 0.8], "cast_heavy": [-0.9, 0.8],
	"cast_quick": [0.0, 0.26], "cast_ultimate": [0.0, 0.26], "shield_bash": [0.14, 0.88], "war_cry": [0.14, 0.88],
	"boss_roar": [0.2, 1.3], "boss_slam": [0.2, 1.3], "leap_slam": [0.2, 1.3], "cast_weapon": [0.2, 1.3],
	"hero_axe_smash": [0.0, 0.6], "blink": [0.06, 0.32]}

var _clips_only: Array = []
var _model := HeroLook.MODEL
var _out := OUT
var _units := false

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			_clips_only = Array(a.substr(8).split(",", false))
		elif a == "--body=sludge":
			# Sludge's own body (same skeleton, a much wider belly) gets its own set
			_model = "res://assets/characters/hero/sludge.glb"
			_out = RepairedClips.FIXED_SLUDGE
			torso = Vector2(0.30, 0.28)
		elif a == "--units":
			_units = true
		elif a.begins_with("--model="):
			_model = a.substr(8)
			_out = RepairedClips.path_for(_model)
	_run.call_deferred()

func _run() -> void:
	if _units:
		for path in RepairedClips.unit_models():
			await _repair_model(path, RepairedClips.path_for(path))
	else:
		await _repair_model(_model, _out)
	quit()

func _repair_model(path: String, out_path: String) -> void:
	var m: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var sks := m.find_children("*", "Skeleton3D", true, false)
	var sk: Skeleton3D = sks[0] if not sks.is_empty() else null
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
	if sk == null or ap == null or sk.find_bone("upper_arm.L") < 0:
		print("skipped %s (no arms)" % path.get_file())
		m.queue_free()
		return
	if path.contains("/units/"):
		_measure(sk, path)
	var lib := AnimationLibrary.new()
	var n_clips := 0
	for clip in ap.get_animation_list():
		if not _clips_only.is_empty() and not (String(clip) in _clips_only):
			continue
		lib.add_animation(clip, _repair(sk, ap, String(clip)))
		n_clips += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var err := ResourceSaver.save(lib, out_path)
	print("repaired %d clips of %s -> %s (%s)" % [n_clips, path.get_file(), out_path, error_string(err)])
	m.queue_free()
	await process_frame

## A unit's body from its rig: the torso as wide as its shoulders, everything else scaled by its height against
## the hero's (shoulders at 1.44 m); its blade is the weapon its catalog entry holds.
func _measure(sk: Skeleton3D, path: String) -> void:
	var l := sk.get_bone_global_rest(sk.find_bone("upper_arm.L")).origin
	var r := sk.get_bone_global_rest(sk.find_bone("upper_arm.R")).origin
	var k := l.y / 1.44
	# the body is narrower than the shoulder joints (a golem's or an ogre's arms hang far out from it)
	var half := absf(l.x - r.x) * 0.5 * 0.85
	torso = Vector2(half, half * 0.72)
	pair_dist = 0.3 * k
	head_r = 0.12 * k
	thigh_r = 0.09 * k
	shin_r = 0.065 * k
	margin = 0.025 * k
	hand_step = HAND_STEP * k
	blade_all = []
	wrist_twist = WRIST_TWIST
	wrist_bend = WRIST_BEND
	for key in ModelCatalog.MODELS:
		var cfg: Dictionary = ModelCatalog.MODELS[key]
		if String(cfg.scene) == path or String(cfg.get("scene_dusk", "")) == path:
			blade_all = UNIT_BLADES.get(String(cfg.get("R", "")), [])
			if String(cfg.get("R", "")) == "":
				wrist_twist = 60.0
				wrist_bend = 85.0
			break
	print("  %s: torso %.2f x %.2f, head %.2f, blade %s" % [path.get_file(), torso.x, torso.y, head_r, str(blade_all)])

## Signed angle (degrees) from a to b around axis n (all perpendicular to n).
static func _signed(a: Vector3, b: Vector3, n: Vector3) -> float:
	return rad_to_deg(atan2(n.dot(a.cross(b)), a.dot(b)))

static func _perp(v: Vector3, axis: Vector3) -> Vector3:
	return v - axis * v.dot(axis)

## Twist (degrees) of local rotation q about +Y and the swing left after it.
static func _twist_swing(q: Quaternion) -> Array:
	var tw := Quaternion(0.0, q.y, 0.0, q.w)
	if tw.length_squared() < 1e-12:
		tw = Quaternion()
	tw = tw.normalized()
	var t := wrapf(rad_to_deg(2.0 * atan2(tw.y, tw.w)), -180.0, 180.0)
	return [t, q * tw.inverse()]

func _repair(sk: Skeleton3D, ap: AnimationPlayer, clip: String) -> Animation:
	var a := ap.get_animation(clip)
	var n := maxi(1, int(round(a.length * FPS)))
	var bi := {}
	for b in ["chest", "shoulder.L", "shoulder.R", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R",
			"hips", "neck", "head", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R", "weapon.L", "weapon.R"]:
		bi[b] = sk.find_bone(b)
	# rest lengths
	var L1 := {}
	var L2 := {}
	var rest_local := {}
	for s in ["L", "R"]:
		var gu := sk.get_bone_global_rest(bi["upper_arm." + s])
		var gf := sk.get_bone_global_rest(bi["forearm." + s])
		var gh := sk.get_bone_global_rest(bi["hand." + s])
		L1[s] = gu.origin.distance_to(gf.origin)
		L2[s] = gf.origin.distance_to(gh.origin)
	# pass 1: read the clip
	ap.play(clip)
	ap.pause()
	var frames: Array = []
	for f in n + 1:
		ap.seek(minf(a.length, f / FPS), true)
		var fr := {}
		for b in bi:
			fr[b] = sk.get_bone_global_pose(int(bi[b]))
		frames.append(fr)
	for fr in frames:
		for s in ["L", "R"]:
			fr["hand_o." + s] = fr["hand." + s]
	for s in ["L", "R"]:
		_smooth_hand(frames, s)
	_hands_out(frames)
	var blade: Array = _blade_of(clip)
	var out := Animation.new()
	out.length = a.length
	out.loop_mode = a.loop_mode
	var path_of := {}
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var p := String(a.track_get_path(t))
		var bone := p.get_slice(":", 1)
		path_of[bone] = a.track_get_path(t)
	for s in ["L", "R"]:
		var side := 1.0 if s == "L" else -1.0
		# the elbow's direction (pole) per frame, carried over from the frame before (it can never flip to the other
		# side of the arm), turned toward the clip's elbow at most SWIVEL_STEP a frame, kept within SWIVEL_MAX of
		# the natural direction where that reference is well defined, then smoothed
		var poles: Array = []
		for f in n + 1:
			var fr: Dictionary = frames[f]
			var S: Vector3 = (fr["upper_arm." + s] as Transform3D).origin
			var W: Vector3 = (fr["hand." + s] as Transform3D).origin
			var E: Vector3 = (fr["forearm." + s] as Transform3D).origin
			var C: Basis = (fr.chest as Transform3D).basis.orthonormalized()
			var ax := (W - S).normalized()
			var rr: Array = _ref2(C, ax, side)
			var ref: Vector3 = rr[0]
			var e := _perp(E - S, ax)
			var p: Vector3
			if f == 0:
				p = e.normalized() if e.length() > 1e-3 else ref
			else:
				p = _perp(poles[f - 1], ax)
				p = p.normalized() if p.length() > 1e-3 else ref
				if e.length() > 1e-3:
					var dlt := clampf(_signed(p, e.normalized(), ax), -SWIVEL_STEP, SWIVEL_STEP)
					p = p.rotated(ax, deg_to_rad(dlt))
			if float(rr[1]) > 0.15:
				var nu := _signed(ref, p, ax)
				if absf(nu) > SWIVEL_MAX:
					p = ref.rotated(ax, deg_to_rad(signf(nu) * SWIVEL_MAX))
			poles.append(p.normalized())
		var sm_p: Array = poles.duplicate()
		for f in range(1, poles.size() - 1):
			sm_p[f] = ((poles[f - 1] as Vector3) * 0.25 + (poles[f] as Vector3) * 0.5 + (poles[f + 1] as Vector3) * 0.25)
		# pass 2: solve
		var tw_prev := 0.0
		var keys := {"upper_arm": [], "forearm": [], "hand": [], "weapon": []}
		var hinge_prev := Vector3.ZERO
		for f in n + 1:
			var fr: Dictionary = frames[f]
			var P: Basis = (fr["shoulder." + s] as Transform3D).basis.orthonormalized()
			var S: Vector3 = (fr["upper_arm." + s] as Transform3D).origin
			var W: Vector3 = (fr["hand." + s] as Transform3D).origin
			var Hb: Basis = (fr["hand." + s] as Transform3D).basis.orthonormalized()
			var C: Basis = (fr.chest as Transform3D).basis.orthonormalized()
			var l1: float = L1[s]
			var l2: float = L2[s]
			var d := W - S
			var D := clampf(d.length(), absf(l1 - l2) + 0.01, l1 + l2 - 0.002)
			var ax := d.normalized() if d.length() > 1e-5 else C * Vector3(side, 0, 0)
			W = S + ax * D
			var pole := _perp(sm_p[f], ax)
			pole = pole.normalized() if pole.length() > 1e-4 else (_ref2(C, ax, side)[0] as Vector3)
			var x := (l1 * l1 - l2 * l2 + D * D) / (2.0 * D)
			var h := sqrt(maxf(0.0, l1 * l1 - x * x))
			var E := S + ax * x + pole * h
			var u := (E - S).normalized()
			var fv := (W - E).normalized()
			var hinge := u.cross(fv)
			if hinge.length() < 1e-3:
				hinge = u.cross(-pole) if hinge_prev == Vector3.ZERO else hinge_prev
			hinge = hinge.normalized()
			hinge_prev = hinge
			# the natural bend axis is local -Z on the left forearm, +Z on the right (anim_audit learns the same)
			var zu := -hinge if s == "L" else hinge
			var Ub := Basis(u.cross(zu), u, zu).orthonormalized()
			var Fb := Basis(fv.cross(zu), fv, zu).orthonormalized()
			# the hand: its twist into the forearm (continuous), the wrist clamped
			var q := (Fb.inverse() * Hb).get_rotation_quaternion()
			var ts: Array = _twist_swing(q)
			var t := float(ts[0])
			if f > 0:
				t = tw_prev + wrapf(t - tw_prev, -180.0, 180.0)
			tw_prev = t
			var tf := clampf(t, -FORE_TWIST, FORE_TWIST)
			var th := clampf(t - tf, -wrist_twist, wrist_twist)
			var Fb2 := Fb * Basis(Vector3.UP, deg_to_rad(tf))
			var swing: Quaternion = ts[1]
			var sa := swing.get_angle()
			if sa > deg_to_rad(wrist_bend):
				swing = Quaternion(swing.get_axis(), deg_to_rad(wrist_bend))
			var Hb2 := Fb2 * Basis(swing) * Basis(Vector3.UP, deg_to_rad(th))
			var wl: Transform3D = (fr["hand_o." + s] as Transform3D).affine_inverse() * (fr["weapon." + s] as Transform3D)
			if not blade.is_empty():
				Hb2 = _clear_blade(fr, W, Hb2, wl, blade)
				# the turn that clears the blade may bend the wrist a little further, not past WRIST_BEND + 15
				var qh := (Fb2.inverse() * Hb2).get_rotation_quaternion()
				var tsh: Array = _twist_swing(qh)
				var swh: Quaternion = tsh[1]
				if swh.get_angle() > deg_to_rad(wrist_bend + 15.0):
					Hb2 = Fb2 * Basis(Quaternion(swh.get_axis(), deg_to_rad(wrist_bend + 15.0))) * Basis(Vector3.UP, deg_to_rad(float(tsh[0])))
			keys.weapon.append(wl.basis.orthonormalized().get_rotation_quaternion())
			keys.upper_arm.append((P.inverse() * Ub).get_rotation_quaternion())
			keys.forearm.append((Ub.inverse() * Fb2).get_rotation_quaternion())
			keys.hand.append((Fb2.inverse() * Hb2).get_rotation_quaternion())
		# single-frame spikes on any of the three, then a turn-speed limit
		for b in ARM + ["weapon"]:
			var ks: Array = keys[b]
			for f in range(1, ks.size() - 1):
				var q0: Quaternion = ks[f - 1]
				var q1: Quaternion = ks[f]
				var q2: Quaternion = ks[f + 1]
				if rad_to_deg(q0.angle_to(q1)) > 25.0 and rad_to_deg(q1.angle_to(q2)) > 25.0 and rad_to_deg(q0.angle_to(q2)) < 25.0:
					ks[f] = q0.slerp(q2, 0.5)
			keys[b] = _limit_turn(ks, BONE_STEP)
			ks = keys[b]
			var bone := "%s.%s" % [b, s]
			if not path_of.has(bone):
				continue
			var tr := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(tr, path_of[bone])
			out.track_set_interpolation_type(tr, Animation.INTERPOLATION_LINEAR)
			for f in ks.size():
				out.rotation_track_insert_key(tr, minf(a.length, f / FPS), ks[f])
	return out

## The natural elbow direction for an arm along `ax`: down, a little out to its side and back (chest frame), made
## perpendicular to the arm; never degenerate (a second reference straight back always has a share).
static func _ref(C: Basis, ax: Vector3, side: float) -> Vector3:
	var r1 := _perp(C * Vector3(side * 0.35, -1.0, -0.25).normalized(), ax)
	var r2 := _perp(C * Vector3(0.0, 0.0, -1.0), ax)
	var r := r1 + r2 * 0.35
	return r.normalized() if r.length() > 1e-4 else r2.normalized()

## Rotations limited to `step` degrees per frame, going forward and backward in time and averaged (no lag).
static func _limit_turn(ks: Array, step: float) -> Array:
	if ks.size() < 3:
		return ks
	var r := deg_to_rad(step)
	var fw: Array = ks.duplicate()
	for f in range(1, fw.size()):
		fw[f] = _toward(fw[f - 1], ks[f], r)
	var bw: Array = ks.duplicate()
	for f in range(bw.size() - 2, -1, -1):
		bw[f] = _toward(bw[f + 1], ks[f], r)
	var out: Array = []
	for f in ks.size():
		var qa: Quaternion = fw[f]
		var qb: Quaternion = bw[f]
		# two limits far apart (the clip turned round): the forward one, never a midpoint of opposites
		out.append(qa if qa.angle_to(qb) > PI * 0.5 else qa.slerp(qb, 0.5))
	return out

static func _toward(from: Quaternion, to: Quaternion, max_r: float) -> Quaternion:
	var ang := from.angle_to(to)
	if ang <= max_r or ang < 1e-6:
		return to
	return from.slerp(to, max_r / ang)

## The hand's path and turn (seen from the chest, so the body's own turning does not count) limited per frame,
## both ways in time and averaged; written back into the frames as the targets the arm is solved for.
static func _smooth_hand(frames: Array, s: String) -> void:
	var n := frames.size()
	if n < 3:
		return
	# the hand as seen from its shoulder (chest space): a direction and a reach. Limiting the direction's turn and the
	# reach's change moves a too-fast hand along an arc round the shoulder, as an arm swings; a straight line would
	# cut through the head and chest (an overhead slam)
	var dirs: Array = []
	var reach: Array = []
	var rot: Array = []
	var sh: Array = []
	for f in n:
		var C: Transform3D = frames[f].chest
		var H: Transform3D = frames[f]["hand." + s]
		var loc := C.affine_inverse() * H
		var so: Vector3 = C.affine_inverse() * (frames[f]["upper_arm." + s] as Transform3D).origin
		var v := loc.origin - so
		sh.append(so)
		dirs.append(v.normalized() if v.length() > 1e-4 else Vector3.DOWN)
		reach.append(v.length())
		rot.append(loc.basis.orthonormalized().get_rotation_quaternion())
	var step_of := func(r: float) -> float:
		return hand_step / maxf(0.15, r)
	var df: Array = dirs.duplicate()
	var rf: Array = reach.duplicate()
	for f in range(1, n):
		df[f] = _turn_toward(df[f - 1], dirs[f], step_of.call(float(rf[f - 1])))
		rf[f] = float(rf[f - 1]) + clampf(float(reach[f]) - float(rf[f - 1]), -hand_step, hand_step)
	var db: Array = dirs.duplicate()
	var rb: Array = reach.duplicate()
	for f in range(n - 2, -1, -1):
		db[f] = _turn_toward(db[f + 1], dirs[f], step_of.call(float(rb[f + 1])))
		rb[f] = float(rb[f + 1]) + clampf(float(reach[f]) - float(rb[f + 1]), -hand_step, hand_step)
	var rs := _limit_turn(rot, TURN_STEP)
	for f in n:
		var u: Vector3 = df[f]
		var w: Vector3 = db[f]
		# two limits nearly opposite (the clip jumped across): the forward one, never a midpoint through the body
		var dm := u if u.dot(w) < -0.5 else (u + w).normalized() if (u + w).length() > 1e-4 else u
		var p: Vector3 = (sh[f] as Vector3) + dm * ((float(rf[f]) + float(rb[f])) * 0.5)
		var C2: Transform3D = frames[f].chest
		frames[f]["hand." + s] = C2 * Transform3D(Basis(rs[f] as Quaternion), p)

## Direction `from` turned toward `to` by at most `max_r` radians (along the great circle).
static func _turn_toward(from: Vector3, to: Vector3, max_r: float) -> Vector3:
	var ang := from.angle_to(to)
	if ang <= max_r or ang < 1e-6:
		return to
	var axis := from.cross(to)
	if axis.length() < 1e-6:
		axis = from.cross(Vector3.FORWARD if absf(from.z) < 0.9 else Vector3.RIGHT)
	return from.rotated(axis.normalized(), max_r)

## The blade segment for a clip ([] when its heroes hold nothing long there).
static func _blade_of(clip: String) -> Array:
	if blade_all != null:
		return blade_all
	if BLADES.has(clip):
		return BLADES[clip]
	var fam := clip.get_slice("_", 0)
	return BLADES.get(fam, [])

## How far a point is inside the body, as the push that takes it out (zero outside).
static func _push_out(fr: Dictionary, p: Vector3) -> Vector3:
	var a: Vector3 = (fr.hips as Transform3D).origin
	var b: Vector3 = (fr.neck as Transform3D).origin
	var C: Basis = (fr.chest as Transform3D).basis.orthonormalized()
	var ab := b - a
	var k := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var best := Vector3.ZERO
	if k > 0.0 and k < 1.0:
		var dv := C.inverse() * (p - (a + ab * k))
		var e := pow(dv.x / (torso.x + margin), 2.0) + pow(dv.z / (torso.y + margin), 2.0)
		if e < 1.0:
			var radial := Vector3(dv.x, 0.0, dv.z)
			if radial.length() < 1e-4:
				radial = Vector3(0, 0, 1)
			var sc := 1.0 / sqrt(maxf(e, 1e-4))
			best = C * (radial * (sc - 1.0))
	var hc: Vector3 = (fr.head as Transform3D).origin + (fr.head as Transform3D).basis.y.normalized() * 0.09
	var dh := p.distance_to(hc)
	if dh < head_r + margin:
		var v := (p - hc).normalized() * (head_r + margin - dh)
		if v.length() > best.length():
			best = v
	for s in ["L", "R"]:
		for seg in [["thigh.", "shin.", thigh_r], ["shin.", "foot.", shin_r]]:
			var p0: Vector3 = (fr[String(seg[0]) + s] as Transform3D).origin
			var p1: Vector3 = (fr[String(seg[1]) + s] as Transform3D).origin
			var q := p0 + (p1 - p0) * clampf((p - p0).dot(p1 - p0) / maxf(1e-6, (p1 - p0).length_squared()), 0.0, 1.0)
			var d := p.distance_to(q)
			var r := float(seg[2]) + margin
			if d < r:
				var v2 := ((p - q).normalized() if d > 1e-4 else Vector3(0, 0, 1)) * (r - d)
				if v2.length() > best.length():
					best = v2
	return best

## Hands out of the body; two hands within 0.3 of each other (one weapon in both) move by the larger push together.
static func _hands_out(frames: Array) -> void:
	for fr in frames:
		var hl: Transform3D = fr["hand.L"]
		var hr: Transform3D = fr["hand.R"]
		var pl := _push_out(fr, hl.origin)
		var pr := _push_out(fr, hr.origin)
		if hl.origin.distance_to(hr.origin) < pair_dist:
			var big := pl if pl.length() > pr.length() else pr
			pl = big
			pr = big
		hl.origin += pl
		hr.origin += pr
		fr["hand.L"] = hl
		fr["hand.R"] = hr

## The hand turned about the wrist (up to 60 degrees) until its blade stays out of the body; the turn that leaves
## the least of the blade inside when none clears it.
static func _clear_blade(fr: Dictionary, W: Vector3, Hb: Basis, wl: Transform3D, seg: Array) -> Basis:
	var inside := func(hb: Basis) -> Array:
		var wt := Transform3D(hb, W) * wl
		var n := 0
		var push := Vector3.ZERO
		for i in 7:
			var p := wt * Vector3(0, lerpf(float(seg[0]), float(seg[1]), i / 6.0), 0)
			var v := _push_out(fr, p)
			if v != Vector3.ZERO:
				n += 1
				push += v
		return [n, push, (wt.basis.y).normalized()]
	var r0: Array = inside.call(Hb)
	if int(r0[0]) == 0:
		return Hb
	var axis := (r0[2] as Vector3).cross((r0[1] as Vector3).normalized())
	if axis.length() < 1e-4:
		return Hb
	axis = axis.normalized()
	var best := Hb
	var best_n := int(r0[0])
	for deg in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]:
		var hb := Basis(axis, deg_to_rad(deg)) * Hb
		var r: Array = inside.call(hb)
		if int(r[0]) < best_n:
			best = hb
			best_n = int(r[0])
		if best_n == 0:
			break
	return best

## The natural elbow direction for an arm along `ax` and how well defined it is (0..1): down, a little out and back
## (chest frame), made perpendicular to the arm; poorly defined when the arm points that way itself.
static func _ref2(C: Basis, ax: Vector3, side: float) -> Array:
	var v := C * (Vector3(side * 0.35, -1.0, -0.25).normalized() + Vector3(0.0, 0.0, -0.35))
	var r := _perp(v, ax)
	var rel := r.length() / v.length()
	if r.length() < 1e-4:
		r = _perp(C * Vector3(0, 0, -1), ax)
	return [r.normalized(), rel]

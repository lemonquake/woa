extends SceneTree
## Joins and loops (run 2026-10-18 e; the owner: "STRICTLY QA all animations, if they connect properly"). Every
## crossfade the game makes between two clips (UnitView: idle, run, attacks, casts, hit reactions, the stun, knockbacks
## and get-up, deaths; HeroStage: the flourish and back to the idle) is replayed at 60 frames a second the way
## AnimationPlayer blends it (the old clip keeps playing, each bone's local turn eased into the new clip's over the
## blend time), and every looping clip's seam (its last frame into its first) is measured.
##
## Reports, per model:
##   * snap: the most any bone turns in one 1/60 s frame beyond what the two clips themselves turn there (degrees;
##     a big pose gap squeezed into a short blend), FAIL over SNAP; finger bones count AnimBlend.FINGER of theirs
##     (small, fast joints: 30 degrees a frame for them);
##   * seam: a loop's last-to-first step against its own frame steps (degrees beyond 1.5x its 95th percentile step,
##     and the hips' jump in cm), FAIL over SEAM or SEAM_CM;
##   * slide: on run clips, the planted foot's speed against the clip's ground speed (ratio), FAIL outside SLIDE;
##   * floor: the hips, chest or head below the floor (deaths and knockdowns lying inside the ground), FAIL under FLOOR.
##   godot --headless --path . -s tests/tools/anim_joins.gd -- [--models=ezee,hero_burak] [--out=f] [--all]
##     (names: a hero id or a catalog key; none: every hero and the five catalog-only bodies; --all lists every join)

const FPS := 60.0
const SNAP := 12.0                          # degrees in one 1/60 s frame beyond the clips' own motion (720 deg/s)
const SEAM := 6.0                           # degrees beyond the loop's own steps
const SEAM_CM := 3.0
const SLIDE := [0.75, 1.3]                  # planted foot speed / ground speed
const FLOOR := -0.02                        # metres: a trunk bone this far under the floor
const BODIES := ["hero_emelrich", "hero_feran", "hero_burak", "hero_airah", "hero_ghorman", "hero_ghorman_beast", "hero_araki"]

var _models: Array = []
var _out := ""
var _all := false
var _fixed := false                         # --fixed: the game's base blends without AnimBlend (the old behaviour)
var lines: Array = []
var fails := 0

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--models="):
			_models = Array(a.substr(9).split(",", false))
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--all":
			_all = true
		elif a == "--fixed":
			_fixed = true
		elif a == "--nomocap":
			MocapClips.disabled = true
	if _models.is_empty():
		_models = Array(GameSettings.HEROES) + BODIES
	_run.call_deferred()

func out(s: String) -> void:
	lines.append(s)
	print(s)

func _run() -> void:
	for id in _models:
		await _check(String(id))
	out("TOTAL failures %d" % fails)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
	quit()

## [catalog key, scene path, hero id or ""]
func _which(id: String) -> Array:
	if ModelCatalog.MODELS.has(id):
		return [id, String(ModelCatalog.MODELS[id].scene), ""]
	var key := String(SimData.unit(id).model)
	var cfg := ModelCatalog.info(key)
	return [key, String(cfg.scene) if id in GameSettings.OWN_BODY else HeroLook.MODEL, id]

# ---- poses ----------------------------------------------------------------------------------------------------------

var sk: Skeleton3D
var ap: AnimationPlayer
var _cache := {}

## Every bone's local pose of `clip` at time t (wrapped for loops, held at the ends otherwise).
func _pose(clip: String, t: float, loop: bool) -> Array:
	var a := ap.get_animation(clip)
	var L := a.length
	t = fposmod(t, L) if loop and L > 0.0 else clampf(t, 0.0, L)
	var key := "%s@%d" % [clip, roundi(t * 600.0)]
	if _cache.has(key):
		return _cache[key]
	sk.reset_bone_poses()
	ap.play(clip)
	ap.seek(t, true)
	var p: Array = []
	for b in sk.get_bone_count():
		p.append(sk.get_bone_pose(b))
	_cache[key] = p
	return p

func _globals(local: Array) -> Array:
	var g: Array = []
	g.resize(local.size())
	for b in local.size():
		var par := sk.get_bone_parent(b)
		g[b] = (local[b] as Transform3D) if par < 0 else (g[par] as Transform3D) * (local[b] as Transform3D)
	return g

static func _blend(a: Array, b: Array, w: float) -> Array:
	var o: Array = []
	for i in a.size():
		var ta: Transform3D = a[i]
		var tb: Transform3D = b[i]
		var qa := ta.basis.get_rotation_quaternion()
		var qb := tb.basis.get_rotation_quaternion()
		o.append(Transform3D(Basis(qa.slerp(qb, w)), ta.origin.lerp(tb.origin, w)))
	return o

static func _ang(a: Transform3D, b: Transform3D) -> float:
	return rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()))

## A crossfade from clip `a` (at time ta, speed sa, looping or held) into `b` (from 0 at speed sb) over `blend` s.
## Returns [worst snap degrees, bone name, time into the blend, worst pose gap degrees].
func _join(a: String, ta: float, sa: float, la: bool, b: String, sb: float, lb: bool, base: float, cap: float) -> Array:
	var dt := 1.0 / FPS
	# the blend the game picks (AnimBlend: stretched to the pose gap, within the cap); --fixed: the base blend alone
	var from: Array = _pose(a, ta, la).map(func(x): return (x as Transform3D).basis.get_rotation_quaternion())
	var blend := base if _fixed else AnimBlend.time_from(sk, from, ap.get_animation(b), 0.0, base, cap, sb)
	var n := int(ceil(maxf(blend, dt) * FPS)) + 2
	var worst := [0.0, "", 0.0, 0.0, blend]
	var prev_g: Array = []
	var prev_ga: Array = []
	var prev_gb: Array = []
	for k in n + 1:
		var t := k * dt
		var w := clampf(t / blend, 0.0, 1.0) if blend > 0.0 else 1.0
		var pa := _pose(a, ta + t * sa, la)
		var pb := _pose(b, t * sb, lb)
		var ga := _globals(pa)
		var gb := _globals(pb)
		var g := _globals(_blend(pa, pb, w))
		if k == 0:
			for i in g.size():
				worst[3] = maxf(float(worst[3]), _ang(ga[i], gb[i]))
		if k > 0:
			var wt := AnimBlend.weights(sk)
			for i in g.size():
				var own := maxf(_ang(prev_ga[i], ga[i]), _ang(prev_gb[i], gb[i]))
				var d := (_ang(prev_g[i], g[i]) - own) * wt[i]
				if d > float(worst[0]):
					worst = [d, sk.get_bone_name(i), t, worst[3], blend]
		prev_g = g
		prev_ga = ga
		prev_gb = gb
	return worst

## A loop's seam: [degrees beyond 1.5x its p95 step, bone, hips jump cm, p95 step].
func _seam(clip: String) -> Array:
	var a := ap.get_animation(clip)
	var L := a.length
	var dt := 1.0 / 30.0
	var steps := {}
	var prev: Array = []
	var n := maxi(2, int(round(L / dt)))
	var all_steps: Array = []
	for k in n:
		var g := _globals(_pose(clip, k * dt, false))
		if k > 0:
			var m := 0.0
			for i in g.size():
				m = maxf(m, _ang(prev[i], g[i]))
			all_steps.append(m)
		prev = g
	all_steps.sort()
	var p95: float = all_steps[int(all_steps.size() * 0.95)] if not all_steps.is_empty() else 0.0
	# the step across the seam: the last sampled frame before L, into the first
	var ge := _globals(_pose(clip, L - fposmod(L, dt) if fposmod(L, dt) > 0.001 else L - dt, false))
	var gl := _globals(_pose(clip, L, false))
	var g0 := _globals(_pose(clip, 0.0, false))
	var worst := 0.0
	var bone := ""
	for i in g0.size():
		# the last frame (at L) should equal the first; then the step from the frame before it is a normal step
		var d := _ang(gl[i], g0[i])
		if d > worst:
			worst = d
			bone = sk.get_bone_name(i)
	var hips := sk.find_bone("hips")
	var cm := 0.0
	if hips >= 0:
		cm = ((gl[hips] as Transform3D).origin - (g0[hips] as Transform3D).origin).length() * 100.0
	return [worst, bone, cm, p95]

## Planted foot speed on a run clip over its ground speed.
func _slide(clip: String) -> float:
	var gs := float(ModelCatalog.clip(clip).get("ground_speed", 0.0)) * MocapClips.leg_scale(sk)   # as UnitView plays it
	if gs <= 0.0:
		return -1.0
	var a := ap.get_animation(clip)
	var dt := 1.0 / FPS
	var n := int(a.length * FPS)
	var tot := 0.0
	var cnt := 0
	for s in ["L", "R"]:
		var fb := sk.find_bone("foot." + s)
		var tb := sk.find_bone("toe." + s)
		if fb < 0:
			return -1.0
		var ys: Array = []
		var ps: Array = []
		for k in n + 1:
			var g := _globals(_pose(clip, k * dt, true))
			var p: Vector3 = (g[tb if tb >= 0 else fb] as Transform3D).origin
			ys.append(minf(p.y, (g[fb] as Transform3D).origin.y))
			ps.append(p)
		var lo: float = ys.min()
		for k in range(1, n + 1):
			if float(ys[k]) < lo + 0.03 and float(ys[k - 1]) < lo + 0.03:
				var v: Vector3 = ((ps[k] as Vector3) - (ps[k - 1] as Vector3)) / dt
				tot += Vector2(v.x, v.z).length()
				cnt += 1
	return (tot / maxf(1.0, cnt)) / gs

func _floor(clip: String) -> Array:
	var a := ap.get_animation(clip)
	var lo := 9.0
	var bone := ""
	for k in int(a.length * 30.0) + 1:
		var g := _globals(_pose(clip, k / 30.0, false))
		for bn in ["hips", "chest", "head"]:
			var i := sk.find_bone(bn)
			if i >= 0:
				var y := (sk.global_transform * (g[i] as Transform3D)).origin.y
				if y < lo:
					lo = y
					bone = bn
	return [lo, bone]

# ---- the game's clip changes ----------------------------------------------------------------------------------------

func _check(id: String) -> void:
	var w := _which(id)
	var key := String(w[0])
	var hero := String(w[2])
	var cfg := ModelCatalog.info(key)
	var m := (load(String(w[1])) as PackedScene).instantiate() as Node3D
	RepairedClips.patch(m)
	root.add_child(m)
	await process_frame
	var sks := m.find_children("*", "Skeleton3D", true, false)
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	if sks.is_empty() or aps.is_empty():
		m.queue_free()
		return
	sk = sks[0]
	ap = aps[0]
	_cache = {}
	var has := func(c: String) -> bool: return c != "" and ap.has_animation(c)
	var A := func(c: String) -> String: return ModelCatalog.anim(cfg, c)
	var idle: String = A.call(String(cfg.get("idle", "idle")))
	if not has.call(idle):
		idle = "idle"
	var run: String = A.call(String(cfg.get("glide_clip", cfg.get("run", "run"))) if cfg.get("glide", false) else String(cfg.get("run", "run")))
	var attacks: Array = (cfg.get("attack", []) as Array).map(func(c): return A.call(String(c))).filter(func(c): return has.call(c))
	var casts: Array = []
	for c in [String(cfg.get("cast", ""))]:
		if has.call(A.call(c)):
			casts.append(A.call(c))
	if hero != "":
		for aid in SimData.unit(hero).abilities:
			var an: String = A.call(String(SimData.ability(String(aid)).get("anim", "")))
			var own := String(cfg.get("casts", {}).get(String(aid), ""))
			if has.call(own):
				an = own                                  # a hero's own ability clip (run 2026-10-21 b)
			if has.call(an) and not (an in casts) and an != A.call("leap_slam"):
				casts.append(an)
	var hits: Array = []
	for c in ["hit_heavy", "hit_light", "hit_front"]:
		if has.call(A.call(c)) and not (A.call(c) in hits):
			hits.append(A.call(c))
	var stun: String = A.call("idle_hurt") if ap.has_animation("idle_hurt") or has.call(A.call("idle_hurt")) else idle
	var deaths: Array = (cfg.get("deaths", [cfg.get("death", "death")]) as Array).map(func(c): return A.call(String(c))).filter(func(c): return has.call(c))
	var kb: String = A.call("knockback")
	var gu: String = A.call("getup")
	var la: String = A.call("launch")
	var wi: String = A.call("wall_impact")
	out("== %s (%s; idle %s, run %s)" % [id, String(w[1]).get_file(), idle, run])
	var J: Array = []                       # [from, at (s; -1 = end, -2 = loop phases), speed, to, speed, blend, cap]
	var apt := 0.4                          # the attack point the swing is timed to (s)
	if hero != "":
		apt = float(SimData.unit(hero).get("attack_point", 0.4))
	var loops := [idle, run, stun]
	J.append([idle, -2, 1.0, run, 1.0, 0.12])
	J.append([run, -2, 1.0, idle, 1.0, 0.25])
	var spd_of := func(c: String) -> float: return clampf(ModelCatalog.strike_time(c) / maxf(apt, 0.05), 0.35, 3.0)
	for c in attacks:
		var spd := clampf(ModelCatalog.strike_time(c) / maxf(apt, 0.05), 0.35, 3.0)
		J.append([idle, -2, 1.0, c, spd, 0.06, maxf(0.22, 0.9 * apt)])
		J.append([run, -2, 1.0, c, spd, 0.06, maxf(0.22, 0.9 * apt)])
		J.append([c, -1, 1.0, idle, 1.0, 0.25])
		J.append([c, -1, 1.0, run, 1.0, 0.12])
	for i in attacks.size():
		J.append([attacks[i], -1, 1.0, attacks[(i + 1) % attacks.size()], spd_of.call(attacks[(i + 1) % attacks.size()]), 0.06, maxf(0.22, 0.9 * apt)])
	for c in casts:
		var cp := 0.3
		if hero != "":
			for aid in SimData.unit(hero).abilities:
				if A.call(String(SimData.ability(String(aid)).get("anim", ""))) == c:
					cp = float(SimData.ability(String(aid)).get("cast_point", 0.3))
		var rel := ModelCatalog.strike_time(c)
		var cspd := clampf(rel / maxf(cp, 0.05), 0.5, 3.0) if cp > 0.0 else 1.6
		J.append([idle, -2, 1.0, c, cspd, 0.06, maxf(0.22, 0.9 * rel / cspd)])
		J.append([run, -2, 1.0, c, cspd, 0.06, maxf(0.22, 0.9 * rel / cspd)])
		J.append([c, -1, 1.0, idle, 1.0, 0.25])
		J.append([c, -1, 1.0, run, 1.0, 0.12])
	for c in hits:
		J.append([idle, -2, 1.0, c, 1.25, 0.05, 0.3])
		J.append([c, -1, 1.25, idle, 1.0, 0.25])
	var hh: String = A.call("hit_heavy")
	if has.call(hh):
		J.append([run, -2, 1.0, hh, 1.3, 0.06, 0.3])
		for c in attacks.slice(0, 1):
			J.append([c, -3, 1.0, hh, 1.3, 0.06, 0.3])
		J.append([hh, 0.52, 1.3, stun, 0.75, 0.2])
		J.append([stun, -2, 0.75, idle, 1.0, 0.25])
	if has.call(kb):
		J.append([idle, -2, 1.0, kb, 1.2, 0.06, 0.25])
		J.append([run, -2, 1.0, kb, 1.2, 0.06, 0.25])
		if has.call(gu):
			J.append([kb, -1, 1.2, gu, 2.4, 0.08])
			J.append([gu, -1, 2.4, idle, 1.0, 0.25])
			J.append([gu, -1, 2.4, run, 1.0, 0.12])
		if has.call(la):
			J.append([idle, -2, 1.0, la, 1.2, 0.06, 0.25])
			J.append([la, -2, 1.2, kb, 1.6, 0.08, 0.25])
		if has.call(wi):
			J.append([kb, -3, 1.2, wi, 1.5, 0.04, 0.2])
			if has.call(gu):
				J.append([wi, -1, 1.5, gu, 2.4, 0.08])
	for c in deaths:
		J.append([idle, -2, 1.0, c, 1.0, 0.1])
		J.append([run, -2, 1.0, c, 1.0, 0.1])
	if hero != "":
		var ls: String = A.call("leap_slam")
		if "leap_strike" in SimData.unit(hero).abilities and has.call(ls):
			J.append([idle, -2, 1.0, ls, 1.0, 0.06])
			J.append([run, -2, 1.0, ls, 1.0, 0.06])
			J.append([ls, -1, 1.1, idle, 1.0, 0.25])
			J.append([ls, -1, 1.1, run, 1.0, 0.12])
		# Blood Ranger's back leap (UnitView.on_back_leap: dodge_step, or blink without it); Caziel's blink is a cast
		for c in (["dodge_step" if has.call(A.call("dodge_step")) else "blink"] if hero == "blood_ranger" else []):
			var dc: String = A.call(c)
			if has.call(dc) and not (dc in casts):
				J.append([run, -2, 1.0, dc, 1.5, 0.04])
				J.append([dc, -1, 1.5, idle, 1.0, 0.25])
				J.append([dc, -1, 1.5, run, 1.0, 0.12])
		# Hero Select: idle -> flourish (0.2 s), then the queued idle (AnimationPlayer's default blend)
		var fl: String = A.call(String(HeroStage.FLOURISH.get(hero, "")))
		var sid: String = A.call(String(HeroStage.IDLE.get(hero, "idle")))
		if has.call(fl) and has.call(sid):
			J.append([sid, -2, 1.0, fl, 1.0, 0.2])
			J.append([fl, -1, 1.0, sid, 1.0, 0.0, 0.25])
			if not (sid in loops):
				loops.append(sid)
	for c in ["bow_draw_hold", "devour"]:
		if has.call(A.call(c)) and hero != "" and (c != "devour" or "chomp" in SimData.unit(hero).abilities):
			loops.append(A.call(c))
	var nfail := 0
	var worst_snap := [0.0, ""]
	for j in J:
		var a := String(j[0])
		var b := String(j[3])
		if not has.call(a) or not has.call(b) or a == b and int(j[1]) == -2:
			continue
		var la_loop: bool = a in loops
		var lb_loop: bool = b in loops
		var L := ap.get_animation(a).length
		var phases: Array = [0.0, 0.25, 0.5, 0.75] if int(j[1]) == -2 else ([L * 0.45] if int(j[1]) == -3 else ([L] if int(j[1]) == -1 else [float(j[1])]))
		var res := [0.0, "", 0.0, 0.0, 0.0]
		var at := 0.0
		for ph in phases:
			var ta: float = float(ph) * L if int(j[1]) == -2 else float(ph)
			var r := _join(a, ta, float(j[2]), la_loop, b, float(j[4]), lb_loop, float(j[5]),
				float(j[6]) if j.size() > 6 else AnimBlend.MAX)
			if float(r[0]) > float(res[0]) or res[1] == "":
				res = r
				at = ta
		var bad := float(res[0]) > SNAP
		if bad:
			nfail += 1
		if float(res[0]) > float(worst_snap[0]):
			worst_snap = [res[0], "%s -> %s" % [a, b]]
		if bad or _all:
			out("  %s join %-22s -> %-22s blend %.2fs: snap %.1f deg (%s at +%.2fs), gap %.0f deg%s" % [
				"FAIL" if bad else "ok  ", a, b, float(res[4]), float(res[0]), res[1], float(res[2]), float(res[3]),
				"" if int(j[1]) != -2 else " (from %.2fs)" % at])
	for c in loops:
		if not has.call(c):
			continue
		var s := _seam(c)
		var excess := float(s[0]) - 1.5 * float(s[3])
		var bad := excess > SEAM or float(s[2]) > SEAM_CM
		if bad:
			nfail += 1
		if bad or _all:
			out("  %s seam %-22s %.1f deg (%s; its steps p95 %.1f) hips %.1f cm" % ["FAIL" if bad else "ok  ", c,
				float(s[0]), s[1], float(s[3]), float(s[2])])
	if has.call(run) and not cfg.get("glide", false):
		var r := _slide(run)
		if r >= 0.0:
			var bad := r < float(SLIDE[0]) or r > float(SLIDE[1])
			if bad:
				nfail += 1
			out("  %s slide %s: planted foot at %.2fx the ground speed (%.2f m/s)" % ["FAIL" if bad else "ok  ", run, r,
				float(ModelCatalog.clip(run).get("ground_speed", 0.0))])
	if not cfg.has("float"):
		for c in deaths + ([kb, gu] as Array):
			if not has.call(c):
				continue
			var f := _floor(c)
			if float(f[0]) < FLOOR:
				nfail += 1
				out("  FAIL floor %s: %s %.0f cm under the floor" % [c, f[1], -float(f[0]) * 100.0])
	out("  -> %d joins and %d loops checked, worst snap %.1f deg (%s), %d failures" % [J.size(), loops.size(),
		float(worst_snap[0]), worst_snap[1], nfail])
	fails += nfail
	m.queue_free()
	await process_frame

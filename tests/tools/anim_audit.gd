extends SceneTree
## Animation audit (run 2026-10-15 g): every clip each hero plays, measured frame by frame on the shared hero skeleton
## (headless). It reports, per hero and clip:
##   * joints bent the wrong way: an elbow or knee bending against its natural direction (hyperextension);
##   * extreme twist: forearm twist from the upper arm, an elbow pointing up or in toward the chest, wrist bend, head
##     turned from the chest, the chest twisted from the hips;
##   * pops: a bone turning more than 45 degrees between two frames 1/30 s apart (a visible snap);
##   * clipping: the hands or the weapons (blade points, the shield's face) inside the torso, head or legs, and the
##     sword's blade passing through the shield.
## Thresholds are fixed below; a clip passes with no findings.
##   godot --headless --path . -s tests/tools/anim_audit.gd -- [--heroes=kragg,ezee] [--out=path.txt] [--clips=a,b]
##   ... -- --units [--raw]      every humanoid unit model (as "unit:<catalog key>", its body measured from its rig)

const FPS := 30.0
const MAX_FORE_TWIST := 95.0                # degrees
const MAX_SWIVEL := 125.0                  # elbow direction from its natural one
const MAX_WRIST := 75.0
const MAX_HEAD := 80.0
const MAX_CHEST := 65.0
const MAX_HYPER := 12.0                     # degrees against the natural bend
const POP := 45.0                           # degrees in one frame (1350 deg/s): a visible snap
const CLIP_DEPTH := 0.035                   # meters inside a body part before it counts

## Body volumes per hero body (meters, skeleton space): torso half-width and half-depth, head radius, thigh and
## shin radii. Kragg wears plate (a little bigger), Sludge is fat.
const BODY := {"default": [0.17, 0.12, 0.105, 0.075, 0.055], "kragg": [0.19, 0.14, 0.11, 0.085, 0.06],
	"sludge": [0.27, 0.22, 0.12, 0.1, 0.07], "ezee": [0.18, 0.13, 0.105, 0.08, 0.058]}
## The props as segments / plates in their bone's space (+Y along the blade or handle, from the grip).
const BLADE := {"sword": [0.14, 0.88], "sword_aether": [0.14, 0.88], "greatsword": [0.2, 1.3], "dagger": [0.06, 0.32], "axe": [0.0, 0.66],
	"cleaver": [0.0, 0.54], "staff": [-1.0, 0.8], "staff_aether": [-1.0, 0.8], "wand": [0.0, 0.24], "spear": [-0.9, 1.3]}
const SHIELD := Vector3(0.32, 0.46, 0.035)  # half extents (x across, y up, z thickness), centred on the grip
var SHIELD_OFF := Vector3(0.0, -0.03, 0.0)

var _out := ""
var _heroes: Array = []
var _clips_only: Array = []
var lines: Array = []
var _natural := {}                          # joint -> natural bend axis (bone local), learned from all clips
var total_findings := 0
var _raw := false                           # --raw: the clips as built into the bodies (no RepairedClips repair)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--heroes="):
			_heroes = Array(a.substr(9).split(",", false))
		elif a.begins_with("--clips="):
			_clips_only = Array(a.substr(8).split(",", false))
		elif a == "--raw":
			_raw = true
		elif a == "--units":
			_heroes = _unit_ids()
	if _heroes.is_empty():
		_heroes = Array(GameSettings.HEROES)
	_run.call_deferred()

func out(s: String) -> void:
	lines.append(s)
	print(s)

## One catalog key per unit model scene ("unit:<key>"), in catalog order.
static func _unit_ids() -> Array:
	var outk: Array = []
	var seen := {}
	for key in ModelCatalog.MODELS:
		var p := String(ModelCatalog.MODELS[key].scene)
		if p.contains("/units/") and not seen.has(p):
			seen[p] = true
			outk.append("unit:" + String(key))
	return outk

## The clips a hero plays in the game and on the stages (a unit: its idle, run, death and attacks).
func clips_of(id: String) -> Array:
	if not _clips_only.is_empty():
		return _clips_only
	if id == "knight":
		id = "unit:dawn_melee"
	if id.begins_with("unit:"):
		var uc := ModelCatalog.info(id.substr(5))
		var ul: Array = []
		for c in [String(uc.get("idle", "")), String(uc.get("run", "")), String(uc.get("death", ""))] + Array(uc.get("attack", [])):
			if String(c) != "" and not (String(c) in ul):
				ul.append(String(c))
		return ul
	var cfg := ModelCatalog.info(String(SimData.unit(id).model))
	var outc: Array = []
	# the clips as the game plays them (their motion-capture stand-ins, ModelCatalog.anim), and the push and hit clips
	for c in [String(cfg.get("idle", "")), String(HeroStage.IDLE.get(id, "")), String(HeroStage.FLOURISH.get(id, "")),
			String(cfg.get("cast", "")), String(cfg.get("run", "")), String(cfg.get("death", "death")), "knockback", "getup",
			"launch", "wall_impact", "hit_heavy", "hit_light", "idle_hurt"] + Array(cfg.get("deaths", [])):
		c = ModelCatalog.anim(cfg, c)
		if c != "" and not (c in outc):
			outc.append(c)
	for c in cfg.get("attack", []):
		if not (String(c) in outc):
			outc.append(String(c))
	for aid in SimData.unit(id).abilities + ([String(SimData.unit(id).innate)] if String(SimData.unit(id).get("innate", "")) != "" else []):
		var an := ModelCatalog.anim(cfg, String(SimData.ability(String(aid)).get("anim", "")))
		if an != "" and not (an in outc):
			outc.append(an)
	return outc

func _model(id: String) -> Node3D:
	if id == "knight":
		id = "unit:dawn_melee"
	if id.begins_with("unit:"):
		return (load(String(ModelCatalog.info(id.substr(5)).scene)) as PackedScene).instantiate()
	var cfg := ModelCatalog.info(String(SimData.unit(id).model))
	var own := id in GameSettings.OWN_BODY
	return (load(String(cfg.scene) if own else HeroLook.MODEL) as PackedScene).instantiate()

## Twist of rotation `q` about local +Y (degrees, -180..180) and the remaining swing as an axis * angle.
static func twist_swing(q: Quaternion) -> Array:
	var tw := Quaternion(0.0, q.y, 0.0, q.w).normalized()
	if q.y == 0.0 and q.w == 0.0:
		tw = Quaternion()
	var t := rad_to_deg(2.0 * atan2(tw.y, tw.w))
	t = wrapf(t, -180.0, 180.0)
	var sw := q * tw.inverse()
	var ang := rad_to_deg(sw.get_angle())
	var ax := sw.get_axis() if ang > 0.01 else Vector3.ZERO
	return [t, ax, wrapf(ang, -180.0, 180.0)]

func _rel(sk: Skeleton3D, parent: int, child: int) -> Quaternion:
	var pb := sk.get_bone_global_pose(parent).basis.orthonormalized()
	var cb := sk.get_bone_global_pose(child).basis.orthonormalized()
	return (pb.inverse() * cb).get_rotation_quaternion()

func _run() -> void:
	# pass 1: learn each elbow's and knee's natural bend axis from every clip of the shared body (the most common
	# swing direction, weighted by the bend)
	var m0 := (load(HeroLook.MODEL) as PackedScene).instantiate()
	root.add_child(m0)
	await process_frame
	var sk0: Skeleton3D = m0.find_children("*", "Skeleton3D", true, false)[0]
	var ap0: AnimationPlayer = m0.find_children("*", "AnimationPlayer", true, false)[0]
	var acc := {"forearm.L": Vector3.ZERO, "forearm.R": Vector3.ZERO, "shin.L": Vector3.ZERO, "shin.R": Vector3.ZERO}
	for clip in ap0.get_animation_list():
		var a := ap0.get_animation(clip)
		ap0.play(clip)
		ap0.pause()
		var n := int(a.length * FPS)
		for f in range(0, n, 3):
			ap0.seek(f / FPS, true)
			for j in acc:
				var bi := sk0.find_bone(j)
				var ts: Array = twist_swing(_rel(sk0, sk0.get_bone_parent(bi), bi))
				acc[j] += (ts[1] as Vector3) * float(ts[2])
	for j in acc:
		_natural[j] = (acc[j] as Vector3).normalized()
		out("natural bend %s: %s" % [j, str(_natural[j].snapped(Vector3.ONE * 0.01))])
	m0.queue_free()
	await process_frame
	for id in _heroes:
		await _audit(String(id))
	out("TOTAL findings %d" % total_findings)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
	quit()

func _audit(id: String) -> void:
	if id == "knight":
		id = "unit:dawn_melee"
	var unit := id.begins_with("unit:")
	var m := _model(id)
	if not _raw:
		RepairedClips.patch(m)
	root.add_child(m)
	await process_frame
	var sks := m.find_children("*", "Skeleton3D", true, false)
	var sk: Skeleton3D = sks[0] if not sks.is_empty() else null
	if sk == null or sk.find_bone("upper_arm.L") < 0 or m.find_children("*", "AnimationPlayer", true, false).is_empty():
		m.queue_free()
		await process_frame
		return                              # no arms (wolves, couriers)
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	var cfg := ModelCatalog.info(id.substr(5)) if unit else ModelCatalog.info(String(SimData.unit(id).model))
	var body: Array = BODY.get(id, BODY.default)
	if unit:
		# the body from the rig, as tests/tools/anim_repair.gd measures it
		var l := sk.get_bone_global_rest(sk.find_bone("upper_arm.L")).origin
		var r := sk.get_bone_global_rest(sk.find_bone("upper_arm.R")).origin
		var k := l.y / 1.44
		var half := absf(l.x - r.x) * 0.5 * 0.85
		body = [half, half * 0.72, 0.11 * k, 0.085 * k, 0.06 * k]
	var wr := String(cfg.get("R", ""))
	var wl := String(cfg.get("L", ""))
	out("== %s%s (R %s, L %s)" % [id, (" " + String(cfg.scene).get_file()) if unit else "", wr if wr != "" else "-", wl if wl != "" else "-"])
	var bone := {}
	for b in ["hips", "spine", "chest", "neck", "head", "upper_arm.L", "forearm.L", "hand.L", "weapon.L", "upper_arm.R",
			"forearm.R", "hand.R", "weapon.R", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R", "shoulder.L", "shoulder.R"]:
		bone[b] = sk.find_bone(b)
	var hero_total := 0
	for clip in clips_of(id):
		if not ap.has_animation(clip):
			out("  %-16s MISSING" % clip)
			continue
		var a := ap.get_animation(clip)
		ap.play(clip)
		ap.pause()
		var n := maxi(2, int(round(a.length * FPS)))
		var worst := {}                     # finding -> [value, time]
		var counts := {}
		var prev := {}
		for f in n + 1:
			var t := minf(a.length, f / FPS)
			ap.seek(t, true)
			var G := {}
			for b in bone:
				if int(bone[b]) >= 0:
					G[b] = sk.get_bone_global_pose(int(bone[b]))
			var found := {}
			for s in ["L", "R"]:
				var fts: Array = twist_swing(_rel(sk, bone["upper_arm." + s], bone["forearm." + s]))
				if absf(float(fts[0])) > MAX_FORE_TWIST:
					found["forearm twist " + s] = absf(float(fts[0]))
				var hyper := -(fts[1] as Vector3).dot(_natural["forearm." + s]) * absf(float(fts[2]))
				if hyper > MAX_HYPER:
					found["elbow bent backward " + s] = hyper
				# the elbow's direction round the shoulder-wrist line, from its natural one (down, a little out and back)
				var Gs: Transform3D = sk.get_bone_global_pose(bone["upper_arm." + s])
				var Ge: Transform3D = sk.get_bone_global_pose(bone["forearm." + s])
				var Gw: Transform3D = sk.get_bone_global_pose(bone["hand." + s])
				var axw := (Gw.origin - Gs.origin).normalized()
				var refw := _ref(sk.get_bone_global_pose(bone.chest).basis.orthonormalized(), axw, 1.0 if s == "L" else -1.0)
				var ew := Ge.origin - Gs.origin
				ew = ew - axw * ew.dot(axw)
				if ew.length() > 0.03:
					var phi := rad_to_deg(atan2(axw.dot(refw.cross(ew.normalized())), refw.dot(ew.normalized())))
					if absf(phi) > MAX_SWIVEL:
						found["elbow points the wrong way " + s] = absf(phi)
				var hts: Array = twist_swing(_rel(sk, bone["forearm." + s], bone["hand." + s]))
				if absf(float(hts[2])) > MAX_WRIST:
					found["wrist bent " + s] = absf(float(hts[2]))
				var kts: Array = twist_swing(_rel(sk, bone["thigh." + s], bone["shin." + s]))
				var kh := -(kts[1] as Vector3).dot(_natural["shin." + s]) * absf(float(kts[2]))
				if kh > MAX_HYPER:
					found["knee bent backward " + s] = kh
			var head := rad_to_deg(_rel(sk, bone.chest, bone.head).get_angle())
			if head > MAX_HEAD:
				found["head turned"] = head
			var ch := absf(float(twist_swing(_rel(sk, bone.hips, bone.chest))[0]))
			if ch > MAX_CHEST:
				found["chest twisted"] = ch
			# pops
			for b in G:
				if prev.has(b) and f > 0:
					var d := rad_to_deg((prev[b] as Transform3D).basis.get_rotation_quaternion().angle_to((G[b] as Transform3D).basis.get_rotation_quaternion()))
					if d > POP and not (a.loop_mode != Animation.LOOP_NONE and f == n):
						found["pop " + String(b)] = d
			prev = G
			# clipping: body volumes in this pose
			var torso_a: Vector3 = (G.hips as Transform3D).origin
			var torso_b: Vector3 = (G.neck as Transform3D).origin
			var chest_basis: Basis = (G.chest as Transform3D).basis.orthonormalized()
			var head_c: Vector3 = (G.head as Transform3D).origin + (G.head as Transform3D).basis.y.normalized() * 0.09
			var parts := func(p: Vector3, skip_side: String) -> String:
				# torso: an elliptic cylinder along hips -> neck
				var ab := torso_b - torso_a
				var k := clampf((p - torso_a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				var c := torso_a + ab * k
				var dv := chest_basis.inverse() * (p - c)
				var e := pow(dv.x / float(body[0]), 2.0) + pow(dv.z / float(body[1]), 2.0)
				if k > 0.02 and k < 0.98 and e < pow(1.0 - CLIP_DEPTH / float(body[1]), 2.0):
					return "torso"
				if p.distance_to(head_c) < float(body[2]) - CLIP_DEPTH:
					return "head"
				for s2 in ["L", "R"]:
					var th: Vector3 = (G["thigh." + s2] as Transform3D).origin
					var sh: Vector3 = (G["shin." + s2] as Transform3D).origin
					var ft: Vector3 = (G["foot." + s2] as Transform3D).origin
					if _seg_dist(p, th, sh) < float(body[3]) - CLIP_DEPTH:
						return "thigh " + s2
					if _seg_dist(p, sh, ft) < float(body[4]) - CLIP_DEPTH:
						return "shin " + s2
				return ""
			for s in ["L", "R"]:
				var hp: Vector3 = (G["hand." + s] as Transform3D).origin
				var hit: String = parts.call(hp, s)
				if hit != "":
					found["hand %s in %s" % [s, hit]] = 1.0
				var wname := wr if s == "R" else wl
				var W: Transform3D = G["weapon." + s]
				if BLADE.has(wname):
					var seg: Array = BLADE[wname]
					for i in 9:
						var y := lerpf(float(seg[0]), float(seg[1]), i / 8.0)
						var p := W * Vector3(0, y, 0)
						var h2: String = parts.call(p, s)
						if h2 != "":
							found["%s through %s" % [wname, h2]] = 1.0
							break
					# the blade through the shield in the other hand
					if wl == "shield" and s == "R":
						var SW: Transform3D = (G["weapon.L"] as Transform3D) * ModelCatalog.prop_transform(cfg, "L") * Transform3D(Basis(), SHIELD_OFF)
						for i in 9:
							var y2 := lerpf(float(seg[0]), float(seg[1]), i / 8.0)
							var q := SW.affine_inverse() * (W * Vector3(0, y2, 0))
							if absf(q.x) < SHIELD.x and absf(q.y) < SHIELD.y and absf(q.z) < SHIELD.z:
								found["sword through shield"] = 1.0
								break
				elif wname == "shield":
					var SW2: Transform3D = W * ModelCatalog.prop_transform(cfg, "L") * Transform3D(Basis(), SHIELD_OFF)
					var hits := {}
					for ix in 5:
						for iy in 6:
							var p2 := SW2 * Vector3(lerpf(-SHIELD.x, SHIELD.x, ix / 4.0) * 0.92, lerpf(-SHIELD.y, SHIELD.y, iy / 5.0) * 0.92, 0)
							var h3: String = parts.call(p2, s)
							if h3 != "":
								hits[h3] = true
					for h4 in hits:
						found["shield through %s" % h4] = 1.0
			for k2 in found:
				counts[k2] = int(counts.get(k2, 0)) + 1
				if not worst.has(k2) or float(found[k2]) > float(worst[k2][0]):
					worst[k2] = [float(found[k2]), t]
		if counts.is_empty():
			out("  %-16s ok" % clip)
			continue
		var parts_s: Array = []
		for k3 in counts:
			var frac := float(counts[k3]) / float(n + 1)
			var wv: Array = worst[k3]
			var val := (" %d deg" % roundi(float(wv[0]))) if float(wv[0]) > 1.5 else ""
			parts_s.append("%s %d%% of frames (worst%s at %.2f s)" % [k3, roundi(frac * 100.0), val, float(wv[1])])
		hero_total += counts.size()
		out("  %-16s %s" % [clip, "; ".join(parts_s)])
	total_findings += hero_total
	out("  -> %d findings" % hero_total)
	m.queue_free()
	await process_frame

static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var k := clampf((p - a).dot(ab) / maxf(1e-6, ab.length_squared()), 0.0, 1.0)
	return p.distance_to(a + ab * k)

## The natural elbow direction for an arm along `ax` (as tests/tools/anim_repair.gd uses).
static func _ref(C: Basis, ax: Vector3, side: float) -> Vector3:
	var r1 := C * Vector3(side * 0.35, -1.0, -0.25).normalized()
	r1 = r1 - ax * r1.dot(ax)
	var r2 := C * Vector3(0.0, 0.0, -1.0)
	r2 = r2 - ax * r2.dot(ax)
	var r := r1 + r2 * 0.35
	return r.normalized() if r.length() > 1e-4 else r2.normalized()

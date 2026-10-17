extends SceneTree
## Strict animation check (run 2026-10-17 f): every hero model plays every clip the game uses for it, and each bone's
## orientation in skeleton space is compared, frame by frame, with the same clip on the reference hero skeleton
## (assets/characters/hero/hero.glb). Own bodies (tools/blender/hero_body.py) are bound in their own pose and every clip
## is retargeted so each bone keeps the clip's orientation, so any bone that turns away from the reference (a hand
## flipped round, a forearm bent the other way, a weapon pointing up instead of down) shows up here as an angle.
## Prints, per model and clip, the worst bone and its angle; FAIL above --limit degrees (default 25) on the limbs,
## hands, weapons, spine, neck and head.
##   godot --headless --path . -s tests/tools/pose_compare.gd -- [--models=hero_ezee,hero_azrin] [--limit=25] [--all]
## Sludge's own body keeps its own repaired arms (a far wider belly), so his arms differ from the hero body's by design.
## --all lists every bone over the limit, not just the worst. --raw compares the clips before RepairedClips (the
## retarget alone).

const REF := "res://assets/characters/hero/hero.glb"
const BONES := ["hips", "spine", "chest", "neck", "head", "shoulder.L", "upper_arm.L", "forearm.L", "hand.L",
	"shoulder.R", "upper_arm.R", "forearm.R", "hand.R", "weapon.R", "weapon.L", "thigh.L", "shin.L", "foot.L",
	"thigh.R", "shin.R", "foot.R"]
const SAMPLES := 12

var limit := 25.0
var all := false
var models: Array = []

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--models="):
			models = Array(a.substr(9).split(",", false))
		elif a.begins_with("--limit="):
			limit = float(a.substr(8))
		elif a == "--all":
			all = true
		elif a == "--raw":
			RepairedClips.disabled = true        # the clips as built into the bodies, before the arm repair
	if models.is_empty():
		for id in GameSettings.HEROES:
			var k := String(SimData.unit(id).model)
			if String(ModelCatalog.info(k).scene) != REF and not (k in models):
				models.append(k)
		for k in ModelCatalog.MODELS:
			if String(k).begins_with("hero_") and String(ModelCatalog.info(k).scene).contains("/heroes17/") and not (k in models):
				models.append(k)
	_run.call_deferred()

func _load(path: String) -> Node3D:
	var m := (load(path) as PackedScene).instantiate() as Node3D
	RepairedClips.patch(m)
	root.add_child(m)
	return m

func _clips(key: String) -> Array:
	var cfg := ModelCatalog.info(key)
	var out: Array = []
	for c in [cfg.get("idle", ""), cfg.get("run", ""), cfg.get("glide_clip", ""), cfg.get("cast", ""), "death"] \
			+ Array(cfg.get("attack", [])):
		if String(c) != "" and not (String(c) in out):
			out.append(String(c))
	for id in GameSettings.HEROES:
		if String(SimData.unit(id).model) != key:
			continue
		for c in [HeroStage.IDLE.get(id, ""), HeroStage.FLOURISH.get(id, "")]:
			if String(c) != "" and not (String(c) in out):
				out.append(String(c))
		for aid in SimData.unit(id).abilities:
			var an := String(SimData.ability(String(aid)).get("anim", ""))
			if an != "" and not (an in out):
				out.append(an)
	return out

## bone -> global basis (skeleton space) at time t of clip
func _pose(m: Node3D, clip: String, t: float) -> Dictionary:
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	ap.play(clip, 0.0)
	ap.seek(t, true)
	ap.pause()
	var out := {}
	for b in BONES:
		var i := sk.find_bone(b)
		if i >= 0:
			out[b] = sk.get_bone_global_pose(i).basis.orthonormalized()
	return out

## Bones that differ from the hero body on purpose: a weapon bone on an empty hand, the trunk of a body built with
## --posture (the Beast Form keeps its hunch under every clip).
func _skip(cfg: Dictionary, b: String) -> bool:
	if b.begins_with("weapon."):
		return String(cfg.get(b.get_slice(".", 1), "")) == ""
	if b in ["spine", "chest", "neck", "head"]:
		return String(cfg.scene).ends_with("ghorman_beast.glb")
	return false

func _angle(a: Basis, b: Basis) -> float:
	var q := Quaternion(a.inverse() * b).normalized()
	return rad_to_deg(2.0 * acos(clampf(absf(q.w), 0.0, 1.0)))

func _run() -> void:
	var ref := _load(REF)
	var ref_ap: AnimationPlayer = ref.find_children("*", "AnimationPlayer", true, false)[0]
	var fails := 0
	var checked := 0
	for key in models:
		var cfg := ModelCatalog.info(String(key))
		var m := _load(String(cfg.scene))
		var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
		# the rest pose itself: bones whose rest is far from the reference rest (a hand bone pointing back)
		var worst_model := 0.0
		for clip in _clips(String(key)):
			if not ap.has_animation(clip):
				print("MISSING %s %s" % [key, clip])
				fails += 1
				continue
			if not ref_ap.has_animation(clip):
				print("noref   %s %s (not on the reference skeleton)" % [key, clip])
				continue
			var length := ap.get_animation(clip).length
			var worst := 0.0
			var worst_b := ""
			var worst_t := 0.0
			var over := {}
			for s in SAMPLES:
				var t := length * float(s) / float(SAMPLES)
				var pa := _pose(m, clip, t)
				var pb := _pose(ref, clip, t)
				for b in pa:
					if not pb.has(b) or _skip(cfg, String(b)):
						continue
					var ang := _angle(pa[b], pb[b])
					if ang > worst:
						worst = ang
						worst_b = b
						worst_t = t
					if ang > limit:
						over[b] = maxf(float(over.get(b, 0.0)), ang)
			checked += 1
			worst_model = maxf(worst_model, worst)
			var bad := worst > limit
			if bad:
				fails += 1
			print("%s %-20s %-18s worst %-12s %6.1f deg at %.2fs%s" % ["FAIL" if bad else "ok  ", key, clip, worst_b, worst,
				worst_t, ("  over: " + str(over)) if all and bad else ""])
		print("== %s worst %.1f deg" % [key, worst_model])
		m.queue_free()
		await process_frame
	print("pose_compare: %d clips checked, %d failed (limit %.0f deg)" % [checked, fails, limit])
	quit(1 if fails > 0 else 0)

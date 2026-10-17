class_name RepairedClips
extends RefCounted
## The repaired animation clips (run 2026-10-15 g). The clips built into the hero bodies and the humanoid unit models
## come from the beyond-heroes procedural library, whose hand IK flips elbows and spins forearms between frames and
## pushes weapons through bodies. tests/tools/anim_repair.gd solves the arms of every clip again on each model's own
## rig and saves the arm tracks to one library per model; patch() copies them over the matching tracks of a model's
## clips. A model's clips are shared by every copy of it, so each library is patched once.
##   hero body (and Azrin's, the same skeleton)   FIXED
##   Sludge's body (a far wider belly)            FIXED_SLUDGE
##   each humanoid unit model                     res://assets/characters/units/anim_fixed/<model>.res
##   each 2026-10-17 hero body (heroes17)         FIXED as well (same bone tracks as the hero body)

const FIXED := "res://assets/characters/hero/hero_anims_fixed.res"
const FIXED_SLUDGE := "res://assets/characters/hero/hero_anims_fixed_sludge.res"
const UNIT_DIR := "res://assets/characters/units/anim_fixed/"

static var _sets := {}                      # library path -> AnimationLibrary (or null when missing)
static var disabled := false                # tools only (--raw): leave the clips as built

## The repaired library for a model scene.
static func path_for(scene_path: String) -> String:
	if scene_path.ends_with("sludge.glb"):
		return FIXED_SLUDGE
	if scene_path.contains("/units/"):
		return UNIT_DIR + scene_path.get_file().get_basename() + ".res"
	if scene_path.contains("/heroes17/"):
		# the 2026-10-17 hero bodies (tools/blender/hero_body.py) are bound in their own pose, and every clip is
		# retargeted so each bone keeps the hero clip's orientation: their bone tracks are the hero body's, so the hero
		# body's repaired arms fit them as they are. (Repairing them on their own rest flipped arms and wrists: the
		# repair measures twist and elbow swivel from the rest, and their rest has the arms hanging; run 2026-10-17 f,
		# tests/tools/pose_compare.gd.)
		return FIXED
	return FIXED

## Every unit model scene the game uses (the repair tool skips those without arms: wolves, couriers).
static func unit_models() -> Array:
	var out: Array = []
	for key in ModelCatalog.MODELS:
		var cfg: Dictionary = ModelCatalog.MODELS[key]
		for p in [String(cfg.scene), String(cfg.get("scene_dusk", ""))]:
			if p.contains("/units/") and not (p in out):
				out.append(p)
	return out

## Lay the repaired arm tracks over every clip of `model` (the instanced model scene).
static func patch(model: Node) -> void:
	if model == null or disabled:
		return
	var path := path_for(String(model.scene_file_path))
	if not _sets.has(path):
		_sets[path] = load(path) as AnimationLibrary if ResourceLoader.exists(path) else null
	var fixed: AnimationLibrary = _sets[path]
	if fixed == null:
		return
	for ap: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		for ln in ap.get_animation_library_list():
			var lib := ap.get_animation_library(ln)
			if lib == null or lib.has_meta("arms_fixed"):
				continue
			lib.set_meta("arms_fixed", true)
			for clip in fixed.get_animation_list():
				if lib.has_animation(clip):
					_copy_arms(fixed.get_animation(clip), lib.get_animation(clip))

## Replace the keys of each bone track in `dst` that `src` has (matched by bone name).
static func _copy_arms(src: Animation, dst: Animation) -> void:
	var by_bone := {}
	for t in dst.get_track_count():
		if dst.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			by_bone[String(dst.track_get_path(t)).get_slice(":", 1)] = t
	for t in src.get_track_count():
		var bone := String(src.track_get_path(t)).get_slice(":", 1)
		if not by_bone.has(bone):
			continue
		var d: int = by_bone[bone]
		while dst.track_get_key_count(d) > 0:
			dst.track_remove_key(d, 0)
		for k in src.track_get_key_count(t):
			dst.rotation_track_insert_key(d, src.track_get_key_time(t, k), src.track_get_key_value(t, k))

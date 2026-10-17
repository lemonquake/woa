class_name MocapClips
extends RefCounted
## Motion-capture clips for the hero skeleton (run 2026-10-18 d; the owner asked for downloaded animations, Mixamo,
## that look great). tools/blender/mocap_retarget.py puts each clip on the hero rig and tests/tools/mocap_import.gd
## saves them as one library: every bone's full local turn (the same on every hero-skeleton body: the shared hero,
## Sludge and the heroes17 bodies), and the hips' offset from the hero's resting hip height. add() gives each such
## model its own copy with the hips on its own resting height.
##
## The library and its collision fixes live in assets/characters/hero/mocap/, which git leaves out: Mixamo's terms
## allow its clips inside a game but not as loose files in a public repository. Without that folder every hero plays
## its old clips (ModelCatalog.info only applies a model's "mocap" entry when the library loads).

const DIR := "res://assets/characters/hero/mocap/"
const LIB := DIR + "hero_mocap.res"
const META := DIR + "mocap_meta.json"

static var disabled := false                 # tools only (--nomocap): the old clips
static var _lib: AnimationLibrary = null
static var _tried := false

static func library() -> AnimationLibrary:
	if not _tried:
		_tried = true
		if ResourceLoader.exists(LIB):
			_lib = load(LIB) as AnimationLibrary
	return _lib

static func available() -> bool:
	return not disabled and library() != null

## A model on the hero skeleton (the mocap clips fit it).
static func fits(scene_path: String) -> bool:
	return scene_path.contains("/characters/hero/") or scene_path.contains("/heroes17/")

## The collision fixes of the mocap clips for a model scene (tests/tools/body_collide.gd writes them here).
static func collide_path(scene_path: String) -> String:
	return DIR + "collide/" + scene_path.get_file().get_basename() + ".res"

## A hero-skeleton body's leg length against the hero rig's (its resting hip height over the hero's): the hips'
## moves and the run's ground speed scale with it. 1.0 for any other skeleton or without the library.
static func leg_scale(sk: Skeleton3D) -> float:
	if sk == null or library() == null or sk.owner == null or not fits(String(sk.owner.scene_file_path)):
		return 1.0
	var hips := sk.find_bone("hips")
	var hero: Variant = library().get_meta("hips_rest", null)
	if hips < 0 or not (hero is Vector3) or (hero as Vector3).y <= 0.01:
		return 1.0
	return clampf(sk.get_bone_rest(hips).origin.y / (hero as Vector3).y, 0.5, 1.6)

## Add every mocap clip the model does not have yet to its clip library (once per library: the library is shared by
## every copy of the model).
static func add(model: Node) -> void:
	if model == null or not available() or not fits(String(model.scene_file_path)):
		return
	var src := library()
	for ap: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		var sks := model.find_children("*", "Skeleton3D", true, false)
		if sks.is_empty():
			return
		var sk: Skeleton3D = sks[0]
		var hips := sk.find_bone("hips")
		if hips < 0 or sk.find_bone("hand.R") < 0:
			return
		var rest := sk.get_bone_rest(hips).origin
		# the hips' moves (a crouch, a fall to the floor, a step) scale with the body's leg length: a short-legged
		# body given the hero's metres sank into the floor in its deaths (Ser Emelrich, 26 cm)
		var k := leg_scale(sk)
		var prefix := String(ap.get_node(ap.root_node).get_path_to(sk))
		for ln in ap.get_animation_library_list():
			var lib := ap.get_animation_library(ln)
			if lib == null or lib.has_meta("mocap_added"):
				continue
			lib.set_meta("mocap_added", true)
			for clip in src.get_animation_list():
				if lib.has_animation(clip):
					continue
				var a := (src.get_animation(clip) as Animation).duplicate(true) as Animation
				for t in a.get_track_count():
					var bone := String(a.track_get_path(t)).get_slice(":", 1)
					a.track_set_path(t, NodePath(prefix + ":" + bone))
					if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
						for i in a.track_get_key_count(t):
							a.track_set_key_value(t, i, rest + (a.track_get_key_value(t, i) as Vector3) * k)
				lib.add_animation(clip, a)
			return

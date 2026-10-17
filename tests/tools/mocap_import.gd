extends SceneTree
## Motion-capture clips into the game (run 2026-10-18 d): reads the GLB tools/blender/mocap_retarget.py wrote (the hero
## rig with only the new clips), keeps each bone's turn and the hips' offset from the hero's resting hip height, and
## saves them as one AnimationLibrary for MocapClips; the clip timings (mocap_meta.json, written next to the GLB by
## the retarget) are copied beside it.
##   godot --headless --path . -s tests/tools/mocap_import.gd -- [--src=work/mocap/hero_mocap.glb]

var _src := "work/mocap/hero_mocap.glb"

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			_src = a.substr(6)
	_run.call_deferred()

func _run() -> void:
	var path := _src if _src.is_absolute_path() else ProjectSettings.globalize_path("res://" + _src)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		print("cannot read %s: %s" % [path, error_string(err)])
		quit(1)
		return
	var scene := doc.generate_scene(state)
	var aps := scene.find_children("*", "AnimationPlayer", true, false)
	var sks := scene.find_children("*", "Skeleton3D", true, false)
	if aps.is_empty() or sks.is_empty():
		print("no clips or no skeleton in ", path)
		quit(1)
		return
	var ap: AnimationPlayer = aps[0]
	var sk: Skeleton3D = sks[0]
	var hips_rest := sk.get_bone_rest(sk.find_bone("hips")).origin
	var lib := AnimationLibrary.new()
	var n_keys := 0
	for clip in ap.get_animation_list():
		var a := ap.get_animation(clip)
		var b := Animation.new()
		b.length = a.length
		b.step = 1.0 / 30.0
		for t in a.get_track_count():
			var bone := String(a.track_get_path(t)).get_slice(":", 1)
			if bone == "" or bone == "root" or bone.begins_with("weapon."):
				continue
			var ty := a.track_get_type(t)
			if ty == Animation.TYPE_ROTATION_3D:
				var nt := b.add_track(Animation.TYPE_ROTATION_3D)
				b.track_set_path(nt, NodePath("Skeleton3D:" + bone))
				for k in a.track_get_key_count(t):
					b.rotation_track_insert_key(nt, a.track_get_key_time(t, k), a.track_get_key_value(t, k))
					n_keys += 1
			elif ty == Animation.TYPE_POSITION_3D and bone == "hips":
				var nt := b.add_track(Animation.TYPE_POSITION_3D)
				b.track_set_path(nt, NodePath("Skeleton3D:" + bone))
				for k in a.track_get_key_count(t):
					b.position_track_insert_key(nt, a.track_get_key_time(t, k), (a.track_get_key_value(t, k) as Vector3) - hips_rest)
					n_keys += 1
		lib.add_animation(clip, b)
	lib.set_meta("hips_rest", hips_rest)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MocapClips.DIR))
	err = ResourceSaver.save(lib, MocapClips.LIB)
	print("wrote %s: %d clips, %d keys (%s)" % [MocapClips.LIB, lib.get_animation_list().size(), n_keys, error_string(err)])
	var meta_src := path.get_base_dir().path_join("mocap_meta.json")
	if FileAccess.file_exists(meta_src):
		var txt := FileAccess.get_file_as_string(meta_src)
		var f := FileAccess.open(MocapClips.META, FileAccess.WRITE)
		f.store_string(txt)
		f.close()
		print("copied clip timings to ", MocapClips.META)
	scene.free()
	quit()

extends SceneTree
## Prints how far the hips travel (start -> end) in the given hero clips, to tell a back step from a forward one.
func _init() -> void:
	var s: Node3D = (load("res://assets/characters/hero/hero.glb") as PackedScene).instantiate()
	var ap: AnimationPlayer = s.find_children("*", "AnimationPlayer", true, false)[0]
	for clip in ["dodge_step", "dodge_roll", "blink", "walk_back", "knockback", "bow_release", "bow_draw_hold"]:
		if not ap.has_animation(clip):
			print(clip, " missing")
			continue
		var a := ap.get_animation(clip)
		for i in a.get_track_count():
			var path := String(a.track_get_path(i))
			if a.track_get_type(i) == Animation.TYPE_POSITION_3D and (path.ends_with("hips") or path.ends_with("Hips") or path.ends_with("pelvis") or path.ends_with("root")):
				var p0: Vector3 = a.position_track_interpolate(i, 0.0)
				var p1: Vector3 = a.position_track_interpolate(i, a.length)
				var pm: Vector3 = a.position_track_interpolate(i, a.length * 0.4)
				print("%s %s len=%.2f start=%s mid=%s end=%s" % [clip, path, a.length, p0, pm, p1])
	s.free()
	quit()

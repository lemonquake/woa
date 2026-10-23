extends SceneTree
## Dumps a hero-skeleton body's bones (parent, rest, global rest) and one mocap clip's tracks.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://assets/characters/heroes17/dracoxinia.glb"
	var clip := "drac_run"
	for a in args:
		if a.begins_with("--glb="):
			path = a.substr(6)
		elif a.begins_with("--clip="):
			clip = a.substr(7)
	var n: Node = (load(path) as PackedScene).instantiate()
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	print("bones ", sk.get_bone_count())
	for i in sk.get_bone_count():
		var r := sk.get_bone_rest(i)
		var g := sk.get_bone_global_rest(i)
		print("%d %s parent=%d pos=%s rot=%s gpos=%s gbasisY=%s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i),
			str(r.origin.snapped(Vector3.ONE * 0.001)), str(r.basis.get_rotation_quaternion()),
			str(g.origin.snapped(Vector3.ONE * 0.001)), str(g.basis.y.snapped(Vector3.ONE * 0.01))])
	var lib: AnimationLibrary = load("res://assets/characters/hero/mocap/hero_mocap.res")
	print("lib meta ", lib.get_meta_list(), " hips_rest ", lib.get_meta("hips_rest", null))
	var a: Animation = lib.get_animation(clip)
	print("clip ", clip, " length ", a.length, " loop ", a.loop_mode, " tracks ", a.get_track_count())
	for t in mini(a.get_track_count(), 80):
		print("  ", a.track_get_path(t), " type ", a.track_get_type(t), " keys ", a.track_get_key_count(t),
			" first ", a.track_get_key_value(t, 0))
	quit()

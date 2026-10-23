extends SceneTree
## Bone by bone, the local turn between two frames of the built hand-made clips (hero_hand.res).
##   -- --a=drac_h_idle@0.8 --b=drac_h_run@0.0

func _key(a: Animation, bone: String, t: float) -> Quaternion:
	var tr := a.find_track(NodePath("Skeleton3D:" + bone), Animation.TYPE_ROTATION_3D)
	return a.rotation_track_interpolate(tr, t) if tr >= 0 else Quaternion()

func _init() -> void:
	var a := "drac_h_idle@0.8"
	var b := "drac_h_run@0.0"
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--a="):
			a = x.substr(4)
		elif x.begins_with("--b="):
			b = x.substr(4)
	var lib: AnimationLibrary = load("res://assets/characters/hero/hand/hero_hand.res")
	var ca := lib.get_animation(a.get_slice("@", 0))
	var cb := lib.get_animation(b.get_slice("@", 0))
	for bone in ["chest", "shoulder.R", "upper_arm.R", "forearm.R", "hand.R", "upper_arm.L", "forearm.L", "hand.L"]:
		var qa := _key(ca, bone, float(a.get_slice("@", 1)))
		var qb := _key(cb, bone, float(b.get_slice("@", 1)))
		print("%-12s %6.1f deg" % [bone, rad_to_deg(qa.angle_to(qb))])
	quit()

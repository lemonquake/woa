extends SceneTree
## Compares two hand-made clip poses bone by bone (local turn angle between them) to find where a join's gap comes from.
##   -- --a=drac_h_run@0.0 --b=drac_h_idle@0.0

func _init() -> void:
	var a := "drac_h_run@0.0"
	var b := "drac_h_idle@0.0"
	for x in OS.get_cmdline_user_args():
		if x.begins_with("--a="):
			a = x.substr(4)
		elif x.begins_with("--b="):
			b = x.substr(4)
	var Set: GDScript = load("res://tools/anim/clips_dracoxinia.gd")
	var Rig: GDScript = load("res://tools/anim/hand_rig.gd")
	var body: Node = (load(Set.BODY) as PackedScene).instantiate()
	root.add_child(body)
	var sk: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	var rig = Rig.new()
	rig.setup(sk)
	var cs = Set.new()
	cs.rig = rig
	var clips: Dictionary = cs.clips()
	var pa: Dictionary = rig.solve(clips[a.get_slice("@", 0)].pose.call(float(a.get_slice("@", 1))))
	var pb: Dictionary = rig.solve(clips[b.get_slice("@", 0)].pose.call(float(b.get_slice("@", 1))))
	for n in rig.names:
		if not pa.has(n) or not pb.has(n):
			continue
		var qa := (pa[n] as Transform3D).basis.get_rotation_quaternion()
		var qb := (pb[n] as Transform3D).basis.get_rotation_quaternion()
		print("%-12s %6.1f deg" % [n, rad_to_deg(qa.angle_to(qb))])
	quit()

extends SceneTree
## Applies the hand-made run to Dracoxinia's skeleton and prints, per frame, the left leg's hip, knee and ankle
## (skeleton globals) against the ankle the clip wanted, and whether the knee lies in front of the hip-ankle line.

func _init() -> void:
	var Set: GDScript = load("res://tools/anim/clips_dracoxinia.gd")
	var Rig: GDScript = load("res://tools/anim/hand_rig.gd")
	var body: Node = (load(Set.BODY) as PackedScene).instantiate()
	root.add_child(body)
	var sk: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	var rig = Rig.new()
	rig.setup(sk)
	var cs = Set.new()
	cs.rig = rig
	var clip: String = "drac_h_run"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.substr(7)
	var spec: Dictionary = cs.clips()[clip]
	for i in 11:
		var t := float(spec.length) * i / 10.0
		var c: Dictionary = spec.pose.call(t)
		var p: Dictionary = rig.solve(c)
		for b in p:
			if b == "_g" or not (p[b] is Transform3D):
				continue
			var bi := sk.find_bone(b)
			sk.set_bone_pose_rotation(bi, (p[b] as Transform3D).basis.get_rotation_quaternion())
			sk.set_bone_pose_position(bi, (p[b] as Transform3D).origin)
		sk.force_update_all_bone_transforms()
		for s in ["L", "R"]:
			var g: Dictionary = p._g
			var hip: Vector3 = (g["thigh." + s] as Transform3D).origin
			var knee: Vector3 = (g["shin." + s] as Transform3D).origin
			var ank: Vector3 = (g["foot." + s] as Transform3D).origin
			var want: Vector3 = c["leg." + s].ankle
			var line := hip.lerp(ank, 0.5)
			print("t %.2f %s hip %s knee %s ankle %s want %s  knee ahead %.3f" % [t, s, hip.snapped(Vector3.ONE * 0.01),
				knee.snapped(Vector3.ONE * 0.01), ank.snapped(Vector3.ONE * 0.01), want.snapped(Vector3.ONE * 0.01),
				knee.z - line.z])
	quit()

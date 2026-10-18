extends SceneTree
func _init() -> void:
	for p in ["res://assets/characters/hero/hero.glb", "res://assets/characters/heroes17/ezee.glb", "res://assets/characters/heroes17/emelrich.glb", "res://assets/characters/heroes17/burak.glb", "res://assets/characters/heroes17/feran.glb"]:
		if not ResourceLoader.exists(p):
			print("missing ", p); continue
		var n: Node = (load(p) as PackedScene).instantiate()
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		var line: String = p.get_file() + ": "
		for b in ["hips", "spine", "spine.001", "spine.002", "spine.003", "chest", "neck", "thigh.L", "shin.L", "upper_arm.R"]:
			var i := sk.find_bone(b)
			if i < 0: continue
			var r := sk.get_bone_rest(i)
			line += "%s o=%s q=%s | " % [b, r.origin.snapped(Vector3.ONE*0.01), r.basis.get_rotation_quaternion().get_euler().snapped(Vector3.ONE*0.01)]
		print(line)
		print("  bones: ", sk.get_bone_count(), " first: ", [sk.get_bone_name(0), sk.get_bone_name(1), sk.get_bone_name(2), sk.get_bone_name(3), sk.get_bone_name(4)])
	quit()

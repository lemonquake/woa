extends SceneTree
func _init() -> void:
	var n := (load("res://assets/characters/hero/hero.glb") as PackedScene).instantiate()
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var out := []
	for i in sk.get_bone_count():
		out.append(sk.get_bone_name(i))
	print(" ".join(out))
	n.free()
	quit()

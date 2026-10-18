extends SceneTree
func _init() -> void:
	var n: Node = (load("res://assets/characters/heroes17/emelrich.glb") as PackedScene).instantiate()
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var names: Array = []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	print(names)
	quit()

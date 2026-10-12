extends SceneTree
## Prints each building model's footprint and height (metres at scale 1) for sizing checks.
func _init() -> void:
	for n in ["tower_dawn", "tower_dusk", "rax_melee_dawn", "ancient_dawn", "effigy_dawn", "fountain_dawn"]:
		var s: Node3D = (load("res://assets/buildings/%s.glb" % n) as PackedScene).instantiate()
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in s.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = _xf(mi) * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		print("%s size=%s pos=%s" % [n, box.size, box.position])
		s.free()
	quit()

func _xf(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

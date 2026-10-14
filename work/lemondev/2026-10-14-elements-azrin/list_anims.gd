extends SceneTree
func _init() -> void:
	var s: PackedScene = load("res://assets/characters/hero/hero.glb")
	var n := s.instantiate()
	var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
	var names := ap.get_animation_list()
	var out := []
	for a in names:
		out.append("%s(%.2f)" % [a, ap.get_animation(a).length])
	print(" ".join(out))
	quit()

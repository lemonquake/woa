extends SceneTree
func _init() -> void:
	var d := SimKits5._push_travel(1150.0)
	print("travel at 1150: ", d, "  70%: ", d * 0.7, " -> speed ", SimKits5.push_speed_for(d * 0.7))
	quit()

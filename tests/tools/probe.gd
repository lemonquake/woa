extends SceneTree
func _init() -> void:
	var m := SimMap.new(); m.build(1)
	var tb := TerrainBuilder.new(m)
	tb.V = int(SimMap.HALF * 2.0 / tb.STEP) + 1
	tb._heights()
	var s := ""
	for d in range(-1400, 1500, 100):
		var p := Vector2(d, d) * 0.7071 + Vector2(-1500, 1500)
		s += "%d:%d/%d " % [d, m.height_at(p), tb.height_at(p)]
	print(s)
	quit()

extends SceneTree
func _init() -> void:
	var m := SimMap.new()
	m.build(1)
	for p in [Vector2(1594, -7182), Vector2(1510, -7172), Vector2(1500, -7150)]:
		var c := m.world_to_cell(p)
		var s := ""
		for oy in range(4, -5, -1):
			for ox in range(-6, 7):
				var cc := Vector2i(c.x + ox, c.y + oy)
				s += "." if m.is_walkable_cell(cc) else ("T" if m.tree_cell[cc.y * SimMap.N + cc.x] >= 0 else "#")
			s += "\n"
		print(p, " walk ", m.is_walkable(p), " level ", m.level_at(p), "\n", s)
		var path := m.find_path(Vector2(-450, -6350), p)
		print("path from lane: ", path.size(), " end ", path[-1] if path.size() > 0 else Vector2.INF)
	quit()

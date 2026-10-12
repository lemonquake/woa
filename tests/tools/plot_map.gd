extends SceneTree
## Plot the sim map: levels, cliffs, trees, lanes, paths, camps, buildings, ramps. Writes work/shots/map_plot.png
func _init():
	var m := SimMap.new()
	m.build(1)
	var N := SimMap.N
	var img := Image.create(N * 3, N * 3, false, Image.FORMAT_RGB8)
	for cy in N:
		for cx in N:
			var l := m.level[cy * N + cx]
			var col: Color = [Color(0.2, 0.35, 0.7), Color(0.45, 0.6, 0.3), Color(0.75, 0.7, 0.45), Color(0.5, 0.45, 0.45)][mini(l, 3)]
			if m.walkable[cy * N + cx] == 0:
				col = col.darkened(0.45)
			if m.tree_cell[cy * N + cx] >= 0:
				col = Color(0.1, 0.3, 0.1)
			if m.is_cliff_cell(cx, cy):
				col = Color(0.3, 0.2, 0.15)
			for oy in 3:
				for ox in 3:
					img.set_pixel(cx * 3 + ox, (N - 1 - cy) * 3 + oy, col)
	var w2p := func(p: Vector2) -> Vector2i:
		return Vector2i(int((p.x + SimMap.HALF) / SimMap.CELL * 3), int((SimMap.HALF - p.y) / SimMap.CELL * 3))
	var dot := func(p: Vector2, r: int, c: Color):
		var q: Vector2i = w2p.call(p)
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + y * y <= r * r and q.x + x >= 0 and q.y + y >= 0 and q.x + x < N * 3 and q.y + y < N * 3:
					img.set_pixel(q.x + x, q.y + y, c)
	for pth in m.paths:
		for i in pth.size() - 1:
			for s in 40:
				dot.call(pth[i].lerp(pth[i + 1], s / 40.0), 1, Color(0.9, 0.8, 0.5))
	for k in m.lanes:
		for side in [1.0, -1.0]:
			var ln: PackedVector2Array = m.lanes[k]
			for i in ln.size() - 1:
				for s in 80:
					dot.call(ln[i].lerp(ln[i + 1], s / 80.0) * side, 1, Color(1, 1, 1))
	for r in m.ramps:
		dot.call(r.pos, int(r.radius / SimMap.CELL * 3), Color(1, 0.5, 0))
	for c in m.camps:
		dot.call(c.pos, 6, Color(1, 0.2, 0.9))
	for b in m.buildings:
		dot.call(b.pos, 5, Color(0.3, 0.8, 1) if b.team == 0 else Color(1, 0.3, 0.3))
	img.save_png("work/shots/map_plot.png")
	quit()

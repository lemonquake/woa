extends SceneTree
## Check the neutral camp layout: for each camp of Dawn's side print how clear it stands of lanes, walkways, ramps,
## the river, buildings and other camps, whether its spawn box is all walkable ground on one level, and plot the map
## with the boxes to work/shots/camp_layout.png.
##   godot --headless --path . -s tests/tools/camp_layout.gd
func _init() -> void:
	var m := SimMap.new()
	m.build(1)
	var bad := 0
	for c in m.camps:
		if c.side != SimConst.DAWN:
			continue
		var r := _check(m, c, c.pos)
		if not r.ok:
			bad += 1
			# the nearest spot within 1200 that passes (ignoring the camp's own trees, which follow it)
			var best := Vector2.INF
			var bd := INF
			for oy in range(-12, 13):
				for ox in range(-12, 13):
					var q: Vector2 = c.pos + Vector2(ox, oy) * 100.0
					if q.distance_to(c.pos) < bd and _check(m, c, q).ok:
						bd = q.distance_to(c.pos)
						best = q
			print("    nearest good spot: ", best)
	# every camp (both sides) reachable on foot from both fountains
	for c in m.camps:
		for f in m.fountains:
			var path := m.find_path(f, c.pos)
			if path.is_empty() or path[-1].distance_to(c.pos) > 200.0:
				bad += 1
				print("UNREACHABLE camp %d from %s" % [c.id, str(f)])
	print("camps with problems: ", bad)
	# map sites (Warp Gates, Lily Ponds, Lookout Lamps): on walkable ground, reachable from both fountains, a gate's
	# exit walkable too
	var sbad := 0
	for st in m.sites:
		var spots: Array = [st.pos]
		if String(st.kind) == "gate":
			spots.append(st.exit)
		for sp: Vector2 in spots:
			if not m.is_walkable(sp):
				sbad += 1
				print("SITE %s at %s: not walkable" % [st.kind, str(sp)])
			for f in m.fountains:
				var path := m.find_path(f, sp)
				if path.is_empty() or path[-1].distance_to(sp) > 200.0:
					sbad += 1
					print("SITE %s at %s: unreachable from %s" % [st.kind, str(sp), str(f)])
		print("site %-5s %s pair %d" % [st.kind, str(st.pos), int(st.pair)])
	print("sites with problems: ", sbad)
	_plot(m)
	quit()

func _plot(m: SimMap) -> void:
	var n := SimMap.N
	var img := Image.create(n * 3, n * 3, false, Image.FORMAT_RGB8)
	for cy in n:
		for cx in n:
			var l := m.level[cy * n + cx]
			var col: Color = [Color(0.2, 0.35, 0.7), Color(0.45, 0.6, 0.3), Color(0.75, 0.7, 0.45), Color(0.5, 0.45, 0.45)][mini(l, 3)]
			if m.tree_cell[cy * n + cx] >= 0:
				col = Color(0.1, 0.3, 0.1)
			if m.is_cliff_cell(cx, cy):
				col = Color(0.3, 0.2, 0.15)
			for oy in 3:
				for ox in 3:
					img.set_pixel(cx * 3 + ox, (n - 1 - cy) * 3 + oy, col)
	var w2p := func(p: Vector2) -> Vector2i:
		return Vector2i(int((p.x + SimMap.HALF) / SimMap.CELL * 3), int((SimMap.HALF - p.y) / SimMap.CELL * 3))
	for c in m.camps:
		var box: Vector2 = c.box
		var a: Vector2i = w2p.call(c.pos - box)
		var b: Vector2i = w2p.call(c.pos + box)
		var col: Color = {"small": Color(1, 1, 0.3), "medium": Color(1, 0.7, 0.2), "large": Color(1, 0.4, 0.1), "ancient": Color(1, 0.1, 0.6)}[c.kind]
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			for y in [a.y, b.y]:
				if x >= 0 and y >= 0 and x < n * 3 and y < n * 3:
					img.set_pixel(x, y, col)
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for x in [a.x, b.x]:
				if x >= 0 and y >= 0 and x < n * 3 and y < n * 3:
					img.set_pixel(x, y, col)
	for st in m.sites:
		var c2: Vector2i = w2p.call(st.pos)
		var scol: Color = {"gate": Color(0.75, 0.45, 1.0), "pond": Color(1.0, 0.55, 0.8), "lamp": Color(1.0, 1.0, 1.0)}[st.kind]
		for oy in range(-5, 6):
			for ox in range(-5, 6):
				if ox * ox + oy * oy <= 25 and c2.x + ox >= 0 and c2.y + oy >= 0 and c2.x + ox < n * 3 and c2.y + oy < n * 3:
					img.set_pixel(c2.x + ox, c2.y + oy, scol)
	img.save_png("work/shots/camp_layout.png")

func _check(m: SimMap, c: Dictionary, p: Vector2) -> Dictionary:
	var lane := 1e9
	for k in m.lanes:
		lane = minf(lane, SimMap._polyline_distance(p, m.lanes[k]))
		lane = minf(lane, SimMap._polyline_distance(-p, m.lanes[k]))
	var path := 1e9
	for pth in m.paths:
		path = minf(path, SimMap._polyline_distance(p, pth))
	var ramp := 1e9
	for r in m.ramps:
		ramp = minf(ramp, p.distance_to(r.pos) - float(r.radius))
	var bld := 1e9
	for b in m.buildings:
		bld = minf(bld, p.distance_to(b.pos))
	var other := 1e9
	for o in m.camps:
		if o.id != c.id and o.side == c.side or o.id != c.id and o.pos.distance_to(p) < 900.0:
			other = minf(other, p.distance_to(o.pos))
	var river := absf(p.x + p.y) / sqrt(2.0)
	var box: Vector2 = c.box
	var blocked := 0
	var levels := {}
	var y := -box.y
	while y <= box.y:
		var x := -box.x
		while x <= box.x:
			var q := p + Vector2(x, y)
			var cc := m.world_to_cell(q)
			if m.is_cliff_cell(cc.x, cc.y) or m.level_at(q) == SimMap.MOUNTAIN:
				blocked += 1
			levels[m.level_at(q)] = true
			x += 32.0
		y += 32.0
	var ok := lane > (500 if c.pull else 600) and ramp > 150 and bld > 800 and other > 900 and river > 800 and levels.size() == 1 and blocked <= 2
	if p == c.pos:
		print("%s %2d %-7s %s lane %4d path %4d ramp %4d bld %4d camp %4d river %4d levels %d blocked %d" % [
			"ok " if ok else "BAD", c.id, c.kind, str(p), lane, path, ramp, bld, other, river, levels.size(), blocked])
	return {"ok": ok}

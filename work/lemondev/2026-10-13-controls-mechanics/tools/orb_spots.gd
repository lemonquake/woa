extends SceneTree
## Look for orb spots on the map: nearest walkable cell of the wanted level to each candidate, its distance to camps,
## lanes and the fountain path.
func _init() -> void:
	var m := SimMap.new()
	m.build(1)
	var want := {"power_top": [Vector2(-1300, 1300), SimMap.RIVER], "power_bot": [Vector2(1300, -1300), SimMap.RIVER],
		"bounty_dawn": [Vector2(-3300, -900), SimMap.GROUND], "bounty_dusk": [Vector2(3300, 900), SimMap.GROUND],
		"wisdom_left": [Vector2(-6300, 1200), -1], "wisdom_right": [Vector2(6300, -1200), -1],
		"wisdom_left2": [Vector2(-5200, 900), -1], "wisdom_right2": [Vector2(5200, -900), -1],
		"wisdom_left3": [Vector2(-5400, 2200), -1], "wisdom_right3": [Vector2(5400, -2200), -1]}
	for k in want:
		var t: Vector2 = want[k][0]
		var lv: int = want[k][1]
		var best := Vector2.INF
		for r in range(0, 1600, 32):
			for a in 32:
				var p := t + Vector2.from_angle(a * TAU / 32.0) * r
				if not m.is_walkable(p) or (lv >= 0 and m.level_at(p) != lv) or m.in_ramp(p):
					continue
				if m.tree_at(p, 180.0) >= 0:
					continue
				best = p
				break
			if best != Vector2.INF:
				break
		var camp := INF
		for c in m.camps:
			camp = minf(camp, (c.pos as Vector2).distance_to(best))
		var lane := INF
		for ln in m.lanes:
			var pl: PackedVector2Array = m.lanes[ln]
			for i in pl.size() - 1:
				var cp := Geometry2D.get_closest_point_to_segment(best, pl[i], pl[i + 1])
				lane = minf(lane, cp.distance_to(best))
		var path0 := m.find_path(m.fountains[0], best).size()
		var path1 := m.find_path(m.fountains[1], best).size()
		print("%s %s level %d camp %.0f lane %.0f path %d/%d" % [k, str(best.round()), m.level_at(best), camp, lane, path0, path1])
	quit()

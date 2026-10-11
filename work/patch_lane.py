def rw(p, pairs):
    s = open(p, encoding='utf-8', newline='').read()
    for a, b in pairs:
        if b in s:
            continue
        if a not in s:
            raise SystemExit("missing in %s: %s" % (p, a[:70]))
        s = s.replace(a, b)
    open(p, 'w', encoding='utf-8', newline='').write(s)

rw('src/game/dressing.gd', [
    # stronger, larger contact pools
    ('''			img.set_pixel(x, y, Color(0.02, 0.025, 0.015, clampf(1.0 - d, 0.0, 1.0) ** 1.6 * 0.6))''',
     '''			img.set_pixel(x, y, Color(0.015, 0.02, 0.01, clampf(1.0 - d, 0.0, 1.0) ** 1.3 * 0.82))'''),
    ('''		blob(p, clampf(foot * 0.55, 0.12, 2.2))''', '''		blob(p, clampf(foot * 0.7, 0.16, 2.6))'''),
    # path slabs sit flush, not floating
    ('''						_add(slab, q, _rng.randf_range(0.55, 0.95), 0.07)''', '''						_add(slab, q, _rng.randf_range(0.55, 0.95), 0.1)'''),
    # curb stones: a continuous edged border along both sides of every lane, plus ruins and landmarks
    ('''	_lane_edges()
	_river_banks()''', '''	_lane_edges()
	_curbs()
	_ruins()
	_river_banks()'''),
    ('''## River banks: rocks and reeds where the ground drops into the water.''', '''## Curbs: square edging stones set end to end along both lane edges, so the road reads as a built lane with a clear
## border (gaps where the lane meets the river and inside the bases).
func _curbs() -> void:
	for line: PackedVector2Array in _lane_lines:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var dir := (b - a).normalized()
			var side := dir.orthogonal()
			var length := a.distance_to(b)
			var t := 40.0
			while t < length - 40.0:
				var base := a + dir * t
				t += _rng.randf_range(78.0, 96.0)
				for sgn in [-1.0, 1.0]:
					var p: Vector2 = base + side * sgn * _rng.randf_range(238.0, 250.0)
					if _in_river(p) or map.level_at(p) == SimMap.HIGH or _rng.randf() < 0.07:
						continue
					var slab: String = ["RockPath_Square_Small_1", "RockPath_Square_Small_2", "RockPath_Square_Small_3"][_rng.randi_range(0, 2)]
					var yaw := -dir.angle() + PI * 0.5 + _rng.randf_range(-0.12, 0.12)
					_add(slab, p, _rng.randf_range(0.62, 0.75), 0.05, false, yaw)

## Ruins and landmarks beside the lanes: broken columns, standing arches and statues every ~2.5 km of lane,
## alternating sides, themed per faction.
func _ruins() -> void:
	var k := 0
	for line: PackedVector2Array in _lane_lines:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var dir := (b - a).normalized()
			var length := a.distance_to(b)
			var t := 900.0
			while t < length - 600.0:
				k += 1
				var sgn := 1.0 if k % 2 == 0 else -1.0
				var p := a + dir * t + dir.orthogonal() * sgn * _rng.randf_range(470.0, 560.0)
				t += _rng.randf_range(2100.0, 2700.0)
				if _in_river(p) or map.level_at(p) == SimMap.HIGH or map.tree_at(p, 150.0) >= 0 and _rng.randf() < 0.3:
					continue
				var face := (-dir.orthogonal() * sgn).angle()
				var dusk := _dusk(p)
				match k % 4:
					0:
						_add("kd_column", p, _rng.randf_range(0.9, 1.15), 0.1, true, -1.0, 0.12)
						_add("kd_column", p + dir * 220.0, _rng.randf_range(0.5, 0.7), 0.05, true, -1.0, 0.25)
						_add("kd_debris_stone", p + dir * 110.0 + dir.orthogonal() * 60.0, 1.0, 0.05, false)
					1:
						_add("arch", p, _rng.randf_range(0.75, 0.9), 0.1, true, -face + PI * 0.5)
					2:
						if dusk:
							_add("basalt_column", p, 0.45, 0.15, true)
						else:
							_add("kf_gothic_statue", p, 1.25, 0.05, true, -face + PI * 0.5)
					3:
						_add("kd_obelisk", p, _rng.randf_range(0.9, 1.1), 0.05, true)
						_add("kf_lantern_cage", p + dir * 140.0, 1.0, 0.0, true)

## River banks: rocks and reeds where the ground drops into the water.'''),
])

# soft contact shadow under every unit
rw('src/game/unit_view.gd', [
    ('''	_make_ring(u)
	_play(String(cfg.idle), true)''', '''	_make_ring(u)
	var shade := MeshInstance3D.new()
	shade.mesh = Dressing.blob_mesh()
	var r := maxf(u.hull, 16.0) * View.S * 3.2
	shade.scale = Vector3(r, 1.0, r)
	shade.position.y = 0.04
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shade)
	_play(String(cfg.idle), true)'''),
])
print("ok")

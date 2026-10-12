class_name Landscape
extends Node3D
## Built landscape on top of the terrain: what turns the bases into fortresses and the high ground into places.
##   * Base walls: crenellated stone walls along the top of every base cliff, round towers at corners and every few
##     segments, gate towers with torches and banners flanking each ramp.
##   * Ramps: stone stairs following the slope of every ramp (base and jungle plateaus), torch pillars at the top.
##   * Plazas: an emblem slab between fountain and Ancient (Dawn sun, Dusk crescent), framed by stone blocks.
##   * Roads: paved base roads (stamped into the terrain splat, see base_roads()), braziers along them.
##   * Gardens and groves: flower beds, hedges, blossom trees (Dawn); dead trees, graves and bones (Dusk).
##   * Mountains: boulders and cliff rocks at the foot, pines on the lower slopes.
## Purely visual and deterministic. Procedural pieces are MultiMesh-instanced; model props go through Dressing._add.

const C = preload("res://src/sim/sim_const.gd")
const BUILDING_SHADER := preload("res://src/game/building.gdshader")
const FLAME_SHADER := preload("res://src/game/flame.gdshader")
const EMBLEM_SHADER := preload("res://src/game/emblem.gdshader")
const BANNER_SHADER := preload("res://src/game/banner.gdshader")
const TEX := "res://assets/textures/building/"
const WALL_LEN := 160.0                    # game units per wall segment

var map: SimMap
var terrain: TerrainBuilder
var dressing: Dressing
var _rng := RandomNumberGenerator.new()
var _inst := {}                            # piece key -> [Transform3D]
var _meshes := {}                          # piece key -> Mesh
var _shadow := {}                          # piece key -> casts shadows
var flames: Array = []                     # [Vector3 world position, team] (lights for some)

## Paved roads inside Dawn's base (Dusk's are the same rotated 180 degrees). Used by the terrain splat too.
static func base_roads() -> Array:
	var f := Vector2(-7050, -6650)
	var anc := Vector2(-5800, -5350)
	return [
		PackedVector2Array([f, Vector2(-6425, -6000), anc]),
		PackedVector2Array([anc, Vector2(-6150, -4600), Vector2(-6550, -4350), Vector2(-6550, -3600)]),
		PackedVector2Array([anc, Vector2(-5000, -4650), Vector2(-4420, -4020)]),
		PackedVector2Array([anc, Vector2(-5050, -5700), Vector2(-4350, -6350), Vector2(-4150, -6350)]),
	]

func build(p_map: SimMap, p_terrain: TerrainBuilder, p_dressing: Dressing) -> void:
	map = p_map
	terrain = p_terrain
	dressing = p_dressing
	name = "Landscape"
	_rng.seed = map.seed_value * 977 + 5
	_make_meshes()
	for team in [C.DAWN, C.DUSK]:
		_walls(team)
		_plaza(team)
		_road_dressing(team)
		_gardens(team)
	for team in [C.DAWN, C.DUSK]:
		_stall(team)
		_supplies(team)
		_paving_edges(team)
	_ramps()
	_mountain_props()
	_emit()

# ---- Geometry helpers ---------------------------------------------------------------------------------------------

## Mirror a Dawn-side point for a team.
static func side(p: Vector2, team: int) -> Vector2:
	return p if team == C.DAWN else -p

func _h(p: Vector2) -> float:
	return terrain.height_at(p) * View.S

func _put(key: String, p: Vector2, yaw: float, scale := Vector3.ONE, lift := 0.0) -> void:
	if not _inst.has(key):
		_inst[key] = []
	var b := Basis(Vector3.UP, yaw) * Basis.from_scale(scale)    # local scale (Basis.scaled would shear rotated boxes)
	_inst[key].append(Transform3D(b, View.to3(p, 0.0) + Vector3(0, _h(p) + lift, 0)))

static func _box(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n * h
		var uu := u * h
		var vv := v * h
		var q := [o - uu - vv, o + uu - vv, o + uu + vv, o - uu + vv]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_uv(Vector2(q[i].dot(u), q[i].dot(v)))
			st.add_vertex(q[i])

## An n-sided upright prism (radius r, from y0 to y1), optionally tapering to r1 at the top.
static func _prism(st: SurfaceTool, c: Vector3, r: float, y0: float, y1: float, sides := 8, r1 := -1.0, cap := true) -> void:
	if r1 < 0.0:
		r1 = r
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := c + Vector3(cos(a0) * r, y0, sin(a0) * r)
		var p1 := c + Vector3(cos(a1) * r, y0, sin(a1) * r)
		var q0 := c + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var q1 := c + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var n := Vector3(cos((a0 + a1) * 0.5), (r - r1) / maxf(0.01, y1 - y0), sin((a0 + a1) * 0.5)).normalized()
		for v in [p0, q1, p1, p0, q0, q1]:
			st.set_normal(n)
			st.set_uv(Vector2(atan2(v.z - c.z, v.x - c.x) * r, v.y))
			st.add_vertex(v)
		if cap and r1 > 0.0:
			for v in [c + Vector3(0, y1, 0), q1, q0]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z))
				st.add_vertex(v)

func _stone(team: int, tex := "ph_castle_brick_02_white", scale := 0.9, blocks := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BUILDING_SHADER
	var t := tex if team == C.DAWN else "ph_rough_block_wall"
	m.set_shader_parameter("albedo_tex", load(TEX + t + "_albedo.png"))
	m.set_shader_parameter("normal_tex", load(TEX + t + "_normal.png"))
	m.set_shader_parameter("rough_tex", load(TEX + t + "_rough.png"))
	m.set_shader_parameter("tint", Color(0.93, 0.88, 0.78) if team == C.DAWN else Color(0.42, 0.38, 0.44))
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("blocks", blocks)
	m.set_shader_parameter("base_y", -100.0)
	return m

func _commit(st: SurfaceTool, mat: Material) -> ArrayMesh:
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m

func _make_meshes() -> void:
	for team in [C.DAWN, C.DUSK]:
		var sfx := "_d" if team == C.DAWN else "_k"
		var stone := _stone(team)
		# wall segment: plinth, body, two merlons (local x along the wall, z out of the base)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(st, Vector3(0, -0.12, 0), Vector3(WALL_LEN * View.S + 0.04, 0.5, 0.86))
		_box(st, Vector3(0, 0.55, 0), Vector3(WALL_LEN * View.S + 0.02, 1.3, 0.62))
		for mx in [-0.42, 0.42]:
			_box(st, Vector3(mx, 1.38, 0.0), Vector3(0.44, 0.38, 0.66))
		_meshes["wall" + sfx] = _commit(st, stone)
		_shadow["wall" + sfx] = true
		# round wall tower with a crown of merlons and a roof
		var tw := SurfaceTool.new()
		tw.begin(Mesh.PRIMITIVE_TRIANGLES)
		_prism(tw, Vector3.ZERO, 0.78, -0.6, 2.3, 10, 0.68)
		_prism(tw, Vector3.ZERO, 0.86, 2.3, 2.55, 10)
		for i in 10:
			var a := TAU * i / 10.0
			if i % 2 == 0:
				_box(tw, Vector3(cos(a) * 0.76, 2.75, sin(a) * 0.76), Vector3(0.3, 0.4, 0.3))
		_meshes["tower" + sfx] = _commit(tw, stone)
		_shadow["tower" + sfx] = true
		var roof := SurfaceTool.new()
		roof.begin(Mesh.PRIMITIVE_TRIANGLES)
		_prism(roof, Vector3.ZERO, 0.62, 2.55, 3.9, 10, 0.0, false)
		var rm := ShaderMaterial.new()
		rm.shader = BUILDING_SHADER
		rm.set_shader_parameter("albedo_tex", load(TEX + "ph_clay_roof_tiles_02_albedo.png"))
		rm.set_shader_parameter("normal_tex", load(TEX + "ph_clay_roof_tiles_02_normal.png"))
		rm.set_shader_parameter("rough_tex", load(TEX + "ph_clay_roof_tiles_02_rough.png"))
		rm.set_shader_parameter("tint", Color(0.36, 0.42, 0.7) if team == C.DAWN else Color(0.36, 0.1, 0.12))
		rm.set_shader_parameter("scale", 1.4)
		rm.set_shader_parameter("blocks", 0.0)
		rm.set_shader_parameter("base_y", -100.0)
		_meshes["roof" + sfx] = _commit(roof, rm)
		_shadow["roof" + sfx] = true
		# torch pillar: square shaft, capital and a fire bowl (the flame is a separate instance)
		var pl := SurfaceTool.new()
		pl.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(pl, Vector3(0, -0.15, 0), Vector3(0.78, 0.4, 0.78))
		_box(pl, Vector3(0, 0.1, 0), Vector3(0.6, 0.16, 0.6))
		_prism(pl, Vector3.ZERO, 0.2, 0.18, 1.75, 8, 0.17)
		_prism(pl, Vector3.ZERO, 0.17, 1.75, 1.86, 8, 0.27)
		_box(pl, Vector3(0, 1.9, 0), Vector3(0.5, 0.1, 0.5))
		_meshes["pillar" + sfx] = _commit(pl, stone)
		_shadow["pillar" + sfx] = true
		var bowl := SurfaceTool.new()
		bowl.begin(Mesh.PRIMITIVE_TRIANGLES)
		_prism(bowl, Vector3.ZERO, 0.12, 1.95, 2.18, 10, 0.3)
		for i in 4:
			var a := TAU * i / 4.0 + 0.785
			_box(bowl, Vector3(cos(a) * 0.27, 2.12, sin(a) * 0.27), Vector3(0.05, 0.22, 0.05))
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.16, 0.14, 0.13) if team == C.DAWN else Color(0.1, 0.07, 0.07)
		iron.metallic = 0.7
		iron.roughness = 0.45
		_meshes["bowl" + sfx] = _commit(bowl, iron)
		_shadow["bowl" + sfx] = true
		_shadow["pillar" + sfx] = true
		# plaza border block and stair block
		var bb := SurfaceTool.new()
		bb.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(bb, Vector3(0, 0, 0), Vector3(1, 1, 1))
		var bm := _stone(team, "ph_castle_brick_02_white", 0.45, 0.0)
		bm.set_shader_parameter("tint", Color(0.8, 0.78, 0.74) if team == C.DAWN else Color(0.36, 0.33, 0.36))
		bm.set_shader_parameter("side_dark", 0.42)
		_meshes["block" + sfx] = _commit(bb, bm)
		_shadow["block" + sfx] = true
		# emblem slab
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		var em := ShaderMaterial.new()
		em.shader = EMBLEM_SHADER
		em.set_shader_parameter("stone_tex", load(TEX + ("ph_medieval_blocks_02_albedo.png" if team == C.DAWN else "ph_volcanic_rock_tiles_albedo.png")))
		em.set_shader_parameter("stone_tint", Color(0.4, 0.6, 0.58) if team == C.DAWN else Color(0.2, 0.17, 0.2))
		em.set_shader_parameter("inlay", Color(0.98, 0.76, 0.34) if team == C.DAWN else Color(0.85, 0.16, 0.14))
		em.set_shader_parameter("motif", 0 if team == C.DAWN else 1)
		pm.material = em
		_meshes["emblem" + sfx] = pm
		# banner: a pole with a hanging cloth strip
		var bp := SurfaceTool.new()
		bp.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(bp, Vector3(0, 1.6, 0), Vector3(0.08, 3.4, 0.08))
		_box(bp, Vector3(0.3, 3.1, 0), Vector3(0.8, 0.06, 0.06))
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.3, 0.22, 0.14) if team == C.DAWN else Color(0.12, 0.1, 0.1)
		pole_mat.metallic = 0.3
		pole_mat.roughness = 0.6
		_meshes["pole" + sfx] = _commit(bp, pole_mat)
		_shadow["pole" + sfx] = true
		var cloth := PlaneMesh.new()
		cloth.size = Vector2(0.7, 1.7)
		cloth.subdivide_width = 3
		cloth.subdivide_depth = 8
		cloth.orientation = PlaneMesh.FACE_Z
		cloth.center_offset = Vector3(0.32, 2.2, 0.0)
		var cm := ShaderMaterial.new()
		cm.shader = BANNER_SHADER
		cm.set_shader_parameter("cloth", Color(0.14, 0.3, 0.75) if team == C.DAWN else Color(0.45, 0.04, 0.07))
		cm.set_shader_parameter("trim", Color(0.96, 0.78, 0.38) if team == C.DAWN else Color(0.12, 0.1, 0.1))
		cloth.material = cm
		_meshes["cloth" + sfx] = cloth
		_shadow["cloth" + sfx] = true
		# quartermaster's stall: plank counter and posts, a striped cloth canopy, a patterned rug
		var planks := ShaderMaterial.new()
		planks.shader = BUILDING_SHADER
		planks.set_shader_parameter("albedo_tex", load(TEX + "ph_weathered_planks_albedo.png"))
		planks.set_shader_parameter("normal_tex", load(TEX + "ph_weathered_planks_normal.png"))
		planks.set_shader_parameter("rough_tex", load(TEX + "ph_weathered_planks_rough.png"))
		planks.set_shader_parameter("tint", Color(0.78, 0.6, 0.42) if team == C.DAWN else Color(0.4, 0.3, 0.28))
		planks.set_shader_parameter("scale", 1.2)
		planks.set_shader_parameter("blocks", 0.0)
		planks.set_shader_parameter("base_y", -100.0)
		var sl := SurfaceTool.new()
		sl.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(sl, Vector3(0, 0.45, 0.55), Vector3(3.2, 0.9, 0.7))
		_box(sl, Vector3(0, 0.93, 0.55), Vector3(3.4, 0.08, 0.86))
		for px in [-1.6, 1.6]:
			for pz in [-0.9, 1.0]:
				_box(sl, Vector3(px, 1.3, pz), Vector3(0.14, 2.6 if pz < 0.0 else 2.2, 0.14))
		_box(sl, Vector3(-0.8, 0.35, -0.5), Vector3(1.0, 0.7, 0.8))
		_meshes["stall" + sfx] = _commit(sl, planks)
		_shadow["stall" + sfx] = true
		var canopy := PlaneMesh.new()
		canopy.size = Vector2(3.8, 2.4)
		canopy.subdivide_width = 6
		canopy.subdivide_depth = 4
		var cs := ShaderMaterial.new()
		cs.shader = BANNER_SHADER
		cs.set_shader_parameter("cloth", Color(0.82, 0.74, 0.58) if team == C.DAWN else Color(0.35, 0.08, 0.1))
		cs.set_shader_parameter("trim", Color(0.18, 0.36, 0.78) if team == C.DAWN else Color(0.1, 0.08, 0.08))
		cs.set_shader_parameter("wind", 0.25)
		cs.set_shader_parameter("emblem", 0.0)
		cs.set_shader_parameter("stripes", 7.0)
		cs.set_shader_parameter("notch", 0.0)
		canopy.material = cs
		var cst := SurfaceTool.new()
		cst.create_from(canopy, 0)
		var cmesh := cst.commit()
		var cxf := Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-14.0)), Vector3(0, 2.45, 0.05))
		var cm2 := ArrayMesh.new()
		var cst2 := SurfaceTool.new()
		cst2.append_from(cmesh, 0, cxf)
		cst2.commit(cm2)
		cm2.surface_set_material(0, cs)
		_meshes["canopy" + sfx] = cm2
		_shadow["canopy" + sfx] = true
		var rug := PlaneMesh.new()
		rug.size = Vector2(1, 1)
		var rm2 := ShaderMaterial.new()
		rm2.shader = BANNER_SHADER
		rm2.set_shader_parameter("cloth", Color(0.55, 0.16, 0.12) if team == C.DAWN else Color(0.18, 0.12, 0.2))
		rm2.set_shader_parameter("trim", Color(0.92, 0.72, 0.36))
		rm2.set_shader_parameter("wind", 0.0)
		rm2.set_shader_parameter("notch", 0.0)
		rug.material = rm2
		_meshes["rug" + sfx] = rug
		# flame
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		q.center_offset = Vector3(0, 0.5, 0)
		var fm := ShaderMaterial.new()
		fm.shader = FLAME_SHADER
		if team == C.DUSK:
			fm.set_shader_parameter("core", Color(1.0, 0.6, 0.45))
			fm.set_shader_parameter("edge", Color(0.85, 0.08, 0.12))
		q.material = fm
		_meshes["flame" + sfx] = q
		_shadow["flame" + sfx] = false

static func _sfx(team: int) -> String:
	return "_d" if team == C.DAWN else "_k"

func _flame(p: Vector2, team: int, lift: float, size := 0.55) -> void:
	_put("flame" + _sfx(team), p, 0.0, Vector3(size, size * 1.5, size), lift)
	flames.append([View.to3(p, 0.0) + Vector3(0, _h(p) + lift + size * 0.5, 0), team])

func _pillar(p: Vector2, team: int, yaw := 0.0) -> void:
	_put("pillar" + _sfx(team), p, yaw + PI / 8.0)
	_put("bowl" + _sfx(team), p, yaw)
	_flame(p, team, 2.05, 0.7)
	dressing.blob(p, 0.75)
	# growth and a stone or two at its foot, so it stands in the ground rather than on it
	for k in 2:
		var g := p + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(45.0, 70.0)
		dressing._add("Grass_Wispy_Short" if team == C.DAWN else "kd_mushrooms_pale", g, _rng.randf_range(0.6, 0.9), 0.0)

## A banner on a pole; the crossbar and cloth point along `out` (a sim direction).
func _banner(p: Vector2, team: int, out: Vector2) -> void:
	_put("pole" + _sfx(team), p, out.angle())
	_put("cloth" + _sfx(team), p, out.angle())

# ---- Base walls -----------------------------------------------------------------------------------------------------

## Dawn's base edge as straight runs (start, end, outward normal); see SimMap._in_base. Mirrored for Dusk.
func _wall_runs() -> Array:
	return [
		[Vector2(-7900, -3700), Vector2(-4470, -3700), Vector2(0, 1)],
		[Vector2(-4300, -3870), Vector2(-4300, -7900), Vector2(1, 0)],
	]

func _blocked_wall(p: Vector2) -> bool:
	for r in map.ramps:
		if p.distance_to(r.pos) < float(r.radius) + 90.0:
			return true
	return map.level_at(p) == SimMap.MOUNTAIN or terrain.mountain_dist(p) > 0.0

func _walls(team: int) -> void:
	var sfx := _sfx(team)
	for run in _wall_runs():
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var n: Vector2 = run[2]
		var inset := 120.0
		var dir := (b - a).normalized()
		var length := a.distance_to(b)
		var count := int(length / WALL_LEN)
		var since_tower := 0
		var was_open := true
		for i in count:
			var c := a + dir * (i + 0.5) * WALL_LEN - n * inset
			var pc := side(c, team)
			var open := _blocked_wall(c + n * inset * 0.5)
			if open:
				if not was_open:
					# the wall ends at a ramp: a gate tower with a banner and a torch pillar beside the stairs
					var g := a + dir * i * WALL_LEN - n * inset
					_tower(side(g, team), team, side(n, team))
				was_open = true
				continue
			if was_open and i > 0:
				var g2 := a + dir * i * WALL_LEN - n * inset
				_tower(side(g2, team), team, side(n, team))
				since_tower = 0
			was_open = false
			_put("wall" + sfx, pc, side(dir, team).angle(), Vector3.ONE, -0.15)
			dressing.blob(pc, 1.0)
			if _rng.randf() < 0.35:
				dressing._add("Grass_Wispy_Tall" if team == C.DAWN else "Grass_Wispy_Short", pc - side(n, team) * 70.0, _rng.randf_range(0.7, 1.0), 0.0)
			since_tower += 1
			if since_tower >= 7 and i < count - 2:
				_tower(side(a + dir * (i + 1) * WALL_LEN - n * inset, team), team, side(n, team))
				since_tower = 0

## A round wall tower with a roof; its banner hangs out over the cliff (`out`, a sim direction).
func _tower(p: Vector2, team: int, out: Vector2) -> void:
	var sfx := _sfx(team)
	_put("tower" + sfx, p, _rng.randf() * TAU, Vector3.ONE, -0.1)
	_put("roof" + sfx, p, 0.0, Vector3.ONE, -0.1)
	dressing.blob(p, 1.3)
	_banner(p + out * 80.0, team, out)

# ---- Ramps ----------------------------------------------------------------------------------------------------------

## Stone stairs on every ramp: rows of blocks across the slope from the bottom to the top, torch pillars at the top.
func _ramps() -> void:
	for r in map.ramps:
		var c: Vector2 = r.pos
		var rad := float(r.radius)
		# uphill direction from the simulation's smooth heights
		var g := Vector2(map.height_at(c + Vector2(80, 0)) - map.height_at(c - Vector2(80, 0)),
			map.height_at(c + Vector2(0, 80)) - map.height_at(c - Vector2(0, 80)))
		if g.length() < 1.0:
			continue
		var up := g.normalized()
		var across := up.orthogonal()
		var team := C.DAWN if (c.x + c.y) < 0.0 else C.DUSK
		var plateau := bool(r.get("plateau", false))
		var width := rad * (1.25 if plateau else 1.35)
		var sfx := _sfx(team)
		var top := c
		var lo_h := INF
		var hi_h := -INF
		for t in range(-int(rad * 1.3), int(rad * 1.3), 20):
			var hh := map.height_at(c + up * t)
			lo_h = minf(lo_h, hh)
			hi_h = maxf(hi_h, hh)
		var t0 := -rad * 1.3
		var step := 85.0
		var t := t0
		var bottom := Vector2(INF, INF)
		while t < rad * 1.3:
			var p := c + up * t
			var hh := map.height_at(p)
			if hh > lo_h + 8.0 and hh < hi_h - 8.0:
				if bottom.x == INF:
					bottom = p
				# one step: a row of dressed slabs whose top is the walking height here, with a tall riser in front
				var x := -width * 0.5
				while x < width * 0.5 - 10.0:
					var bw := _rng.randf_range(90.0, 150.0)
					bw = minf(bw, width * 0.5 - x)
					var q := p + across * (x + bw * 0.5)
					var yaw := across.angle() + _rng.randf_range(-0.03, 0.03)
					# the tread sits level with the ground at its back edge, so the slope never shows through
					var back := (terrain.height_at(q + up * step * 0.5) - terrain.height_at(q)) * View.S
					_put("block" + sfx, q, yaw, Vector3(bw * View.S * 0.97, 0.6, step * View.S * 1.06), back - 0.26)
					x += bw
				# low retaining walls along both sides, stepping with the stairs
				for sd in [-1.0, 1.0]:
					var wq: Vector2 = p + across * sd * (width * 0.5 + 28.0)
					_put("block" + sfx, wq, across.angle(), Vector3(0.5, 1.0, step * View.S * 1.04), 0.0)
					if _rng.randf() < 0.35:
						dressing._add("Grass_Wispy_Short" if _rng.randf() < 0.5 else "Fern_1", wq + across * sd * 60.0, _rng.randf_range(0.7, 1.0), 0.0)
				top = p
			t += step
		# pillars with torches on both sides of the top step (and the bottom one), banners on base ramps
		for s in [-1.0, 1.0]:
			var pp: Vector2 = top + up * 40.0 + across * s * (width * 0.5 + 45.0)
			_pillar(pp, team)
			if not plateau:
				_banner(pp + up * 70.0, team, across * s)
			if bottom.x != INF:
				_pillar(bottom - up * 50.0 + across * s * (width * 0.5 + 45.0), team)
		# a few loose stones and grass at the foot
		for k in 6:
			var fp := c - up * rad * 1.2 + across * _rng.randf_range(-width * 0.6, width * 0.6)
			dressing._add(["kf_stones", "kf_rocks", "Grass_Wispy_Tall"][k % 3], fp, [0.6, 2.5, 0.9][k % 3], 0.02)

# ---- Plaza ----------------------------------------------------------------------------------------------------------

## The emblem slab between fountain and Ancient, framed by stone blocks, statues on the corners, braziers.
func _plaza(team: int) -> void:
	var sfx := _sfx(team)
	var c := side(Vector2(-6425, -6000), team)
	var size := 560.0
	var yaw := PI * 0.25
	var ax := Vector2.from_angle(PI * 0.25)
	var ay := ax.orthogonal()
	_put("emblem" + sfx, c, yaw, Vector3(size * View.S, 1.0, size * View.S), 0.06)
	# border: long blocks along the edges, chunky corner stones
	for e in 4:
		var n := [ax, ay, -ax, -ay][e] as Vector2
		var tng := n.orthogonal()
		var k := -size * 0.5
		while k < size * 0.5:
			var len := minf(_rng.randf_range(90.0, 150.0), size * 0.5 - k)
			var q := c + n * (size * 0.5 + 35.0) + tng * (k + len * 0.5)
			_put("block" + sfx, q, tng.angle(), Vector3(len * View.S * 0.95, 0.22, 0.62), 0.02)
			k += len
		var corner := c + (n + n.orthogonal()) * (size * 0.5 + 35.0)
		_put("block" + sfx, corner, n.angle() + 0.785, Vector3(0.95, 0.42, 0.95), 0.06)
		var outward := (corner - c).normalized()
		if team == C.DAWN:
			dressing._add("kf_gothic_statue", corner + outward * 120.0, 1.15, 0.05, true, (c - corner).angle() + PI * 0.5)
		else:
			dressing._add("basalt_column", corner + outward * 110.0, 0.5, 0.1, true)
			dressing._add("bones_scatter", corner + outward * 200.0, 0.6, 0.02)
		_pillar(corner + outward * 260.0 + n.orthogonal() * 120.0, team)

# ---- Roads ----------------------------------------------------------------------------------------------------------

## Kerbs along the paved base roads, braziers and banners at intervals, lanterns (Dawn) or graves (Dusk).
func _road_dressing(team: int) -> void:
	for road: PackedVector2Array in base_roads():
		var acc := 0.0
		for i in road.size() - 1:
			var a := side(road[i], team)
			var b := side(road[i + 1], team)
			var d := (b - a).normalized()
			var nrm := d.orthogonal()
			var length := a.distance_to(b)
			var s := 0.0
			while s < length:
				var p := a + d * s
				var in_plaza := p.distance_to(side(Vector2(-6425, -6000), team)) < 520.0
				for sd in [-1.0, 1.0]:
					var e: Vector2 = p + nrm * sd * 262.0
					if not in_plaza and _clear(e, 120.0):
						# a kerb of dressed stones along the paving, tufts and ferns growing against it
						_put("block" + _sfx(team), e, d.angle() + _rng.randf_range(-0.05, 0.05),
							Vector3(0.62, 0.16, 0.3), 0.02)
						var g: Vector2 = e + nrm * sd * _rng.randf_range(40.0, 110.0)
						var r := _rng.randf() if not _in_plaza(g, team) else 1.0
						if r < 0.35:
							dressing._add("Grass_Wispy_Short" if team == C.DAWN else "Grass_Wispy_Tall", g, _rng.randf_range(0.7, 1.1), 0.0)
						elif r < 0.5:
							dressing._add("Fern_1" if team == C.DAWN else "kd_mushrooms_pale", g, _rng.randf_range(0.6, 0.9), 0.0)
						elif r < 0.56:
							dressing._add("Pebble_Round_2", g, _rng.randf_range(0.6, 1.0), 0.02)
				if fmod(acc + s, 620.0) < 70.0 and not in_plaza:
					var sd2 := 1.0 if int((acc + s) / 620.0) % 2 == 0 else -1.0
					var bp := p + nrm * sd2 * 330.0
					if _clear(bp, 200.0):
						if team == C.DAWN:
							dressing._add("brazier", bp, 0.9, 0.02, true)
							_flame(bp, team, 0.95, 0.5)
						else:
							dressing._add("kd_fire_basket", bp, 1.0, 0.02, true)
							_flame(bp, team, 1.0, 0.5)
				s += 70.0
			acc += length

## Inside the emblem plaza (and its border) of a team's base.
func _in_plaza(p: Vector2, team: int) -> bool:
	var d := (p - side(Vector2(-6425, -6000), team)).rotated(-PI * 0.25)
	return absf(d.x) < 400.0 and absf(d.y) < 400.0

## Nothing important (buildings, the fountain pool, lanes) within r of p.
func _clear(p: Vector2, r: float) -> bool:
	for b in map.buildings:
		if p.distance_to(b.pos) < float(SimData.unit(b.unit).hull) + r:
			return false
	return map.level_at(p) != SimMap.MOUNTAIN and map.is_walkable(p)

# ---- Lived-in clutter ---------------------------------------------------------------------------------------------

## The quartermaster's stall at the side shop by the fountain: a plank counter under a striped canopy on four posts,
## crates, barrels, a lantern, a rug and a brazier.
func _stall(team: int) -> void:
	var sfx := _sfx(team)
	# beside the fountain, clear of the plaza (the shop's range covers the fountain area)
	var c := side(Vector2(-7250, -5950), team)
	var toward: Vector2 = ((map.fountains[team] as Vector2) - c).normalized()
	var yaw := toward.orthogonal().angle()
	_put("stall" + sfx, c, yaw)
	_put("canopy" + sfx, c, yaw)
	var side_v := toward.orthogonal()
	dressing._add("kf_crate_a", c - toward * 170.0 + side_v * 200.0, 0.6, 0.0, true)
	dressing._add("kf_crate_a", c - toward * 120.0 + side_v * 250.0, 0.45, 0.0, true)
	dressing._add("kf_barrels", c - toward * 160.0 - side_v * 230.0, 0.7, 0.0, true)
	dressing._add("kf_lantern", c + toward * 120.0 + side_v * 230.0, 0.9, 0.0, true)
	dressing.blob(c, 2.2)
	dressing._add("kf_crate_a", c + side_v * 60.0 - toward * 60.0, 0.4, -0.85, true)
	dressing._add("Grass_Wispy_Short", c + toward * 200.0 + side_v * 120.0, 0.9, 0.0)
	dressing._add("Grass_Wispy_Short", c - toward * 230.0 - side_v * 60.0, 0.8, 0.0)
	if team == C.DAWN:
		dressing._add("brazier", c + toward * 120.0 - side_v * 260.0, 0.8, 0.02, true)
	else:
		dressing._add("kd_fire_basket", c + toward * 120.0 - side_v * 260.0, 0.9, 0.02, true)
	_flame(c + toward * 120.0 - side_v * 260.0, team, 0.9, 0.45)
	_banner(c - toward * 60.0 + side_v * 330.0, team, toward)

## Supplies stacked by each barracks and tier 3 / 4 tower (the side away from the lane): crates, barrels, a fence
## stretch, a banner, and grass at the foot of it all.
func _supplies(team: int) -> void:
	for b in map.buildings:
		if int(b.team) != team:
			continue
		var unit := String(b.unit)
		if not (unit.ends_with("rax") or unit in ["tower3", "tower4"]):
			continue
		var p: Vector2 = b.pos
		var hull := float(SimData.unit(unit).hull)
		# the open side: away from the nearest lane
		var best := Vector2.ZERO
		var best_d := INF
		for k in map.lanes:
			var ln: PackedVector2Array = map.lanes[k]
			for i in ln.size() - 1:
				var q := Geometry2D.get_closest_point_to_segment(p, side(ln[i], team), side(ln[i + 1], team))
				if q.distance_to(p) < best_d:
					best_d = q.distance_to(p)
					best = q
		var away := (p - best).normalized() if best_d > 1.0 else Vector2.from_angle(_rng.randf() * TAU)
		var tang := away.orthogonal()
		var o := p + away * (hull + 150.0)
		if not _clear(o, 60.0):
			continue
		dressing._add("kf_crate_a", o + tang * 90.0, _rng.randf_range(0.45, 0.6), 0.0, true, _rng.randf() * TAU)
		dressing._add("kf_barrels", o - tang * 100.0, _rng.randf_range(0.55, 0.7), 0.0, true)
		if _rng.randf() < 0.6:
			dressing._add("kd_fence", o + away * 120.0, 0.9, 0.02, true, tang.angle())
		if _rng.randf() < 0.5:
			_banner(o + tang * 200.0, team, away)
		for k in 3:
			dressing._add("Grass_Wispy_Tall" if team == C.DAWN else "kd_mushrooms_pale",
				o + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(80.0, 180.0), _rng.randf_range(0.7, 1.0), 0.0)

## Where the base paving meets grass: loose flagstones, pebbles and tufts so the edge is worn rather than a line.
func _paving_edges(team: int) -> void:
	for b in map.buildings:
		if int(b.team) != team:
			continue
		var def := SimData.unit(b.unit)
		var r := float(def.hull) * 1.5 + 260.0
		if b.unit == "fountain":
			r = 1000.0
		elif b.unit == "ancient":
			r = 900.0
		var n := int(r * TAU / 140.0)
		for k in n:
			if _rng.randf() > 0.55:
				continue
			var a := TAU * k / n + _rng.randf_range(-0.05, 0.05)
			var p: Vector2 = (b.pos as Vector2) + Vector2.from_angle(a) * (r + _rng.randf_range(-90.0, 40.0))
			if not _clear(p, 40.0) or _in_plaza(p, team):
				continue
			var x := _rng.randf()
			if x < 0.25:
				dressing._add("Fern_1" if team == C.DAWN else "Grass_Wispy_Tall", p, _rng.randf_range(0.6, 0.9), 0.0)
			elif x < 0.7:
				dressing._add("Grass_Wispy_Short" if team == C.DAWN else "Grass_Wispy_Tall", p, _rng.randf_range(0.7, 1.0), 0.0)
			elif x < 0.85:
				dressing._add("Pebble_Round_%d" % _rng.randi_range(1, 4), p, _rng.randf_range(0.5, 0.8), 0.04)
			else:
				dressing._add("Clover_1" if team == C.DAWN else "kd_mushrooms_pale", p, _rng.randf_range(0.7, 1.0), 0.0)

# ---- Gardens --------------------------------------------------------------------------------------------------------

## Open lawn inside the base gets flower beds, hedge rows and blossom trees (Dawn), or dead trees, graves, bones and
## basalt (Dusk). Kept off roads, lanes and building footprints.
func _gardens(team: int) -> void:
	var roads := base_roads()
	var spots: Array = []
	var y := -7900.0
	while y < -3900.0:
		var x := -7900.0
		while x < -4500.0:
			var p := Vector2(x + _rng.randf_range(-120, 120), y + _rng.randf_range(-120, 120))
			x += 360.0
			if not (map.level_at(p) == SimMap.HIGH):
				continue
			var near_road := false
			for rd: PackedVector2Array in roads:
				if SimMap._polyline_distance(p, rd) < 420.0:
					near_road = true
			for k in map.lanes:
				if SimMap._polyline_distance(p, map.lanes[k]) < 480.0:
					near_road = true
			if near_road or not _clear(p, 300.0) or p.distance_to(Vector2(-6425, -6000)) < 650.0:
				continue
			if p.distance_to(map.fountains[0]) < 900.0:
				continue
			spots.append(p)
		y += 360.0
	for p0: Vector2 in spots:
		var p := side(p0, team)
		var r := _rng.randf()
		if team == C.DAWN:
			if r < 0.3:
				dressing._add("blossom", p, _rng.randf_range(0.8, 1.15), 0.0, true)
				for k in 4:
					dressing._add("kd_flower_purple" if k % 2 == 0 else "kd_flower_yellow", p + Vector2.from_angle(k * 1.57 + 0.4) * 140.0, _rng.randf_range(0.8, 1.2), 0.0)
			elif r < 0.55:
				# a round flower bed edged with stones
				for k in 9:
					var a := k * TAU / 9.0
					dressing._add("RockPath_Round_Small_1", p + Vector2.from_angle(a) * 150.0, 0.9, 0.03)
				for k in 6:
					dressing._add(["kd_flower_yellow", "kd_flower_purple", "Bush_Common_Flowers"][k % 3], p + Vector2.from_angle(k * 1.05) * _rng.randf_range(20.0, 100.0), _rng.randf_range(0.9, 1.3), 0.0)
			elif r < 0.75:
				for k in 3:
					dressing._add("Bush_Common_Flowers" if k == 1 else "Bush_Common", p + Vector2(k * 110.0 - 110.0, 0).rotated(0.785), _rng.randf_range(0.9, 1.2), 0.0, true)
			elif r < 0.85:
				dressing._add("kf_lantern", p, 1.0, 0.0, true)
			else:
				dressing._add("crystal_pylon", p, 0.8, 0.05, true)
		else:
			if r < 0.35:
				dressing._add(["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4"][_rng.randi_range(0, 3)], p, _rng.randf_range(0.8, 1.2), 0.0, true)
				dressing._add("bones_scatter", p + Vector2(90, 40), 0.5, 0.02)
			elif r < 0.6:
				for k in 3:
					dressing._add("gravestone_a" if k % 2 == 0 else "gravestone_b", p + Vector2(k * 120.0 - 120.0, 0).rotated(-0.785), _rng.randf_range(0.8, 1.0), 0.05, true, -1.0, 0.12)
			elif r < 0.75:
				dressing._add("basalt_column", p, _rng.randf_range(0.4, 0.6), 0.1, true)
			elif r < 0.85:
				dressing._add("kd_fire_basket", p, 1.0, 0.02, true)
				_flame(p, team, 1.0, 0.5)
			else:
				dressing._add("kd_grave_broken", p, 1.1, 0.05, true)
				dressing._add("kd_mushrooms_pale", p + Vector2(60, -40), 1.0, 0.0)
	# torch pillars around the fountain and the Ancient
	for k in 4:
		var a := k * TAU / 4.0 + 0.2
		_pillar(side(map.fountains[0] + Vector2.from_angle(a) * 1000.0, team), team)
	for k in 4:
		var a2 := k * TAU / 4.0 + 0.785
		_pillar(side(Vector2(-5800, -5350) + Vector2.from_angle(a2) * 760.0, team), team)

# ---- Mountains --------------------------------------------------------------------------------------------------------

## Boulders and cliff rocks where the mountains meet the ground, pines and shrubs on the lower slopes.
func _mountain_props() -> void:
	var step := 150.0
	var y := -SimMap.HALF + 60.0
	while y < SimMap.HALF - 60.0:
		var x := -SimMap.HALF + 60.0
		while x < SimMap.HALF - 60.0:
			var p := Vector2(x + _rng.randf_range(-50, 50), y + _rng.randf_range(-50, 50))
			x += step
			var d := terrain.mountain_dist(p)
			if d <= 0.0:
				continue
			var dusk := (p.x + p.y) > 0.0
			var q := p if not dusk else -p
			if q.x < -4200.0 and q.y < -3600.0 and q.distance_to(map.fountains[0]) < 2200.0:
				continue                   # the base's own corner stays clear
			if d < 120.0:
				if _rng.randf() < 0.4:
					var m: String = ["kf_boulder_a", "kf_boulder_b", "kf_rock_moss_set", "kf_boulder_c", "kf_rock_07"][_rng.randi_range(0, 4)]
					if dusk and m == "kf_boulder_b":
						m = "kf_boulder_b_dark"
					dressing._add(m, p, _rng.randf_range(0.35, 0.6), 0.2, true)
			elif d < 900.0 and _rng.randf() < 0.22:
				var tree := "Pine_%d" % _rng.randi_range(1, 5) if not dusk or _rng.randf() < 0.5 else "DeadTree_%d" % _rng.randi_range(1, 5)
				dressing._add(tree, p, _rng.randf_range(0.8, 1.3), 0.1, true)
			elif d < 900.0 and _rng.randf() < 0.1:
				dressing._add("kf_shrub_a" if _rng.randf() < 0.5 else "kf_shrub_c", p, _rng.randf_range(0.7, 1.1), 0.05)
		y += step

# ---- Emit -----------------------------------------------------------------------------------------------------------

func _emit() -> void:
	for key in _inst:
		var list: Array = _inst[key]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[key]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.name = key
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadow.get(key, false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if String(key).begins_with("flame"):
			mi.extra_cull_margin = 2.0
		add_child(mi)
	# warm light from a share of the fires (the rest glow through bloom only)
	var lit := 0
	for i in flames.size():
		if i % 3 != 0 or lit >= 40:
			continue
		var f: Array = flames[i]
		var l := OmniLight3D.new()
		l.position = f[0]
		l.light_color = Color(1.0, 0.62, 0.3) if int(f[1]) == C.DAWN else Color(1.0, 0.3, 0.25)
		l.light_energy = 1.4
		l.omni_range = 4.5
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 40.0
		l.distance_fade_length = 10.0
		add_child(l)
		lit += 1

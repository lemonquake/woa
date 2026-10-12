class_name Dressing
extends Node3D
## Ground dressing that makes the battlefield feel lived-in: pebbles, stones and tufts breaking up the lane edges,
## flagstones embedded in the roads, rocks and reeds on the river banks, scanned rock faces on the base cliffs,
## roots / stumps / fallen trunks at forest edges, camp props at neutral camps, and faction landmarks (Dawn lanterns
## and statues, Dusk graves and bones). Purely visual (the simulation never sees it); placed deterministically from
## the simulation map and MultiMesh-instanced per chunk.

const PROPS := "res://assets/props/"
const NATURE := "res://assets/nature/"
const CHUNK := 2048.0

var map: SimMap
var terrain: TerrainBuilder
var foliage: Foliage                       # nature-kit models use its tinted leaf / grass materials
var _meshes := {}
var _groups := {}                          # model -> {chunk -> [[xf, shadow]]}
var _shadow := {}                          # model -> casts shadows
var _rng := RandomNumberGenerator.new()
var _lane_lines: Array = []

func build(p_map: SimMap, p_terrain: TerrainBuilder) -> void:
	map = p_map
	terrain = p_terrain
	name = "Dressing"
	_rng.seed = map.seed_value * 131 + 9
	for k in map.lanes:
		_lane_lines.append(map.lanes[k])
		var m := PackedVector2Array()
		for p in map.lanes[k]:
			m.append(-p)
		_lane_lines.append(m)
	_lane_edges()
	_curbs()
	_ruins()
	_river_banks()
	_cliffs()
	_forest_edges()
	_camps()
	_landmarks()
	_tree_blobs()
	_emit()

## Every tree trunk gets a contact pool too (canopy shadows come from the sun).
func _tree_blobs() -> void:
	for t in map.trees:
		blob(t.pos, 0.75 * float(t.scale))
	# buildings sit in wide pools of contact shade
	for b in map.buildings:
		var r := float(SimData.unit(b.unit).hull) * View.S * 1.9
		blob(b.pos, r)
		blob(b.pos, r * 0.7)

# ---- Mesh loading ---------------------------------------------------------------------------------------------------

## All meshes of a model scene merged into one mesh (surfaces keep their materials and node transforms).
func _mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	if path.begins_with(NATURE) and foliage and not path.get_file().begins_with("Rock") and not path.get_file().begins_with("Pebble"):
		_meshes[path] = foliage._mesh(path.get_file().get_basename())
		return _meshes[path]
	var ps := load(path) as PackedScene
	var out := ArrayMesh.new()
	if ps:
		var scene: Node = ps.instantiate()
		var mis := scene.find_children("*", "MeshInstance3D", true, false)
		if scene is MeshInstance3D:
			mis.append(scene)
		for mi: MeshInstance3D in mis:
			var xf := _rel_xf(mi, scene)
			for s in mi.mesh.get_surface_count():
				var st := SurfaceTool.new()
				st.append_from(mi.mesh, s, xf)
				st.commit(out)
				var mat := mi.get_surface_override_material(s)
				if mat == null:
					mat = mi.mesh.surface_get_material(s)
				out.surface_set_material(out.get_surface_count() - 1, _tune(mat, path))
		scene.free()
	_meshes[path] = out
	return out

static func _rel_xf(n: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

## Imported materials as they are, a little rougher (scans read as wet otherwise).
func _tune(m: Material, path := "") -> Material:
	var bm := m as BaseMaterial3D
	if bm == null:
		return m
	var f := path.get_file()
	if f.begins_with("RockPath"):
		var rp := bm.duplicate() as BaseMaterial3D
		rp.albedo_color = bm.albedo_color * Color(0.66, 0.64, 0.56)
		rp.roughness = 0.9
		return rp
	if (f.begins_with("Rock_") or f.begins_with("Pebble") or f.begins_with("kf_rock") or f.begins_with("kf_stone")) and not f.begins_with("RockPath"):
		# the source rock textures lean pink; cool them towards the scene's grey-green stone
		var r := bm.duplicate() as BaseMaterial3D
		r.albedo_color = bm.albedo_color * Color(0.74, 0.84, 0.82)
		r.roughness = 0.85
		return r
	if f.begins_with("kd_tent") and bm.albedo_texture == null:
		# plain white canvas glares under the sun: weathered, sun-faded cloth instead
		var tc := bm.duplicate() as BaseMaterial3D
		var c := bm.albedo_color
		var lum := (c.r + c.g + c.b) / 3.0
		tc.albedo_color = Color(0.58, 0.5, 0.4) if lum > 0.6 else c * Color(0.8, 0.72, 0.62)
		tc.roughness = 0.95
		return tc
	if bm.albedo_texture == null and bm.resource_name.begins_with("BH_"):
		var g := GearMaterials.for_material(bm)
		if g:
			return g
	var d := bm.duplicate() as BaseMaterial3D
	d.roughness = maxf(d.roughness, 0.75)
	return d

## Soft contact shadows: radius in metres per placed prop, emitted as one MultiMesh of flat gradient quads per chunk.
var _blobs := {}                           # chunk -> [Transform3D]

static var _blob_mesh: QuadMesh

static func blob_mesh() -> QuadMesh:
	if _blob_mesh:
		return _blob_mesh
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			img.set_pixel(x, y, Color(0.015, 0.02, 0.01, clampf(1.0 - d, 0.0, 1.0) ** 1.3 * 0.82))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = -1
	_blob_mesh = QuadMesh.new()
	_blob_mesh.size = Vector2(1, 1)
	_blob_mesh.orientation = PlaneMesh.FACE_Y
	_blob_mesh.material = m
	return _blob_mesh

func blob(p: Vector2, radius_m: float) -> void:
	var ck := Vector2i(floori((p.x + SimMap.HALF) / CHUNK), floori((p.y + SimMap.HALF) / CHUNK))
	if not _blobs.has(ck):
		_blobs[ck] = []
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(radius_m * 2.0, 1.0, radius_m * 2.0 * _rng.randf_range(0.8, 1.1))),
		View.to3(p, terrain.height_at(p)) + Vector3(0, 0.035, 0))
	_blobs[ck].append(xf)

func _add(model: String, p: Vector2, scale: float, sink := 0.0, shadow := false, yaw := -1.0, tilt := 0.0) -> void:
	if not _ok(p):
		return
	# props and clumps sit in a soft pool of contact shade
	var foot := scale * (0.9 if model.begins_with("Grass") else (0.55 if model.begins_with("kf_rocks") else 1.0))
	if not model.begins_with("RockPath") and not model.begins_with("kf_stones"):
		blob(p, clampf(foot * 0.7, 0.16, 2.6))
	var path := (NATURE + model + ".gltf") if not model.begins_with("kd_") and not model.begins_with("kf_") and not ResourceLoader.exists(PROPS + model + ".glb") else (PROPS + model + ".glb")
	var basis := Basis(Vector3.UP, _rng.randf() * TAU if yaw < 0.0 else yaw)
	if tilt > 0.0:
		basis = basis * Basis(Vector3(1, 0, 0), _rng.randf_range(-tilt, tilt))
	basis = basis.scaled(Vector3.ONE * scale)
	var xf := Transform3D(basis, View.to3(p, terrain.height_at(p)) - Vector3(0, sink, 0))
	var ck := Vector2i(floori((p.x + SimMap.HALF) / CHUNK), floori((p.y + SimMap.HALF) / CHUNK))
	if not _groups.has(path):
		_groups[path] = {}
	if not _groups[path].has(ck):
		_groups[path][ck] = []
	_groups[path][ck].append(xf)
	_shadow[path] = _shadow.get(path, false) or shadow

## Never on top of buildings, inside the fountains or deep in the river.
func _ok(p: Vector2) -> bool:
	if maxf(absf(p.x), absf(p.y)) > SimMap.HALF - 150.0:
		return false
	for b in map.buildings:
		if p.distance_to(b.pos) < float(SimData.unit(b.unit).hull) + 120.0:
			return false
	return true

func _emit() -> void:
	for ck in _blobs:
		var list: Array = _blobs[ck]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = blob_mesh()
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 70.0
		add_child(mi)
	for path in _groups:
		var mesh := _mesh(path)
		for ck in _groups[path]:
			var list: Array = _groups[path][ck]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadow[path] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 70.0
			mmi.visibility_range_end_margin = 6.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)

# ---- Placement --------------------------------------------------------------------------------------------------------

func _pick(list: Array) -> Array:
	var total := 0.0
	for e in list:
		total += float(e[1])
	var r := _rng.randf() * total
	for e in list:
		r -= float(e[1])
		if r <= 0.0:
			return e
	return list[0]

func _dusk(p: Vector2) -> bool:
	return p.x + p.y > 700.0 + sin(p.x * 0.002) * 400.0

func _in_river(p: Vector2) -> bool:
	return absf(p.x + p.y) / sqrt(2.0) < 560.0

## Lane edges: pebble clusters, stones, ferns and tufts; flagstones set into the road bed.
func _lane_edges() -> void:
	var edge_items := [["kf_rocks", 1.2], ["kf_stones", 0.8], ["kd_rock_small_a", 1.6], ["kf_fern", 1.5],
		["Grass_Common_Short", 4.0], ["Grass_Wispy_Tall", 2.0], ["Grass_Wispy_Short", 2.0]]
	for line: PackedVector2Array in _lane_lines:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var dir := (b - a).normalized()
			var side := dir.orthogonal()
			var length := a.distance_to(b)
			var t := 0.0
			while t < length:
				t += _rng.randf_range(70.0, 140.0)
				var base := a + dir * t
				for sgn in [-1.0, 1.0]:
					var p: Vector2 = base + side * sgn * _rng.randf_range(250.0, 360.0) + dir * _rng.randf_range(-30, 30)
					if _in_river(p) or map.level_at(p) == SimMap.HIGH:
						continue
					var e := _pick(edge_items)
					match String(e[0]):
						"kf_rocks":
							_add("kf_rocks", p, _rng.randf_range(2.5, 4.5), 0.02)
						"kf_stones":
							_add("kf_stones", p, _rng.randf_range(1.2, 2.2), 0.0)
						"kd_rock_small_a", "kd_rock_small_b":
							var peb: String = ["Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Square_1", "Pebble_Square_3", "Pebble_Square_5"][_rng.randi_range(0, 5)]
							_add(peb, p, _rng.randf_range(0.7, 1.4), 0.02, true)
						"kf_stone":
							_add("kf_stone", p, _rng.randf_range(0.25, 0.5), 0.08, true)
						"kf_rock_moss_set":
							_add("kf_rock_moss_set", p, _rng.randf_range(0.3, 0.5), 0.08, true)
						"kf_fern":
							_add("kf_fern", p, _rng.randf_range(0.6, 1.0), 0.0)
						"kf_roots":
							_add("kf_roots", p, _rng.randf_range(0.6, 1.0), 0.02)
						"kf_dry_branches":
							_add("kf_dry_branches", p, _rng.randf_range(0.8, 1.3), 0.0)
						_:
							_add(e[0], p, _rng.randf_range(0.5, 0.9), 0.0)
				# flagstones set into the road
				if _rng.randf() < 0.22:
					var q := base + side * _rng.randf_range(-170.0, 170.0)
					if not _in_river(q):
						var slab: String = ["RockPath_Round_Small_1", "RockPath_Round_Small_2", "RockPath_Square_Small_1", "RockPath_Square_Small_2", "RockPath_Round_Thin"][_rng.randi_range(0, 4)]
						_add(slab, q, _rng.randf_range(0.55, 0.95), 0.1)

## Curbs: square edging stones set end to end along both lane edges, so the road reads as a built lane with a clear
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
					_add(slab, p, _rng.randf_range(0.62, 0.75), 0.075, false, yaw)
					# tufts poke up between and just inside the curb stones
					if _rng.randf() < 0.35:
						_add("Grass_Common_Short", base + side * sgn * _rng.randf_range(195.0, 230.0), _rng.randf_range(0.4, 0.65), 0.0)

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

## River banks: rocks and reeds where the ground drops into the water.
func _river_banks() -> void:
	var dir := Vector2(1, -1).normalized()
	var across := Vector2(1, 1).normalized()
	var t := -11000.0
	while t < 11000.0:
		t += _rng.randf_range(90.0, 170.0)
		for sgn in [-1.0, 1.0]:
			var p: Vector2 = dir * t + across * sgn * _rng.randf_range(470.0, 640.0)
			if absf(p.x) > SimMap.HALF - 200 or absf(p.y) > SimMap.HALF - 200:
				continue
			var r := _rng.randf()
			if r < 0.12:
				_add(["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"][_rng.randi_range(0, 2)], p, _rng.randf_range(0.12, 0.3), 0.12, true)
			elif r < 0.75:
				_add("Grass_Wispy_Tall", p, _rng.randf_range(0.7, 1.1), 0.0)
			elif r < 0.85:
				_add("kf_sand_rocks", p, _rng.randf_range(0.25, 0.45), 0.05)
			else:
				_add("kf_rocks", p, _rng.randf_range(3.0, 5.0), 0.02)

## Base cliffs: scanned rock faces along every few cliff cells, so the high ground reads as rock, not a slope.
func _cliffs() -> void:
	var n := SimMap.N
	for cy in range(0, n, 2):
		for cx in range(0, n, 2):
			if not map.is_cliff_cell(cx, cy):
				continue
			var p := map.cell_center(cx, cy) + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
			var dusk := _dusk(p)
			var model: String = ["kf_rock_face_a", "kf_rock_face_b", "kf_cliff_c"][_rng.randi_range(0, 2)]
			if dusk and model == "kf_rock_face_a":
				model = "kf_rock_face_a_dark"
			if dusk and model == "kf_cliff_c":
				model = "kf_cliff_c_dark"
			var s := _rng.randf_range(0.35, 0.55) if model.begins_with("kf_cliff") else _rng.randf_range(0.45, 0.75)
			_add(model, p, s, 0.6, true)

## Forest edges near lanes and paths: roots, stumps, fallen trunks, mushrooms.
func _forest_edges() -> void:
	for i in map.trees.size():
		if i % 3 != 0:
			continue
		var tp: Vector2 = map.trees[i].pos
		var near_lane := false
		for line in _lane_lines:
			if SimMap._polyline_distance(tp, line) < 700.0:
				near_lane = true
				break
		if not near_lane:
			continue
		var p := tp + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(70.0, 140.0)
		var r := _rng.randf()
		if r < 0.3:
			_add("kf_root_cluster_b", p, _rng.randf_range(0.5, 0.8), 0.03)
		elif r < 0.45:
			_add("kf_stump_a" if _rng.randf() < 0.5 else "kf_stump_b", p, _rng.randf_range(0.3, 0.45), 0.05, true)
		elif r < 0.55:
			_add("kf_dead_trunk_a" if _rng.randf() < 0.5 else "kf_dead_trunk_b", p, _rng.randf_range(0.6, 0.9), 0.15, true)
		elif r < 0.7:
			_add("kd_mushrooms_pale", p, _rng.randf_range(0.8, 1.3), 0.0)
		elif r < 0.85:
			_add("kf_fern", p, _rng.randf_range(0.7, 1.1), 0.0)
		else:
			_add("Rock_Medium_1", p, _rng.randf_range(0.1, 0.18), 0.08, true)

## Neutral camps: a fire pit, a tent and some crates (or bones on the Dusk side).
func _camps() -> void:
	for c in map.camps:
		var p: Vector2 = c.pos
		var away: Vector2 = (p - map.fountains[c.side]).normalized()
		var side: Vector2 = away.orthogonal()
		_add("kf_fire_pit", p + away * 300.0, 0.7, 0.05, true)
		_add("kd_tent", p + away * 420.0 + side * 180.0, 0.9, 0.0, true, (side).angle())
		if c.side == SimConst.DUSK:
			_add("bones_scatter", p + side * -260.0, 0.6, 0.02)
			_add("kd_grave_broken", p + side * -320.0 + away * 120.0, 0.8, 0.05, true)
		else:
			_add("kf_crate_a", p + side * -280.0, 0.55, 0.0, true)
			_add("kf_barrels", p + side * -320.0 + away * 90.0, 0.6, 0.0, true)

## Faction landmarks along lanes and jungle paths: Dawn lantern posts and a statue, Dusk graves and bones.
func _landmarks() -> void:
	for line in _lane_lines:
		for i in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var steps := int(a.distance_to(b) / 1500.0)
			for s in range(1, steps + 1):
				var base := a.lerp(b, float(s) / (steps + 1))
				var side := (b - a).normalized().orthogonal() * (1.0 if s % 2 == 0 else -1.0)
				var p := base + side * 390.0
				if _in_river(p) or map.level_at(p) == SimMap.HIGH:
					continue
				if _dusk(p):
					if _rng.randf() < 0.6:
						_add("gravestone_a" if _rng.randf() < 0.5 else "gravestone_b", p, _rng.randf_range(0.8, 1.1), 0.05, true, -1.0, 0.15)
						_add("bones_scatter", p + side * 80.0, 0.45, 0.02)
				else:
					_add("kf_lantern_cage", p, 1.0, 0.0, true, (-side).angle())
	for spot in [Vector2(-2600, -2700), Vector2(-5400, -1900), Vector2(2200, -5100)]:
		_add("kf_gothic_statue", spot, 1.4, 0.05, true, (Vector2.ZERO - spot).angle())
	for spot in [Vector2(2600, 2700), Vector2(5400, 1900), Vector2(-2200, 5100)]:
		_add("kd_grave_broken", spot, 1.4, 0.05, true)
		_add("bones_scatter", spot + Vector2(150, 0), 0.9, 0.02)

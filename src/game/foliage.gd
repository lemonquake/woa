class_name Foliage
extends Node3D
## Trees (one per simulation tree, so cutting one removes exactly that tree), plus purely decorative grass, ferns,
## flowers, bushes and rocks. Everything is MultiMesh-instanced per 16x16 m chunk so the renderer culls by chunk.

const LEAF_SHADER := preload("res://src/game/foliage.gdshader")
const NATURE := "res://assets/nature/"
const CHUNK := 2048.0                      # game units per chunk side

## Tree models per faction side: [file, scale min, scale max, weight]
const DAWN_TREES := [["CommonTree_1", 0.42, 0.52, 3], ["CommonTree_2", 0.42, 0.52, 3], ["CommonTree_3", 0.42, 0.52, 3],
	["CommonTree_4", 0.42, 0.52, 2], ["CommonTree_5", 0.42, 0.52, 2], ["Pine_1", 0.48, 0.6, 2], ["Pine_3", 0.48, 0.6, 2],
	["Pine_4", 0.48, 0.6, 1]]
const DUSK_TREES := [["TwistedTree_1", 0.21, 0.26, 2], ["TwistedTree_2", 0.21, 0.26, 2], ["TwistedTree_4", 0.21, 0.26, 2],
	["DeadTree_1", 0.36, 0.44, 2], ["DeadTree_3", 0.36, 0.44, 2], ["Pine_2", 0.46, 0.58, 3], ["Pine_5", 0.46, 0.58, 3],
	["CommonTree_3", 0.42, 0.5, 1]]
const DECOR := [["Grass_Common_Short", 0.55, 0.9, 10], ["Grass_Wispy_Short", 0.55, 0.9, 8], ["Grass_Common_Tall", 0.45, 0.7, 4],
	["Fern_1", 0.12, 0.18, 2], ["Flower_3_Group", 0.5, 0.8, 2], ["Flower_4_Group", 0.5, 0.8, 2], ["Bush_Common", 0.5, 0.75, 2],
	["Bush_Common_Flowers", 0.5, 0.75, 1], ["Plant_1", 0.4, 0.6, 1], ["Mushroom_Common", 0.18, 0.28, 1]]

var map: SimMap
var terrain: TerrainBuilder
var _meshes := {}                          # model -> Mesh (all surfaces, game materials)
var _tree_slot := {}                       # tree index -> [MultiMesh, instance index, Transform3D]
var _mats := {}

func build(p_map: SimMap, p_terrain: TerrainBuilder) -> void:
	map = p_map
	terrain = p_terrain
	name = "Foliage"
	_build_trees()
	_build_decor()

func _mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var ps := load(NATURE + model + ".gltf") as PackedScene
	var scene := ps.instantiate()
	var mis := scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D:
		mis.append(scene)
	var src: Mesh = (mis[0] as MeshInstance3D).mesh
	# duplicate keeps the importer's generated LODs (copying surface arrays would drop them)
	var out := src.duplicate() as Mesh
	for s in out.get_surface_count():
		out.surface_set_material(s, _game_material(src.surface_get_material(s), model))
	scene.free()
	_meshes[model] = out
	return out

func _game_material(src: Material, model: String) -> Material:
	var sm := src as BaseMaterial3D
	var nm := sm.resource_name if sm else "?"
	var key := nm + "|" + model.get_slice("_", 0)
	if _mats.has(key):
		return _mats[key]
	var out: Material
	var leafy := nm.begins_with("Leaves") or nm.begins_with("Leaf") or nm == "Grass" or nm == "Flowers"
	if leafy and sm and sm.albedo_texture:
		var m := ShaderMaterial.new()
		m.shader = LEAF_SHADER
		var tex := sm.albedo_texture
		# bushes share the twisted tree's red leaf mask; give Dawn's undergrowth green leaves instead
		if model.begins_with("Bush"):
			tex = load(NATURE + "Leaves_NormalTree_C.png")
		m.set_shader_parameter("albedo_tex", tex)
		var grass := nm == "Grass"
		m.set_shader_parameter("sway_height", 1.0 if grass else 6.0)
		m.set_shader_parameter("wind", 0.9 if grass else 1.0)
		if model.begins_with("Twisted"):
			m.set_shader_parameter("tint", Color(0.95, 0.5, 0.55))
			m.set_shader_parameter("tint2", Color(0.78, 0.36, 0.42))
		elif model.begins_with("Pine"):
			m.set_shader_parameter("tint", Color(0.82, 0.98, 0.86))
			m.set_shader_parameter("tint2", Color(0.62, 0.82, 0.7))
		elif grass:
			m.set_shader_parameter("tint", Color(0.44, 0.66, 0.2))
			m.set_shader_parameter("tint2", Color(0.56, 0.72, 0.26))
			m.set_shader_parameter("alpha_cut", 0.3)
		else:
			m.set_shader_parameter("tint", Color(1.0, 1.08, 0.86))
			m.set_shader_parameter("tint2", Color(0.86, 1.0, 0.72))
		out = m
	elif sm:
		var b := sm.duplicate() as BaseMaterial3D
		b.roughness = 0.9
		# trunks near the camera dither away with the leaves
		b.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		b.distance_fade_min_distance = 5.5
		b.distance_fade_max_distance = 8.5
		if nm.begins_with("Bark"):
			b.albedo_color = Color(0.92, 0.85, 0.78)
		out = b
	_mats[key] = out
	return out

func _pick(list: Array, rng: RandomNumberGenerator) -> Array:
	var total := 0
	for e in list:
		total += int(e[3])
	var r := rng.randi_range(0, total - 1)
	for e in list:
		r -= int(e[3])
		if r < 0:
			return e
	return list[0]

func _chunk_key(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x + SimMap.HALF) / CHUNK), floori((p.y + SimMap.HALF) / CHUNK))

## A cheap opaque stand-in that casts a tree's shadow (canopy ellipsoid + trunk), so the alpha-tested leaf cards
## never render into the shadow map. Top-down, the soft blob reads like a painted canopy shadow.
var _proxies := {}

func _proxy(model: String) -> Mesh:
	if _proxies.has(model):
		return _proxies[model]
	var src := _mesh(model)
	var bb := src.get_aabb()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 10
	sphere.rings = 5
	var canopy := model.begins_with("Pine") or model.begins_with("Dead")
	var r := Vector3(bb.size.x * (0.3 if canopy else 0.4), bb.size.y * (0.38 if canopy else 0.27), bb.size.z * (0.3 if canopy else 0.4))
	var c := bb.get_center() + Vector3(0, bb.size.y * (0.02 if canopy else 0.12), 0)
	st.append_from(sphere, 0, Transform3D(Basis.from_scale(r * 2.0), c))
	var trunk := CylinderMesh.new()
	trunk.top_radius = bb.size.x * 0.05
	trunk.bottom_radius = bb.size.x * 0.07
	trunk.height = bb.size.y * 0.5
	trunk.radial_segments = 6
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(bb.get_center().x, bb.position.y + trunk.height * 0.5, bb.get_center().z)))
	var m := st.commit()
	_proxies[model] = m
	return m

## Group instances {model: {chunk: [[Transform3D, custom, tree index]]}} then build one MultiMesh per pair.
func _emit(groups: Dictionary, vis_end: float, shadows: bool) -> void:
	for model in groups:
		var mesh := _mesh(model)
		for ck in groups[model]:
			var list: Array = groups[model][ck]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = list.size()
			for i in list.size():
				var e: Array = list[i]
				mm.set_instance_transform(i, e[0])
				mm.set_instance_custom_data(i, e[1])
				if e[2] >= 0:
					_tree_slot[e[2]] = [mm, i, e[0]]
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if shadows:
				var smm := mm.duplicate() as MultiMesh
				smm.mesh = _proxy(model)
				var sh := MultiMeshInstance3D.new()
				sh.multimesh = smm
				sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				add_child(sh)
				for i in list.size():
					var e2: Array = list[i]
					if e2[2] >= 0:
						(_tree_slot[e2[2]] as Array).append(smm)
			if vis_end > 0.0:
				mmi.visibility_range_end = vis_end
				mmi.visibility_range_end_margin = 4.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map.seed_value * 31 + 5
	var groups := {}
	for i in map.trees.size():
		var t: Dictionary = map.trees[i]
		var p: Vector2 = t.pos
		var dusk_side := (p.x + p.y) > 600.0 + sin(p.x * 0.002) * 500.0
		var e := _pick(DUSK_TREES if dusk_side else DAWN_TREES, rng)
		var s := rng.randf_range(e[1], e[2]) * float(t.scale) * 0.92
		var basis := Basis(Vector3.UP, float(t.rot)).scaled(Vector3.ONE * s)
		var xf := Transform3D(basis, View.to3(p, terrain.height_at(p) - 8.0))
		var model: String = e[0]
		var ck := _chunk_key(p)
		if not groups.has(model):
			groups[model] = {}
		if not groups[model].has(ck):
			groups[model][ck] = []
		groups[model][ck].append([xf, Color(rng.randf(), 0, 0, 0), i])
	_emit(groups, 0.0, true)

## Grass and plants on open ground, thick at forest edges, never on roads, cliffs, paving or in the river.
func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map.seed_value * 97 + 3
	var groups := {}
	var count := 0
	var step := 150.0
	var y := -SimMap.HALF + 200.0
	while y < SimMap.HALF - 200.0:
		var x := -SimMap.HALF + 200.0
		while x < SimMap.HALF - 200.0:
			var p := Vector2(x + rng.randf_range(-70, 70), y + rng.randf_range(-70, 70))
			x += step
			if map.level_at(p) == SimMap.RIVER or map.level_at(p) == SimMap.HIGH:
				continue
			if not map.is_walkable(p) and map.tree_at(p, 60.0) < 0:
				continue
			var road := 1e9
			for k in map.lanes:
				road = minf(road, SimMap._polyline_distance(p, map.lanes[k]))
				road = minf(road, SimMap._polyline_distance(-p, map.lanes[k]))
			if road < 330.0:
				continue
			var on_site := false
			for st in map.sites:
				if p.distance_to(st.pos) < 330.0:
					on_site = true
			if on_site:
				continue
			var near_tree := map.tree_at(p, 260.0) >= 0
			if not near_tree and rng.randf() < 0.55:
				continue
			var e := _pick(DECOR, rng)
			if (p.x + p.y) > 1500.0 and String(e[0]).begins_with("Flower") and rng.randf() < 0.8:
				continue
			var s := rng.randf_range(e[1], e[2])
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			var xf := Transform3D(basis, View.to3(p, terrain.height_at(p) - 2.0))
			var model: String = e[0]
			var ck := _chunk_key(p)
			if not groups.has(model):
				groups[model] = {}
			if not groups[model].has(ck):
				groups[model][ck] = []
			groups[model][ck].append([xf, Color(rng.randf(), 0, 0, 0), -1])
			count += 1
		y += step
	_emit(groups, 60.0, false)

## A tree knocked down: a copy of it topples away from `from_pos`, then sinks into the ground.
func fell_tree(index: int, from_pos: Vector2) -> void:
	if not _tree_slot.has(index):
		return
	var s: Array = _tree_slot[index]
	var mm: MultiMesh = s[0]
	var xf: Transform3D = s[2]
	# a one-tree multimesh keeps the per-instance colour and wind data the foliage shader reads
	var one := MultiMesh.new()
	one.transform_format = MultiMesh.TRANSFORM_3D
	one.use_custom_data = true
	one.mesh = mm.mesh
	one.instance_count = 1
	one.set_instance_transform(0, Transform3D.IDENTITY)
	one.set_instance_custom_data(0, mm.get_instance_custom_data(int(s[1])))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = one
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	mi.transform = xf
	var d := Vector3(xf.origin.x, 0.0, xf.origin.z) - Vector3(from_pos.x * View.S, 0.0, -from_pos.y * View.S)
	if d.length() < 0.01:
		d = Vector3.RIGHT
	var axis := Vector3.UP.cross(d.normalized()).normalized()
	var base := xf.basis
	var origin := xf.origin
	var tw := mi.create_tween()
	tw.tween_method(_tilt.bind(mi, axis, base, origin), 0.0, deg_to_rad(84.0), 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(_tilt.bind(mi, axis, base, origin), deg_to_rad(84.0), deg_to_rad(79.0), 0.12)
	tw.tween_interval(1.4)
	tw.tween_property(mi, "position:y", origin.y - 2.5, 1.2)
	tw.tween_callback(mi.queue_free)

static func _tilt(a: float, mi: Node3D, axis: Vector3, base: Basis, origin: Vector3) -> void:
	if is_instance_valid(mi):
		mi.transform = Transform3D(Basis(axis, a) * base, origin)

var _fade_at := -1.0

## Foreground canopies dither away: anything nearer the camera than ~70% of its distance to the ground it looks at.
func set_near_fade(cam_distance: float) -> void:
	var d := cam_distance * 0.68
	if absf(d - _fade_at) < 0.05:
		return
	_fade_at = d
	for m in _mats.values():
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("near_fade", d)
		elif m is BaseMaterial3D and (m as BaseMaterial3D).distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
			(m as BaseMaterial3D).distance_fade_max_distance = d
			(m as BaseMaterial3D).distance_fade_min_distance = d - 3.0

func set_tree_alive(index: int, alive: bool) -> void:
	if not _tree_slot.has(index):
		return
	var s: Array = _tree_slot[index]
	var xf: Transform3D = s[2]
	if not alive:
		xf = Transform3D(Basis().scaled(Vector3.ONE * 0.0001), xf.origin - Vector3(0, 5, 0))
	(s[0] as MultiMesh).set_instance_transform(s[1], xf)
	if s.size() > 3:
		(s[3] as MultiMesh).set_instance_transform(s[1], xf)

## The world was replaced (a multiplayer snapshot): every tree takes the state the new world says, planted ones too.
func resync_trees() -> void:
	for i in map.trees.size():
		var t: Dictionary = map.trees[i]
		if not _tree_slot.has(i) and t.get("planted", false):
			_make_planted(i)
		set_tree_alive(i, bool(t.alive))

## A tree grows back (after 180 s) or is planted: it rises out of the ground and springs up to full size.
## Planted trees (Ironwood Twig) get their own small tree and a ring of glowing leaves at the base while they stand.
func grow_tree(index: int) -> void:
	if not _tree_slot.has(index):
		if index < 0 or index >= map.trees.size() or not map.trees[index].get("planted", false):
			return
		_make_planted(index)
	var s: Array = _tree_slot[index]
	var xf: Transform3D = s[2]
	_tween_tree(index, 0.05, 1.0, 1.1, Tween.TRANS_BACK)
	var p := View.to2(xf.origin)
	if game_fx != null and game_fx._seen(p):
		game_fx.debris(game_fx.ground3(p), 6, Color(0.36, 0.28, 0.2), 2.0, 0.5, "chip")
		game_fx.debris(game_fx.ground3(p, 0.6), 6, Color(0.3, 0.55, 0.2), 1.6, 0.9, "leaf")

## A tree eaten (Vegan Picker) or a planted tree withering: it shrinks into the ground.
func shrink_tree(index: int) -> void:
	if not _tree_slot.has(index):
		return
	var s: Array = _tree_slot[index]
	var p := View.to2((s[2] as Transform3D).origin)
	if game_fx != null and game_fx._seen(p):
		game_fx.debris(game_fx.ground3(p, 1.2), 8, Color(0.3, 0.55, 0.2), 1.8, 1.0, "leaf")
	_tween_tree(index, 1.0, 0.0, 0.45, Tween.TRANS_QUAD)

var _tree_tweens := {}

func _tween_tree(index: int, from: float, to: float, dur: float, trans: int) -> void:
	if _tree_tweens.has(index) and (_tree_tweens[index] as Tween).is_valid():
		(_tree_tweens[index] as Tween).kill()
	var tw := create_tween()
	tw.tween_method(_scale_tree.bind(index), from, to, dur).set_trans(trans).set_ease(Tween.EASE_OUT if to > from else Tween.EASE_IN)
	if to <= 0.0:
		tw.tween_callback(_tree_gone.bind(index))
	_tree_tweens[index] = tw

func _scale_tree(k: float, index: int) -> void:
	if not _tree_slot.has(index):
		return
	var s: Array = _tree_slot[index]
	var xf: Transform3D = s[2]
	var shown := Transform3D(xf.basis.scaled(Vector3.ONE * maxf(k, 0.0001)), xf.origin - Vector3(0, (1.0 - clampf(k, 0.0, 1.0)) * 0.4, 0))
	(s[0] as MultiMesh).set_instance_transform(s[1], shown)
	if s.size() > 3 and s[3] is MultiMesh:
		(s[3] as MultiMesh).set_instance_transform(s[1], shown)

func _tree_gone(index: int) -> void:
	set_tree_alive(index, false)
	if _planted.has(index):
		for n in _planted[index]:
			if is_instance_valid(n):
				(n as Node).queue_free()
		_planted.erase(index)
		_tree_slot.erase(index)

var _planted := {}                          # tree index -> [nodes]
var game_fx: Fx

func _make_planted(index: int) -> void:
	var t: Dictionary = map.trees[index]
	var p: Vector2 = t.pos
	var model := "CommonTree_2"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh(model)
	mm.instance_count = 1
	var xf := Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * 0.36), View.to3(p, terrain.height_at(p) - 8.0))
	mm.set_instance_transform(0, xf)
	mm.set_instance_custom_data(0, Color(randf(), 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	# Dota's planted trees glow faintly at the base so everyone can tell them apart
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.62
	tm.rings = 32
	tm.ring_segments = 4
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.55, 1.0, 0.45, 0.5)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position = View.to3(p, terrain.height_at(p)) + Vector3(0, 0.06, 0)
	var spin := ring.create_tween().set_loops()
	spin.tween_property(rm, "albedo_color:a", 0.2, 0.9)
	spin.tween_property(rm, "albedo_color:a", 0.5, 0.9)
	_tree_slot[index] = [mm, 0, xf]
	_planted[index] = [mmi, ring]

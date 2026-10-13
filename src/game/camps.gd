class_name Camps
extends Node3D
## Neutral camps you recognise at a glance, and their spawn boxes.
##
## Each camp is a trampled clearing (painted by TerrainBuilder) with a fire that burns day and night (a flame, embers
## and a warm light), tents or round huts at the back, and a carved totem whose cloth strips show the camp's size
## (small yellow, medium orange, large red, ancient violet; the same colours as the boxes' labels). Bigger camps add a
## drying rack, a palisade of stakes, more fires and bones. Props face the walkway the camp is reached by and stay at the
## edge of the box, so the creeps stand among them. Built from tools/blender/camps.py props; visual only.
##
## Holding Shift shows every camp's spawn box as a yellow outline on the ground (as Dota shows them with Alt): the
## area that must be empty at the minute mark for the camp to spawn, which you pull the creeps out of to stack it.
## A box turns red while something other than its own creeps stands in it (that blocks the spawn). A label names the
## camp's size and marks the safe lane's pull camps.

const C = preload("res://src/sim/sim_const.gd")
const PROPS := "res://assets/props/"
const CHUNK := 2048.0
const FLAME_SHADER := preload("res://src/game/flame.gdshader")
const TIER_COLOR := {"small": Color(1.0, 0.86, 0.3), "medium": Color(1.0, 0.6, 0.18), "large": Color(0.92, 0.22, 0.16),
	"ancient": Color(0.62, 0.3, 0.95)}
const TIER_NAME := {"small": "Small camp", "medium": "Medium camp", "large": "Large camp", "ancient": "Ancient camp"}

var game: Node
var map: SimMap
var terrain: TerrainBuilder
var _meshes := {}                          # prop key -> ArrayMesh with game materials
var _xforms := {}                          # prop key -> [Transform3D]
var _lights: Array = []                    # [OmniLight3D, phase]
var _boxes: MeshInstance3D
var _box_mesh: ImmediateMesh
var _box_mat: StandardMaterial3D
var _labels: Array = []                    # [Label3D, camp id]
var _t := 0.0
var _box_t := 0.0
var _wood: StandardMaterial3D

func build(p_map: SimMap, p_terrain: TerrainBuilder) -> void:
	map = p_map
	terrain = p_terrain
	name = "Camps"
	for c in map.camps:
		_camp(c)
	for key in _xforms:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[String(key).get_slice("#", 0)]
		var list: Array = _xforms[key]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.name = key
		# the big pieces cast shadows; flames and small clutter do not
		var big: bool = key.begins_with("camp_tent") or key.begins_with("camp_hut") or key.begins_with("camp_totem") \
			or key.begins_with("camp_stakes") or key.begins_with("camp_rack")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 75.0
		mi.visibility_range_end_margin = 5.0
		if key.begins_with("flame"):
			mi.extra_cull_margin = 2.0
		add_child(mi)
	_build_boxes()

# ---- Materials and meshes ---------------------------------------------------------------------------------------------

func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _noise_normal(freq: float) -> NoiseTexture2D:
	var n := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = freq
	fn.fractal_octaves = 3
	n.noise = fn
	n.as_normal_map = true
	n.bump_strength = 6.0
	n.seamless = true
	n.width = 256
	n.height = 256
	return n

## The game's look for a CAMP_<Kind> material from the Blender props: real wood grain, hide, bone, cloth (tinted by
## camp size), rope, burlap.
func _material(src_name: String, tier: String) -> Material:
	var key := src_name + ":" + (tier if src_name == "CAMP_Cloth" else "")
	if _meshes.has("mat:" + key):
		return _meshes["mat:" + key]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.roughness = 0.85
	match src_name:
		"CAMP_Wood", "CAMP_WoodEnd":
			m.albedo_texture = _tex("res://assets/textures/building/ph_weathered_planks_albedo.png")
			m.normal_enabled = true
			m.normal_texture = _tex("res://assets/textures/building/ph_weathered_planks_normal.png")
			m.roughness_texture = _tex("res://assets/textures/building/ph_weathered_planks_rough.png")
			m.uv1_scale = Vector3(1.6, 1.6, 1.6)
			m.albedo_color = Color(0.72, 0.6, 0.5) if src_name == "CAMP_Wood" else Color(1.15, 1.0, 0.82)
		"CAMP_Hide", "CAMP_Hide2":
			m.albedo_color = Color(0.5, 0.36, 0.23) if src_name == "CAMP_Hide" else Color(0.34, 0.24, 0.16)
			m.normal_enabled = true
			m.normal_texture = _noise_normal(0.04)
			m.normal_scale = 0.6
			m.uv1_scale = Vector3(2.0, 2.0, 2.0)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"CAMP_Cloth":
			m.albedo_color = TIER_COLOR.get(tier, Color(0.8, 0.66, 0.26)).darkened(0.12)
			m.normal_enabled = true
			m.normal_texture = _noise_normal(0.09)
			m.normal_scale = 0.4
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"CAMP_Bone":
			m.albedo_color = Color(0.86, 0.81, 0.68)
			m.roughness = 0.6
		"CAMP_Burlap", "CAMP_Rope":
			m.albedo_color = Color(0.6, 0.52, 0.37) if src_name == "CAMP_Burlap" else Color(0.55, 0.47, 0.33)
			m.normal_enabled = true
			m.normal_texture = _noise_normal(0.18)
			m.normal_scale = 0.5
			m.uv1_scale = Vector3(3.0, 3.0, 3.0)
		"CAMP_Meat":
			m.albedo_color = Color(0.42, 0.14, 0.09)
			m.roughness = 0.45
		"CAMP_Feather", "CAMP_Dark":
			m.albedo_color = Color(0.12, 0.1, 0.09)
		_:
			m.albedo_color = Color(0.5, 0.48, 0.45)
	_meshes["mat:" + key] = m
	return m

## A prop model merged into one mesh. Camp props (camp_*) get the game's materials; others keep their own.
func _mesh(model: String, tier := "") -> Mesh:
	var key := model + ("@" + tier if model == "camp_totem" else "")
	if _meshes.has(key):
		return _meshes[key]
	var ps := load(PROPS + model + ".glb") as PackedScene
	var out := ArrayMesh.new()
	if ps:
		var scene: Node = ps.instantiate()
		var mis := scene.find_children("*", "MeshInstance3D", true, false)
		if scene is MeshInstance3D:
			mis.append(scene)
		for mi: MeshInstance3D in mis:
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != scene:
				if n is Node3D:
					xf = (n as Node3D).transform * xf
				n = n.get_parent()
			for s in mi.mesh.get_surface_count():
				var st := SurfaceTool.new()
				st.append_from(mi.mesh, s, xf)
				var src := mi.get_active_material(s)
				var mat: Material = src
				if model.begins_with("camp_") and src != null:
					mat = _material(src.resource_name, tier)
				var before := out.get_surface_count()
				st.commit(out)
				if out.get_surface_count() > before:
					out.surface_set_material(out.get_surface_count() - 1, mat)
		scene.free()
	_meshes[key] = out
	return out

func _flame_mesh() -> Mesh:
	if _meshes.has("flame"):
		return _meshes["flame"]
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.center_offset = Vector3(0, 0.5, 0)
	var fm := ShaderMaterial.new()
	fm.shader = FLAME_SHADER
	q.material = fm
	_meshes["flame"] = q
	return q

# ---- Placing a camp --------------------------------------------------------------------------------------------------

func _put(model: String, p: Vector2, yaw: float, scale := 1.0, tier := "", sink := 0.02) -> void:
	var mkey := model + ("@" + tier if model == "camp_totem" else "")
	if not _meshes.has(mkey):
		_mesh(model, tier)
	# one MultiMesh per prop and map chunk, so camps out of view are culled
	var ck := Vector2i(floori((p.x + SimMap.HALF) / CHUNK), floori((p.y + SimMap.HALF) / CHUNK))
	var key := "%s#%d_%d" % [mkey, ck.x, ck.y]
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	var xf := Transform3D(basis, View.to3(p, terrain.height_at(p)) - Vector3(0, sink, 0))
	if not _xforms.has(key):
		_xforms[key] = []
	_xforms[key].append(xf)

func _fire(p: Vector2, size := 1.0) -> void:
	_put("campfire", p, randf() * TAU, 1.1 * size)
	if not _meshes.has("flame"):
		_flame_mesh()
	var h := terrain.height_at(p) * View.S
	for k in 3:
		var off := Vector2.from_angle(k * TAU / 3.0 + 0.4) * 14.0 * size
		var s := (0.55 - k * 0.1) * size
		var xf := Transform3D(Basis().scaled(Vector3(s, s * 1.45, s)), View.to3(p + off, 0.0) + Vector3(0, h + 0.05, 0))
		var ck := Vector2i(floori((p.x + SimMap.HALF) / CHUNK), floori((p.y + SimMap.HALF) / CHUNK))
		var fk := "flame#%d_%d" % [ck.x, ck.y]
		if not _xforms.has(fk):
			_xforms[fk] = []
		_xforms[fk].append(xf)
	var l := OmniLight3D.new()
	l.position = View.to3(p, 0.0) + Vector3(0, h + 0.9, 0)
	l.light_color = Color(1.0, 0.6, 0.28)
	l.light_energy = 1.5
	l.omni_range = 5.5
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 45.0
	l.distance_fade_length = 10.0
	add_child(l)
	_lights.append([l, randf() * 10.0])

## The props of one camp, in its own frame: x points at the walkway it is reached by, the props at the back and sides.
func _camp(c: Dictionary) -> void:
	var p: Vector2 = c.pos
	var front := _approach(c)
	var side := front.orthogonal()
	var at := func(x: float, y: float) -> Vector2: return p + front * x + side * y
	# the Blender props face +x: a yaw of the sim angle turns that side toward the target
	var face := func(q: Vector2, target: Vector2) -> float: return (target - q).angle()
	var tier := String(c.kind)
	var box: Vector2 = c.box
	var k := maxf(box.x, box.y)
	var fire_at: Vector2 = at.call(-0.55 * k, 0.0)
	match tier:
		"small":
			_fire(fire_at)
			_put("camp_spit", fire_at, face.call(fire_at, p) + PI * 0.5)
			var tp: Vector2 = at.call(-1.15 * k, 0.55 * k)
			_put("camp_tent", tp, face.call(tp, fire_at))
			var lp: Vector2 = at.call(-0.2 * k, -0.75 * k)
			_put("camp_log", lp, face.call(lp, fire_at) + PI * 0.5)
			_put("camp_sacks", at.call(-1.0 * k, -0.7 * k), randf() * TAU, 0.9)
			_put("kf_crate_a", at.call(-1.25 * k, -0.25 * k), randf() * TAU, 0.45, "", 0.0)
		"medium":
			_fire(fire_at)
			var t1: Vector2 = at.call(-1.2 * k, 0.6 * k)
			var t2: Vector2 = at.call(-1.1 * k, -0.7 * k)
			_put("camp_tent", t1, face.call(t1, fire_at))
			_put("camp_tent", t2, face.call(t2, fire_at), 0.92)
			var rp: Vector2 = at.call(-0.15 * k, 1.05 * k)
			_put("camp_rack", rp, face.call(rp, p) + PI * 0.5)
			var lp2: Vector2 = at.call(0.0, -0.85 * k)
			_put("camp_log", lp2, face.call(lp2, fire_at) + PI * 0.5)
			_put("camp_sacks", at.call(-1.45 * k, 0.0), randf() * TAU)
		"large":
			_fire(fire_at, 1.15)
			_put("camp_spit", fire_at, face.call(fire_at, p) + PI * 0.5, 1.1)
			var hp: Vector2 = at.call(-1.25 * k, 0.45 * k)
			_put("camp_hut", hp, face.call(hp, fire_at))
			var t3: Vector2 = at.call(-1.0 * k, -0.85 * k)
			_put("camp_tent", t3, face.call(t3, fire_at))
			for y in [-1.0, 1.15]:
				var sp: Vector2 = at.call(-1.75 * k, y * 0.75 * k)
				_put("camp_stakes", sp, face.call(sp, p) + PI * 0.5)
			var rp2: Vector2 = at.call(0.1 * k, 1.1 * k)
			_put("camp_rack", rp2, face.call(rp2, p) + PI * 0.5)
			var lp3: Vector2 = at.call(0.2 * k, -0.9 * k)
			_put("camp_log", lp3, face.call(lp3, fire_at) + PI * 0.5)
		"ancient":
			_fire(fire_at, 1.3)
			for y in [-1.0, 1.0]:
				_fire(at.call(0.5 * k, y * 1.05 * k), 0.7)
				var hp2: Vector2 = at.call(-1.25 * k, y * 0.7 * k)
				_put("camp_hut", hp2, face.call(hp2, fire_at), 1.1)
			for y2 in [-1.2, 0.0, 1.2]:
				var sp2: Vector2 = at.call(-1.9 * k + absf(y2) * 0.35 * k, y2 * 0.85 * k)
				_put("camp_stakes", sp2, face.call(sp2, p) + PI * 0.5, 1.1)
			_put("bones_scatter", at.call(0.1 * k, -0.4 * k), randf() * TAU, 0.8, "", 0.0)
			_put("bones_scatter", at.call(-0.6 * k, 1.3 * k), randf() * TAU, 0.7, "", 0.0)
			_put("camp_rack", at.call(-0.2 * k, 1.35 * k), randf() * TAU)
	# the totem by the walkway: the first thing you see of the camp
	var top: Vector2 = at.call(0.85 * k, 0.95 * k)
	# its skull faces the walkway (the skull looks along the model's -z: a quarter turn)
	_put("camp_totem", top, face.call(top, p + front * 800.0) - PI * 0.5, 1.0 + (0.15 if tier in ["large", "ancient"] else 0.0), tier)
	if c.side == C.DUSK:
		_put("bones_scatter", at.call(-0.4 * k, -1.2 * k), randf() * TAU, 0.6, "", 0.0)

## The direction a camp is approached from: toward the nearest point of a walkway or lane.
func _approach(c: Dictionary) -> Vector2:
	var p: Vector2 = c.pos
	var best := Vector2.INF
	var bd := INF
	var lines: Array = map.paths.duplicate()
	for k in map.lanes:
		lines.append(map.lanes[k])
		var m := PackedVector2Array()
		for q in map.lanes[k]:
			m.append(-q)
		lines.append(m)
	for line: PackedVector2Array in lines:
		for i in line.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
			var d := q.distance_to(p)
			if d > 120.0 and d < bd:
				bd = d
				best = q
	if best == Vector2.INF:
		return (Vector2.ZERO - p).normalized()
	return (best - p).normalized()

# ---- Spawn boxes (hold Shift) -----------------------------------------------------------------------------------------

func _build_boxes() -> void:
	_box_mesh = ImmediateMesh.new()
	_box_mat = StandardMaterial3D.new()
	_box_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_box_mat.vertex_color_use_as_albedo = true
	_box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box_mat.no_depth_test = false
	_box_mat.render_priority = 2
	_boxes = MeshInstance3D.new()
	_boxes.name = "SpawnBoxes"
	_boxes.mesh = _box_mesh
	_boxes.material_override = _box_mat
	_boxes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boxes.visible = false
	add_child(_boxes)
	for c in map.camps:
		var l := Label3D.new()
		l.text = TIER_NAME[c.kind] + ("\n(pull camp)" if bool(c.pull) else "")
		l.font = UiKit.font("bold")
		l.font_size = 30
		l.outline_size = 10
		l.pixel_size = 0.0011
		l.modulate = TIER_COLOR[c.kind].lightened(0.35)
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		var p: Vector2 = c.pos
		l.position = View.to3(p, terrain.height_at(p) + 330.0)
		l.visible = false
		add_child(l)
		_labels.append([l, c.id])

## Whether the spawn boxes show: Shift held in a match (not while typing in chat).
func boxes_wanted() -> bool:
	if game != null and game.get("args") != null and game.args.has("boxes"):
		return true
	if not Input.is_key_pressed(KEY_SHIFT):
		return false
	if game != null and game.get("hud") != null and game.hud.get("chat") != null and game.hud.chat.is_open():
		return false
	return true

func _process(dt: float) -> void:
	_t += dt
	for e in _lights:
		var l: OmniLight3D = e[0]
		var ph: float = e[1]
		l.light_energy = 1.35 + 0.25 * sin(_t * 9.0 + ph) + 0.15 * sin(_t * 23.0 + ph * 2.0)
	var show := boxes_wanted()
	_boxes.visible = show
	for lb in _labels:
		(lb[0] as Label3D).visible = show
	if not show:
		return
	_box_t -= dt
	if _box_t > 0.0:
		return
	_box_t = 0.15
	_draw_boxes()

func _draw_boxes() -> void:
	var w: SimWorld = game.world if game != null else null
	_box_mesh.clear_surfaces()
	_box_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in map.camps:
		var blocked := false
		if w != null:
			for u in w.ai.box_units(c):
				if u.camp_id != c.id:
					blocked = true
					break
		var col := Color(1.0, 0.28, 0.2) if blocked else Color(1.0, 0.86, 0.25)
		var p: Vector2 = c.pos
		var box: Vector2 = c.box
		var corners := [p + Vector2(-box.x, -box.y), p + Vector2(box.x, -box.y), p + Vector2(box.x, box.y), p + Vector2(-box.x, box.y)]
		# a faint fill, then a solid band along each edge, both draped over the ground
		_fill(p, box, Color(col, 0.1))
		for i in 4:
			_band(corners[i], corners[(i + 1) % 4], p, Color(col, 0.95))
	_box_mesh.surface_end()

func _ground(q: Vector2, lift := 12.0) -> Vector3:
	return View.to3(q, terrain.height_at(q) + lift)

## A strip 22 units wide along an edge, on the inside of the box, following the terrain.
func _band(a: Vector2, b: Vector2, centre: Vector2, col: Color) -> void:
	var n := maxi(2, int(a.distance_to(b) / 40.0))
	var dir := (b - a).normalized()
	var inward := dir.orthogonal()
	if inward.dot(centre - a) < 0.0:
		inward = -inward
	for i in n:
		var p0 := a.lerp(b, float(i) / n)
		var p1 := a.lerp(b, float(i + 1) / n)
		var q0 := p0 + inward * 22.0
		var q1 := p1 + inward * 22.0
		_quad(_ground(p0), _ground(p1), _ground(q1), _ground(q0), col)

func _fill(p: Vector2, box: Vector2, col: Color) -> void:
	var n := 6
	for j in n:
		for i in n:
			var x0 := -box.x + 2.0 * box.x * i / n
			var x1 := -box.x + 2.0 * box.x * (i + 1) / n
			var y0 := -box.y + 2.0 * box.y * j / n
			var y1 := -box.y + 2.0 * box.y * (j + 1) / n
			_quad(_ground(p + Vector2(x0, y0), 8.0), _ground(p + Vector2(x1, y0), 8.0), _ground(p + Vector2(x1, y1), 8.0),
				_ground(p + Vector2(x0, y1), 8.0), col)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		_box_mesh.surface_set_color(col)
		_box_mesh.surface_add_vertex(v)

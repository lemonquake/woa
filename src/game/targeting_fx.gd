class_name TargetingFx
extends Node3D
## Ground indicators while aiming or inspecting an ability, as in Dota: the cast range around your hero, the area at
## the cursor for area spells, the path of a line spell, and for no-target spells (while hovering their button) their
## radius, plus the unit Leap Strike would jump at. Drawn over water and terrain alike.

var game: Node
var _range: MeshInstance3D
var _area: MeshInstance3D
var _area_ring: MeshInstance3D
var _line: MeshInstance3D
var _pick: MeshInstance3D
var _mat_ring: StandardMaterial3D
var _mat_fill: StandardMaterial3D
var _mat_line: StandardMaterial3D
var _mat_pick: StandardMaterial3D

func _ready() -> void:
	name = "TargetingFx"
	_mat_ring = _mat(Color(0.55, 0.85, 1.0, 0.75))
	_mat_fill = _mat(Color(0.45, 0.75, 1.0, 0.16))
	_mat_line = _mat(Color(0.5, 0.85, 1.0, 0.2))
	_mat_pick = _mat(Color(1.0, 0.3, 0.25, 0.9))
	_range = _ring_mesh(_mat_ring, 0.04)
	_area_ring = _ring_mesh(_mat_ring, 0.06)
	_pick = _ring_mesh(_mat_pick, 0.12)
	_area = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 64
	_area.mesh = disc
	_area.material_override = _mat_fill
	_area.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_area)
	_line = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 0.01, 1)
	_line.mesh = bm
	_line.material_override = _mat_line
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	_hide_all()

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.render_priority = 18
	m.no_depth_test = false
	return m

## A flat ring of radius 1 (scaled per use); thickness as a fraction of the radius.
func _ring_mesh(mat: Material, thick: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0 - thick
	tm.outer_radius = 1.0
	tm.rings = 96
	tm.ring_segments = 4
	mi.mesh = tm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _hide_all() -> void:
	for n in [_range, _area, _area_ring, _line, _pick]:
		n.visible = false

func _place_ring(mi: MeshInstance3D, at: Vector2, radius_units: float, flat := 0.05) -> void:
	var r := radius_units * View.S
	mi.scale = Vector3(r, flat, r)
	mi.global_position = game.fx.ground3(at, 0.07)
	mi.visible = true

func frame() -> void:
	_hide_all()
	var input = game.input
	var h: SimUnit = game.world.get_unit(game.player_hero_id)
	if input == null or h == null or not h.alive:
		return
	var aid: String = input.targeting
	if aid == "attack":
		_place_ring(_range, h.pos, h.attack_range + h.hull)
		return
	if aid.begins_with("item:"):
		# Mini-Axe, Vegan Picker, Ironwood Twig, wards: their cast range
		var r: float = game.world.abilities.cast_range(h, "", int(aid.substr(5)))
		if r > 0.0 and r < 5000.0:
			_place_ring(_range, h.pos, r + h.hull)
		return
	var hovered := false
	if aid == "" or aid == "attack" or aid == "tp":
		aid = String(input.get("hover_ability"))
		hovered = true
	if aid == "":
		return
	var a := SimData.ability(aid)
	if a.is_empty():
		return
	var lv := maxi(1, h.ability_level_of(aid))
	var vals: Dictionary = a.values
	var mouse: Vector2 = game.camera.ground_at(game.get_viewport().get_mouse_position())
	var beh := String(a.behavior)
	match beh:
		"point":
			var rng := float(a.range)
			_place_ring(_range, h.pos, rng + h.hull)
			if hovered:
				return
			if vals.has("radius"):
				var rad := float((vals.radius as Array)[lv - 1])
				var c := mouse
				_place_ring(_area_ring, c, rad)
				_area.scale = Vector3(rad * View.S, 1.0, rad * View.S)
				_area.global_position = game.fx.ground3(c, 0.06)
				_area.visible = true
			elif vals.has("width"):
				var width := float((vals.width as Array)[lv - 1]) * 2.0
				var dist := clampf(h.pos.distance_to(mouse), 300.0, float((vals.distance as Array)[lv - 1]))
				var dir := (mouse - h.pos).normalized()
				if dir == Vector2.ZERO:
					dir = Vector2.from_angle(h.facing)
				var mid := h.pos + dir * dist * 0.5
				_line.scale = Vector3(width * View.S, 1.0, dist * View.S)
				_line.global_position = game.fx.ground3(mid, 0.08)
				# the box's local +Z runs along the shot: (dir.x, 0, -dir.y) in the rendered world
				_line.rotation = Vector3(0, atan2(dir.x, -dir.y), 0)
				_line.visible = true
		"autocast_attack", "unit":
			_place_ring(_range, h.pos, h.attack_range + h.hull)
		"no_target":
			match aid:
				"dark_stomp":
					_place_ring(_area_ring, h.pos, float((vals.radius as Array)[lv - 1]) + h.hull)
				"unholy_might":
					_place_ring(_area_ring, h.pos, float((vals.reflect_radius as Array)[lv - 1]))
				"leap_strike":
					_place_ring(_range, h.pos, float(a.range) + h.hull)
					var t: SimUnit = game.world.abilities.leap_target(h, lv)
					if t:
						_place_ring(_pick, t.pos, maxf(t.hull, 24.0) * 2.2, 0.08)

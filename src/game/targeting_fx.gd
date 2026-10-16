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
var _path: MeshInstance3D                    # Bounce Shot's predicted ricochets, Summon Boulders' spread (ribbons)
var _path_mesh: ImmediateMesh
var _mat_path: StandardMaterial3D

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
	_mat_path = _mat(Color(0.55, 0.92, 1.0, 0.6))
	_mat_path.cull_mode = BaseMaterial3D.CULL_DISABLED      # the ribbon is seen from above whichever way it winds
	_path_mesh = ImmediateMesh.new()
	_path = MeshInstance3D.new()
	_path.mesh = _path_mesh
	_path.material_override = _mat_path
	_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_path)
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
	for n in [_range, _area, _area_ring, _line, _pick, _path]:
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
		# Mini-Axe, Vegan Picker, Tree Twig, wards, Push Staff, Gold Glove: their cast range; Jump Knife: its reach
		var r: float = game.world.abilities.cast_range(h, "", int(aid.substr(5)))
		var it = h.inventory[int(aid.substr(5))]
		if it != null and not is_finite(r):
			r = float(SimData.item(it.id).values.get("range", 0.0)) + h.cast_range_bonus
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
			var rng: float = game.world.abilities.cast_range(h, aid, -1)
			if not is_finite(rng):
				rng = game.world.abilities.val(h, aid, "distance")   # aimed by direction: how far it flies
			_place_ring(_range, h.pos, rng + h.hull)
			if hovered:
				return
			if aid == "bounce_shot":
				_bounce_path(h, mouse, lv)
			elif aid == "summon_boulders":
				_boulder_fan(h, mouse, lv)
			elif aid == "place_turret":
				# where it would stand and how far it would shoot
				_place_ring(_area_ring, mouse, float((vals.attack_range as Array)[lv - 1]))
				_place_ring(_pick, mouse, 60.0, 0.08)
			elif vals.has("radius"):
				var rad := float((vals.radius as Array)[lv - 1])
				var c := mouse
				_place_ring(_area_ring, c, rad)
				_area.scale = Vector3(rad * View.S, 1.0, rad * View.S)
				_area.global_position = game.fx.ground3(c, 0.06)
				_area.visible = true
			elif vals.has("width"):
				var width := float((vals.width as Array)[lv - 1]) * 2.0
				var dist := float((vals.distance as Array)[lv - 1])
				var dir := (mouse - h.pos).normalized()
				if dir == Vector2.ZERO:
					dir = Vector2.from_angle(h.facing)
				var mid := h.pos + dir * dist * 0.5
				_line.scale = Vector3(width * View.S, 1.0, dist * View.S)
				_line.global_position = game.fx.ground3(mid, 0.08)
				# the box's local +Z runs along the shot: (dir.x, 0, -dir.y) in the rendered world
				_line.rotation = Vector3(0, atan2(dir.x, -dir.y), 0)
				_line.visible = true
		"autocast_attack":
			_place_ring(_range, h.pos, h.attack_range + h.hull)
		"unit":
			_place_ring(_range, h.pos, game.world.abilities.cast_range(h, aid, -1) + h.hull)
		"no_target":
			match aid:
				"dark_stomp":
					_place_ring(_area_ring, h.pos, float((vals.radius as Array)[lv - 1]) + h.hull)
				"unholy_might":
					_place_ring(_area_ring, h.pos, float((vals.reflect_radius as Array)[lv - 1]))
				"void_rush":
					_place_ring(_area_ring, h.pos, float((vals.radius as Array)[lv - 1]) + h.hull)
				"anomaly":
					_place_ring(_area_ring, h.pos, float((vals.attack_range as Array)[lv - 1]) + h.hull)
				"lay_trap":
					# where he lands (400 behind him) and where the trap stays (where he stands)
					var land := h.pos + Vector2.from_angle(h.facing + PI) * float((vals.leap as Array)[lv - 1])
					_place_ring(_pick, land, 50.0, 0.08)
					_place_ring(_area_ring, h.pos, float((vals.trigger_radius as Array)[lv - 1]))
				"leap_strike":
					_place_ring(_range, h.pos, game.world.abilities.cast_range(h, "leap_strike", -1) + h.hull)
					var t: SimUnit = game.world.abilities.leap_target(h, lv)
					if t:
						_place_ring(_pick, t.pos, maxf(t.hull, 24.0) * 2.2, 0.08)
	if beh == "passive" and aid == "dark_matter_skin":
		_place_ring(_area_ring, h.pos, float((vals.radius as Array)[lv - 1]) + h.hull)

## A ribbon on the ground through `pts` (game units), `width` metres wide.
func _ribbon(pts: Array, width: float, begin := true) -> void:
	if begin:
		_path_mesh.clear_surfaces()
	if pts.size() < 2:
		return
	_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d := b - a
		var n := int(ceil(d.length() / 60.0))
		var side := Vector2(-d.y, d.x).normalized() * (width / View.S) * 0.5
		for k in n:
			var p0 := a + d * (float(k) / n)
			var p1 := a + d * (float(k + 1) / n)
			var q := [game.fx.ground3(p0 - side, 0.09), game.fx.ground3(p0 + side, 0.09), game.fx.ground3(p1 + side, 0.09),
				game.fx.ground3(p1 - side, 0.09)]
			for idx in [0, 1, 2, 0, 2, 3]:
				_path_mesh.surface_add_vertex(q[idx])
	_path_mesh.surface_end()
	_path.visible = true

## Bounce Shot: the path the bullet would take from here (its ricochets off trees, walls, boulders and units).
var _bounce_key := Vector4.INF
var _bounce_at := 0.0
var _bounce_pick := -1

func _bounce_path(h: SimUnit, mouse: Vector2, lv: int) -> void:
	# traced again only when the aim or Blau moved, or every tenth of a second (units move)
	var key := Vector4(roundf(mouse.x / 6.0), roundf(mouse.y / 6.0), roundf(h.pos.x / 6.0), roundf(h.pos.y / 6.0))
	var now := Time.get_ticks_msec() / 1000.0
	if key == _bounce_key and now - _bounce_at < 0.1:
		_path.visible = true
		var pu: SimUnit = game.world.get_unit(_bounce_pick)
		if pu and pu.alive:
			_place_ring(_pick, pu.pos, maxf(pu.hull, 24.0) * 2.0, 0.08)
		return
	_bounce_key = key
	_bounce_at = now
	var k3: SimKits3 = game.world.abilities.kits3
	var dir := mouse - h.pos
	if dir.length() < 1.0:
		dir = Vector2.from_angle(h.facing)
	dir = dir.normalized()
	var ab: SimAbilities = game.world.abilities
	var tr := k3.trace_bullet(h.pos + dir * (h.hull + 10.0), dir, h.team, ab.val(h, "bounce_shot", "distance"),
		int(ab.val(h, "bounce_shot", "bounces")), h.id, SimKits3.SUBSTEP, {}, ab.val(h, "bounce_shot", "bounce_distance"))
	_ribbon(tr.corners, 0.16)
	_bounce_pick = -1
	for id in tr.passed:
		var u: SimUnit = game.world.get_unit(int(id))
		if u and game.world.vision.sees(h.team, u):
			_place_ring(_pick, u.pos, maxf(u.hull, 24.0) * 2.0, 0.08)
			_bounce_pick = u.id
			break

## Summon Boulders: the spread they roll out in (a fan of lanes ahead).
func _boulder_fan(h: SimUnit, mouse: Vector2, lv: int) -> void:
	var dir := mouse - h.pos
	if dir.length() < 1.0:
		dir = Vector2.from_angle(h.facing)
	var ab: SimAbilities = game.world.abilities
	var n := int(ab.val(h, "summon_boulders", "count"))
	var spread := ab.val(h, "summon_boulders", "spread")
	# they roll about as far as the cursor, 200 at least and 700 at most
	var reach := clampf(dir.length(), ab.val(h, "summon_boulders", "min_distance"), ab.val(h, "summon_boulders", "distance"))
	_path_mesh.clear_surfaces()
	for i in n:
		var a := dir.angle() - spread + 2.0 * spread * (float(i) + 0.5) / float(n)
		_ribbon([h.pos, h.pos + Vector2.from_angle(a) * reach], 0.5, false)


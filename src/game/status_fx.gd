class_name StatusFx
extends Node3D
## Visuals that last as long as a unit's modifier does: a ring of stars circling a stunned unit's head, a violet
## sigil under a cursed one, Ezee's enchanted sword (glow, light, crackling arcs) and his Unholy Might aura.
## Rebuilt from the simulation's modifiers every frame, so nothing outlives the state it shows.

const AURA_SHADER := preload("res://src/game/dark_aura.gdshader")

var game: Node
var fx: Fx
var _stun := {}                             # unit id -> Node3D (orbiting stars)
var _curse := {}                            # unit id -> MeshInstance3D (ground sigil)
var _taint := {}                            # unit id -> {light, next_arc}
var _aura := {}                             # unit id -> {node, mat, t}
var _star_mesh: Mesh
var _star_mat: StandardMaterial3D
var _sigil_mat: ShaderMaterial

func _ready() -> void:
	name = "StatusFx"
	var p := PrismMesh.new()
	p.size = Vector3(0.17, 0.22, 0.04)
	_star_mesh = p
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.albedo_color = Color(1.0, 0.9, 0.45)
	_star_mat.emission_enabled = true
	_star_mat.emission = Color(1.0, 0.85, 0.4)
	_star_mat.emission_energy_multiplier = 4.5
	var sh := Shader.new()
	sh.code = SIGIL_CODE
	_sigil_mat = ShaderMaterial.new()
	_sigil_mat.shader = sh
	_sigil_mat.render_priority = 3

const SIGIL_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.6, 0.22, 1.0, 1.0);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * 0.8;
	float ring = smoothstep(0.86, 0.9, r) * (1.0 - smoothstep(0.94, 0.98, r));
	float ring2 = smoothstep(0.6, 0.63, r) * (1.0 - smoothstep(0.66, 0.69, r));
	float runes = step(0.55, fract(a * 6.0 / 6.2832 * 3.0)) * smoothstep(0.7, 0.72, r) * (1.0 - smoothstep(0.82, 0.84, r));
	float spokes = (1.0 - smoothstep(0.0, 0.04, abs(sin(a * 3.0)) * r)) * smoothstep(0.2, 0.6, r) * (1.0 - smoothstep(0.6, 0.64, r));
	float pulse = 0.75 + 0.25 * sin(TIME * 5.0);
	ALBEDO = col.rgb * 2.2;
	ALPHA = clamp((ring + ring2 * 0.8 + runes * 0.7 + spokes * 0.5) * pulse, 0.0, 1.0) * 0.85;
}
"""

var _scan_i := 0

func frame(dt: float) -> void:
	_scan_i += 1
	if _scan_i % 3 == 0:
		_scan()
	_follow(dt)

## Which units need which visuals (every third frame: modifiers change at 30 Hz at most).
func _scan() -> void:
	var w: SimWorld = game.world
	var seen_stun := {}
	var seen_curse := {}
	var seen_taint := {}
	var seen_aura := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView):
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive or not v.visible:
			continue
		for m in u.modifiers:
			match String(m.get("fx", "")):
				"stun":
					seen_stun[id] = true
				"curse":
					if int(m.get("reveal", -1)) == game.player_team or u.team == game.player_team:
						seen_curse[id] = true
				"taint":
					seen_taint[id] = true
				"unholy":
					seen_aura[id] = true
		if not u.knock.is_empty() and float(u.knock.get("stun", 0.0)) > 0.0:
			seen_stun[id] = true
	_sync(_stun, seen_stun, _make_stun)
	_sync(_curse, seen_curse, _make_curse)
	_want_taint = seen_taint
	_want_aura = seen_aura

var _want_taint := {}
var _want_aura := {}

func _follow(dt: float) -> void:
	_sync_taint(_want_taint)
	_sync_aura(_want_aura, dt)
	var t := Time.get_ticks_msec() / 1000.0
	for id in _stun:
		var v: UnitView = game.views.get(id)
		if not is_instance_valid(_stun[id]):
			continue
		var n: Node3D = _stun[id]
		if v:
			n.global_position = v.global_position + Vector3(0, v.bar_height * 0.88, 0)
			n.rotation.y = t * 5.0
	for id in _curse:
		var v2: UnitView = game.views.get(id)
		if not is_instance_valid(_curse[id]):
			continue
		var c: Node3D = _curse[id]
		if v2:
			var gp := v2.global_position
			c.global_position = Vector3(gp.x, fx.ground_y(View.to2(gp)) + 0.07, gp.z)

func _sync(store: Dictionary, want: Dictionary, make: Callable) -> void:
	for id in store.keys():
		if not want.has(id):
			var n = store[id]
			if is_instance_valid(n):
				n.queue_free()
			store.erase(id)
	for id in want:
		if not store.has(id):
			store[id] = make.call(id)

func _make_stun(id: int) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	for i in 4:
		var s := MeshInstance3D.new()
		s.mesh = _star_mesh
		s.material_override = _star_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := i * TAU / 4.0
		s.position = Vector3(cos(a) * 0.42, sin(a * 2.0) * 0.05, sin(a) * 0.42)
		s.rotation = Vector3(0, -a, 0)
		n.add_child(s)
		var tw := s.create_tween().set_loops()
		tw.tween_property(s, "rotation:z", TAU, 0.6).from(0.0)
	return n

func _make_curse(id: int) -> Node3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = _sigil_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

## Ezee's enchanted sword: glow overlay, a flickering violet light at the blade and arcs crackling now and then.
func _sync_taint(want: Dictionary) -> void:
	for id in _taint.keys():
		if not want.has(id):
			var d: Dictionary = _taint[id]
			if is_instance_valid(d.light):
				(d.light as Node).queue_free()
			if is_instance_valid(d.get("trail")):
				(d.trail as Trail3D).stop()
			if is_instance_valid(d.get("anchor")):
				(d.anchor as Node).queue_free()
			var v0: UnitView = game.views.get(id)
			if v0:
				v0.set_weapon_glow(false)
			_taint.erase(id)
	var now := Time.get_ticks_msec() / 1000.0
	for id in want:
		var v: UnitView = game.views.get(id)
		if v == null:
			continue
		if not _taint.has(id):
			v.set_weapon_glow(true, Color(0.6, 0.2, 1.0, 0.7))
			var l := OmniLight3D.new()
			l.light_color = Color(0.65, 0.3, 1.0)
			l.light_energy = 2.0
			l.omni_range = 3.5
			add_child(l)
			# a violet swing trail off the blade tip while the sword is enchanted
			var anchor := Node3D.new()
			if not v.weapons.is_empty():
				v.weapons[0].add_child(anchor)
				anchor.position = Vector3(0, 0.95, 0)
			else:
				v.add_child(anchor)
				anchor.position = Vector3(0, 1.4, 0)
			var tr := Trail3D.make(anchor, Color(0.7, 0.35, 1.0, 0.9), 0.07, 0.16)
			add_child(tr)
			_taint[id] = {"light": l, "next_arc": now + 0.2, "anchor": anchor, "trail": tr}
		var d: Dictionary = _taint[id]
		var tip := v.weapon_tip()
		(d.light as OmniLight3D).global_position = tip
		(d.light as OmniLight3D).light_energy = 1.6 + 0.8 * sin(now * 17.0) + 0.4 * sin(now * 41.0)
		if now >= float(d.next_arc):
			d.next_arc = now + randf_range(0.18, 0.45)
			var base := v.global_position + Vector3(0, v.bar_height * 0.45, 0)
			fx.lightning(base.lerp(tip, randf_range(0.3, 0.6)), tip + Vector3(randf_range(-0.25, 0.25), randf_range(-0.1, 0.3), randf_range(-0.25, 0.25)),
				Color(0.7, 0.4, 1.0), 0.08, 0.025, 5)

## Unholy Might: a dark flame shell that fades in, flickers and fades out with the modifier.
func _sync_aura(want: Dictionary, dt: float) -> void:
	for id in want:
		if not _aura.has(id):
			var mi := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.72
			cap.height = 2.9
			cap.radial_segments = 24
			cap.rings = 10
			mi.mesh = cap
			var m := ShaderMaterial.new()
			m.shader = AURA_SHADER
			m.render_priority = 4
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var l := OmniLight3D.new()
			l.light_color = Color(0.5, 0.2, 0.9)
			l.light_energy = 1.4
			l.omni_range = 4.0
			mi.add_child(l)
			l.position = Vector3(0, 0.2, 0)
			_aura[id] = {"node": mi, "mat": m, "k": 0.0, "on": true}
	for id in _aura.keys():
		var a: Dictionary = _aura[id]
		a.on = want.has(id)
		a.k = clampf(float(a.k) + (dt / 0.35 if a.on else -dt / 0.5), 0.0, 1.0)
		var v: UnitView = game.views.get(id)
		var n: MeshInstance3D = a.node
		if v == null or (not a.on and a.k <= 0.0):
			n.queue_free()
			_aura.erase(id)
			continue
		n.global_position = v.global_position + Vector3(0, 1.25, 0)
		(a.mat as ShaderMaterial).set_shader_parameter("strength", float(a.k))

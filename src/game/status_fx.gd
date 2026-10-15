class_name StatusFx
extends Node3D
## Visuals that last as long as a unit's modifier does: a ring of stars circling a stunned unit's head, a violet
## sigil under a cursed one, Ezee's enchanted sword (glow, light, crackling arcs), his Unholy Might aura and Blood
## Ranger's crimson aura while her ultimate lasts. Disables: roots at the feet of a rooted unit, a violet ring over a
## silenced head, two crossed blades over a disarmed one, a red cracked ring under a broken one, and a hexed unit
## turns into a sheep.
## Rebuilt from the simulation's modifiers every frame, so nothing outlives the state it shows.

const AURA_SHADER := preload("res://src/game/dark_aura.gdshader")

var game: Node
var fx: Fx
var _stun := {}                             # unit id -> Node3D (orbiting stars)
var _curse := {}                            # unit id -> MeshInstance3D (ground sigil)
var _taint := {}                            # unit id -> {light, next_arc}
var _aura := {}                             # unit id -> {node, mat, t}
var _blubber := {}                          # unit id -> {node, mat, k, on}
var _blubber_shader: Shader
var _star_mesh: Mesh
var _star_mat: StandardMaterial3D
var _sigil_mat: ShaderMaterial
var _root := {}                             # unit id -> Node3D (roots and thorns at the feet)
var _silence := {}                          # unit id -> Node3D (ring over the head)
var _disarm := {}                           # unit id -> Node3D (crossed blades over the head)
var _break := {}                            # unit id -> MeshInstance3D (cracked ring on the ground)
var _hex := {}                              # unit id -> Node3D (the sheep); the unit's model is hidden meanwhile
var _ring_mats := {}                        # colour key -> ShaderMaterial for ground rings

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
	_blubber_shader = Shader.new()
	_blubber_shader.code = BLUBBER_CODE

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

## Blubber: a greasy, wobbling layer of fat wrapped round the body (fresnel sheen, slow jiggle), lasting as long as
## the damage block does.
const BLUBBER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform float strength = 1.0;
uniform vec4 fat : source_color = vec4(0.95, 0.82, 0.5, 1.0);
uniform vec4 sheen : source_color = vec4(1.0, 0.97, 0.85, 1.0);
void vertex() {
	float j = sin(TIME * 7.0 + VERTEX.y * 5.0) * 0.035 + sin(TIME * 11.0 + VERTEX.x * 7.0) * 0.02;
	VERTEX += NORMAL * j * strength;
}
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float band = 0.5 + 0.5 * sin(UV.y * 40.0 + TIME * 3.0);
	ALBEDO = mix(fat.rgb, sheen.rgb, f * 0.8) * (0.9 + 0.2 * band);
	ALPHA = clamp((0.015 + pow(f, 1.6) * 0.6) * strength, 0.0, 0.6);
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
	var seen_blubber := {}
	var seen_root := {}
	var seen_silence := {}
	var seen_disarm := {}
	var seen_break := {}
	var seen_hex := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView):
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive or not v.visible:
			continue
		for m in u.modifiers:
			if m.get("root", false):
				seen_root[id] = true
			if m.get("hex", false):
				seen_hex[id] = true
			elif m.get("silence", false):
				seen_silence[id] = true
			if m.get("disarm", false) and not m.get("hex", false):
				seen_disarm[id] = true
			if m.get("break", false):
				seen_break[id] = true
			match String(m.get("fx", "")):
				"stun":
					seen_stun[id] = true
				"curse":
					if int(m.get("reveal", -1)) == game.player_team or u.team == game.player_team:
						seen_curse[id] = true
				"taint":
					seen_taint[id] = true
				"unholy":
					seen_aura[id] = "unholy"
				"blood":
					seen_aura[id] = "blood"
				"blubber":
					seen_blubber[id] = true
		if not u.knock.is_empty() and float(u.knock.get("stun", 0.0)) > 0.0:
			seen_stun[id] = true
	_sync(_stun, seen_stun, _make_stun)
	_sync(_curse, seen_curse, _make_curse)
	_sync(_root, seen_root, _make_root)
	_sync(_silence, seen_silence, _make_silence)
	_sync(_disarm, seen_disarm, _make_disarm)
	_sync(_break, seen_break, _make_break)
	_sync_hex(seen_hex)
	_want_taint = seen_taint
	_want_aura = seen_aura
	_want_blubber = seen_blubber

var _want_taint := {}
var _want_aura := {}
var _want_blubber := {}

func _follow(dt: float) -> void:
	_sync_taint(_want_taint)
	_sync_aura(_want_aura, dt)
	_sync_blubber(_want_blubber, dt)
	var t := Time.get_ticks_msec() / 1000.0
	for id in _stun:
		var v: UnitView = game.views.get(id)
		if not is_instance_valid(_stun[id]):
			continue
		var n: Node3D = View.live(_stun[id])
		if v:
			n.global_position = v.global_position + Vector3(0, v.bar_height * 0.88, 0)
			n.rotation.y = t * 5.0
	for id in _curse:
		var v2: UnitView = game.views.get(id)
		if not is_instance_valid(_curse[id]):
			continue
		var c: Node3D = View.live(_curse[id])
		if v2:
			var gp := v2.global_position
			c.global_position = Vector3(gp.x, fx.ground_y(View.to2(gp)) + 0.07, gp.z)
	for store in [_root, _break]:
		for id in store:
			var vg: UnitView = game.views.get(id)
			if vg and is_instance_valid(store[id]):
				var gp2 := vg.global_position
				(store[id] as Node3D).global_position = Vector3(gp2.x, fx.ground_y(View.to2(gp2)) + 0.06, gp2.z)
	for store2 in [_silence, _disarm]:
		for id in store2:
			var vh: UnitView = game.views.get(id)
			if vh and is_instance_valid(store2[id]):
				var n2: Node3D = View.live(store2[id])
				# at head height, under the health bar that is drawn over the unit
				n2.global_position = vh.global_position + Vector3(0, vh.bar_height * (0.74 if store2 == _disarm else 0.8), 0)
				n2.rotation.y = t * (1.6 if store2 == _silence else 0.0)

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

## A flat ring on the ground in a colour, with a pattern: "thorns" (roots) or "cracks" (break).
func _ground_ring(col: Color, pattern: String, size: float) -> MeshInstance3D:
	var key := col.to_html() + pattern
	var m: ShaderMaterial = _ring_mats.get(key)
	if m == null:
		var sh := Shader.new()
		sh.code = RING_CODE
		m = ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("col", col)
		m.set_shader_parameter("cracks", 1.0 if pattern == "cracks" else 0.0)
		m.render_priority = 3
		_ring_mats[key] = m
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

const RING_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.4, 0.8, 0.25, 1.0);
uniform float cracks = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ring = smoothstep(0.62, 0.7, r) * (1.0 - smoothstep(0.86, 0.95, r));
	float thorns = (1.0 - smoothstep(0.0, 0.18, abs(sin(a * 9.0)) + (r - 0.35))) * smoothstep(0.25, 0.5, r) * (1.0 - smoothstep(0.85, 0.95, r));
	float crack = (1.0 - smoothstep(0.0, 0.05, abs(sin(a * 5.0 + r * 9.0)) * r)) * smoothstep(0.3, 0.6, r) * (1.0 - smoothstep(0.9, 0.98, r));
	float shape = cracks > 0.5 ? max(ring * 0.7, crack) : max(ring, thorns);
	ALBEDO = col.rgb * 1.6;
	ALPHA = clamp(shape * (0.75 + 0.25 * sin(TIME * 4.0)), 0.0, 0.9);
}
"""

## Roots: a thorny green ring under the unit and a few dark stakes around its feet.
func _make_root(id: int) -> Node3D:
	var n := _ground_ring(Color(0.35, 0.75, 0.2), "thorns", 1.6)
	var stake := CylinderMesh.new()
	stake.top_radius = 0.0
	stake.bottom_radius = 0.06
	stake.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.2, 0.1)
	mat.roughness = 0.9
	for i in 6:
		var s := MeshInstance3D.new()
		s.mesh = stake
		s.material_override = mat
		var a := i * TAU / 6.0
		s.position = Vector3(cos(a) * 0.45, 0.3, sin(a) * 0.45)
		s.rotation = Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5)
		n.add_child(s)
		s.scale = Vector3(1, 0.05, 1)
		s.create_tween().tween_property(s, "scale", Vector3.ONE, 0.18)
	return n

## Silence: a violet ring turning over the head.
func _make_silence(id: int) -> Node3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.38
	mi.mesh = tm
	mi.material_override = fx._glow(Color(0.62, 0.3, 1.0, 0.85), 4.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1, 0.35, 1)
	add_child(mi)
	return mi

## Disarm: two crossed blades over the head, in orange.
func _make_disarm(id: int) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.6, 0.02)
	var mat := fx._glow(Color(1.0, 0.55, 0.15, 0.9), 3.5)
	for sgn in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		b.mesh = bm
		b.material_override = mat
		b.rotation.z = sgn * PI * 0.25
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(b)
	return n

## Break: a red cracked ring on the ground.
func _make_break(id: int) -> Node3D:
	return _ground_ring(Color(1.0, 0.25, 0.2), "cracks", 1.5)

## Hex: the unit's model is hidden and a small sheep stands in its place (it walks and turns with the unit).
func _sync_hex(want: Dictionary) -> void:
	for id in _hex.keys():
		if not want.has(id):
			var v0: UnitView = game.views.get(id)
			if v0 and v0.model:
				v0.model.visible = true
			if is_instance_valid(_hex[id]):
				(_hex[id] as Node).queue_free()
			_hex.erase(id)
			if v0:
				fx.debris(v0.global_position + Vector3(0, 0.6, 0), 8, Color(0.9, 0.95, 0.9), 2.0, 0.5, "chip")
	for id in want:
		if _hex.has(id):
			continue
		var v: UnitView = game.views.get(id)
		if v == null or v.pivot == null:
			continue
		if v.model:
			v.model.visible = false
		var sheep := _make_sheep()
		v.pivot.add_child(sheep)
		_hex[id] = sheep

func _make_sheep() -> Node3D:
	var n := Node3D.new()
	var wool := StandardMaterial3D.new()
	wool.albedo_color = Color(0.93, 0.92, 0.88)
	wool.roughness = 1.0
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.18, 0.16, 0.15)
	skin.roughness = 0.8
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.5
	body.mesh = sm
	body.material_override = wool
	body.position = Vector3(0, 0.45, 0)
	body.scale = Vector3(0.95, 1.0, 1.35)
	n.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.13
	hm.height = 0.26
	head.mesh = hm
	head.material_override = skin
	head.position = Vector3(0, 0.62, -0.42)          # the view faces -Z in its pivot
	n.add_child(head)
	var leg := CylinderMesh.new()
	leg.top_radius = 0.035
	leg.bottom_radius = 0.035
	leg.height = 0.3
	for p in [Vector3(0.14, 0.15, 0.22), Vector3(-0.14, 0.15, 0.22), Vector3(0.14, 0.15, -0.22), Vector3(-0.14, 0.15, -0.22)]:
		var l := MeshInstance3D.new()
		l.mesh = leg
		l.material_override = skin
		l.position = p
		n.add_child(l)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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

			var v0: UnitView = game.views.get(id)
			if v0:
				v0.set_weapon_glow(false)
				if v0.swing_trail:
					v0.swing_trail.color = Color(0.92, 0.92, 1.0, 0.45)
					v0.swing_trail.width = 0.06
					v0.swing_lit = false
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
			# the blade's swing trail turns violet and stays lit while the sword is enchanted
			if v.swing_trail:
				v.swing_trail.color = Color(0.7, 0.35, 1.0, 0.9)
				v.swing_trail.width = 0.08
				v.swing_lit = true
			_taint[id] = {"light": l, "next_arc": now + 0.2}
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
			var blood := String(want[id]) == "blood"
			if blood:
				# a thinner crimson flame, so her silhouette stays readable
				m.set_shader_parameter("core", Color(0.12, 0.0, 0.02))
				m.set_shader_parameter("rim", Color(0.6, 0.015, 0.05))
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.2, 0.15) if blood else Color(0.5, 0.2, 0.9)
			l.light_energy = 1.4
			l.omni_range = 4.0
			mi.add_child(l)
			l.position = Vector3(0, 0.2, 0)
			_aura[id] = {"node": mi, "mat": m, "k": 0.0, "on": true, "max": 0.6 if blood else 1.0}
	for id in _aura.keys():
		var a: Dictionary = _aura[id]
		a.on = want.has(id)
		a.k = clampf(float(a.k) + (dt / 0.35 if a.on else -dt / 0.5), 0.0, 1.0)
		var v: UnitView = game.views.get(id)
		var n: MeshInstance3D = View.live(a.node)
		if v == null or (not a.on and a.k <= 0.0):
			n.queue_free()
			_aura.erase(id)
			continue
		n.global_position = v.global_position + Vector3(0, 1.25, 0)
		(a.mat as ShaderMaterial).set_shader_parameter("strength", float(a.k) * float(a.max))

func _sync_blubber(want: Dictionary, dt: float) -> void:
	for id in want:
		if not _blubber.has(id):
			var mi := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.62
			cap.height = 2.2
			cap.radial_segments = 28
			cap.rings = 12
			mi.mesh = cap
			var m := ShaderMaterial.new()
			m.shader = _blubber_shader
			m.render_priority = 3
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_blubber[id] = {"node": mi, "mat": m, "k": 0.0, "on": true}
	for id in _blubber.keys():
		var b: Dictionary = _blubber[id]
		b.on = want.has(id)
		b.k = clampf(float(b.k) + (dt / 0.2 if b.on else -dt / 0.4), 0.0, 1.0)
		var v: UnitView = game.views.get(id)
		var n: MeshInstance3D = View.live(b.node)
		if v == null or (not b.on and b.k <= 0.0):
			n.queue_free()
			_blubber.erase(id)
			continue
		n.global_position = v.global_position + Vector3(0, 1.05, 0)
		# swells in with a little overshoot, like a belly being slapped
		var k := float(b.k)
		var s := 0.9 + 0.12 * k + 0.05 * sin(k * PI)
		n.scale = Vector3(s * 1.08, s, s * 1.08)
		(b.mat as ShaderMaterial).set_shader_parameter("strength", k)

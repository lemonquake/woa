class_name ItemFx
extends Node
## Visual feedback for the combination items, driven by simulation events: Jump Knife's flashes at both ends,
## Shock Hammer's lightning arcs, Spell Shield's golden burst, Gold Glove's coins, the Mana Boots and Medic Kit
## pulses, a dust trail behind a Push Staff push, a puff when Sneak Blade's invisibility ends, a sparkle when items
## combine, Spike Armor's thorns flying back at an attacker, Block Shield's flash, Cleave Axe's sweep.
## Lasting states, rebuilt from the units' modifiers (frame): Spike Armor's crown of turning spikes while active,
## Spell Shield's golden dome, the rust ring of Rust Stone / Armor Breaker corruption, Frenzy Mask's red rage, Slip
## Boots' wind at the feet. (Spell Shield's size and an invisible hero's fade are in UnitView.)

var game: Node
var fx: Fx
var fire: FireFx
var _thorns: Array = []                    # Spike Armor's returned thorns: {node, from, to_id, t, dur}
var _bubbles: Array = []                   # Block Shield flashes: {node, mat, t, dur}
var _arcs: Array = []                      # Cleave sweeps: {node, mat, t, dur}
var _lasting := {}                         # "kind:unit id" -> {node, mats}
var _scan_i := 0

const FRESNEL_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float strength = 1.0;
uniform float hexes = 0.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	vec2 h = UV * vec2(36.0, 18.0);
	vec2 g = abs(fract(h + vec2(0.5 * floor(h.y), 0.0)) - 0.5);
	float cell = smoothstep(0.42, 0.48, max(g.x, g.y)) * hexes;
	float shimmer = 0.75 + 0.25 * sin(TIME * 4.0 + UV.y * 30.0);
	ALBEDO = col.rgb * 2.2;
	ALPHA = clamp((f * 0.9 + cell * 0.35 * (0.3 + f)) * shimmer * strength, 0.0, 1.0);
}
"""

const RING_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.45, 0.32, 0.12, 1.0);
float h1(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float crack = step(0.82, h1(vec2(floor(a * 7.0), 3.0))) * smoothstep(0.35, 0.9, r);
	float ring = smoothstep(0.62, 0.7, r) * (1.0 - smoothstep(0.86, 0.95, r));
	float spots = step(0.7, h1(floor(p * 9.0))) * (1.0 - smoothstep(0.6, 0.95, r)) * 0.5;
	ALBEDO = col.rgb * (0.7 + 0.3 * sin(TIME * 2.0 + a * 3.0));
	ALPHA = clamp(ring * 0.75 + crack * 0.6 + spots * 0.4, 0.0, 0.85);
}
"""

static var _fresnel: Shader
static var _ring: Shader

static func fresnel_mat(col: Color, hexes := 0.0) -> ShaderMaterial:
	if _fresnel == null:
		_fresnel = Shader.new()
		_fresnel.code = FRESNEL_CODE
	var m := ShaderMaterial.new()
	m.shader = _fresnel
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("hexes", hexes)
	return m

func event(e: Dictionary) -> void:
	match String(e.t):
		"jump":
			_jump(e)
		"chain":
			_chain(e)
		"spell_shield":
			var su: SimUnit = game.world.get_unit(int(e.u))
			var c := fx._chest(int(e.u), 0.5)
			if su and fx._seen(su.pos):
				fx.shockwave(fx.ground3(su.pos, 0.05), 1.4, Color(1.0, 0.8, 0.3), 0.4, 0.2, 2.5)
				fx.impact(c, Color(1.0, 0.85, 0.4), 0.45)
				fx.flash_light(c, Color(1.0, 0.85, 0.45), 3.0, 5.0, 0.3)
		"gold_glove":
			var t: SimUnit = game.world.get_unit(int(e.target))
			if t and fx._seen(t.pos):
				var c2 := fx._chest(t.id, 0.5)
				fx.debris(c2, 10, Color(1.0, 0.8, 0.2), 3.5, 0.8, "sphere")
				fx.flash_light(c2, Color(1.0, 0.85, 0.3), 3.0, 4.0, 0.3)
			if int(e.u) == game.player_hero_id and t:
				game.bars.popup("+%d" % int(e.gold), fx._chest(t.id, 1.0), Color(1.0, 0.82, 0.25), 24, 1.4, 1.6)
		"mana_burst":
			var u: SimUnit = game.world.get_unit(int(e.u))
			if u and fx._seen(u.pos):
				fx.shockwave(fx.ground3(u.pos, 0.05), float(e.radius) * View.S, Color(0.35, 0.55, 1.0), 0.7, 0.25, 2.0)
		"mend":
			var u2: SimUnit = game.world.get_unit(int(e.u))
			if u2 and fx._seen(u2.pos):
				fx.shockwave(fx.ground3(u2.pos, 0.05), float(e.radius) * View.S, Color(0.45, 1.0, 0.5), 0.7, 0.25, 2.0)
				fx.impact(fx._chest(u2.id, 0.5), Color(0.6, 1.0, 0.6), 0.4)
		"knockback":
			if bool(e.get("push_staff", false)):
				var u3: SimUnit = game.world.get_unit(int(e.u))
				if u3 and fx._seen(u3.pos):
					var dir: Vector2 = (e.to as Vector2) - u3.pos
					fx.sparks(fx.ground3(u3.pos, 0.3), Vector3(-dir.x, 0.4, dir.y).normalized(), 8,
						Color(0.85, 0.85, 1.0), 4.0)
					fx.edge_ring(fx.ground3(u3.pos, 0.05), 0.9, Color(0.75, 0.8, 1.0), 0.5)
		"sneak_end":
			var u4: SimUnit = game.world.get_unit(int(e.u))
			if u4 and fx._seen(u4.pos):
				fx.debris(fx._chest(u4.id, 0.5), 8, Color(0.3, 0.3, 0.35), 2.0, 1.2, "sphere")
		"combine":
			if int(e.u) == game.player_hero_id:
				var u5: SimUnit = game.world.get_unit(int(e.u))
				if u5:
					fx.sparks(fx._chest(u5.id, 0.8), Vector3.UP, 10, Color(1.0, 0.85, 0.4), 3.0)
		"spikes_return":
			_spikes_return(e)
		"blocked":
			_block_flash(int(e.u))
		"cleave":
			_cleave(e)
		"item_use":
			if String(e.get("item", "")) == "spike_armor":
				var su: SimUnit = game.world.get_unit(int(e.u))
				if su and fx._seen(su.pos):
					fx.shockwave(fx.ground3(su.pos, 0.05), 1.3, Color(0.9, 0.15, 0.1), 0.35, 0.18, 2.5)
					fx.sparks(fx._chest(su.id, 0.5), Vector3.UP, 14, Color(1.0, 0.35, 0.25), 4.5)

# ---- Thorns, blocks and sweeps ------------------------------------------------------------------------------------------

func _spike_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.045
	c.height = 0.32
	c.radial_segments = 6
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.06, 0.05)
	m.metallic = 0.9
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = Color(1.0, 0.15, 0.08)
	m.emission_energy_multiplier = 1.6
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Spike Armor sends damage back: red steel thorns fly from the wearer into the attacker (more while it is active).
func _spikes_return(e: Dictionary) -> void:
	var u: SimUnit = game.world.get_unit(int(e.u))
	var t: SimUnit = game.world.get_unit(int(e.target))
	if u == null or t == null or not (fx._seen(u.pos) or fx._seen(t.pos)):
		return
	var n := 3 if bool(e.get("active", false)) else 1
	for i in n:
		var th := Node3D.new()
		var sp := _spike_mesh()
		sp.rotation.x = -PI * 0.5
		th.add_child(sp)
		add_child(th)
		var from := fx._chest(u.id, 0.55) + Vector3(randf_range(-0.2, 0.2), randf_range(-0.15, 0.2), randf_range(-0.2, 0.2))
		th.global_position = from
		_thorns.append({"node": th, "from": from, "to_id": t.id, "t": -0.04 * i, "dur": 0.16})

func _block_flash(uid: int) -> void:
	var v := fx._view_of(uid)
	if v == null or not v.visible:
		return
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.75
	s.height = 1.6
	mi.mesh = s
	var m := fresnel_mat(Color(0.55, 0.8, 1.0), 1.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = v.global_position + Vector3(0, v.bar_height * 0.45, 0)
	_bubbles.append({"node": mi, "mat": m, "t": 0.0, "dur": 0.32})
	fx.sparks(mi.global_position + v.global_transform.basis.z * -0.5, Vector3.UP, 6, Color(0.7, 0.9, 1.0), 3.0)

## Cleave Axe: a pale sweep across the cone in front of the attacker.
func _cleave(e: Dictionary) -> void:
	var u: SimUnit = game.world.get_unit(int(e.u))
	if u == null or not fx._seen(u.pos):
		return
	var dir: Vector2 = e.dir
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(float(e.dist) * View.S * 0.9, float(e.dist) * View.S * 0.9)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float k = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - vec2(1.0, 2.0);
	float r = length(p);
	float a = atan(p.x, -p.y);
	float sweep = smoothstep(0.75, 0.0, abs(a)) * smoothstep(0.55, 0.85, r) * (1.0 - smoothstep(0.92, 1.0, r));
	float edge = smoothstep(0.08, 0.0, abs(a - mix(-0.7, 0.7, k)));
	ALBEDO = vec3(1.0, 0.95, 0.85) * 1.8;
	ALPHA = clamp(sweep * (0.25 + edge) * (1.0 - k), 0.0, 1.0);
}
"""
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = fx.ground3(u.pos, 0.9)
	mi.rotation.y = View.yaw(dir.angle()) + PI
	_arcs.append({"node": mi, "mat": m, "t": 0.0, "dur": 0.22})

# ---- Lasting states ---------------------------------------------------------------------------------------------------

func frame(dt: float) -> void:
	_scan_i += 1
	if _scan_i % 3 == 0:
		_scan()
	_follow(dt)
	for i in range(_thorns.size() - 1, -1, -1):
		var th: Dictionary = _thorns[i]
		var n: Node3D = th.node
		th.t = float(th.t) + dt
		var to := fx._chest(int(th.to_id), 0.55)
		var k := clampf(float(th.t) / float(th.dur), 0.0, 1.0)
		n.global_position = (th.from as Vector3).lerp(to, k)
		if (to - n.global_position).length() > 0.01:
			n.look_at(to, Vector3.UP)
		if k >= 1.0:
			fx.sparks(to, Vector3.UP, 5, Color(1.0, 0.3, 0.2), 3.0)
			fx.impact(to, Color(0.9, 0.15, 0.1), 0.25)
			n.queue_free()
			_thorns.remove_at(i)
	for list in [_bubbles, _arcs]:
		for i in range(list.size() - 1, -1, -1):
			var b: Dictionary = list[i]
			b.t = float(b.t) + dt
			var k := clampf(float(b.t) / float(b.dur), 0.0, 1.0)
			if list == _bubbles:
				(b.mat as ShaderMaterial).set_shader_parameter("strength", 1.0 - k)
				(b.node as Node3D).scale = Vector3.ONE * (0.9 + 0.25 * k)
			else:
				(b.mat as ShaderMaterial).set_shader_parameter("k", k)
			if k >= 1.0:
				(b.node as Node3D).queue_free()
				list.remove_at(i)

func _scan() -> void:
	var w: SimWorld = game.world
	var want := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView) or not v.visible:
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive:
			continue
		for m in u.modifiers:
			var f := String(m.get("fx", ""))
			if f in ["spikes", "spell_shield", "corruption", "berserk", "slip"]:
				want["%s:%d" % [f, id]] = true
	for k in _lasting.keys():
		if not want.has(k):
			var e: Dictionary = _lasting[k]
			if is_instance_valid(e.node):
				if fire:
					for mi in (e.node as Node3D).find_children("*", "MeshInstance3D", true, false):
						mi.visible = false
					fire.timed(e.node, 0.0)
				else:
					(e.node as Node3D).queue_free()
			_lasting.erase(k)
	for k in want:
		if not _lasting.has(k):
			_lasting[k] = _make_lasting(String(k).get_slice(":", 0), int(String(k).get_slice(":", 1)))

func _make_lasting(kind: String, id: int) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	match kind:
		"spikes":
			# a crown of red steel spikes turning round the chest, pointing out
			var ring := Node3D.new()
			ring.name = "Ring"
			n.add_child(ring)
			for i in 10:
				var sp := _spike_mesh()
				var a := TAU * i / 10.0
				sp.position = Vector3(cos(a), (i % 2) * 0.12, sin(a)) * 0.5
				sp.rotation = Vector3(0, -a, -PI * 0.5)
				ring.add_child(sp)
			var gl := FireFx.light(Color(1.0, 0.2, 0.12), 0.9, 2.5)
			n.add_child(gl)
		"spell_shield":
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 2.2
			mi.mesh = s
			var dome := fresnel_mat(Color(1.0, 0.78, 0.3), 0.6)
			dome.set_shader_parameter("strength", 0.5)
			mi.material_override = dome
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "Dome"
			n.add_child(mi)
		"corruption":
			var mi2 := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(1.5, 1.5)
			q.orientation = PlaneMesh.FACE_Y
			mi2.mesh = q
			if _ring == null:
				_ring = Shader.new()
				_ring.code = RING_CODE
			var rm := ShaderMaterial.new()
			rm.shader = _ring
			mi2.material_override = rm
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi2.name = "Ground"
			n.add_child(mi2)
		"berserk":
			var mi3 := MeshInstance3D.new()
			var s3 := SphereMesh.new()
			s3.radius = 0.6
			s3.height = 1.9
			mi3.mesh = s3
			var rage := fresnel_mat(Color(0.9, 0.06, 0.04), 0.0)
			rage.set_shader_parameter("strength", 0.32)
			mi3.material_override = rage
			mi3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi3.name = "Rage"
			n.add_child(mi3)
			n.add_child(FireFx.embers(0.35, 10.0, 0.9, 1.2, 0.04, Color(1.0, 0.15, 0.1)))
		"slip":
			var e := FireFx.embers(0.25, 26.0, 0.45, 0.25, 0.05, Color(0.85, 0.92, 1.0))
			(e.process_material as ParticleProcessMaterial).gravity = Vector3.ZERO
			e.name = "Wind"
			n.add_child(e)
	return {"node": n, "kind": kind, "id": id}

func _follow(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for k in _lasting:
		var e: Dictionary = _lasting[k]
		var v := fx._view_of(int(e.id))
		var n: Node3D = e.node
		if v == null or not is_instance_valid(n):
			continue
		var base := v.global_position
		match String(e.kind):
			"spikes":
				n.global_position = base + Vector3(0, v.bar_height * 0.5, 0)
				var ring := n.get_node("Ring") as Node3D
				ring.rotation.y = now * 1.8
				ring.scale = Vector3.ONE * (1.0 + 0.06 * sin(now * 9.0))
			"spell_shield":
				n.global_position = base + Vector3(0, v.bar_height * 0.5, 0)
				n.scale = Vector3.ONE * (v.bar_height / 2.2) * 0.95
			"corruption":
				n.global_position = Vector3(base.x, fx.ground_y(View.to2(base)) + 0.05, base.z)
			"berserk":
				n.global_position = base + Vector3(0, v.bar_height * 0.45, 0)
			"slip":
				n.global_position = base + Vector3(0, 0.15, 0)

func _jump(e: Dictionary) -> void:
	var from: Vector2 = e.from
	var to: Vector2 = e.to
	for p in [from, to]:
		if fx._seen(p):
			var at := fx.ground3(p, 1.0)
			fx.flash_light(at, Color(0.8, 0.7, 1.0), 3.5, 5.0, 0.25)
			fx.sparks(at, Vector3.UP, 12, Color(0.85, 0.75, 1.0), 4.0)
			fx.shockwave(fx.ground3(p, 0.05), 0.9, Color(0.7, 0.6, 1.0), 0.35, 0.15, 2.0)

func _chain(e: Dictionary) -> void:
	var to: Vector2 = e.pos
	var from: Vector2 = e.get("from", to)
	if not fx._seen(to) and not fx._seen(from):
		return
	var t3 := fx._chest(int(e.u), 0.55)
	if from.distance_to(to) < 1.0:
		# the first strike comes down from above the target
		fx.lightning(t3 + Vector3(0, 3.5, 0), t3, Color(0.6, 0.8, 1.0), 0.3, 0.08, 10)
	else:
		fx.lightning(fx.ground3(from, 1.0), t3, Color(0.6, 0.8, 1.0), 0.3, 0.08, 14)
	fx.sparks(t3, Vector3.UP, 6, Color(0.7, 0.85, 1.0), 4.0)
	fx.flash_light(t3, Color(0.6, 0.8, 1.0), 2.5, 4.0, 0.15)

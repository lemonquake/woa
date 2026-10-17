class_name AzraelFx
extends Node
## Azrael's visuals (2026-10-17), all built from FireFx particles and a few small shaders, freed with what they show:
##   * her presence: white soul flame streaming off the hem of her robe as she floats, pale motes, a cold light, red
##     glowing eyes (two tiny additive sprites on her head bone), white wisps along the scythe's blade;
##   * Soul Tap: a crimson ring on the ground drawing in; a soul wisp flies from every unit in it to her chest; while
##     charged her blade burns crimson and black, a red light pulsing on it;
##   * the charged slash: a great crescent of black and crimson sweeping through the cleave, sparks and a dark burst on
##     the target, a short camera shake;
##   * Death Scythe: a thin white-silver slash across the target with a flash;
##   * Door of the End: an arched spirit door rising out of the ground (white swirl, red veins, a bright rim), the exit
##     the same in red; units fade into it and step out in a spirit blast (white and crimson rings, soul flame thrown
##     up, a flash and a shake);
##   * Divine Darkness: her white wings burst open (feathers and light), beat slowly while she flies, and fold away at
##     the end; darkness pools on the ground round her; blinded enemies have a dark haze about their heads.

const EVENTS := ["soul_tap", "soul_slash", "death_scythe", "door_open", "door_exit_set", "door_in", "door_out",
	"door_blast", "divine_darkness", "darkness_end"]

const RED := Color(0.95, 0.08, 0.1)
const SOUL := Color(0.85, 0.92, 1.0)
const WINGS := "res://assets/characters/hero/azrael_wings.glb"
const EYE_SKEL := Vector3(0.026, 1.674, 0.078)       # her eyes in skeleton space (measured on azrael.glb, 2026-10-17 f)
const WING_SKEL := Vector3(0.0, 1.40, -0.15)         # between the shoulder blades

var game: Node
var fx: Fx
var fire: FireFx
var _aura := {}                            # Azrael id -> {hem, motes, light, blade, eyes: [..], eye_root}
var _charge := {}                          # Azrael id -> {flames, smoke, light}
var _wings := {}                           # Azrael id -> {root, parts: {}, t, spread, folding, pool, motes}
var _blind := {}                           # unit id -> haze node
var _doors := {}                           # seq -> {entrance: node, exit: node, until}
var _flyers: Array = []                    # soul wisps: {node, from, to_id, t, dur, arc}
var _slashes: Array = []                   # {node, mat, t, dur}
var _scan_i := 0

static var _slash_shader: Shader
static var _door_shader: Shader
static var _pool_shader: Shader
static var _wing_shader: Shader
static var _eye_mat: StandardMaterial3D

# ---- Events -------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	match String(e.t):
		"soul_tap":
			_soul_tap(e)
		"soul_slash":
			_soul_slash(e)
		"death_scythe":
			_death_scythe(e)
		"door_open":
			_door(e, false)
		"door_exit_set":
			_door(e, true)
		"door_in":
			var p: Vector2 = e.pos
			if fx._seen(p):
				var c := fx._chest(int(e.u), 0.5)
				fire.burst(c, 0.35, "soul", 0.5)
				fx.flash_light(c, SOUL, 2.5, 4.0, 0.25)
		"door_out":
			var p2: Vector2 = e.pos
			if fx._seen(p2):
				fire.burst(fx.ground3(p2, 1.0), 0.45, "soul", 0.7)
		"door_blast":
			_door_blast(e)
		"divine_darkness":
			var u: SimUnit = game.world.get_unit(int(e.u))
			if u and fx._seen(u.pos):
				var c2 := fx._chest(u.id, 0.75)
				fire.burst(c2, 0.9, "soul", 1.3)
				fx.flash_light(c2, Color(1.0, 0.97, 0.9), 6.0, 9.0, 0.5)
				fx.shockwave(fx.ground3(u.pos, 0.05), 7.0, Color(0.05, 0.02, 0.06), 0.8, 0.3, 0.6)
		"darkness_end":
			pass

# ---- Per frame -----------------------------------------------------------------------------------------------------

func update(w: SimWorld, _alpha: float, dt: float) -> void:
	_scan_i += 1
	if _scan_i % 3 == 0:
		_scan(w)
	_follow(w, dt)
	_update_flyers(dt)
	_update_slashes(dt)
	_update_doors(w)

func _scan(w: SimWorld) -> void:
	var want_aura := {}
	var want_charge := {}
	var want_wings := {}
	var want_blind := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView):
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive or not v.visible:
			continue
		var hidden := u.has_flag("hidden")
		if String(u.def.get("model", "")) == "hero_azrael" and not hidden:
			want_aura[id] = true
			if not u.get_modifier("soul_tap").is_empty():
				want_charge[id] = true
			if not u.get_modifier("divine_darkness").is_empty():
				want_wings[id] = true
		if not u.get_modifier("darkness_blind").is_empty() and not hidden:
			want_blind[id] = true
	for id in _aura.keys():
		if not want_aura.has(id):
			_free_aura(id)
	for id in want_aura:
		if not _aura.has(id):
			_aura[id] = _make_aura(id)
	for id in _charge.keys():
		if not want_charge.has(id):
			for k in ["flames", "smoke", "light"]:
				fire.timed(_charge[id][k], 0.0)
			_charge.erase(id)
	for id in want_charge:
		if not _charge.has(id):
			_charge[id] = _make_charge()
	for id in _wings.keys():
		if not want_wings.has(id) and not bool(_wings[id].folding):
			_wings[id].folding = true
			_wings[id].t = 0.0
	for id in want_wings:
		if not _wings.has(id):
			_wings[id] = _make_wings(id)
		elif bool(_wings[id].folding):
			_wings[id].folding = false
	for id in _blind.keys():
		if not want_blind.has(id):
			fire.timed(_blind[id], 0.0)
			_blind.erase(id)
	for id in want_blind:
		if not _blind.has(id):
			var hz := FireFx.smoke(0.25, 8.0, 0.7, 1.2, 0.3, 0.55)
			add_child(hz)
			_blind[id] = hz

## Everything that rides with her: placed every frame (the particles are world-space, so they stream behind).
func _follow(w: SimWorld, dt: float) -> void:
	for id in _aura:
		var v: UnitView = fx._view_of(id)
		if v == null:
			continue
		var a: Dictionary = _aura[id]
		var base := v.global_position + Vector3(0, v.model.position.y if v.model else 0.0, 0)
		(a.hem as Node3D).global_position = base + Vector3(0, 0.35, 0)
		(a.motes as Node3D).global_position = base + Vector3(0, 0.9, 0)
		(a.light as Node3D).global_position = base + Vector3(0, 1.4, 0.3)
		var blade = a.get("blade")
		if blade is Node3D and is_instance_valid(blade):
			var wn = v.weapon_nodes.get("R")
			if wn is Node3D and is_instance_valid(wn):
				(blade as Node3D).global_transform = (wn as Node3D).global_transform
		if _charge.has(id):
			var ch: Dictionary = _charge[id]
			var wn2 = v.weapon_nodes.get("R")
			var at: Vector3 = v.global_position + Vector3(0, 1.6, 0)
			if wn2 is Node3D and is_instance_valid(wn2):
				at = (wn2 as Node3D).global_transform * Vector3(-0.4, 1.05, 0.0)
			for k in ["flames", "smoke", "light"]:
				(ch[k] as Node3D).global_position = at
			var l := ch.light as OmniLight3D
			l.light_energy = 1.6 + 0.6 * sin(Time.get_ticks_msec() * 0.012)
	for id in _blind:
		var bv: UnitView = fx._view_of(id)
		if bv:
			(_blind[id] as Node3D).global_position = bv.global_position + Vector3(0, bv.bar_height * 0.85, 0)
	for id in _wings.keys():
		if not _update_wings(id, dt, w):
			_wings.erase(id)

# ---- Presence ------------------------------------------------------------------------------------------------------

func _make_aura(id: int) -> Dictionary:
	var hem := FireFx.flames(0.0, 0.3, 40.0, 0.55, 0.6, "soul", 0.6)
	var hm := hem.process_material as ParticleProcessMaterial
	hm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	hm.emission_ring_axis = Vector3.UP
	hm.emission_ring_radius = 0.24
	hm.emission_ring_inner_radius = 0.05
	hm.emission_ring_height = 0.35
	hm.gravity = Vector3(0, 0.5, 0)
	add_child(hem)
	var motes := FireFx.embers(0.45, 9.0, 1.8, 0.5, 0.035, SOUL)
	add_child(motes)
	var l := FireFx.light(Color(0.78, 0.86, 1.0), 0.9, 4.5)
	add_child(l)
	var out := {"hem": hem, "motes": motes, "light": l}
	# white wisps along the scythe blade (follows the weapon's transform every frame)
	var v: UnitView = fx._view_of(id)
	if v and v.weapon_nodes.has("R"):
		var bn := Node3D.new()
		add_child(bn)
		var wisp := FireFx.flames(0.0, 0.18, 26.0, 0.45, 0.35, "soul", 1.2)
		var wm := wisp.process_material as ParticleProcessMaterial
		wm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		wm.emission_box_extents = Vector3(0.38, 0.22, 0.02)
		wisp.position = Vector3(-0.42, 1.08, 0.0)
		bn.add_child(wisp)
		out["blade"] = bn
	# red eyes: two tiny glowing sprites on her head bone
	if v and v.skeleton:
		var hb := v.skeleton.find_bone("head")
		if hb >= 0:
			var at := BoneAttachment3D.new()
			at.bone_name = "head"
			v.skeleton.add_child(at)
			var rest := v.skeleton.get_bone_global_rest(hb)
			var eyes: Array = []
			for sx in [-1.0, 1.0]:
				var e := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(0.055, 0.055)
				e.mesh = q
				e.material_override = _eye_material()
				e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				at.add_child(e)
				e.transform = Transform3D(Basis(), rest.affine_inverse() * Vector3(EYE_SKEL.x * sx, EYE_SKEL.y, EYE_SKEL.z + 0.012))
				eyes.append(e)
			out["eye_root"] = at
	return out

static func _eye_material() -> StandardMaterial3D:
	if _eye_mat == null:
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_eye_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_eye_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_eye_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_eye_mat.no_depth_test = false
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		gr.colors = PackedColorArray([Color(1.0, 0.85, 0.8, 1.0), Color(1.0, 0.1, 0.08, 0.9), Color(0.6, 0.0, 0.0, 0.0)])
		g.gradient = gr
		g.width = 32
		g.height = 32
		_eye_mat.albedo_texture = g
		_eye_mat.albedo_color = Color(3.0, 1.2, 1.2)
	return _eye_mat

func _free_aura(id: int) -> void:
	var a: Dictionary = _aura[id]
	for k in ["hem", "motes", "light"]:
		fire.timed(a[k], 0.0)
	if a.has("blade") and is_instance_valid(a.blade):
		fire.timed(a.blade, 0.0)
	if a.has("eye_root") and is_instance_valid(a.eye_root):
		(a.eye_root as Node).queue_free()
	_aura.erase(id)

# ---- Soul Tap ------------------------------------------------------------------------------------------------------

func _soul_tap(e: Dictionary) -> void:
	var p: Vector2 = e.pos
	var u: SimUnit = game.world.get_unit(int(e.u))
	if not fx._seen(p) and (u == null or not fx._seen(u.pos)):
		return
	var r := float(e.radius) * View.S
	fx.shockwave(fx.ground3(p, 0.05), r * 1.1, Color(0.7, 0.02, 0.06), 0.55, 0.12, 2.2)
	fx.edge_ring(fx.ground3(p, 0.06), r, Color(0.9, 0.1, 0.12), 0.9)
	var vortex := FireFx.flames(r * 0.8, 0.35, 50.0, 0.5, 1.2, "blood", 1.2)
	var vm := vortex.process_material as ParticleProcessMaterial
	vm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	vm.emission_ring_axis = Vector3.UP
	vm.emission_ring_radius = r
	vm.emission_ring_inner_radius = r * 0.7
	vm.emission_ring_height = 0.1
	vm.radial_accel_min = -6.0
	vm.radial_accel_max = -3.0
	add_child(vortex)
	vortex.global_position = fx.ground3(p, 0.1)
	fire.timed(vortex, 0.4)
	for id in e.souls:
		var from := fx._chest(int(id), 0.6)
		var wisp := FireFx.fireball(0.45, "soul")
		add_child(wisp)
		wisp.global_position = from
		_flyers.append({"node": wisp, "from": from, "to_id": int(e.u), "t": 0.0, "dur": 0.45 + randf() * 0.25,
			"arc": 0.8 + randf() * 0.6})

func _make_charge() -> Dictionary:
	var f := FireFx.flames(0.12, 0.3, 40.0, 0.4, 0.8, "blood", 1.5)
	var fm := f.process_material as ParticleProcessMaterial
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	fm.emission_box_extents = Vector3(0.3, 0.2, 0.05)
	add_child(f)
	var s := FireFx.smoke(0.15, 10.0, 0.45, 0.9, 0.5, 0.5)
	add_child(s)
	var l := FireFx.light(RED, 1.8, 3.5)
	add_child(l)
	return {"flames": f, "smoke": s, "light": l}

func _update_flyers(dt: float) -> void:
	for i in range(_flyers.size() - 1, -1, -1):
		var f: Dictionary = _flyers[i]
		f.t = float(f.t) + dt
		var k := clampf(float(f.t) / float(f.dur), 0.0, 1.0)
		var to := fx._chest(int(f.to_id), 0.6)
		var ease := k * k * (3.0 - 2.0 * k)
		var pos := (f.from as Vector3).lerp(to, ease) + Vector3(0, sin(k * PI) * float(f.arc), 0)
		if is_instance_valid(f.node):
			(f.node as Node3D).global_position = pos
		if k >= 1.0:
			if is_instance_valid(f.node):
				fire.timed(f.node, 0.0)
			fire.burst(to, 0.2, "soul", 0.25)
			_flyers.remove_at(i)

# ---- Slashes -------------------------------------------------------------------------------------------------------

const SLASH_CODE := """
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float progress = 0.0;          // 0..1.3: the leading edge sweeps across, the tail fades behind it
uniform vec4 edge_col : source_color = vec4(0.95, 0.08, 0.1, 1.0);
uniform vec4 core_col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float hot = 1.0;               // the white-hot leading edge
uniform float dark = 0.85;             // how much the black core darkens what is behind it
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	float a = UV.x;                     // along the sweep
	float r = UV.y;                     // 0 inner rim .. 1 outer rim
	float lead = progress - a;          // >0 behind the leading edge
	if (lead < 0.0) { discard; }
	float tail = clamp(1.0 - lead / 0.55, 0.0, 1.0);
	// thick in the middle of the sweep, thin at both ends: a crescent
	float thick = sin(clamp(a, 0.0, 1.0) * 3.14159);
	float band = smoothstep(0.5 - 0.5 * thick, 0.5 - 0.35 * thick, r) * (1.0 - smoothstep(0.5 + 0.35 * thick, 0.5 + 0.5 * thick, r));
	float n = vnoise(vec2(a * 18.0 - TIME * 3.0, r * 6.0));
	band *= 0.75 + 0.5 * n;
	float outer = smoothstep(0.55, 0.9, r) * band;       // the cutting edge on the outside of the arc
	float leading = exp(-lead * 30.0) * hot;
	vec3 glow = edge_col.rgb * (outer * 2.4 + band * 0.6) + vec3(1.0, 0.9, 0.85) * leading * band * 2.0;
	float alpha = clamp(band * dark * (1.0 - outer * 0.5), 0.0, 1.0) * tail;
	ALBEDO = (core_col.rgb * alpha + glow * tail);
	ALPHA = alpha;
}
"""

## A crescent ribbon (annulus sector) lying in the XZ plane round the origin, swept from angle a0 to a1.
static func _arc_mesh(r0: float, r1: float, a0: float, a1: float, segs := 28) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var b0 := lerpf(a0, a1, t0)
		var b1 := lerpf(a0, a1, t1)
		var p00 := Vector3(cos(b0) * r0, 0, sin(b0) * r0)
		var p01 := Vector3(cos(b0) * r1, 0, sin(b0) * r1)
		var p10 := Vector3(cos(b1) * r0, 0, sin(b1) * r0)
		var p11 := Vector3(cos(b1) * r1, 0, sin(b1) * r1)
		for q in [[p00, Vector2(t0, 0)], [p01, Vector2(t0, 1)], [p11, Vector2(t1, 1)], [p00, Vector2(t0, 0)],
				[p11, Vector2(t1, 1)], [p10, Vector2(t1, 0)]]:
			st.set_uv(q[1])
			st.add_vertex(q[0])
	return st.commit()

func _slash(at: Vector3, yaw: float, r0: float, r1: float, span: float, tilt: float, edge: Color, core: Color, dur: float,
		dark := 0.85) -> void:
	if _slash_shader == null:
		_slash_shader = Shader.new()
		_slash_shader.code = SLASH_CODE
	var mi := MeshInstance3D.new()
	mi.mesh = _arc_mesh(r0, r1, -span * 0.5, span * 0.5)
	var m := ShaderMaterial.new()
	m.shader = _slash_shader
	m.set_shader_parameter("edge_col", edge)
	m.set_shader_parameter("core_col", core)
	m.set_shader_parameter("dark", dark)
	m.render_priority = 6
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	mi.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	_slashes.append({"node": mi, "mat": m, "t": 0.0, "dur": dur})

func _update_slashes(dt: float) -> void:
	for i in range(_slashes.size() - 1, -1, -1):
		var s: Dictionary = _slashes[i]
		s.t = float(s.t) + dt
		var k := float(s.t) / float(s.dur)
		(s.mat as ShaderMaterial).set_shader_parameter("progress", k * 1.6)
		if k >= 1.0:
			(s.node as Node).queue_free()
			_slashes.remove_at(i)

func _soul_slash(e: Dictionary) -> void:
	var u: SimUnit = game.world.get_unit(int(e.u))
	var t: SimUnit = game.world.get_unit(int(e.target))
	if u == null or not fx._seen(u.pos):
		return
	var dir: Vector2 = e.dir
	var origin := fx.ground3(u.pos, 1.05)
	# the sweep: its middle points at the target, from her right to her left, tilted like a diagonal stroke
	var yaw := atan2(-dir.x, -dir.y) + PI * 0.5
	var reach := clampf(float(e.dist) * View.S * 0.55, 2.2, 3.8)
	_slash(origin, -atan2(-dir.y, dir.x) + 0.0, 0.5, reach, deg_to_rad(150.0), deg_to_rad(-14.0), RED, Color.BLACK, 0.42)
	_slash(origin + Vector3(0, 0.25, 0), -atan2(-dir.y, dir.x), 0.9, reach * 0.8, deg_to_rad(120.0), deg_to_rad(10.0),
		Color(1.0, 0.25, 0.2), Color(0.05, 0.0, 0.0), 0.36, 0.5)
	var hit := fx._chest(t.id, 0.5) if t else origin + Vector3(dir.x, 0, -dir.y) * 1.5
	fire.burst(hit, 0.6, "blood", 1.1)
	fx.sparks(hit, Vector3(dir.x, 0.4, -dir.y), 18, Color(1.0, 0.3, 0.25), 7.0)
	fx.flash_light(hit, RED, 6.0, 7.0, 0.3)
	var smoke := FireFx.smoke(0.4, 30.0, 1.0, 1.0, 0.8, 0.6)
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	add_child(smoke)
	smoke.global_position = hit
	smoke.emitting = true
	fire.timed(smoke, 0.2)
	for id in e.hits:
		fire.burst(fx._chest(int(id), 0.5), 0.3, "blood", 0.6)
	fx._shake(u.pos, 0.35, 0.25)
	if yaw == INF:
		pass

## Her ordinary blow: a thin white crescent sweeping through the target (the charged slash and Death Scythe have their
## own, bigger ones).
func scythe_hit(u: SimUnit, t: SimUnit) -> void:
	if not fx._seen(t.pos):
		return
	var d := (t.pos - u.pos)
	d = d.normalized() if d.length() > 1.0 else Vector2.from_angle(u.facing)
	_slash(fx.ground3(u.pos, 1.1), -atan2(-d.y, d.x), 0.7, 2.0, deg_to_rad(120.0), deg_to_rad(-10.0 + randf() * 20.0),
		Color(0.8, 0.86, 1.0), Color(0.02, 0.02, 0.04), 0.24, 0.35)

func _death_scythe(e: Dictionary) -> void:
	var t: SimUnit = game.world.get_unit(int(e.target))
	var u: SimUnit = game.world.get_unit(int(e.u))
	if t == null or u == null or not fx._seen(t.pos):
		return
	var c := fx._chest(t.id, 0.55)
	var d := (t.pos - u.pos).normalized()
	_slash(c + Vector3(0, -0.1, 0), -atan2(-d.y, d.x) + PI * 0.5, 0.25, 1.25, deg_to_rad(110.0), deg_to_rad(62.0),
		Color(0.85, 0.9, 1.0), Color(0.02, 0.02, 0.05), 0.28, 0.6)
	fx.sparks(c, Vector3(0, 1, 0), 10, Color(0.9, 0.95, 1.0), 5.0)
	fx.flash_light(c, Color(0.85, 0.9, 1.0), 4.0, 4.0, 0.2)

# ---- Door of the End -----------------------------------------------------------------------------------------------

const DOOR_CODE := """
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float rise = 1.0;              // 0..1: the door grows out of the ground
uniform float fade = 1.0;
uniform vec4 vein : source_color = vec4(0.95, 0.1, 0.12, 1.0);
uniform vec4 rim : source_color = vec4(0.9, 0.95, 1.0, 1.0);
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.1) * 0.3 + vnoise(p * 4.3 - 1.7) * 0.15;
}
void vertex() {
	// stands upright and turns about its own vertical axis to face the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	// an arch: a rectangle below, a half circle on top (UV: x across, y down)
	vec2 p = vec2(UV.x * 2.0 - 1.0, (1.0 - UV.y) * 2.6);
	float half_w = 0.78;
	float d_rect = max(abs(p.x) - half_w, -p.y);
	float top = 2.6 - half_w;
	float d_arch = p.y > top ? length(vec2(p.x, p.y - top)) - half_w : d_rect;
	float d = p.y > top ? d_arch : max(abs(p.x) - half_w, -p.y);
	float risen = step(p.y, rise * 2.7);
	// the swirl inside: white soul light turning round the middle, red veins through it
	vec2 c = vec2(p.x, p.y - 1.25);
	float ang = atan(c.y, c.x);
	float rad = length(c);
	vec2 sw = vec2(ang * 1.6 + TIME * 1.4 + rad * 2.5, rad * 3.0 - TIME * 0.8);
	float n = fbm(sw * 1.4);
	float veins = smoothstep(0.62, 0.7, fbm(sw * 2.2 + 7.0)) * (1.0 - smoothstep(0.7, 0.85, fbm(sw * 2.2 + 7.0)));
	float inside = 1.0 - smoothstep(-0.08, 0.0, d);
	float core = (0.35 + 0.65 * n) * inside;
	float edge = exp(-abs(d) * 18.0);
	float outer = (1.0 - smoothstep(0.0, 0.35, d)) * smoothstep(0.0, 0.02, d) * (0.4 + 0.6 * fbm(p * 3.0 + TIME));
	// a dark void inside the frame, white soul light streaming round it in bright threads, red veins, a hard white rim
	float streak = pow(clamp(n, 0.0, 1.0), 3.5) * 2.6;
	vec3 col = vec3(0.86, 0.92, 1.0) * streak * inside + vein.rgb * veins * inside * 2.4 + rim.rgb * edge * 3.0;
	col += vec3(0.05, 0.06, 0.1) * core;
	float alpha = clamp(inside * 0.9 + outer * 0.55, 0.0, 1.0);
	float a = risen * fade;
	ALBEDO = col * a;
	ALPHA = alpha * a * 0.75;
}
"""

func _door_node(red: bool) -> Node3D:
	if _door_shader == null:
		_door_shader = Shader.new()
		_door_shader.code = DOOR_CODE
	var root := Node3D.new()
	add_child(root)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.7, 2.9)
	q.center_offset = Vector3(0, 1.45, 0)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _door_shader
	m.set_shader_parameter("rise", 0.0)
	if red:
		m.set_shader_parameter("vein", Color(1.0, 0.2, 0.2))
		m.set_shader_parameter("rim", Color(1.0, 0.45, 0.4))
	m.render_priority = 4
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 3.0
	root.add_child(mi)
	var base := FireFx.flames(0.0, 0.4, 36.0, 0.6, 0.9, "soul", 1.0)
	var bm := base.process_material as ParticleProcessMaterial
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	bm.emission_ring_axis = Vector3.UP
	bm.emission_ring_radius = 0.95
	bm.emission_ring_inner_radius = 0.6
	bm.emission_ring_height = 0.05
	root.add_child(base)
	var pull := FireFx.embers(1.4, 18.0, 1.0, 0.4, 0.04, Color(1.0, 0.3, 0.3) if red else SOUL)
	var pm := pull.process_material as ParticleProcessMaterial
	pm.radial_accel_min = -3.0
	pm.radial_accel_max = -1.5
	pull.position = Vector3(0, 1.3, 0)
	root.add_child(pull)
	var l := FireFx.light(Color(1.0, 0.5, 0.5) if red else Color(0.8, 0.88, 1.0), 1.4, 5.0)
	l.position = Vector3(0, 1.5, 0.3)
	root.add_child(l)
	root.set_meta("mat", m)
	return root

func _door(e: Dictionary, exit: bool) -> void:
	var seq := int(e.seq)
	var p: Vector2 = e.pos
	var d: Dictionary = _doors.get(seq, {})
	var node := _door_node(exit)
	node.global_position = fx.ground3(p, 0.02)
	node.visible = int(e.get("team", game.player_team)) == game.player_team or fx._seen(p)
	if node.visible:
		fx.shockwave(fx.ground3(p, 0.05), 1.6, Color(0.85, 0.9, 1.0) if not exit else Color(1.0, 0.3, 0.3), 0.5, 0.15, 2.0)
		fire.burst(fx.ground3(p, 0.3), 0.5, "soul", 0.6)
	d[("exit" if exit else "entrance")] = {"node": node, "pos": p, "born": Time.get_ticks_msec() / 1000.0}
	if e.has("until"):
		d["until"] = float(e.until)
	elif e.has("dur"):
		d["until"] = game.world.time + float(e.dur)
	_doors[seq] = d

func _update_doors(w: SimWorld) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for seq in _doors.keys():
		var d: Dictionary = _doors[seq]
		var left := float(d.get("until", w.time + 1.0)) - w.time
		var gone := true
		for k in ["entrance", "exit"]:
			if not d.has(k):
				continue
			var it: Dictionary = d[k]
			var n: Node3D = it.node
			if not is_instance_valid(n):
				continue
			var m: ShaderMaterial = n.get_meta("mat")
			var age := now - float(it.born)
			m.set_shader_parameter("rise", clampf(age / 0.5, 0.0, 1.0))
			var fade := clampf((left + 0.35) / 0.35, 0.0, 1.0)
			m.set_shader_parameter("fade", fade)
			n.visible = n.visible or fx._seen(it.pos)
			if left < -0.4:
				fire.timed(n, 0.0)
				d.erase(k)
			else:
				gone = false
		if gone:
			_doors.erase(seq)

func _door_blast(e: Dictionary) -> void:
	var p: Vector2 = e.pos
	if not fx._seen(p):
		return
	var r := float(e.radius) * View.S
	var c := fx.ground3(p, 0.05)
	fx.shockwave(c, r, Color(0.88, 0.94, 1.0), 0.6, 0.22, 3.0)
	fx.shockwave(c, r * 0.7, Color(0.95, 0.1, 0.12), 0.45, 0.15, 2.5)
	fire.burst(fx.ground3(p, 0.6), r * 0.6, "soul", 1.6)
	fire.burst(fx.ground3(p, 0.3), r * 0.35, "blood", 0.9)
	var col := FireFx.flames(0.6, 0.9, 120.0, 0.7, 4.0, "soul", 1.6)
	col.one_shot = true
	col.explosiveness = 0.9
	add_child(col)
	col.global_position = fx.ground3(p, 0.2)
	col.emitting = true
	fire.timed(col, 0.2)
	fx.crack(c, r * 0.8, Color(0.85, 0.9, 1.0), 2.5)
	fx.flash_light(fx.ground3(p, 1.5), Color(0.9, 0.95, 1.0), 8.0, 10.0, 0.5)
	for id in e.hits:
		fire.burst(fx._chest(int(id), 0.5), 0.35, "soul", 0.5)
	fx._shake(p, 0.6, 0.4)

# ---- Divine Darkness: wings and the pool of darkness ---------------------------------------------------------------

const POOL_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float fade = 1.0;
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float n = vnoise(vec2(a * 3.0 + TIME * 0.4, r * 5.0 - TIME * 0.6)) * 0.6 + vnoise(p * 7.0 + TIME * 0.3) * 0.4;
	float disc = 1.0 - smoothstep(0.55, 1.0, r + (n - 0.5) * 0.25);
	ALBEDO = vec3(0.015, 0.0, 0.025);
	ALPHA = disc * (0.5 + 0.22 * n) * fade;
}
"""

const WING_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
uniform float glow = 0.3;
uniform float fade = 1.0;
void fragment() {
	// soft white feathers: grey-blue at the roots, white at the tips, a little light through them and on the edges
	vec3 c = COLOR.rgb;
	ALBEDO = c * vec3(0.78, 0.8, 0.86);
	ROUGHNESS = 0.85;
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	EMISSION = vec3(0.86, 0.92, 1.0) * (glow * (0.2 + 0.8 * rim)) * c * c;
	BACKLIGHT = vec3(0.35, 0.38, 0.45);
	if (fade < 0.999) {
		// folding away: the feathers dissolve from the tips
		float h = fract(sin(dot(floor(VERTEX.xz * 40.0), vec2(12.9898, 78.233))) * 43758.5453);
		if (h > fade) { discard; }
	}
}
"""

func _make_wings(id: int) -> Dictionary:
	var v: UnitView = fx._view_of(id)
	var out := {"t": 0.0, "folding": false, "root": null, "parts": {}, "pool": null, "motes": null, "id": id}
	if v == null or v.skeleton == null or not ResourceLoader.exists(WINGS):
		return out
	var ps := load(WINGS) as PackedScene
	var wing := ps.instantiate() as Node3D
	var ci := v.skeleton.find_bone("chest")
	var at := BoneAttachment3D.new()
	at.bone_name = "chest"
	v.skeleton.add_child(at)
	at.add_child(wing)
	var rest := v.skeleton.get_bone_global_rest(ci)
	wing.transform = rest.affine_inverse() * Transform3D(Basis(), WING_SKEL)
	if _wing_shader == null:
		_wing_shader = Shader.new()
		_wing_shader.code = WING_CODE
	var wm := ShaderMaterial.new()
	wm.shader = _wing_shader
	var parts := {}
	for mi: MeshInstance3D in wing.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = wm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for n: Node3D in wing.find_children("wing_*", "Node3D", true, false):
		parts[String(n.name)] = n
	out.root = at
	out.parts = parts
	out["mat"] = wm
	if _pool_shader == null:
		_pool_shader = Shader.new()
		_pool_shader.code = POOL_CODE
	var pool := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(14.0, 14.0)
	q.orientation = PlaneMesh.FACE_Y
	pool.mesh = q
	var pm := ShaderMaterial.new()
	pm.shader = _pool_shader
	pm.render_priority = 2
	pool.material_override = pm
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	out.pool = pool
	out["pool_mat"] = pm
	var motes := FireFx.embers(0.9, 10.0, 2.2, -0.2, 0.05, Color(0.95, 0.97, 1.0))
	(motes.process_material as ParticleProcessMaterial).gravity = Vector3(0, -0.6, 0)
	add_child(motes)
	out.motes = motes
	return out

## Spread (0 folded .. 1 open) and a slow beat; folding away at the end. False when the wings are gone.
func _update_wings(id: int, dt: float, w: SimWorld) -> bool:
	var d: Dictionary = _wings[id]
	if d.root == null:
		return not bool(d.folding)
	d.t = float(d.t) + dt
	var v: UnitView = fx._view_of(id)
	var open: float
	if bool(d.folding):
		open = 1.0 - clampf(float(d.t) / 0.6, 0.0, 1.0)
	else:
		var k := clampf(float(d.t) / 0.45, 0.0, 1.0)
		open = 1.0 - pow(1.0 - k, 3.0) + sin(k * PI) * 0.12          # a little overshoot as they burst open
	var beat := sin(Time.get_ticks_msec() * 0.001 * TAU * 0.75) * open
	var parts: Dictionary = d.parts
	for side in ["r", "l"]:
		var sgn := 1.0 if side == "r" else -1.0
		var arm: Node3D = parts.get("wing_%s_arm" % side)
		var fore: Node3D = parts.get("wing_%s_fore" % side)
		var hand: Node3D = parts.get("wing_%s_hand" % side)
		if arm == null:
			continue
		# folded: swept back along the body; open: raised to the side, beating
		var fold_back := (1.0 - open) * deg_to_rad(80.0)
		arm.rotation = Vector3(0.0, sgn * fold_back, sgn * (deg_to_rad(18.0) * open + deg_to_rad(14.0) * beat))
		if fore:
			fore.rotation = Vector3(0.0, sgn * (1.0 - open) * deg_to_rad(70.0), sgn * deg_to_rad(6.0) * beat)
		if hand:
			hand.rotation = Vector3(0.0, sgn * (1.0 - open) * deg_to_rad(60.0), sgn * deg_to_rad(-10.0) * beat)
	var m: ShaderMaterial = d.get("mat")
	if m:
		m.set_shader_parameter("fade", clampf(open * 1.3, 0.0, 1.0) if bool(d.folding) else 1.0)
	var pmat: ShaderMaterial = d.get("pool_mat")
	if v and d.pool:
		(d.pool as Node3D).global_position = Vector3(v.global_position.x, v.global_position.y + 0.05, v.global_position.z)
		pmat.set_shader_parameter("fade", clampf(open, 0.0, 1.0))
	if v and d.motes:
		(d.motes as Node3D).global_position = v.global_position + Vector3(0, 1.9, 0)
	if bool(d.folding) and float(d.t) >= 0.65:
		if is_instance_valid(d.root):
			(d.root as Node).queue_free()
		if d.pool:
			(d.pool as Node).queue_free()
		if d.motes:
			fire.timed(d.motes, 0.0)
		return false
	if w == null:
		return true
	return true

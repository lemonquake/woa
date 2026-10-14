class_name FrosterFx
extends Node
## Froster's cold, drawn with GPU particles and ice:
##   * his presence: snow drifting round him, cold mist at his feet, a pale glow on his staff;
##   * his attacks: frost bolts (an icy core in a trail of glittering vapour) that burst in ice shards;
##   * Breath of Cold: a widening cone of freezing vapour rolling out to 800, frost left on the ground;
##   * Ice Pulse: a ring of ice shards circling the cursed unit over a closing timer ring, then a blast of ice;
##   * Frost Heart: small glowing ice hearts circling his chest (one per heart); an attack that spends one bursts in ice;
##   * Endless Winter: a blizzard over the whole area (falling and whirling snow, a frost disc on the ground, a vortex
##     over Froster, a cold light) with a wave of cold every second;
##   * Frosted: the unit frozen inside a block of ice, which shatters when the stun ends;
##   * Chilled: anything slowed by his cold carries frost vapour at its feet.
## Built from simulation events and the units' modifiers every frame, so nothing outlives what it shows.
## Units: metres (1 game unit = 1 cm).

const EVENTS := ["breath_cast", "breath_move", "breath_hit", "ice_pulse_cast", "ice_pulse_blast", "frost_heart_gain",
	"frost_heart_hit", "winter_pulse", "frosted"]
const ICE := Color(0.62, 0.86, 1.0)
const ICE_HOT := Color(0.85, 0.96, 1.0)
const DEEP := Color(0.18, 0.42, 0.85)

var game: Node
var fx: Fx
var fire: FireFx
var _aura := {}                            # Froster's view id -> {snow, mist, glow, light}
var _hearts := {}                          # Froster's id -> Array of Node3D (orbiting hearts)
var _cones := {}                           # seq -> {node, origin, dir, emit}
var _curses := {}                          # unit id -> {node, ring_mat, until, total}
var _winters := {}                         # Froster's id -> Node3D (blizzard)
var _blocks := {}                          # unit id -> Node3D (ice block)
var _chill := {}                           # unit id -> GPUParticles3D
var _shards: Array = []                    # flying ice shards: {node, vel, life, t, spin}
var _scan_i := 0

# ---- Materials and emitters -------------------------------------------------------------------------------------------

const MIST_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float density = 0.5;
varying vec4 pcol;
varying float age;
varying float seed;
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
void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	pcol = COLOR;
	age = INSTANCE_CUSTOM.y;
	seed = fract(sin(float(INSTANCE_ID) * 9.17 + 2.3) * 43758.5453);
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float t = mod(TIME, 600.0);
	float n = vnoise(q * 2.4 + vec2(seed * 11.0, -t * 0.5)) * 0.6 + vnoise(q * 5.1 - vec2(t * 0.35, seed * 5.0)) * 0.4;
	float puff = 1.0 - smoothstep(0.15, 1.0, length(q) + (n - 0.5) * 0.6);
	float a = puff * smoothstep(0.0, 0.15, age) * (1.0 - smoothstep(0.4, 1.0, age));
	ALBEDO = mix(pcol.rgb * 0.85, vec3(1.0), n * 0.35) * (1.0 + 0.4 * n);
	ALPHA = clamp(a * density * pcol.a, 0.0, 1.0);
}
"""

const ICE_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(0.62, 0.86, 1.0, 1.0);
uniform float alpha = 0.72;
uniform float glow = 1.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = tint.rgb * 0.45;
	ROUGHNESS = 0.06;
	SPECULAR = 0.95;
	EMISSION = tint.rgb * (0.18 + f * 1.8) * glow;
	ALPHA = clamp(alpha + f * 0.3, 0.0, 1.0);
}
"""

const FROST_GROUND_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float fade = 1.0;
uniform float reach = 1.0;
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
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float ang = atan(q.y, q.x);
	float n = vnoise(q * 6.0) * 0.6 + vnoise(q * 17.0) * 0.4;
	// frost feathers radiating from the centre
	float feather = vnoise(vec2(ang * 9.0, r * 2.5)) * 0.6 + vnoise(vec2(ang * 23.0, r * 6.0)) * 0.4;
	float veins = smoothstep(0.58, 0.85, feather) * (0.4 + 0.6 * n);
	float edge = 1.0 - smoothstep(reach - 0.3 - n * 0.2, reach, r);
	vec3 col = mix(vec3(0.72, 0.86, 0.96), vec3(1.0), veins + n * 0.2);
	ALBEDO = col;
	ALPHA = clamp(edge * (0.16 + veins * 0.42 + n * 0.08) * fade, 0.0, 1.0);
}
"""

const FAN_CODE := """
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float progress = 0.0;
uniform float fade = 1.0;
uniform float ground = 0.0;
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
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}
void fragment() {
	// UV.x runs from Froster out to the reach, UV.y across the cone
	float t = mod(TIME, 600.0);
	float across = abs(UV.y - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.55, 1.0, across);
	vec3 col;
	float a;
	if (ground > 0.5) {
		// frost on the ground: crystalline veins in a pale bloom, reaching as far as the cold went
		// frost feathers: streaks running outwards from Froster, broken up by a coarser noise
		float n = fbm(vec2(UV.x * 7.0, UV.y * 5.0));
		float feather = fbm(vec2(UV.x * 2.5, UV.y * 38.0));
		float streak = smoothstep(0.55, 0.85, feather) * (0.5 + 0.5 * n);
		float reach = 1.0 - smoothstep(progress - 0.25, progress, UV.x + (n - 0.5) * 0.15);
		float soft = (1.0 - smoothstep(0.25, 1.0, across)) * smoothstep(0.0, 0.12, UV.x);
		a = soft * reach * (0.1 + streak * 0.42 + n * 0.1) * fade;
		col = mix(vec3(0.74, 0.87, 1.0), vec3(1.0), streak);
	} else {
		// the breath: streaks of freezing vapour rushing outwards, thickest just behind the front
		float n = fbm(vec2(UV.x * 5.0 - t * 4.5, UV.y * 3.5 + t * 0.4));
		float n2 = fbm(vec2(UV.x * 11.0 - t * 7.0, UV.y * 8.0));
		float front = smoothstep(progress, progress - 0.12, UV.x);
		float wake = 0.35 + 0.65 * smoothstep(progress - 0.55, progress - 0.05, UV.x);
		a = front * wake * edge * smoothstep(0.0, 0.08, UV.x) * clamp(n * 1.3 + n2 * 0.4 - 0.15, 0.0, 1.0) * fade;
		col = mix(vec3(0.55, 0.8, 1.0), vec3(1.0), n2 * 0.7 + 0.2);
	}
	ALBEDO = col * a * 1.25;
	ALPHA = clamp(a * 0.9, 0.0, 1.0);
}
"""

static var _fan_shader: Shader

## A flat fan (a slice of a disc) from radius r0 to r1 over `angle` radians, lying on XZ and pointing along +Z.
static func fan_mesh(angle: float, r0: float, r1: float, segs := 24, rings := 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings:
		for i in segs:
			var corners := []
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var u := float(c[1]) / rings
				var v := float(c[0]) / segs
				var r := lerpf(r0, r1, u)
				var a := (v - 0.5) * angle
				corners.append([Vector3(sin(a) * r, 0.0, cos(a) * r), Vector2(u, v)])
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv(corners[k][1])
				st.set_normal(Vector3.UP)
				st.add_vertex(corners[k][0])
	return st.commit()

static func fan_material(on_ground: bool) -> ShaderMaterial:
	if _fan_shader == null:
		_fan_shader = Shader.new()
		_fan_shader.code = FAN_CODE
	var m := ShaderMaterial.new()
	m.shader = _fan_shader
	m.set_shader_parameter("ground", 1.0 if on_ground else 0.0)
	m.render_priority = 3 if on_ground else 6
	return m

static var _mist_shader: Shader
static var _ice_shader: Shader
static var _ground_shader: Shader
static var _shard_meshes: Array = []
static var _ice_mat: ShaderMaterial
static var _ice_mat_bright: ShaderMaterial

static func _init_static() -> void:
	if _mist_shader != null:
		return
	_mist_shader = Shader.new()
	_mist_shader.code = MIST_CODE
	_ice_shader = Shader.new()
	_ice_shader.code = ICE_CODE
	_ground_shader = Shader.new()
	_ground_shader.code = FROST_GROUND_CODE
	_ice_mat = ShaderMaterial.new()
	_ice_mat.shader = _ice_shader
	_ice_mat_bright = ShaderMaterial.new()
	_ice_mat_bright.shader = _ice_shader
	_ice_mat_bright.set_shader_parameter("glow", 2.4)
	_ice_mat_bright.set_shader_parameter("tint", ICE_HOT)
	for k in 3:
		_shard_meshes.append(_shard(k))

## An ice shard: a long irregular double pyramid.
static func _shard(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	var sides := 5 + variant % 2
	var top := Vector3(rng.randf_range(-0.05, 0.05), 1.0, rng.randf_range(-0.05, 0.05))
	var bot := Vector3(0, -0.35, 0)
	var ring: Array = []
	for i in sides:
		var a := TAU * i / sides + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(0.16, 0.24)
		ring.append(Vector3(cos(a) * r, rng.randf_range(-0.05, 0.08), sin(a) * r))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sides:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % sides]
		for tri in [[top, b, a], [bot, a, b]]:
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for v in tri:
				st.set_normal(n)
				st.add_vertex(v)
	return st.commit()

static func ice_material(bright := false) -> ShaderMaterial:
	_init_static()
	return _ice_mat_bright if bright else _ice_mat

## Cold vapour: soft pale puffs drifting from a disc (`radius` m).
static func mist(radius: float, rate: float, size := 0.8, life := 1.6, rise := 0.3, density := 0.45,
		col := Color(0.8, 0.92, 1.0)) -> GPUParticles3D:
	_init_static()
	var p := GPUParticles3D.new()
	p.amount = maxi(4, int(rate * life))
	p.lifetime = life
	p.local_coords = false
	p.randomness = 0.6
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = maxf(radius, 0.05)
	m.direction = Vector3.UP
	m.spread = 60.0
	m.initial_velocity_min = rise * 0.3
	m.initial_velocity_max = rise
	m.gravity = Vector3.ZERO
	m.damping_min = 0.2
	m.damping_max = 0.6
	m.scale_min = size * 0.6
	m.scale_max = size
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(1.0, 1.5))
	var ct := CurveTexture.new()
	ct.curve = c
	m.scale_curve = ct
	m.color = col
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.8
	m.turbulence_influence_min = 0.04
	m.turbulence_influence_max = 0.1
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = _mist_shader
	mat.set_shader_parameter("density", density)
	q.material = mat
	p.draw_pass_1 = q
	return p

## Glittering ice dust (bright additive specks).
static func glitter(radius: float, rate: float, life := 1.0, rise := 0.6, size := 0.045) -> GPUParticles3D:
	return FireFx.embers(radius, rate, life, rise, size, Color(0.55, 0.85, 1.0))

## Snow: flakes falling and swirling over a disc of `radius` m from `height` m up.
static func snow(radius: float, height: float, rate: float, life := 2.4, wind := 0.0) -> GPUParticles3D:
	FireFx._init_static()
	var p := GPUParticles3D.new()
	p.amount = maxi(8, int(rate * life))
	p.lifetime = life
	p.local_coords = false
	p.randomness = 0.7
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-radius - 2, -2, -radius - 2), Vector3(radius * 2 + 4, height + 4, radius * 2 + 4))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(radius, 0.2, radius)
	m.direction = Vector3.DOWN
	m.spread = 25.0
	m.initial_velocity_min = height / life * 0.6
	m.initial_velocity_max = height / life * 1.1
	m.gravity = Vector3(0, -0.6, 0)
	m.scale_min = 0.03
	m.scale_max = 0.07
	if wind > 0.0:
		m.orbit_velocity_min = wind * 0.6
		m.orbit_velocity_max = wind
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.6
	m.turbulence_influence_min = 0.1
	m.turbulence_influence_max = 0.25
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(0.92, 0.97, 1.0, 1.0), Color(0.8, 0.9, 1.0, 0.9), Color(0.7, 0.85, 1.0, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.draw_pass_1 = FireFx._ember_quad
	p.position.y = height
	return p

static func ground_frost(radius: float) -> MeshInstance3D:
	_init_static()
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _ground_shader
	m.render_priority = 3
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func core(radius: float, energy := 4.0) -> MeshInstance3D:
	return FireFx.core(radius, ICE, energy)

## A frost bolt (Froster's attacks): an icy core, a vapour and glitter trail.
static func bolt(size := 1.0) -> Node3D:
	var n := Node3D.new()
	n.add_child(core(0.13 * size, 5.0))
	var m := mist(0.06 * size, 40.0, 0.32 * size, 0.45, 0.05, 0.55)
	n.add_child(m)
	var g := glitter(0.08 * size, 30.0, 0.5, 0.2, 0.035)
	n.add_child(g)
	_init_static()
	var sh := MeshInstance3D.new()
	sh.mesh = _shard_meshes[0]
	sh.material_override = _ice_mat_bright
	sh.scale = Vector3.ONE * 0.22 * size
	sh.rotation.x = -PI * 0.5
	n.add_child(sh)
	return n

# ---- Events -----------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	match String(e.t):
		"breath_cast":
			_breath_cast(e)
		"breath_move":
			_breath_move(e)
		"breath_hit":
			_chilled_hit(int(e.u))
		"ice_pulse_cast":
			_pulse_cast(e)
		"ice_pulse_blast":
			_pulse_blast(e)
		"frost_heart_gain":
			var v := fx._view_of(int(e.u))
			if v and v.visible:
				burst_shards(fx._chest(int(e.u), 0.6), 5, 0.12, 2.5)
		"frost_heart_hit":
			var tv := fx._view_of(int(e.target))
			if tv and tv.visible:
				var at := fx._chest(int(e.target), 0.5)
				burst_shards(at, 12, 0.22, 5.0)
				_puff(at, 0.8, 0.7)
				fx.flash_light(at, ICE, 3.0, 4.0, 0.25)
		"winter_pulse":
			var p2: Vector2 = e.pos
			if fx._seen(p2):
				fx.shockwave(fx.ground3(p2), float(e.radius) * View.S, Color(0.7, 0.9, 1.0), 0.8, 0.1, 2.0)
		"frosted":
			var fv := fx._view_of(int(e.u))
			if fv and fv.visible:
				burst_shards(fx._chest(int(e.u), 0.5), 8, 0.18, 3.0)

func _breath_cast(e: Dictionary) -> void:
	var from: Vector2 = e.from
	var dir: Vector2 = e.dir
	if not fx._seen(from) and not fx._seen(from + dir * float(e.dist)):
		return
	var n := Node3D.new()
	add_child(n)
	var o3 := fx.ground3(from, 1.4)
	n.global_position = o3
	var d3 := Vector3(dir.x, 0.0, -dir.y).normalized()
	# the cone of vapour: particles thrown along the cast at the cone's angle, carried to the end of its reach
	var reach := float(e.dist) * View.S
	var speed := float(e.speed) * View.S
	var half := atan2(float(e.w1) * 0.5, float(e.dist))
	var p := mist(0.25, 200.0, 0.75, reach / speed + 0.3, 0.0, 0.38, Color(0.66, 0.84, 1.0))
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = d3
	pm.spread = rad_to_deg(half) * 0.9
	pm.initial_velocity_min = speed * 0.9
	pm.initial_velocity_max = speed * 1.05
	pm.damping_min = 0.0
	pm.damping_max = 0.3
	pm.scale_min = 0.45
	pm.scale_max = 1.25
	n.add_child(p)
	var g := glitter(0.2, 220.0, reach / speed + 0.2, 0.0, 0.05)
	var gm := g.process_material as ParticleProcessMaterial
	gm.direction = d3
	gm.spread = rad_to_deg(half)
	gm.initial_velocity_min = speed * 0.85
	gm.initial_velocity_max = speed * 1.1
	gm.gravity = Vector3(0, -1.5, 0)
	n.add_child(g)
	fire.timed(n, reach / speed + 0.05)
	fx.flash_light(o3, ICE, 2.5, 5.0, 0.4)
	# the sheet of streaming cold, and frost in the same fan on the ground
	var angle := 2.0 * half * 1.15
	var yaw := atan2(d3.x, d3.z)
	for ground in [false, true]:
		var mi := MeshInstance3D.new()
		mi.mesh = fan_mesh(angle, 0.2, reach)
		var mat := fan_material(ground)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = fx.ground3(from, 0.08) if ground else o3 - Vector3(0, 0.45, 0)
		mi.rotation.y = yaw
		_fans.append({"node": mi, "mat": mat, "t": 0.0, "grow": reach / speed, "life": 3.0 if ground else reach / speed + 0.5,
			"ground": ground})

var _fans: Array = []

var _frosts: Array = []

func _breath_move(_e: Dictionary) -> void:
	pass

## A unit caught by the cold: a puff of frost on it.
func _chilled_hit(uid: int) -> void:
	var v := fx._view_of(uid)
	if v == null or not v.visible:
		return
	var at := fx._chest(uid, 0.45)
	_puff(at, 0.55, 0.5)
	burst_shards(at, 3, 0.1, 2.0)

func _puff(at: Vector3, size: float, life: float) -> void:
	var p := mist(size * 0.3, 60.0, size, life, 0.6, 0.6)
	p.one_shot = true
	p.explosiveness = 0.9
	add_child(p)
	p.global_position = at
	fire.timed(p, 0.1)

func _pulse_cast(e: Dictionary) -> void:
	var uid := int(e.target)
	if _curses.has(uid) and is_instance_valid(_curses[uid].node):
		(_curses[uid].node as Node3D).queue_free()
	var n := Node3D.new()
	add_child(n)
	# six shards circling the chest, points outward
	var orbit := Node3D.new()
	orbit.name = "Orbit"
	n.add_child(orbit)
	_init_static()
	for k in 6:
		var s := MeshInstance3D.new()
		s.mesh = _shard_meshes[k % 3]
		s.material_override = _ice_mat
		var a := TAU * k / 6.0
		s.position = Vector3(cos(a) * 0.55, 0, sin(a) * 0.55)
		s.rotation = Vector3(0, -a, PI * 0.5)
		s.scale = Vector3.ONE * 0.3
		orbit.add_child(s)
	n.add_child(glitter(0.4, 18.0, 0.8, 0.3, 0.04))
	# the timer ring on the ground
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 2.4)
	q.orientation = PlaneMesh.FACE_Y
	ring.mesh = q
	var rm := ShaderMaterial.new()
	rm.shader = _ring_shader()
	rm.set_shader_parameter("col", ICE)
	rm.render_priority = 4
	ring.material_override = rm
	ring.name = "Ring"
	n.add_child(ring)
	var dur := float(e.dur)
	_curses[uid] = {"node": n, "ring_mat": rm, "start": Time.get_ticks_msec() / 1000.0, "total": dur}

static var _ring_sh: Shader

static func _ring_shader() -> Shader:
	if _ring_sh == null:
		_ring_sh = Shader.new()
		_ring_sh.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform float left = 1.0;
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float a = atan(q.x, -q.y) / 6.2831853 + 0.5;
	float band = smoothstep(0.80, 0.84, r) * (1.0 - smoothstep(0.9, 0.94, r));
	float arc = step(a, left);
	float inner = (1.0 - smoothstep(0.0, 0.84, r)) * 0.12;
	ALBEDO = col.rgb * 2.2;
	ALPHA = clamp(band * (0.25 + 0.75 * arc) + inner, 0.0, 1.0);
}
"""
	return _ring_sh

func _pulse_blast(e: Dictionary) -> void:
	var uid := int(e.target)
	if _curses.has(uid):
		if is_instance_valid(_curses[uid].node):
			(_curses[uid].node as Node3D).queue_free()
		_curses.erase(uid)
	var p2: Vector2 = e.pos
	if not fx._seen(p2):
		return
	var at := fx.ground3(p2, 1.0)
	var r := float(e.radius) * View.S
	fx.shockwave(fx.ground3(p2), r, Color(0.7, 0.92, 1.0), 0.45, 0.22, 3.0)
	burst_shards(at, 18, 0.3, 6.5)
	var p := mist(r * 0.4, 160.0, 1.2, 0.9, 1.4, 0.6)
	p.one_shot = true
	p.explosiveness = 0.95
	add_child(p)
	p.global_position = at
	fire.timed(p, 0.1)
	var gl := glitter(r * 0.3, 140.0, 0.9, 2.5, 0.06)
	gl.one_shot = true
	gl.explosiveness = 0.9
	add_child(gl)
	gl.global_position = at
	fire.timed(gl, 0.1)
	fx.flash_light(at, ICE, 6.0, 6.0, 0.35)
	var fr := ground_frost(r)
	add_child(fr)
	fr.global_position = fx.ground3(p2, 0.06)
	_frosts.append({"node": fr, "t": 0.0, "grow": 0.15, "life": 2.5})

## Ice shards thrown out from `at`.
func burst_shards(at: Vector3, n: int, size: float, speed: float) -> void:
	_init_static()
	for i in n:
		if _shards.size() > 160:
			break
		var s := MeshInstance3D.new()
		s.mesh = _shard_meshes[i % 3]
		s.material_override = _ice_mat_bright if i % 4 == 0 else _ice_mat
		s.scale = Vector3.ONE * size * randf_range(0.6, 1.2)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		s.global_position = at
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized()
		_shards.append({"node": s, "vel": dir * speed * randf_range(0.5, 1.1), "t": 0.0, "life": randf_range(0.5, 0.9),
			"spin": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)), "s0": s.scale.x})

# ---- Every frame ------------------------------------------------------------------------------------------------------

func update(w: SimWorld, _alpha: float, dt: float) -> void:
	_scan_i += 1
	if _scan_i % 3 == 0:
		_scan(w)
	var now := Time.get_ticks_msec() / 1000.0
	# auras follow Froster
	for id in _aura:
		var v := fx._view_of(int(id))
		var a: Dictionary = _aura[id]
		if v == null or not is_instance_valid(a.root):
			continue
		(a.root as Node3D).visible = v.visible
		(a.root as Node3D).global_position = v.global_position
		if is_instance_valid(a.glow):
			var tip := v.weapon_tip() if not v.weapons.is_empty() else v.global_position + Vector3(0, 1.8, 0)
			(a.glow as Node3D).global_position = tip
	# hearts circle his chest
	for id in _hearts:
		var v2 := fx._view_of(int(id))
		var list: Array = _hearts[id]
		for i in list.size():
			var hn: Node3D = list[i]
			if not is_instance_valid(hn) or v2 == null:
				continue
			hn.visible = v2.visible
			var a2 := now * 2.2 + TAU * i / maxf(1.0, list.size())
			hn.global_position = v2.global_position + Vector3(cos(a2) * 0.55, v2.bar_height * 0.62 + sin(now * 3.0 + i) * 0.06, sin(a2) * 0.55)
			hn.rotation.y = now * 3.0
	# curses follow their units, rings close
	for uid in _curses.keys():
		var c: Dictionary = _curses[uid]
		var v3 := fx._view_of(int(uid))
		if not is_instance_valid(c.node):
			_curses.erase(uid)
			continue
		var cn: Node3D = c.node
		if v3 == null or now - float(c.start) > float(c.total) + 1.0:
			cn.queue_free()
			_curses.erase(uid)
			continue
		cn.visible = v3.visible
		cn.global_position = v3.global_position
		var orbit: Node3D = cn.get_node("Orbit")
		orbit.position.y = v3.bar_height * 0.55
		orbit.rotation.y = now * 2.6
		var ring: Node3D = cn.get_node("Ring")
		ring.global_position = Vector3(v3.global_position.x, fx.ground_y(View.to2(v3.global_position)) + 0.07, v3.global_position.z)
		(c.ring_mat as ShaderMaterial).set_shader_parameter("left", clampf(1.0 - (now - float(c.start)) / float(c.total), 0.0, 1.0))
	# blizzards stay on Froster
	for id in _winters:
		var wn: Node3D = _winters[id]
		var v4 := fx._view_of(int(id))
		if v4 and is_instance_valid(wn):
			wn.global_position = Vector3(v4.global_position.x, fx.ground_y(View.to2(v4.global_position)), v4.global_position.z)
			var vort: Node3D = wn.get_node_or_null("Vortex")
			if vort:
				vort.rotation.y = now * 1.6
	# ice blocks and chill follow their units
	for uid in _blocks:
		var b: Node3D = _blocks[uid]
		var v5 := fx._view_of(int(uid))
		if v5 and is_instance_valid(b):
			b.global_position = v5.global_position
			b.visible = v5.visible
	for uid in _chill:
		var cp: Node3D = _chill[uid]
		var v6 := fx._view_of(int(uid))
		if v6 and is_instance_valid(cp):
			cp.global_position = v6.global_position + Vector3(0, 0.25, 0)
	# shards in flight
	for i in range(_shards.size() - 1, -1, -1):
		var s: Dictionary = _shards[i]
		var sn: Node3D = s.node
		s.t = float(s.t) + dt
		if not is_instance_valid(sn) or float(s.t) >= float(s.life):
			if is_instance_valid(sn):
				sn.queue_free()
			_shards.remove_at(i)
			continue
		s.vel = (s.vel as Vector3) + Vector3(0, -9.0, 0) * dt
		sn.global_position += (s.vel as Vector3) * dt
		sn.rotation += (s.spin as Vector3) * dt
		var k := 1.0 - float(s.t) / float(s.life)
		sn.scale = Vector3.ONE * float(s.s0) * (0.4 + 0.6 * k)
	# breath sheets sweep out and thin away; their ground frost lingers, then melts
	for i in range(_fans.size() - 1, -1, -1):
		var fa: Dictionary = _fans[i]
		var fan: MeshInstance3D = fa.node
		fa.t = float(fa.t) + dt
		if not is_instance_valid(fan) or float(fa.t) >= float(fa.life):
			if is_instance_valid(fan):
				fan.queue_free()
			_fans.remove_at(i)
			continue
		var fm := fa.mat as ShaderMaterial
		fm.set_shader_parameter("progress", clampf(float(fa.t) / maxf(0.05, float(fa.grow)), 0.0, 1.0) * 1.12)
		var tail := 1.0 if bool(fa.ground) else 0.5
		fm.set_shader_parameter("fade", clampf((float(fa.life) - float(fa.t)) / tail, 0.0, 1.0))
	# frost on the ground spreads, then melts away
	for i in range(_frosts.size() - 1, -1, -1):
		var f: Dictionary = _frosts[i]
		var fnode: MeshInstance3D = f.node
		f.t = float(f.t) + dt
		if not is_instance_valid(fnode) or float(f.t) >= float(f.life):
			if is_instance_valid(fnode):
				fnode.queue_free()
			_frosts.remove_at(i)
			continue
		var m := fnode.material_override as ShaderMaterial
		m.set_shader_parameter("reach", clampf(float(f.t) / maxf(0.05, float(f.grow)), 0.05, 1.0))
		m.set_shader_parameter("fade", clampf((float(f.life) - float(f.t)) / 0.8, 0.0, 1.0))

## Which units need which cold visuals: Froster's presence, hearts and blizzard; ice blocks; chill.
func _scan(w: SimWorld) -> void:
	var want_aura := {}
	var want_block := {}
	var want_chill := {}
	var want_winter := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView):
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive:
			continue
		if String(u.def.get("model", "")) == "hero_froster":
			want_aura[id] = true
			_sync_hearts(u, v)
			if not u.channel.is_empty() and String(u.channel.ability) == "endless_winter":
				want_winter[id] = float(u.channel.radius)
		if not v.visible:
			continue
		for m in u.modifiers:
			match String(m.get("fx", "")):
				"frozen":
					want_block[id] = true
				"chill":
					want_chill[id] = true
	for id in _aura.keys():
		if not want_aura.has(id):
			for k in ["root", "glow"]:
				if is_instance_valid(_aura[id][k]):
					fire.timed(_aura[id][k], 0.0)
			_aura.erase(id)
	for id in want_aura:
		if not _aura.has(id):
			_aura[id] = _make_aura(int(id))
	_sync(_blocks, want_block, _make_block, true)
	_sync(_chill, want_chill, _make_chill)
	for id in _winters.keys():
		if not want_winter.has(id):
			var n: Node3D = _winters[id]
			if is_instance_valid(n):
				fire.timed(n, 0.0)
				for mi in n.find_children("*", "MeshInstance3D", true, false):
					var tw := create_tween()
					tw.tween_property(mi, "transparency", 1.0, 0.8)
			_winters.erase(id)
	for id in want_winter:
		if not _winters.has(id):
			_winters[id] = _make_winter(float(want_winter[id]) * View.S)
	for id in _hearts.keys():
		if not want_aura.has(id):
			for hn in _hearts[id]:
				if is_instance_valid(hn):
					hn.queue_free()
			_hearts.erase(id)

func _sync(store: Dictionary, want: Dictionary, make: Callable, shatter := false) -> void:
	for id in store.keys():
		if not want.has(id):
			var n = store[id]
			if is_instance_valid(n):
				if shatter:
					burst_shards((n as Node3D).global_position + Vector3(0, 1.0, 0), 14, 0.25, 4.5)
					n.queue_free()
				else:
					fire.timed(n, 0.0)
			store.erase(id)
	for id in want:
		if not store.has(id):
			store[id] = make.call(int(id))

func _make_aura(_id: int) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	root.add_child(snow(0.9, 2.6, 14.0, 2.2, 0.15))
	var feet := mist(0.45, 10.0, 0.7, 1.8, 0.1, 0.35)
	feet.position.y = 0.15
	root.add_child(feet)
	var glow := Node3D.new()
	add_child(glow)
	glow.add_child(core(0.07, 3.5))
	glow.add_child(glitter(0.06, 10.0, 0.7, 0.3, 0.03))
	var l := FireFx.light(ICE, 0.7, 3.0)
	glow.add_child(l)
	return {"root": root, "glow": glow}

## The hearts on show match the hearts he has.
func _sync_hearts(u: SimUnit, _v: UnitView) -> void:
	var n := int(u.stacks.get("frost_hearts", 0))
	var list: Array = _hearts.get(u.id, [])
	while list.size() < n:
		var hn := Node3D.new()
		add_child(hn)
		_init_static()
		var s := MeshInstance3D.new()
		s.mesh = _heart_mesh()
		s.material_override = _ice_mat_bright
		s.scale = Vector3.ONE * 0.11
		hn.add_child(s)
		hn.add_child(glitter(0.03, 8.0, 0.5, 0.1, 0.025))
		list.append(hn)
	while list.size() > n:
		var last: Node3D = list.pop_back()
		if is_instance_valid(last):
			burst_shards(last.global_position, 4, 0.1, 2.0)
			last.queue_free()
	_hearts[u.id] = list

static var _heart: ArrayMesh

## A heart cut from ice: two lobes and a point, extruded.
static func _heart_mesh() -> ArrayMesh:
	if _heart != null:
		return _heart
	var pts := PackedVector2Array()
	for i in 40:
		var t := TAU * i / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
		pts.append(Vector2(x, y) / 16.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(pts)
	var depth := 0.35
	for side in [1.0, -1.0]:
		for k in range(0, tris.size(), 3):
			var idx := [tris[k], tris[k + 1], tris[k + 2]] if side > 0.0 else [tris[k], tris[k + 2], tris[k + 1]]
			for j in idx:
				st.set_normal(Vector3(0, 0, side))
				st.add_vertex(Vector3(pts[j].x, pts[j].y, depth * side))
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var n := Vector3(b.y - a.y, -(b.x - a.x), 0).normalized()
		for v in [Vector3(a.x, a.y, depth), Vector3(b.x, b.y, depth), Vector3(b.x, b.y, -depth),
				Vector3(a.x, a.y, depth), Vector3(b.x, b.y, -depth), Vector3(a.x, a.y, -depth)]:
			st.set_normal(n)
			st.add_vertex(v)
	_heart = st.commit()
	return _heart

func _make_block(id: int) -> Node3D:
	var v := fx._view_of(id)
	var n := Node3D.new()
	add_child(n)
	_init_static()
	var h := v.bar_height if v else 2.0
	# a cluster of big shards leaning together round the body
	for k in 7:
		var s := MeshInstance3D.new()
		s.mesh = _shard_meshes[k % 3]
		s.material_override = _ice_mat
		var a := TAU * k / 7.0
		s.position = Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32)
		s.rotation = Vector3(sin(a) * 0.25, -a, cos(a) * 0.25)
		s.scale = Vector3(0.9, h * 0.55, 0.9)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(s)
	var core_shard := MeshInstance3D.new()
	core_shard.mesh = _shard_meshes[1]
	core_shard.material_override = _ice_mat
	core_shard.scale = Vector3(2.2, h * 0.62, 2.2)
	n.add_child(core_shard)
	n.add_child(mist(0.5, 12.0, 0.8, 1.4, 0.15, 0.35))
	var l := FireFx.light(ICE, 1.2, 3.0)
	l.position.y = 1.0
	n.add_child(l)
	if v:
		n.global_position = v.global_position
		burst_shards(v.global_position + Vector3(0, 1.0, 0), 8, 0.16, 3.0)
	return n

func _make_chill(id: int) -> Node3D:
	var p := mist(0.35, 8.0, 0.5, 1.2, 0.15, 0.4)
	add_child(p)
	var v := fx._view_of(id)
	if v:
		p.global_position = v.global_position + Vector3(0, 0.25, 0)
	return p

func _make_winter(r: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.add_child(snow(r, 5.5, r * r * 9.0, 2.0, 0.35))
	var swirl := snow(r * 0.9, 1.6, r * r * 4.0, 1.4, 0.8)
	n.add_child(swirl)
	var edge := mist(r, r * 10.0, 1.4, 2.2, 0.2, 0.22)
	edge.position.y = 0.3
	(edge.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	(edge.process_material as ParticleProcessMaterial).emission_ring_radius = r
	(edge.process_material as ParticleProcessMaterial).emission_ring_inner_radius = r * 0.85
	(edge.process_material as ParticleProcessMaterial).emission_ring_height = 0.2
	(edge.process_material as ParticleProcessMaterial).emission_ring_axis = Vector3.UP
	n.add_child(edge)
	var fr := ground_frost(r)
	fr.position.y = 0.06
	n.add_child(fr)
	_frosts.append({"node": fr, "t": 0.0, "grow": 1.2, "life": 8.0})
	# a slow vortex of vapour and glitter over Froster
	var vort := Node3D.new()
	vort.name = "Vortex"
	n.add_child(vort)
	var vm := mist(1.2, 30.0, 1.2, 1.6, 0.6, 0.25)
	vm.position.y = 3.2
	vort.add_child(vm)
	var vg := glitter(1.5, 40.0, 1.2, 0.8, 0.05)
	vg.position.y = 2.8
	vort.add_child(vg)
	var l := FireFx.light(Color(0.55, 0.78, 1.0), 2.5, r * 1.3)
	l.position.y = 3.0
	n.add_child(l)
	return n

class_name FireFx
extends Node
## Particle fire for every Fire effect: GPU particles drawn as camera-facing quads with a flame shader (noise-licked
## tongues that rise, narrow and cool from white-gold to orange to deep red), additive embers drifting on turbulence,
## dark smoke that blends over the scene, and flickering warm light. Builders return ready emitters; one-shot effects
## (bursts, burning ground) are tracked here and freed once their last particle is gone.
##
## Units: metres (1 game unit = 1 cm). Everything is world-space (local_coords off), so flames on a moving unit trail
## behind it like real fire.

const FLAME_CODE := """
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float intensity = 1.6;
uniform float cover = 0.8;
uniform float lick = 1.0;
uniform float stretch = 1.25;
uniform float cool = 0.0;
varying vec4 pcol;
varying float age;
varying float seed;

float hash(vec2 p) {
	// sine-free (Hoskins): stays exact at large inputs, where fract(sin(x)) turns into flat blocks
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
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}
void vertex() {
	// face the camera, keep the particle's own size
	float sc = length(MODEL_MATRIX[0].xyz);
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc * stretch, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	pcol = COLOR;
	age = INSTANCE_CUSTOM.y;
	seed = fract(sin(float(INSTANCE_ID) * 12.9898 + 4.1) * 43758.5453);
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	q.y = -q.y;                                    // +y is up
	float t = mod(TIME, 600.0) * 1.9 + seed * 17.0;
	float n = fbm(vec2(q.x * 1.7 + seed * 7.0, q.y * 1.4 - t));
	float n2 = fbm(vec2(q.x * 3.1 - seed * 3.0, q.y * 2.6 - t * 1.6));
	// a round hot base low in the quad, a tongue that sways and tapers to a tip above it
	float yb = q.y + 0.3;
	float up = clamp(yb / 1.15, 0.0, 1.0);
	q.x += (n - 0.5) * 0.75 * lick * (0.15 + up * 1.2);
	float r = 0.44;
	float w = r * (1.0 - up * up * 0.88);
	float dx = abs(q.x) / max(w, 0.02);
	float dy = yb < 0.0 ? -yb / r : 0.0;
	float d = length(vec2(dx, dy));
	float body = 1.0 - smoothstep(0.15, 1.0, d);
	body *= 1.0 - smoothstep(0.55, 1.0, up + (n - 0.5) * 0.35);
	float licks = smoothstep(0.2, 0.8, n2 * 0.75 + body * 0.75);
	// never reach the quad's border (no straight edges)
	vec2 e = abs(UV * 2.0 - 1.0);
	float edge = (1.0 - smoothstep(0.62, 0.95, e.x)) * (1.0 - smoothstep(0.7, 0.97, e.y));
	float a = body * licks * edge;
	// born small and bright, gone by the end of its life
	a *= smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.5, 1.0, age));
	float heat = clamp(a * 1.35 - cool - age * 0.8, 0.0, 1.0);
	vec3 deep = pcol.rgb * vec3(0.85, 0.3, 0.12);
	vec3 col = mix(deep, pcol.rgb, smoothstep(0.05, 0.6, heat));
	col = mix(col, vec3(1.0, 0.8, 0.45), smoothstep(0.9, 1.0, heat) * 0.2);
	// premultiplied: the hot light adds on top while the flame's body also covers what is behind it, so fire stays
	// orange over a bright sunlit ground instead of washing out to white
	float al = clamp(a * pcol.a, 0.0, 1.0);
	ALBEDO = col * intensity * (0.55 + 0.45 * heat) * al;
	ALPHA = al * cover;
}
"""

const SMOKE_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.08, 0.06, 0.06, 1.0);
uniform float density = 0.45;
varying vec4 pcol;
varying float age;
varying float seed;
float hash(vec2 p) {
	// sine-free (Hoskins): stays exact at large inputs, where fract(sin(x)) turns into flat blocks
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
	seed = fract(sin(float(INSTANCE_ID) * 7.31 + 1.3) * 43758.5453);
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float n = vnoise(q * 2.2 + vec2(seed * 9.0, -TIME * 0.6)) * 0.6 + vnoise(q * 4.7 - vec2(TIME * 0.3, seed * 3.0)) * 0.4;
	float puff = 1.0 - smoothstep(0.2, 1.0, length(q) + (n - 0.5) * 0.5);
	float a = puff * smoothstep(0.0, 0.2, age) * (1.0 - smoothstep(0.45, 1.0, age));
	ALBEDO = mix(tint.rgb, tint.rgb * 2.2, n * 0.4);
	ALPHA = clamp(a * density * pcol.a, 0.0, 1.0);
}
"""

static var _flame_shader: Shader
static var _smoke_shader: Shader
static var _ember_mat: StandardMaterial3D
static var _quad: QuadMesh
static var _ember_quad: QuadMesh
static var _ramps := {}

var _timed: Array = []                     # {node, stop_at, free_at, light, light_e, light_t}
var _lights: Array = []                    # flickering lights: {light, base, seed}

# ---- Materials ------------------------------------------------------------------------------------------------------

static func _init_static() -> void:
	if _flame_shader != null:
		return
	_flame_shader = Shader.new()
	_flame_shader.code = FLAME_CODE
	_smoke_shader = Shader.new()
	_smoke_shader.code = SMOKE_CODE
	_quad = QuadMesh.new()
	_quad.size = Vector2(1, 1)
	_ember_quad = QuadMesh.new()
	_ember_quad.size = Vector2(1, 1)
	_ember_mat = StandardMaterial3D.new()
	_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_ember_mat.billboard_keep_scale = true
	_ember_mat.vertex_color_use_as_albedo = true
	_ember_mat.disable_receive_shadows = true
	_ember_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.25, Color(1, 1, 1, 0.9))
	g.gradient = gr
	g.width = 32
	g.height = 32
	_ember_mat.albedo_texture = g
	_ember_mat.albedo_color = Color(2.2, 2.2, 2.2)
	_ember_quad.material = _ember_mat

## A flame material: `intensity` brightness (over 1 blooms), `lick` how much the tongues sway, `stretch` how tall a
## tongue is against its width.
static func flame_material(intensity := 1.5, lick := 1.0, stretch := 1.25) -> ShaderMaterial:
	_init_static()
	var m := ShaderMaterial.new()
	m.shader = _flame_shader
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("lick", lick)
	m.set_shader_parameter("stretch", stretch)
	return m

## Colour over a particle's life: hot gold to orange to red to nothing. Spirit flames ("spirit") burn paler, with a
## violet-pink edge.
static func ramp(kind := "fire") -> GradientTexture1D:
	if _ramps.has(kind):
		return _ramps[kind]
	var g := Gradient.new()
	match kind:
		"spirit":
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
			g.colors = PackedColorArray([Color(1.0, 0.62, 0.42, 1.0), Color(1.0, 0.36, 0.3, 1.0), Color(0.85, 0.14, 0.32, 0.85),
				Color(0.4, 0.05, 0.25, 0.0)])
		"void":
			# Roydo's Anomaly: violet-white cores, magenta, dying to deep purple
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
			g.colors = PackedColorArray([Color(1.0, 0.8, 1.0, 1.0), Color(0.95, 0.3, 0.85, 1.0), Color(0.45, 0.1, 0.75, 0.85),
				Color(0.1, 0.0, 0.2, 0.0)])
		"soul":
			# Azrael: white soul flame, cooling to a pale blue-grey and vanishing
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
			g.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(0.86, 0.92, 1.0, 0.95), Color(0.55, 0.62, 0.78, 0.6),
				Color(0.2, 0.22, 0.3, 0.0)])
		"blood":
			# Azrael's charged slash and her soul charge: crimson cores, deep red, dying to black
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
			g.colors = PackedColorArray([Color(1.0, 0.35, 0.3, 1.0), Color(0.85, 0.05, 0.08, 1.0), Color(0.3, 0.0, 0.03, 0.85),
				Color(0.02, 0.0, 0.0, 0.0)])
		"shadowflame":
			# Araki (run 2026-10-19 c): the soul-fire of his body's arms and eyes, white-green cores, acid green, dying
			# to a dark teal
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
			g.colors = PackedColorArray([Color(0.92, 1.0, 0.85, 1.0), Color(0.5, 1.0, 0.3, 1.0), Color(0.12, 0.55, 0.25, 0.8),
				Color(0.02, 0.12, 0.08, 0.0)])
		"underworld":
			# Blackfire (run 2026-10-21): pale violet cores, violet, dying to black-purple
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
			g.colors = PackedColorArray([Color(0.95, 0.85, 1.0, 1.0), Color(0.6, 0.25, 1.0, 1.0), Color(0.25, 0.06, 0.5, 0.85),
				Color(0.03, 0.0, 0.06, 0.0)])
		"water":
			# Dracoxinia's Blue Sword (run 2026-10-21 b): white-blue cores, clear blue, dying to deep sea blue
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
			g.colors = PackedColorArray([Color(0.9, 0.97, 1.0, 1.0), Color(0.35, 0.65, 1.0, 1.0), Color(0.1, 0.3, 0.75, 0.8),
				Color(0.02, 0.06, 0.2, 0.0)])
		"holy":
			g.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
			g.colors = PackedColorArray([Color(1.0, 0.97, 0.85, 1.0), Color(1.0, 0.78, 0.35, 1.0), Color(1.0, 0.42, 0.12, 0.8),
				Color(0.6, 0.12, 0.04, 0.0)])
		_:
			g.offsets = PackedFloat32Array([0.0, 0.2, 0.55, 1.0])
			g.colors = PackedColorArray([Color(1.0, 0.72, 0.3, 1.0), Color(1.0, 0.42, 0.08, 1.0), Color(0.85, 0.16, 0.03, 0.9),
				Color(0.3, 0.04, 0.02, 0.0)])
	var t := GradientTexture1D.new()
	t.gradient = g
	_ramps[kind] = t
	return t

static func _scale_curve(grow := 0.15) -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(grow, 1.0))
	c.add_point(Vector2(1.0, 0.25))
	var t := CurveTexture.new()
	t.curve = c
	return t

# ---- Emitters -------------------------------------------------------------------------------------------------------

## Flames rising from a disc (`radius` m) or a point: `rate` particles a second, each `size` m across, living `life`
## seconds and rising at `rise` m/s. kind: "fire", "spirit", "holy".
static func flames(radius: float, size: float, rate: float, life := 0.75, rise := 1.6, kind := "fire",
		intensity := 1.5) -> GPUParticles3D:
	_init_static()
	var p := GPUParticles3D.new()
	p.amount = maxi(4, int(rate * life))
	p.lifetime = life
	p.local_coords = false
	p.randomness = 0.6
	p.fixed_fps = 0
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 10, 8))
	var m := ParticleProcessMaterial.new()
	if radius > 0.01:
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = radius
	m.direction = Vector3.UP
	m.spread = 14.0
	m.initial_velocity_min = rise * 0.45
	m.initial_velocity_max = rise
	m.gravity = Vector3(0, rise * 1.1, 0)               # hot air: flames speed up as they rise
	m.damping_min = 0.6
	m.damping_max = 1.4
	m.scale_min = size * 0.7
	m.scale_max = size * 1.15
	m.scale_curve = _scale_curve()
	m.color_ramp = ramp(kind)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.9
	m.turbulence_noise_scale = 2.2
	m.turbulence_noise_speed = Vector3(0, 0.6, 0)
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.14
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = flame_material(intensity, 1.0 if kind != "spirit" else 1.3)
	p.draw_pass_1 = q
	return p

## Glowing sparks that drift up and wander (turbulence), `rate` per second.
static func embers(radius: float, rate: float, life := 1.4, rise := 1.4, size := 0.05, col := Color(1.0, 0.55, 0.15)) -> GPUParticles3D:
	_init_static()
	var p := GPUParticles3D.new()
	p.amount = maxi(4, int(rate * life))
	p.lifetime = life
	p.local_coords = false
	p.randomness = 0.8
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 10, 8))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = maxf(radius, 0.02)
	m.direction = Vector3.UP
	m.spread = 35.0
	m.initial_velocity_min = rise * 0.4
	m.initial_velocity_max = rise
	m.gravity = Vector3(0, rise * 0.4, 0)
	m.damping_min = 0.3
	m.damping_max = 0.8
	m.scale_min = size * 0.6
	m.scale_max = size * 1.3
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 2.4
	m.turbulence_noise_scale = 1.4
	m.turbulence_influence_min = 0.15
	m.turbulence_influence_max = 0.35
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.75, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.7, 1.0), col, Color(col.r, col.g * 0.4, col.b * 0.2, 0.8), Color(0.3, 0.05, 0.0, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	p.process_material = m
	p.draw_pass_1 = _ember_quad
	return p

## Soot rising off a fire.
static func smoke(radius: float, rate: float, size := 0.9, life := 2.0, rise := 1.0, density := 0.4) -> GPUParticles3D:
	_init_static()
	var p := GPUParticles3D.new()
	p.amount = maxi(3, int(rate * life))
	p.lifetime = life
	p.local_coords = false
	p.randomness = 0.6
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-5, -2, -5), Vector3(10, 12, 10))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = maxf(radius, 0.05)
	m.direction = Vector3.UP
	m.spread = 20.0
	m.initial_velocity_min = rise * 0.5
	m.initial_velocity_max = rise
	m.damping_min = 0.2
	m.damping_max = 0.5
	m.scale_min = size * 0.6
	m.scale_max = size
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.4))
	c.add_point(Vector2(1.0, 1.6))
	var ct := CurveTexture.new()
	ct.curve = c
	m.scale_curve = ct
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	m.turbulence_influence_min = 0.03
	m.turbulence_influence_max = 0.08
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = _smoke_shader
	mat.set_shader_parameter("density", density)
	q.material = mat
	p.draw_pass_1 = q
	return p

const CORE_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform float energy = 4.0;
void fragment() {
	float f = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float c = pow(f, 2.2);
	float flick = 0.85 + 0.15 * sin(TIME * 23.0) * sin(TIME * 7.0 + 1.0);
	ALBEDO = mix(col.rgb, vec3(1.0, 0.95, 0.82), c) * energy * flick;
	ALPHA = clamp(pow(f, 0.8) * 0.9, 0.0, 1.0);
}
"""

static var _core_shader: Shader

## A bright burning core (fireballs, spirits, the hammer's head): a glowing sphere, white-hot in the middle, its rim
## fading into its colour, so it blooms like a ball of fire rather than a solid ball.
static func core(radius: float, col := Color(1.0, 0.55, 0.15), energy := 4.0) -> MeshInstance3D:
	if _core_shader == null:
		_core_shader = Shader.new()
		_core_shader.code = CORE_CODE
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 20
	s.rings = 10
	mi.mesh = s
	var m := ShaderMaterial.new()
	m.shader = _core_shader
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("energy", energy)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func light(col := Color(1.0, 0.55, 0.2), energy := 2.0, rng := 5.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	return l

# ---- Lifetimes ----------------------------------------------------------------------------------------------------------

## Keep `node` for `dur` seconds, then stop its emitters and free it once their particles have died. A light inside
## fades out over the last part.
func timed(node: Node3D, dur: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var tail := 0.0
	for p: GPUParticles3D in node.find_children("*", "GPUParticles3D", true, false):
		tail = maxf(tail, p.lifetime)
	if node is GPUParticles3D:
		tail = maxf(tail, (node as GPUParticles3D).lifetime)
	_timed.append({"node": node, "stop_at": now + dur, "free_at": now + dur + tail + 0.1, "stopped": false,
		"start": now, "dur": dur})

## Lights in `node` flicker like a fire (call once after adding it).
func flicker(l: OmniLight3D) -> void:
	_lights.append({"light": l, "base": l.light_energy, "seed": randf() * 50.0})

func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_timed.size() - 1, -1, -1):
		var e: Dictionary = _timed[i]
		if not is_instance_valid(e.node):
			_timed.remove_at(i)
			continue
		var n: Node3D = View.live(e.node)
		if not bool(e.stopped) and now >= float(e.stop_at):
			e.stopped = true
			for p: GPUParticles3D in n.find_children("*", "GPUParticles3D", true, false):
				p.emitting = false
			if n is GPUParticles3D:
				(n as GPUParticles3D).emitting = false
			# its lights stop flickering and fade out with the last particles
			var ls: Array = []
			for l: OmniLight3D in n.find_children("*", "OmniLight3D", true, false):
				ls.append([l, l.light_energy])
				for j in range(_lights.size() - 1, -1, -1):
					if _lights[j].light == l:
						_lights.remove_at(j)
			e["lights"] = ls
		if e.has("bed"):
			# the ember bed glows up quickly, then dies down with the flames
			var life := now - float(e.start)
			var fade_in := clampf(life / 0.25, 0.0, 1.0)
			var fade_out := 1.0 if not bool(e.stopped) else clampf(1.0 - (now - float(e.stop_at)) / 0.8, 0.0, 1.0)
			(e.bed as ShaderMaterial).set_shader_parameter("fade", fade_in * fade_out)
		if bool(e.stopped):
			var k := clampf(1.0 - (now - float(e.stop_at)) / maxf(0.1, (float(e.free_at) - float(e.stop_at)) * 0.6), 0.0, 1.0)
			for pair in e.get("lights", []):
				if is_instance_valid(pair[0]) and pair[0] is OmniLight3D:
					(pair[0] as OmniLight3D).light_energy = float(pair[1]) * k * k
		if now >= float(e.free_at):
			n.queue_free()
			_timed.remove_at(i)
	for i in range(_lights.size() - 1, -1, -1):
		var f: Dictionary = _lights[i]
		if not is_instance_valid(f.light):
			_lights.remove_at(i)
			continue
		var l: OmniLight3D = f.light
		var s := float(f.seed) + now
		l.light_energy = float(f.base) * (0.78 + 0.14 * sin(s * 11.0) + 0.08 * sin(s * 23.0 + 1.3) + 0.06 * sin(s * 37.0))

# ---- Ready-made effects -----------------------------------------------------------------------------------------------

## A fire burst: flames thrown outward and up, sparks, a puff of smoke and a flash of light, `radius` m across.
func burst(at: Vector3, radius: float, kind := "fire", strength := 1.0) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	var f := flames(radius * 0.45, 0.6 * strength + radius * 0.25, 60.0 * strength, 0.55, 2.2 * strength, kind, 1.3)
	(f.process_material as ParticleProcessMaterial).spread = 70.0
	(f.process_material as ParticleProcessMaterial).initial_velocity_max = 3.5 * strength + radius
	f.one_shot = true
	f.explosiveness = 0.85
	root.add_child(f)
	var e := embers(radius * 0.3, 70.0 * strength, 1.3, 4.0 * strength)
	(e.process_material as ParticleProcessMaterial).spread = 80.0
	e.one_shot = true
	e.explosiveness = 0.9
	root.add_child(e)
	var s := smoke(radius * 0.4, 14.0 * strength, 1.2 + radius * 0.3, 1.8, 1.4, 0.35)
	s.one_shot = true
	s.explosiveness = 0.7
	root.add_child(s)
	var l := light(Color(1.0, 0.55, 0.2) if kind == "fire" else Color(1.0, 0.7, 0.4), 5.0 * strength, 4.0 + radius * 2.0)
	l.position.y = 0.8
	root.add_child(l)
	for p: GPUParticles3D in [f, e, s]:
		p.emitting = true
	timed(root, 0.25)
	return root

const BED_CODE := """
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float fade = 1.0;
uniform vec4 hot : source_color = vec4(1.0, 0.38, 0.06, 1.0);
float hash(vec2 p) {
	// sine-free (Hoskins): stays exact at large inputs, where fract(sin(x)) turns into flat blocks
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
	float n = vnoise(p * 4.0 + vec2(TIME * 0.3, -TIME * 0.5)) * 0.55 + vnoise(p * 9.0 - TIME * 0.7) * 0.45;
	float disc = 1.0 - smoothstep(0.55, 1.0, r + (n - 0.5) * 0.35);
	float embers = smoothstep(0.45, 0.8, n) * disc;
	float flick = 0.8 + 0.2 * sin(TIME * 9.0 + n * 12.0);
	vec3 col = mix(hot.rgb * 0.5, mix(hot.rgb, vec3(1.0, 0.75, 0.35), embers), embers) * 1.5 * flick;
	float a = disc * fade;
	// ash darkens the ground; only the ember spots glow
	ALBEDO = (vec3(0.04, 0.025, 0.02) * (1.0 - embers) + col * embers * 0.9) * a;
	ALPHA = a * 0.55;
}
"""

static var _bed_shader: Shader

## A glowing bed of embers on the ground (under burning ground), fading in and out with its fire.
func _bed(radius: float, kind: String) -> MeshInstance3D:
	if _bed_shader == null:
		_bed_shader = Shader.new()
		_bed_shader.code = BED_CODE
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.1, radius * 2.1)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _bed_shader
	m.set_shader_parameter("hot", Color(1.0, 0.38, 0.06) if kind != "spirit" else Color(1.0, 0.3, 0.35))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Burning ground: a bed of embers under flames over a disc of `radius` m for `dur` seconds, thicker at the rim, with
## sparks and smoke.
func ground_fire(at: Vector3, radius: float, dur: float, kind := "fire") -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	var bed := _bed(radius, kind)
	bed.position.y = 0.03
	root.add_child(bed)
	var area := PI * radius * radius
	var fs := clampf(radius * 0.4, 0.6, 1.05)
	var inner := flames(radius * 0.75, fs, clampf(area * 3.0, 14.0, 60.0), 0.7, 0.9, kind, 0.75)
	var pm := inner.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 0.05
	pm.emission_ring_radius = radius * 0.95
	pm.emission_ring_inner_radius = 0.0
	root.add_child(inner)
	var rim := flames(0.0, fs * 1.1, clampf(radius * 12.0, 14.0, 60.0), 0.65, 1.3, kind, 0.85)
	var rm := rim.process_material as ParticleProcessMaterial
	rm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	rm.emission_ring_axis = Vector3.UP
	rm.emission_ring_height = 0.05
	rm.emission_ring_radius = radius
	rm.emission_ring_inner_radius = radius * 0.85
	root.add_child(rim)
	var e := embers(radius * 0.8, clampf(area * 4.0, 10.0, 60.0), 1.8, 1.8)
	root.add_child(e)
	var s := smoke(radius * 0.6, clampf(area * 0.8, 3.0, 14.0), 1.4, 2.6, 0.9, 0.3)
	s.position.y = 0.8
	root.add_child(s)
	var l := light(Color(1.0, 0.5, 0.18), 3.0, radius * 2.2 + 2.0)
	l.position.y = 0.7
	root.add_child(l)
	flicker(l)
	timed(root, dur)
	_timed[-1]["bed"] = bed.material_override
	return root

## A fireball: a white-hot core in a ball of licking flame, trailing fire and sparks (it is world-space, so the trail
## is left behind as it flies). `size` scales it.
static func fireball(size := 1.0, kind := "fire") -> Node3D:
	var n := Node3D.new()
	n.add_child(core(0.12 * size, Color(1.0, 0.5, 0.12) if kind != "spirit" else Color(1.0, 0.45, 0.5), 3.0))
	var f := flames(0.06 * size, 0.42 * size, 70.0, 0.32, 0.6, kind, 1.8)
	(f.process_material as ParticleProcessMaterial).gravity = Vector3(0, 1.5, 0)
	n.add_child(f)
	var e := embers(0.05 * size, 26.0, 0.7, 0.8, 0.04 * size)
	n.add_child(e)
	var l := light(Color(1.0, 0.55, 0.2), 1.6, 3.5)
	n.add_child(l)
	return n

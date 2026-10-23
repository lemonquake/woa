class_name HitFx
extends RefCounted
## The look of a blow landing (run 2026-10-23, the owner: "total improvement on the overall aesthetics and effects of
## attacks/hits"). Everything here is a camera-facing quad with one of three shared shaders, drawn additively on top of
## the bodies it lands on (a hit sits on the target's skin, so the body must not hide it); each quad has its own copy of
## the material for its colour and age (instance parameters ran out of the engine's buffer in big fights).
##   flare  a hot core with a few thin rays, flashing out in a fraction of a second (every impact in the game: Fx.impact)
##   ring   a thin ring racing outward and fading (heavy blows, crits, bursts)
##   slash  a crescent cut across the target in the weapon's colour, revealed along its length as the blade passes
## A melee hero's hit: slash, flare and sparks; a critical strike: a crossed double slash, a bigger flare, a ring and a
## small shake; a creep's: a small flare and sparks.

const MAX_LIVE := 96                       # quads alive at once (the oldest go first)

const BILLBOARD := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint = vec4(1.0, 0.85, 0.6, 1.0);
uniform float age = 0.0;          // 0 at birth .. 1 gone
uniform float spin = 0.0;         // turn in the screen's plane (radians)
uniform float seed = 0.0;
void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	float c = cos(spin);
	float s = sin(spin);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sc, INV_VIEW_MATRIX[1] * sc, INV_VIEW_MATRIX[2] * sc,
		MODEL_MATRIX[3]);
}
"""

const FLARE_FRAG := """
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float grow = 0.55 + 0.45 * sqrt(age);
	float rr = r / grow;
	float core = exp(-rr * rr * 18.0);
	float halo = exp(-rr * 3.6) * 0.35;
	float rays = pow(abs(cos(a * 2.0 + seed * 6.2831)), 40.0) + 0.6 * pow(abs(cos(a * 3.0 + seed * 3.1)), 60.0);
	rays *= exp(-rr * 2.4) * (1.0 - smoothstep(0.7, 1.0, rr));
	float fade = pow(1.0 - age, 1.6);
	vec3 hot = mix(tint.rgb, vec3(1.0), core * 0.85);
	ALBEDO = hot * (core * 2.2 + halo + rays * 1.4) * fade * tint.a;
	ALPHA = clamp((core + halo + rays) * fade * tint.a, 0.0, 1.0) * (1.0 - smoothstep(0.92, 1.0, r));
}
"""

const RING_FRAG := """
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float e = 1.0 - pow(1.0 - age, 3.0);
	float rad = mix(0.15, 0.95, e);
	float w = mix(0.05, 0.012, e);
	float band = 1.0 - smoothstep(0.0, w, abs(r - rad));
	float fade = pow(1.0 - age, 1.6);
	ALBEDO = mix(tint.rgb, vec3(1.0), band * 0.3) * band * 1.6 * fade * tint.a;
	ALPHA = clamp(band * fade * tint.a, 0.0, 1.0);
}
"""

## The crescent: an arc of a circle about the quad's centre, thick in its middle and tapering to points, revealed from
## one end to the other over the first third of its life, its leading edge white-hot, then fading from its tail.
const SLASH_FRAG := """
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float th = atan(p.x, p.y);                        // 0 straight up the quad, -PI..PI
	float span = 1.25;                                // half the arc (radians)
	float u = clamp((th + span) / (2.0 * span), 0.0, 1.0);
	float inside = step(abs(th), span);
	float reveal = smoothstep(0.0, 0.32, age) * 1.15;
	float shown = 1.0 - smoothstep(reveal - 0.12, reveal, u);
	float tail = smoothstep(age * 1.2 - 0.25, age * 1.2 + 0.25, u);
	float thick = sin(u * 3.14159) * 0.075 + 0.008;
	float mid = 0.72 + seed * 0.04;
	float d = abs(r - mid) / thick;
	float body = (1.0 - smoothstep(0.55, 1.0, d)) * inside * shown * tail;
	float edge = (1.0 - smoothstep(0.0, 0.35, abs(u - reveal + 0.06))) * body;
	float fade = 1.0 - smoothstep(0.45, 1.0, age);
	vec3 col = mix(tint.rgb, vec3(1.0), clamp(1.0 - d, 0.0, 1.0) * 0.55 + edge * 0.6);
	ALBEDO = col * body * (1.2 + edge * 1.8) * fade * tint.a;
	ALPHA = clamp(body * fade * tint.a * 0.85, 0.0, 1.0);
}
"""

static var _mats := {}
static var _quad: QuadMesh = null

var fx: Fx
var _live: Array = []                       # {node, t, life, grow}

func _init(p_fx: Fx) -> void:
	fx = p_fx

static func _mat(kind: String) -> ShaderMaterial:
	if not _mats.has(kind):
		var sh := Shader.new()
		sh.code = BILLBOARD + {"flare": FLARE_FRAG, "ring": RING_FRAG, "slash": SLASH_FRAG}[kind]
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = 6
		_mats[kind] = m
	return _mats[kind]

func _spawn(kind: String, at: Vector3, size: float, col: Color, life: float, spin := 0.0, grow := 0.0) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(2.0, 2.0)
	while _live.size() >= MAX_LIVE:
		var old: Dictionary = _live.pop_front()
		if is_instance_valid(old.node):
			(old.node as Node).queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	var m := _mat(kind).duplicate() as ShaderMaterial      # shares the compiled shader; its own colour and age
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = size * 2.0
	fx.add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * size
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("spin", spin)
	m.set_shader_parameter("seed", randf())
	m.set_shader_parameter("age", 0.0)
	_live.append({"node": mi, "mat": m, "t": 0.0, "life": life, "size": size, "grow": grow})
	return mi

func update(dt: float) -> void:
	for i in range(_live.size() - 1, -1, -1):
		var h: Dictionary = _live[i]
		h.t = float(h.t) + dt
		var n: MeshInstance3D = View.live(h.node)
		if n == null or float(h.t) >= float(h.life):
			if n:
				n.queue_free()
			_live.remove_at(i)
			continue
		var k := float(h.t) / float(h.life)
		(h.mat as ShaderMaterial).set_shader_parameter("age", k)
		if float(h.grow) != 0.0:
			n.scale = Vector3.ONE * float(h.size) * (1.0 + float(h.grow) * k)

# ---- What the game calls ----------------------------------------------------------------------------------------------

## A flash where something struck: `size` is about the flash's radius in metres.
func flare(at: Vector3, col: Color, size := 0.4, life := 0.22) -> void:
	_spawn("flare", at, size * 1.6, col, life, randf() * TAU)

func ring(at: Vector3, col: Color, size := 0.8, life := 0.3) -> void:
	_spawn("ring", at, size, col, life)

## A crescent cut through `at`, its arc crossing the line from the attacker (`from`) to the target as the camera sees it.
func slash(at: Vector3, from: Vector3, col: Color, size := 0.7, life := 0.3, flip := false, tilt := 0.0) -> void:
	var cam := fx.get_viewport().get_camera_3d()
	var spin := 0.0
	if cam:
		var a := cam.unproject_position(from)
		var b := cam.unproject_position(at)
		var d := b - a
		if d.length() > 0.5:
			# the arc's middle (the quad's -Y) bulges along the blow (screen y runs down, view y up): the blade swept
			# round the attacker, so its cut crosses the target bowed away from it
			d = d.normalized()
			spin = atan2(d.x, d.y)
	spin += tilt + (PI if flip else 0.0)
	_spawn("slash", at, size, col, life, spin)

## A melee blow landed (Fx.melee_hit): `at` where it met the target, `back` toward the attacker.
func melee(src: SimUnit, at: Vector3, back: Vector3, col: Color, hero: bool, crit: bool, heavy: bool) -> void:
	var from := at + back * 1.5
	if hero or crit:
		var flip := randf() < 0.5
		var tilt := randf_range(-0.6, 0.6)
		slash(at, from, col, 0.62 if not crit else 0.85, 0.28, flip, tilt)
		if crit:
			slash(at, from, Color(1.0, 0.35, 0.2), 0.78, 0.32, not flip, tilt + 1.1)
	flare(at, col.lerp(Color(1.0, 0.95, 0.85), 0.5), 0.42 if crit else (0.3 if heavy else 0.2), 0.2 if not crit else 0.24)
	if crit or (hero and heavy):
		ring(at, col, 1.0 if crit else 0.6, 0.28)

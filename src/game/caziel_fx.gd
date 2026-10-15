class_name CazielFx
extends Node
## Caziel's shadows:
##   * his presence: a thin drift of shadow at his feet, violet light on his blades;
##   * Swift Dagger: dark afterimages of him frozen along the path he flashed, a violet streak, and the stab bursting
##     in violet light on the target;
##   * Sweet Poison: a second, green slash and drops of poison; a poisoned unit trails sickly green vapour;
##   * Master of Shadows: black and violet smoke pours off him and his body is half seen;
##   * Death Order: a crossing crimson-black cut, a burst of dark and red light, cracks in the ground, a short shake.
## Units: metres (1 game unit = 1 cm).

const EVENTS := ["swift_dagger", "poison_blow", "shadows_start", "death_order"]
const VIOLET := Color(0.66, 0.34, 1.0)
const POISON := Color(0.45, 1.0, 0.35)
const BLOOD := Color(1.0, 0.12, 0.1)

var game: Node
var fx: Fx
var fire: FireFx
var _ghosts: Array = []                    # afterimages: {node, t, life}
var _slashes: Array = []                   # slash arcs: {node, mat, t, life}
var _feet := {}                            # Caziel's id -> shadow drift
var _shroud := {}                          # unit id -> smoke (Master of Shadows)
var _poison := {}                          # unit id -> green vapour
var _scan_i := 0

const GHOST_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(0.5, 0.25, 0.95, 1.0);
uniform float fade = 1.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	ALBEDO = col.rgb * (0.25 + f * 2.2);
	ALPHA = clamp((0.18 + f * 0.8) * fade, 0.0, 1.0);
}
"""

const SLASH_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.7, 0.35, 1.0, 1.0);
uniform float t = 0.0;
void fragment() {
	// a crescent: thick in the middle of the sweep, sharp at both ends, revealed along the arc as it plays
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float a = (atan(q.y, q.x) + 3.14159) / 6.28318;
	float band = smoothstep(0.62, 0.78, r) * (1.0 - smoothstep(0.86, 0.98, r));
	float sweep = smoothstep(0.08, 0.5, a) * (1.0 - smoothstep(0.5, 0.92, a));
	float shown = smoothstep(t * 1.2 - 0.2, t * 1.2, a);
	float hot = smoothstep(0.78, 0.84, r) * (1.0 - smoothstep(0.84, 0.9, r));
	float alpha = band * sweep * (1.0 - shown) * (1.0 - smoothstep(0.6, 1.0, t));
	ALBEDO = mix(col.rgb, vec3(1.0), hot * 0.6) * 3.0;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""

static var _ghost_shader: Shader
static var _slash_shader: Shader

static func _init_static() -> void:
	if _ghost_shader != null:
		return
	_ghost_shader = Shader.new()
	_ghost_shader.code = GHOST_CODE
	_slash_shader = Shader.new()
	_slash_shader.code = SLASH_CODE

## Dark smoke (Master of Shadows, the dagger's path): FireFx's smoke tinted black-violet.
static func shadow_smoke(radius: float, rate: float, size := 0.7, life := 1.2, rise := 0.6, density := 0.55) -> GPUParticles3D:
	var p := FireFx.smoke(radius, rate, size, life, rise, density)
	var q := p.draw_pass_1 as QuadMesh
	var m := (q.material as ShaderMaterial).duplicate() as ShaderMaterial
	m.set_shader_parameter("tint", Color(0.06, 0.02, 0.1))
	q.material = m
	return p

static func motes(radius: float, rate: float, col: Color, life := 0.9, rise := 0.5, size := 0.04) -> GPUParticles3D:
	return FireFx.embers(radius, rate, life, rise, size, col)

# ---- Events -------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	match String(e.t):
		"swift_dagger":
			_dagger(e)
		"poison_blow":
			_poison_blow(int(e.u), int(e.target))
		"shadows_start":
			var v := fx._view_of(int(e.u))
			if v and v.visible:
				var p := shadow_smoke(0.4, 80.0, 0.9, 0.8, 1.2, 0.7)
				p.one_shot = true
				p.explosiveness = 0.9
				add_child(p)
				p.global_position = v.global_position + Vector3(0, 0.8, 0)
				fire.timed(p, 0.1)
		"death_order":
			_execute(int(e.u), int(e.target))

## Swift Dagger: afterimages along the path, a violet streak, a violet burst where he stabs.
func _dagger(e: Dictionary) -> void:
	var from: Vector2 = e.from
	var to: Vector2 = e.to
	if not fx._seen(from) and not fx._seen(to):
		return
	var v := fx._view_of(int(e.u))
	var n := 5
	for i in n:
		var f := float(i + 1) / float(n + 1)
		var p := from.lerp(to, f)
		_ghost(v, fx.ground3(p), (to - from).angle(), 0.35 + f * 0.25, 0.75 * (1.0 - f * 0.4))
	# the streak: shadow smoke and violet motes laid along the path
	var path := Node3D.new()
	add_child(path)
	var steps := int(clampf(from.distance_to(to) / 120.0, 2.0, 9.0))
	for i in steps + 1:
		var p2 := from.lerp(to, float(i) / steps)
		var s := shadow_smoke(0.2, 30.0, 0.6, 0.7, 0.4, 0.6)
		s.one_shot = true
		s.explosiveness = 0.8
		path.add_child(s)
		s.global_position = fx.ground3(p2, 0.9)
		var mo := motes(0.15, 30.0, VIOLET, 0.6, 0.6)
		mo.one_shot = true
		mo.explosiveness = 0.8
		path.add_child(mo)
		mo.global_position = fx.ground3(p2, 1.0)
	fire.timed(path, 0.1)
	var at := fx._chest(int(e.target), 0.5)
	_slash(at, (to - from).angle(), VIOLET, 1.4, 0.32)
	fx.sparks(at, Vector3.UP, 10, Color(0.8, 0.55, 1.0), 4.5)
	fx.flash_light(at, VIOLET, 4.0, 4.0, 0.25)

## A frozen copy of Caziel's body in violet light that fades.
func _ghost(v: UnitView, at: Vector3, facing: float, delay: float, strength: float) -> void:
	if v == null or v.model == null:
		return
	_init_static()
	var g := v.model.duplicate() as Node3D
	# no animation: it keeps the pose it had when copied
	for ap: AnimationPlayer in g.find_children("*", "AnimationPlayer", true, false):
		ap.active = false
	var mat := ShaderMaterial.new()
	mat.shader = _ghost_shader
	mat.set_shader_parameter("col", Color(0.42, 0.2, 0.9))
	for gi: GeometryInstance3D in g.find_children("*", "GeometryInstance3D", true, false):
		gi.material_override = mat
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	g.global_position = at
	g.rotation.y = View.yaw(facing) + PI
	g.scale = v.model.scale
	_ghosts.append({"node": g, "mat": mat, "t": 0.0, "life": delay + 0.25, "k": strength})

func _slash(at: Vector3, angle: float, col: Color, size: float, life: float, tilt := 0.0) -> void:
	_init_static()
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _slash_shader
	m.set_shader_parameter("col", col)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	# face the camera, tilted so the cut runs across the body
	var cam: Camera3D = game.camera.cam if game.get("camera") != null else get_viewport().get_camera_3d()
	if cam:
		mi.look_at(cam.global_position, Vector3.UP)
		mi.rotate_object_local(Vector3.FORWARD, angle * 0.0 + tilt + randf_range(-0.5, 0.5))
	_slashes.append({"node": mi, "mat": m, "t": 0.0, "life": life})

func _poison_blow(src: int, target: int) -> void:
	var v := fx._view_of(target)
	if v == null or not v.visible:
		return
	var at := fx._chest(target, 0.5)
	_slash(at, 0.0, POISON, 1.2, 0.3, 0.9)
	var drops := motes(0.15, 40.0, POISON, 0.7, 1.2, 0.05)
	drops.one_shot = true
	drops.explosiveness = 0.9
	(drops.process_material as ParticleProcessMaterial).gravity = Vector3(0, -5.0, 0)
	add_child(drops)
	drops.global_position = at
	fire.timed(drops, 0.1)
	var _s := src

## Death Order: the execution.
func _execute(src: int, target: int) -> void:
	var v := fx._view_of(target)
	if v == null or not v.visible:
		return
	var at := fx._chest(target, 0.5)
	_slash(at, 0.0, BLOOD, 2.6, 0.45, 0.75)
	_slash(at, 0.0, Color(0.5, 0.1, 0.9), 2.6, 0.5, -0.75)
	var burst := shadow_smoke(0.3, 140.0, 1.3, 1.0, 2.2, 0.8)
	burst.one_shot = true
	burst.explosiveness = 0.95
	add_child(burst)
	burst.global_position = at
	fire.timed(burst, 0.1)
	var red := motes(0.3, 120.0, BLOOD, 0.8, 3.5, 0.07)
	red.one_shot = true
	red.explosiveness = 0.95
	add_child(red)
	red.global_position = at
	fire.timed(red, 0.1)
	var gp := View.to2(v.global_position)
	fx.crack(fx.ground3(gp), 1.6, Color(0.9, 0.1, 0.12), 2.5)
	fx.shockwave(fx.ground3(gp), 2.2, Color(0.8, 0.08, 0.1), 0.4, 0.2, 3.5)
	fx.flash_light(at, BLOOD, 7.0, 6.0, 0.35)
	fx._shake(gp, 0.12, 0.25)
	var _s := src

# ---- Every frame --------------------------------------------------------------------------------------------------------

func update(w: SimWorld, _alpha: float, dt: float) -> void:
	_scan_i += 1
	if _scan_i % 3 == 0:
		_scan(w)
	for i in range(_ghosts.size() - 1, -1, -1):
		var g: Dictionary = _ghosts[i]
		g.t = float(g.t) + dt
		var n: Node3D = View.live(g.node)
		if not is_instance_valid(n) or float(g.t) >= float(g.life):
			if is_instance_valid(n):
				n.queue_free()
			_ghosts.remove_at(i)
			continue
		(g.mat as ShaderMaterial).set_shader_parameter("fade", float(g.k) * (1.0 - float(g.t) / float(g.life)))
	for i in range(_slashes.size() - 1, -1, -1):
		var s: Dictionary = _slashes[i]
		s.t = float(s.t) + dt
		var sn: Node3D = View.live(s.node)
		if not is_instance_valid(sn) or float(s.t) >= float(s.life):
			if is_instance_valid(sn):
				sn.queue_free()
			_slashes.remove_at(i)
			continue
		(s.mat as ShaderMaterial).set_shader_parameter("t", float(s.t) / float(s.life))
	for store in [_feet, _shroud, _poison]:
		for id in store:
			var v := fx._view_of(int(id))
			var p: Node3D = View.live(store[id])
			if v and is_instance_valid(p):
				p.global_position = v.global_position + Vector3(0, 0.1 if store == _feet else 0.9, 0)
				p.visible = v.visible

func _scan(w: SimWorld) -> void:
	var want_feet := {}
	var want_shroud := {}
	var want_poison := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView):
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive:
			continue
		if String(u.def.get("model", "")) == "hero_caziel":
			want_feet[id] = true
			v.swing_lit = true
		for m in u.modifiers:
			if String(m.get("fx", "")) == "shadows":
				want_shroud[id] = true
	for d in w.status.dots:
		if String(d.key) == "sweet_poison" and float(d.until) > w.time:
			want_poison[int(d.t)] = true
	_sync(_feet, want_feet, func(_i): return shadow_smoke(0.25, 6.0, 0.5, 1.2, 0.25, 0.4))
	_sync(_shroud, want_shroud, func(_i): return _shroud_node())
	_sync(_poison, want_poison, func(_i): return FrosterFx.mist(0.25, 14.0, 0.5, 0.9, 0.5, 0.45, Color(0.4, 0.9, 0.3)))

func _shroud_node() -> Node3D:
	var n := Node3D.new()
	n.add_child(shadow_smoke(0.35, 34.0, 0.8, 1.1, 0.9, 0.6))
	n.add_child(motes(0.35, 14.0, VIOLET, 0.9, 0.6, 0.035))
	return n

func _sync(store: Dictionary, want: Dictionary, make: Callable) -> void:
	for id in store.keys():
		if not want.has(id):
			var n = store[id]
			if is_instance_valid(n):
				fire.timed(n, 0.0)
			store.erase(id)
	for id in want:
		if not store.has(id):
			var n: Node3D = make.call(int(id))
			add_child(n)
			store[id] = n

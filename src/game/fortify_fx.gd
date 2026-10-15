class_name FortifyFx
extends Node
## Fortify on the map: while a team's Fortify lasts, every one of its buildings stands in a shell of light.
##   Ancient Light: a warm gold shell with light rising through it, a beam of light from the sky and a turning halo
##   above the roof.
##   Black Sun: a dark violet shell with a crimson rim and slow swirling shadow, and a black sun with a crimson corona
##   hovering above the roof.
## Both fade in when Fortify is pressed and out as it ends. Rebuilt from the units' `glyph_until` every frame, so
## nothing outlives it. Splash from a Fortified tower: a ring of the team's colour where the shot burst.

const LIGHT_COL := Color(1.0, 0.86, 0.5)
const DARK_RIM := Color(0.95, 0.2, 0.32)
const DARK_IN := Color(0.16, 0.03, 0.24)
const FADE_IN := 0.35
const FADE_OUT := 0.6

var game: Node
var fx: Fx
var _shells := {}                          # unit id -> {root, mats: [ShaderMaterial], light, halo, born}
static var _shell_shader: Shader
static var _beam_shader: Shader

func frame(dt: float) -> void:
	var w: SimWorld = game.world
	var seen := {}
	for u in w.units:
		if not u.alive or not u.is_building() or w.time >= u.glyph_until:
			continue
		seen[u.id] = true
		var s: Dictionary = _shells.get(u.id, {})
		if s.is_empty():
			s = _make(u)
			_shells[u.id] = s
		var root: Node3D = s.root
		root.visible = u.team == game.player_team or w.vision.cell_visible(game.player_team, u.pos)
		s.age = float(s.age) + dt
		var k := minf(1.0, float(s.age) / FADE_IN) * clampf((u.glyph_until - w.time) / FADE_OUT, 0.0, 1.0)
		for m in s.mats:
			(m as ShaderMaterial).set_shader_parameter("fade", k)
		(s.light as OmniLight3D).light_energy = 2.2 * k
		var halo: Node3D = s.halo
		halo.rotation.y += dt * (0.8 if u.team == C_DAWN else -0.5)
	for id in _shells.keys():
		if not seen.has(id):
			(_shells[id].root as Node).queue_free()
			_shells.erase(id)

const C_DAWN := 0

## Fortify was pressed: a ring bursts out from every building of that team the player can see.
func on_glyph(e: Dictionary) -> void:
	var w: SimWorld = game.world
	var team := int(e.team)
	var col := LIGHT_COL if team == C_DAWN else DARK_RIM
	for u in w.units:
		if u.alive and u.is_building() and u.team == team and u.kind != SimConst.Kind.FOUNTAIN \
				and (team == game.player_team or w.vision.cell_visible(game.player_team, u.pos)):
			fx.shockwave(fx.ground3(u.pos), _radius(u) * 2.2, col, 0.7, 0.12, 2.5)

## A Fortified tower's splash: a quick ring of the team's colour, 300 across (3 m).
func on_splash(e: Dictionary) -> void:
	var p: Vector2 = e.pos
	if not game.world.vision.cell_visible(game.player_team, p):
		return
	var dawn := int(e.team) == C_DAWN
	fx.shockwave(fx.ground3(p), float(e.radius) / 100.0, LIGHT_COL if dawn else DARK_RIM, 0.32, 0.22, 3.0)

func _radius(u: SimUnit) -> float:
	return clampf(u.hull / 100.0 * 0.95 + 0.35, 1.2, 3.4)

func _height(u: SimUnit) -> float:
	var bv = game.views.get(u.id)
	return float(bv.bar_height) if bv is BuildingView else 5.0

func _make(u: SimUnit) -> Dictionary:
	var dawn := u.team == C_DAWN
	var r := _radius(u)
	var h := clampf(_height(u), 2.5, 12.0)
	var root := Node3D.new()
	add_child(root)
	root.global_position = fx.ground3(u.pos)
	var mats: Array = []
	# the shell: an upright ellipsoid from the ground to above the roof
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 48
	sm.rings = 24
	shell.mesh = sm
	var rad := r
	shell.scale = Vector3(rad, h * 0.56, rad)
	shell.position.y = h * 0.44
	var m := ShaderMaterial.new()
	m.shader = _shell()
	m.set_shader_parameter("dark", 0.0 if dawn else 1.0)
	m.set_shader_parameter("rim_col", LIGHT_COL if dawn else DARK_RIM)
	m.set_shader_parameter("in_col", Color(1.0, 0.95, 0.75) if dawn else DARK_IN)
	m.set_shader_parameter("fade", 0.0)
	m.render_priority = 4
	shell.material_override = m
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shell)
	mats.append(m)
	var top := h * 1.04 + 0.4
	var halo := Node3D.new()
	halo.position.y = top
	root.add_child(halo)
	if dawn:
		# a beam of light from the sky onto the building, and a gold halo turning over the roof
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = rad * 0.4
		cyl.bottom_radius = rad * 0.7
		cyl.height = 14.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		cyl.radial_segments = 32
		beam.mesh = cyl
		beam.position.y = 7.0
		var bm := ShaderMaterial.new()
		bm.shader = _beam()
		bm.set_shader_parameter("col", LIGHT_COL)
		bm.set_shader_parameter("fade", 0.0)
		bm.render_priority = 5
		beam.material_override = bm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)
		mats.append(bm)
		var ring := _torus(rad * 0.42, 0.05, fx._glow(Color(1.0, 0.9, 0.6), 6.0))
		halo.add_child(ring)
		for i in 6:
			var a := i * TAU / 6.0
			var mote := fx._sphere(0.07, fx._glow(Color(1.0, 0.95, 0.8), 8.0))
			mote.position = Vector3(cos(a), 0.0, sin(a)) * rad * 0.42
			halo.add_child(mote)
	else:
		# a black sun with a crimson corona over the roof
		var disc := fx._sphere(rad * 0.22, fx._solid(Color(0.02, 0.0, 0.03), 1.0))
		halo.add_child(disc)
		var corona := _torus(rad * 0.25, 0.06, fx._glow(DARK_RIM, 6.0))
		corona.rotation.x = PI * 0.5
		halo.add_child(corona)
		var outer := _torus(rad * 0.34, 0.025, fx._glow(Color(0.7, 0.2, 0.9), 4.0))
		outer.rotation.x = PI * 0.5
		halo.add_child(outer)
	var l := OmniLight3D.new()
	l.light_color = LIGHT_COL if dawn else Color(0.85, 0.2, 0.45)
	l.light_energy = 0.0
	l.omni_range = rad * 3.0
	l.shadow_enabled = false
	l.position.y = h * 0.6
	root.add_child(l)
	return {"root": root, "mats": mats, "light": l, "halo": halo, "age": 0.0}

func _torus(radius: float, thick: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - thick
	tm.outer_radius = radius + thick
	tm.rings = 48
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## The shell: clear in the middle and bright at the rim. Light: additive gold with light rising through it. Dark: a
## violet tint with a crimson rim and slow swirling shadow (alpha blended, so it darkens what is inside).
static func _shell() -> Shader:
	if _shell_shader == null:
		_shell_shader = Shader.new()
		_shell_shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform float dark = 0.0;
uniform vec4 rim_col : source_color;
uniform vec4 in_col : source_color;
uniform float fade = 0.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float ang = atan(lp.z, lp.x);
	if (dark < 0.5) {
		// a thin bright rim, faint threads of light rising through a clear middle
		float edge = pow(rim, 1.6);
		float rays = smoothstep(0.82, 1.0, sin(ang * 12.0 + sin(ang * 3.0) * 2.0)) * smoothstep(0.0, 0.6, fract(lp.y * 0.7 - TIME * 0.55));
		ALBEDO = mix(in_col.rgb, rim_col.rgb, edge) * (1.2 + edge * 1.6);
		ALPHA = clamp(edge * 0.75 + rays * 0.22, 0.0, 1.0) * fade;
	} else {
		// a shadowy violet veil with slow swirls and a thin crimson rim
		float edge = pow(rim, 2.2);
		float swirl = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin(ang * 4.0 + lp.y * 2.5 - TIME * 1.1));
		ALBEDO = mix(in_col.rgb * (0.35 + 0.5 * swirl), rim_col.rgb * 1.8, edge);
		ALPHA = clamp(0.1 + swirl * 0.1 + edge * 0.8, 0.0, 1.0) * fade;
	}
}
"""
	return _shell_shader

## The beam from the sky: brightest at the foot, fading upward, with slow bands sliding down.
static func _beam() -> Shader:
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color;
uniform float fade = 0.0;
void fragment() {
	float up = UV.y;
	float edge = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float bands = 0.75 + 0.25 * sin(up * 30.0 + TIME * 4.0);
	ALBEDO = col.rgb * (1.0 - edge) * bands * pow(up, 2.0) * 0.45 * fade;
}
"""
	return _beam_shader

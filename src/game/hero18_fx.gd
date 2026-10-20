class_name Hero18Fx
extends Node
## Visuals for the five heroes of hero_ideas.txt (run 2026-10-18 f): Airah, Burak, Ser Emelrich, Feran Mock and
## Ghorman. One-shot effects come from their sim events; lasting things (Gusts, Wind Walls, Hurricanes, thrown axes,
## knives, Joke Boxes, wind-up warnings, auras) are drawn straight from the sim's own state every frame, so they can
## never be left behind. Units: metres (1 game unit = 1 cm).
##   Airah: a Gust is a rushing knot of pale wind with streaks behind it; Tailwind wraps the unit in spiralling
##   streaks; the Wind Wall is a curtain of rising wind; a Hurricane is a spinning funnel over a swirl on the ground,
##   leaves whirling in it, thrown out in a ring of wind when it ends.
##   Burak: his thrown axe spins through the air, sticks in what it hits (a tree, the ground, an enemy) and flashes
##   when he takes it back; Rage glows red about him (hotter as it fills, smoke off him when full); Reckless Swing
##   trails red from his axes; Berserk wraps him in fire.
##   Ser Emelrich: the wind-ups are red warnings on the ground for everyone (the line or cone fills as the blow
##   comes); his cuts crack the ground and throw sparks; Steel Stance is a gold ward in front of him.
##   Feran: spinning knives, a gift box with a lit fuse that pops in confetti and coloured smoke, puffs of smoke where
##   units trade places; Pie leaves cream on the face, dizzy units have birds circling their heads.
##   Ghorman: green spirit light on his beasts, a beam when he tames one, a roar that shakes the ground, gold light
##   for the Blessing; Beast Form's body swap is the unit view's form (ModelCatalog "forms").

const EVENTS := ["gust_hit", "tailwind", "wind_wall_block", "hurricane", "hurricane_end", "axe_throw", "axe_hit",
	"axe_stick", "axe_back", "axe_leap", "axe_leap_land", "reckless_swing", "unstoppable", "burak_berserk",
	"berserk_return", "berserk_cleared", "windup", "windup_end", "overhead_cut", "giant_swing", "sweep",
	"knife_hit", "joke_box", "joke_box_pop", "swap", "swap_mark", "shuffle", "tame", "beast_released", "roar",
	"pack_heal", "blessing", "beast_form", "maul"]

const WIND := Color(0.82, 1.0, 0.95)
const WIND_DEEP := Color(0.35, 0.85, 0.75)
const RAGE := Color(1.0, 0.18, 0.08)
const GOLD := Color(1.0, 0.82, 0.38)
const WARN := Color(1.0, 0.16, 0.08)
const SPIRIT := Color(0.45, 1.0, 0.45)
const CONFETTI := [Color(1.0, 0.3, 0.55), Color(0.35, 0.85, 1.0), Color(1.0, 0.88, 0.25), Color(0.5, 1.0, 0.45),
	Color(0.8, 0.45, 1.0)]

var game: Node
var fx: Fx
var fire: FireFx

var _gusts := {}                            # gust seq -> {node, trail}
var _walls := {}                            # wall seq -> {node, mat, until}
var _storms := {}                           # hurricane seq -> {node, disc_mat, funnel_mat, leaves}
var _axes := {}                             # axe id -> {node, spin}
var _knives := {}                           # knife seq -> {node}
var _boxes := {}                            # joke box seq -> {node, fuse}
var _warns := {}                            # wind-up seq -> {node, mat, start, dur, u}
var _auras := {}                            # unit id ":" kind -> node
var _timed: Array = []                      # {node, t, life, mat, grow, spin}
var _scan_i := 0

# ---- Shaders --------------------------------------------------------------------------------------------------------

## The wind-up warning on the ground: a line (shape 0: UV.x across, UV.y along) or a cone (shape 1: the quad is
## centred on the hero, UV.y forward); a red edge and a fill that creeps out as the blow comes.
const WARN_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.16, 0.08, 1.0);
uniform float fill = 0.0;
uniform float fade = 1.0;
uniform float shape = 0.0;
uniform float half_angle = 0.87;
void fragment() {
	float inside = 0.0;
	float edge = 0.0;
	float along = 0.0;
	if (shape < 0.5) {
		vec2 q = UV;
		along = q.y;
		float ex = min(q.x, 1.0 - q.x);
		float ey = min(q.y, 1.0 - q.y);
		inside = 1.0;
		edge = 1.0 - smoothstep(0.0, 0.06, min(ex, ey * 0.25));
	} else {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float a = abs(atan(q.x, q.y));
		inside = step(r, 1.0) * step(a, half_angle);
		along = r;
		float er = 1.0 - smoothstep(0.0, 0.03, 1.0 - r);
		float ea = 1.0 - smoothstep(0.0, 0.035, (half_angle - a) * r);
		edge = max(er, ea) * inside;
	}
	float filled = step(along, fill) * inside;
	float front = (1.0 - smoothstep(0.0, 0.04, abs(along - fill))) * inside;
	ALBEDO = col.rgb * (1.2 + front * 1.5);
	ALPHA = clamp((inside * 0.14 + filled * 0.3 + edge * 0.8 + front * 0.6) * fade, 0.0, 1.0);
}
"""

## The Wind Wall: a curtain of streaks rising and drifting, soft at its ends and top.
const WALL_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.82, 1.0, 0.95, 1.0);
uniform float fade = 1.0;
float h(float x) { return fract(sin(x * 127.1) * 43758.5453); }
void fragment() {
	float x = UV.x * 40.0;
	float lane = floor(x);
	float sp = 0.6 + h(lane) * 1.2;
	float y = fract(UV.y * 2.0 + TIME * sp + h(lane + 3.0));
	float streak = smoothstep(0.0, 0.3, y) * (1.0 - smoothstep(0.3, 0.75, y));
	float thin = 1.0 - smoothstep(0.0, 0.35, abs(fract(x) - 0.5));
	float ends = smoothstep(0.0, 0.08, UV.x) * smoothstep(0.0, 0.08, 1.0 - UV.x);
	float top = 1.0 - smoothstep(0.55, 1.0, 1.0 - UV.y);
	float base = 0.10 + 0.08 * sin(UV.x * 30.0 + TIME * 3.0);
	ALBEDO = col.rgb * 1.6;
	ALPHA = clamp((streak * thin * 0.75 + base) * ends * top * fade, 0.0, 1.0);
}
"""

## A swirl of wind: on the ground under a Hurricane (disc) and on its funnel (a cylinder's side, UV.x round it).
const SWIRL_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.82, 1.0, 0.95, 1.0);
uniform float fade = 1.0;
uniform float disc = 1.0;
uniform float strength = 0.4;
void fragment() {
	float a;
	float r;
	if (disc > 0.5) {
		vec2 q = UV * 2.0 - 1.0;
		r = length(q);
		a = atan(q.y, q.x);
	} else {
		a = UV.x * 6.2832;
		r = UV.y;
	}
	float arms = sin(a * 5.0 + log(max(r, 0.03)) * 6.0 + TIME * 7.0);
	float band = smoothstep(0.2, 1.0, arms);
	float shape = disc > 0.5 ? smoothstep(1.0, 0.6, r) * smoothstep(0.02, 0.2, r) : smoothstep(0.0, 0.15, r) * smoothstep(1.0, 0.75, r);
	ALBEDO = col.rgb * (0.8 + band * 0.6);
	ALPHA = clamp((band * strength + strength * 0.15) * shape * fade, 0.0, 1.0);
}
"""

## A flash on the ground in the shape of a cut (a line or a cone), white-gold fading out from its middle.
const SLASH_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float fade = 1.0;
uniform float shape = 0.0;
uniform float half_angle = 0.87;
uniform float inner = 0.0;
void fragment() {
	float inside;
	float k;
	if (shape < 0.5) {
		inside = 1.0;
		k = 1.0 - abs(UV.x - 0.5) * 2.0;
	} else {
		vec2 q = UV * 2.0 - 1.0;
		float r = length(q);
		float a = abs(atan(q.x, q.y));
		inside = step(r, 1.0) * step(a, half_angle) * step(inner, r);
		k = smoothstep(inner, 1.0, r) * (1.0 - a / max(half_angle, 0.01) * 0.6);
	}
	ALBEDO = col.rgb * (1.0 + k * 2.0);
	ALPHA = clamp(inside * k * 0.85 * fade, 0.0, 1.0);
}
"""

static var _shaders := {}

func _mat(kind: String) -> ShaderMaterial:
	if _shaders.is_empty():
		for k in ["warn", "wall", "swirl", "slash"]:
			var s := Shader.new()
			s.code = {"warn": WARN_CODE, "wall": WALL_CODE, "swirl": SWIRL_CODE, "slash": SLASH_CODE}[k]
			_shaders[k] = s
	var m := ShaderMaterial.new()
	m.shader = _shaders[kind]
	return m

## A flat quad on the ground, `size` metres (x across, y along), its local +z along sim direction `dir`.
func _ground_quad(centre: Vector2, size: Vector2, dir: Vector2, mat: Material, lift := 0.06) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = fx.ground3(centre, lift)
	mi.rotation.y = atan2(dir.x, -dir.y)
	return mi

func _timed_add(node: Node3D, life: float, mat: ShaderMaterial = null, grow := 0.0, spin := 0.0) -> void:
	_timed.append({"node": node, "t": 0.0, "life": life, "mat": mat, "grow": grow, "spin": spin,
		"scale": node.scale})

func _puff(at: Vector3, col: Color, size := 1.0) -> void:
	var sm := FireFx.smoke(0.35 * size, 40.0 * size, 0.9 * size, 0.9, 0.6, 0.55)
	sm.one_shot = true
	sm.explosiveness = 0.9
	add_child(sm)
	sm.global_position = at
	fire.timed(sm, 1.2)
	var e := FireFx.embers(0.3 * size, 60.0 * size, 0.7, 1.5, 0.05, col)
	e.one_shot = true
	e.explosiveness = 0.95
	add_child(e)
	e.global_position = at
	fire.timed(e, 0.9)

func _confetti(at: Vector3, n: int, speed := 4.0) -> void:
	for k in n:
		var c: Color = CONFETTI[k % CONFETTI.size()]
		fx.debris(at, 1, c, speed, 0.35, "chip")

# ---- Events -----------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	var w: SimWorld = game.world
	match String(e.t):
		"gust_hit":
			var gu: SimUnit = w.get_unit(int(e.u))
			if gu and fx._seen(gu.pos):
				_puff(fx._chest(gu.id, 0.5), WIND, 0.7)
		"tailwind":
			var tu: SimUnit = w.get_unit(int(e.target))
			if tu and fx._seen(tu.pos):
				fx.shockwave(fx.ground3(tu.pos, 0.05), 1.4, WIND_DEEP, 0.4, 0.12, 2.0)
				_puff(fx._chest(tu.id, 0.4), WIND, 0.8)
		"wind_wall_block":
			var bp: Vector2 = e.pos
			if fx._seen(bp):
				_puff(fx.ground3(bp, 1.3), WIND, 0.6)
				fx.sparks(fx.ground3(bp, 1.3), Vector3.UP, 6, WIND, 2.5)
		"hurricane":
			var hp: Vector2 = e.pos
			fx.shockwave(fx.ground3(hp, 0.05), float(e.radius) * View.S, WIND_DEEP, 0.6, 0.3, 2.5)
		"hurricane_end":
			var ep: Vector2 = e.pos
			var r := float(e.radius) * View.S
			fx.shockwave(fx.ground3(ep, 0.1), r * 1.6, WIND, 0.7, 0.35, 3.0)
			fx.force_wall(fx.ground3(ep), r * 0.4, r * 1.5, 2.2, WIND_DEEP, 0.5)
			if fx._seen(ep):
				fx._shake(ep, 0.25, 0.3)
		"axe_throw":
			var au: SimUnit = w.get_unit(int(e.u))
			if au and fx._seen(au.pos):
				fx.sparks(fx._chest(au.id, 0.6), Vector3.UP, 4, Color(1.0, 0.8, 0.5), 2.0)
		"axe_hit":
			var hu: SimUnit = w.get_unit(int(e.target))
			if hu and fx._seen(hu.pos):
				var c := fx._chest(hu.id, 0.55)
				fx.impact(c, Color(1.0, 0.75, 0.45), 0.45)
				fx.sparks(c, Vector3.UP, 10, Color(1.0, 0.85, 0.55), 4.0)
				var hv := fx._view_of(hu.id)
				if hv:
					hv.flash()
		"axe_stick":
			var sp: Vector2 = e.pos
			if fx._seen(sp):
				fx.debris(fx.ground3(sp, 0.8), 5, Color(0.45, 0.32, 0.2) if String(e.what) == "tree" else Color(0.4, 0.38, 0.36),
					3.0, 0.6)
		"axe_back":
			var bu: SimUnit = w.get_unit(int(e.u))
			if bu and fx._seen(bu.pos):
				fx.flash_light(fx._chest(bu.id, 0.6), Color(1.0, 0.7, 0.4), 2.0, 3.0, 0.2)
		"axe_leap":
			var lu: SimUnit = w.get_unit(int(e.u))
			if lu and fx._seen(lu.pos):
				fx.debris(fx.ground3(lu.pos, 0.1), 6, Color(0.45, 0.38, 0.3), 3.0, 0.7)
				fx.shockwave(fx.ground3(lu.pos, 0.05), 1.2, Color(0.7, 0.55, 0.4), 0.3, 0.12, 1.5)
		"axe_leap_land":
			var lp: Vector2 = e.pos
			if fx._seen(lp):
				fx.shockwave(fx.ground3(lp, 0.05), 1.8, RAGE, 0.35, 0.18, 2.5)
				fx.debris(fx.ground3(lp, 0.1), 8, Color(0.45, 0.38, 0.3), 4.0, 0.8)
				fx._shake(lp, 0.15, 0.2)
		"reckless_swing":
			var ru: SimUnit = w.get_unit(int(e.u))
			if ru and fx._seen(ru.pos):
				fire.burst(fx._chest(ru.id, 0.5), 0.5, "blood", 0.6)
				fx.flash_light(fx._chest(ru.id, 0.6), RAGE, 3.0, 4.0, 0.25)
		"unstoppable":
			var uu: SimUnit = w.get_unit(int(e.u))
			if uu and fx._seen(uu.pos):
				var c2 := fx._chest(uu.id, 0.55)
				fx.sparks(c2, Vector3.UP, 18, Color(1.0, 0.85, 0.3), 5.0)
				fx.shockwave(fx.ground3(uu.pos, 0.05), 2.2, Color(1.0, 0.6, 0.2), 0.4, 0.2, 3.0)
				fx.flash_light(c2, Color(1.0, 0.7, 0.3), 5.0, 6.0, 0.3)
				fx.debris(c2, 6, Color(0.6, 0.6, 0.65), 4.0, 0.5, "chip")
		"burak_berserk":
			var ku: SimUnit = w.get_unit(int(e.u))
			if ku and fx._seen(ku.pos):
				fire.burst(fx._chest(ku.id, 0.45), 1.0, "fire", 1.3)
				fx.shockwave(fx.ground3(ku.pos, 0.05), 3.0, RAGE, 0.5, 0.25, 3.0)
				fx._shake(ku.pos, 0.2, 0.3)
		"berserk_return":
			var ru2: SimUnit = w.get_unit(int(e.u))
			if ru2 and fx._seen(ru2.pos):
				fire.burst(fx._chest(ru2.id, 0.5), 0.45, "blood", 0.5)
		"berserk_cleared":
			var cu: SimUnit = w.get_unit(int(e.u))
			if cu and fx._seen(cu.pos):
				fx.flash_light(fx._chest(cu.id, 0.6), GOLD, 4.0, 5.0, 0.4)
				fx.sparks(fx._chest(cu.id, 0.6), Vector3.UP, 12, GOLD, 3.0)
		"windup":
			_windup(e)
		"windup_end":
			var wr: Dictionary = _warns.get(int(e.seq), {})
			if not wr.is_empty():
				_timed_add(wr.node, 0.25, wr.mat)
				_warns.erase(int(e.seq))
		"overhead_cut":
			var f: Vector2 = e.from
			var t: Vector2 = e.to
			var d := (t - f).normalized()
			var sm := _mat("slash")
			sm.set_shader_parameter("shape", 0.0)
			var q := _ground_quad((f + t) * 0.5, Vector2(float(e.width) * View.S, f.distance_to(t) * View.S), d, sm, 0.08)
			_timed_add(q, 0.45, sm)
			if fx._seen(t):
				fx.crack(fx.ground3(f.lerp(t, 0.55)), f.distance_to(t) * View.S * 0.45, GOLD, 2.5)
				fx.debris(fx.ground3(f.lerp(t, 0.4), 0.1), 10, Color(0.45, 0.4, 0.35), 4.0, 0.8)
				fx.sparks(fx.ground3(f.lerp(t, 0.35), 0.2), Vector3.UP, 14, GOLD, 4.5)
				fx.flash_light(fx.ground3(f.lerp(t, 0.4), 1.0), GOLD, 5.0, 6.0, 0.25)
				fx._shake(f, 0.3, 0.3)
			for id in e.get("hits", []):
				fx.impact(fx._chest(int(id), 0.5), GOLD, 0.4)
		"giant_swing":
			var gp: Vector2 = e.pos
			var dist := float(e.distance)
			var sm2 := _mat("slash")
			sm2.set_shader_parameter("shape", 1.0)
			sm2.set_shader_parameter("half_angle", deg_to_rad(float(e.angle)) * 0.5)
			sm2.set_shader_parameter("inner", 0.15)
			var q2 := _ground_quad(gp, Vector2(dist, dist) * 2.0 * View.S, e.dir, sm2, 0.09)
			_timed_add(q2, 0.55, sm2)
			if fx._seen(gp):
				var dv: Vector2 = e.dir
				fx.crack(fx.ground3(gp + dv * dist * 0.5), dist * View.S * 0.4, GOLD, 3.0)
				for k in 5:
					var ang := deg_to_rad(float(e.angle)) * (float(k) / 4.0 - 0.5)
					var at := gp + dv.rotated(ang) * dist * 0.6
					fx.debris(fx.ground3(at, 0.1), 4, Color(0.45, 0.4, 0.35), 4.5, 0.8)
				fx.flash_light(fx.ground3(gp + dv * 200.0, 1.2), GOLD, 7.0, 9.0, 0.35)
				fx._shake(gp, 0.75 if not bool(e.back) else 0.3, 0.5)
				if not bool(e.back):
					# the full blow: a ring of force across the cone and a burst of sparks where the blade bites
					fx.shockwave(fx.ground3(gp + dv * dist * 0.35, 0.05), dist * View.S * 0.55, GOLD, 0.55, 0.22, 3.0)
					fx.sparks(fx.ground3(gp + dv * 150.0, 0.3), Vector3.UP, 28, GOLD, 6.0)
			for id in e.get("hits", []):
				fx.impact(fx._chest(int(id), 0.5), GOLD, 0.5)
		"sweep":
			var sp2: Vector2 = e.pos
			var r2 := float(e.radius)
			var sm3 := _mat("slash")
			sm3.set_shader_parameter("shape", 1.0)
			sm3.set_shader_parameter("half_angle", PI * 0.5)
			sm3.set_shader_parameter("inner", 0.55)
			var q3 := _ground_quad(sp2, Vector2(r2, r2) * 2.0 * View.S, e.dir, sm3, 1.0)
			_timed_add(q3, 0.35, sm3, 0.0, 0.0)
			for id in e.get("hits", []):
				var c3 := fx._chest(int(id), 0.5)
				fx.impact(c3, GOLD, 0.35)
				fx.sparks(c3, Vector3.UP, 6, GOLD, 3.0)
		"knife_hit":
			var kp: Vector2 = e.pos
			if fx._seen(kp):
				fx.sparks(fx._chest(int(e.u), 0.55), Vector3.UP, 4, Color(0.9, 0.9, 1.0), 2.5)
		"joke_box":
			pass                                       # the box itself is drawn from the sim's effects
		"joke_box_pop":
			var jp: Vector2 = e.pos
			if fx._seen(jp):
				var at2 := fx.ground3(jp, 0.4)
				_confetti(at2, 24, 5.0)
				for k in 4:
					_puff(at2 + Vector3(randf_range(-0.8, 0.8), 0.2, randf_range(-0.8, 0.8)), CONFETTI[k], 1.1)
				fx.flash_light(at2 + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.6), 4.0, 6.0, 0.3)
				fx.shockwave(fx.ground3(jp, 0.05), float(e.radius) * View.S, Color(1.0, 0.5, 0.8), 0.4, 0.15, 2.0)
				var pr: Dictionary = e.get("pranks", {})
				for id in pr:
					var pc := fx._chest(int(id), 0.8)
					for p in pr[id]:
						match String(p):
							"pie":
								fx.debris(pc, 5, Color(1.0, 0.96, 0.85), 2.0, 0.45, "chip")
							"confetti":
								_confetti(pc, 6, 2.5)
							"glue":
								fx.debris(fx._chest(int(id), 0.1), 4, Color(0.75, 0.9, 0.3), 1.5, 0.5, "chip")
		"swap":
			for k in ["pos_a", "pos_b"]:
				var p2: Vector2 = e[k]
				if fx._seen(p2):
					_puff(fx.ground3(p2, 0.9), CONFETTI[1 if k == "pos_a" else 0], 1.2)
					fx.sparks(fx.ground3(p2, 1.2), Vector3.UP, 8, Color(1.0, 0.9, 0.4), 3.0)
		"swap_mark":
			var mu: SimUnit = w.get_unit(int(e.target))
			if mu:
				_puff(fx._chest(mu.id, 0.5), CONFETTI[4], 0.6)
		"shuffle":
			var shp: Vector2 = e.pos
			fx.shockwave(fx.ground3(shp, 0.05), float(e.radius) * View.S, Color(0.85, 0.45, 1.0), 0.6, 0.25, 2.5)
			if fx._seen(shp):
				_confetti(fx.ground3(shp, 0.5), 20, 6.0)
			for mv in e.get("moves", []):
				var mp: Vector2 = mv[1]
				if fx._seen(mp):
					_puff(fx.ground3(mp, 0.9), CONFETTI[int(mv[0]) % CONFETTI.size()], 1.0)
		"tame":
			var gu2: SimUnit = w.get_unit(int(e.u))
			var tu2: SimUnit = w.get_unit(int(e.target))
			if gu2 and tu2 and fx._seen(tu2.pos):
				fx.lightning(fx._chest(gu2.id, 0.6), fx._chest(tu2.id, 0.55), SPIRIT, 0.5, 0.08, 14)
				fire.burst(fx._chest(tu2.id, 0.4), 0.6, "spirit", 0.5)
				fx.flash_light(fx._chest(tu2.id, 0.6), SPIRIT, 4.0, 5.0, 0.4)
		"beast_released":
			var ru3: SimUnit = w.get_unit(int(e.target))
			if ru3 and fx._seen(ru3.pos):
				_puff(fx._chest(ru3.id, 0.4), SPIRIT, 0.8)
		"roar":
			var rp: Vector2 = e.pos
			fx.shockwave(fx.ground3(rp, 0.05), float(e.radius) * View.S, Color(0.95, 0.75, 0.4), 0.55, 0.3, 2.5)
			fx.force_wall(fx.ground3(rp), 0.4, float(e.radius) * View.S, 1.6, Color(0.8, 0.6, 0.3), 0.45)
			if fx._seen(rp):
				fx.debris(fx.ground3(rp, 0.1), 8, Color(0.45, 0.38, 0.3), 4.0, 0.7)
				fx._shake(rp, 0.3, 0.35)
			for id in e.get("beasts", []):
				fire.burst(fx._chest(int(id), 0.4), 0.35, "spirit", 0.4)
		"pack_heal":
			var pu: SimUnit = w.get_unit(int(e.u))
			if pu and fx._seen(pu.pos):
				fx.flash_light(fx._chest(pu.id, 0.6), SPIRIT, 3.0, 4.0, 0.4)
				var up := FireFx.embers(0.5, 50.0, 1.0, 1.6, 0.05, SPIRIT)
				up.one_shot = true
				up.explosiveness = 0.8
				add_child(up)
				up.global_position = fx.ground3(pu.pos, 0.2)
				fire.timed(up, 1.2)
		"blessing":
			var bt: SimUnit = w.get_unit(int(e.target))
			if bt and fx._seen(bt.pos):
				var c4 := fx._chest(bt.id, 0.5)
				fx.flash_light(c4, GOLD, 5.0, 6.0, 0.5)
				fire.burst(c4, 0.6, "holy", 0.7)
				fx.shockwave(fx.ground3(bt.pos, 0.05), 1.5, GOLD, 0.5, 0.15, 2.5)
		"beast_form":
			var fu: SimUnit = w.get_unit(int(e.u))
			if fu and fx._seen(fu.pos):
				fx.shockwave(fx.ground3(fu.pos, 0.05), 4.0, Color(0.9, 0.7, 0.35), 0.7, 0.35, 3.5)
				fx.debris(fx.ground3(fu.pos, 0.2), 14, Color(0.5, 0.36, 0.2), 5.0, 0.9)
				fire.burst(fx._chest(fu.id, 0.5), 1.0, "holy", 1.0)
				fx._shake(fu.pos, 0.4, 0.45)
		"maul":
			var mt: SimUnit = w.get_unit(int(e.target))
			if mt and fx._seen(mt.pos):
				var c5 := fx._chest(mt.id, 0.5)
				fx.impact(c5, Color(1.0, 0.55, 0.3), 0.6)
				fx.sparks(c5, Vector3.UP, 10, Color(1.0, 0.6, 0.3), 4.0)
				fx.debris(fx.ground3(mt.pos, 0.1), 5, Color(0.45, 0.38, 0.3), 3.0, 0.6)

## A wind-up: the red warning on the ground (everyone sees it), filling until the blow (main.gd times the hero's
## clip so the blow lands as the wind-up ends).
func _windup(e: Dictionary) -> void:
	var w: SimWorld = game.world
	var from: Vector2 = e.from
	var dir: Vector2 = e.dir
	var dist := float(e.distance)
	var m := _mat("warn")
	var node: MeshInstance3D
	if String(e.ability) == "overhead_cut":
		m.set_shader_parameter("shape", 0.0)
		node = _ground_quad(from + dir * dist * 0.5, Vector2(float(e.width), dist) * View.S, dir, m, 0.1)
	else:
		m.set_shader_parameter("shape", 1.0)
		m.set_shader_parameter("half_angle", deg_to_rad(float(e.angle)) * 0.5)
		node = _ground_quad(from, Vector2(dist, dist) * 2.0 * View.S, dir, m, 0.1)
	_warns[int(e.seq)] = {"node": node, "mat": m, "start": w.time, "dur": float(e.dur), "u": int(e.u)}

# ---- Per frame -------------------------------------------------------------------------------------------------------

func update(w: SimWorld, _alpha: float, dt: float) -> void:
	_scan_i += 1
	if _scan_i % 4 == 0:
		_scan(w)
	for i in range(_timed.size() - 1, -1, -1):
		var t: Dictionary = _timed[i]
		t.t = float(t.t) + dt
		var n: Node3D = View.live(t.node)
		if n == null or float(t.t) >= float(t.life):
			if n != null:
				n.queue_free()
			_timed.remove_at(i)
			continue
		var k := float(t.t) / float(t.life)
		var mat: ShaderMaterial = t.mat
		if mat:
			mat.set_shader_parameter("fade", clampf(1.0 - k, 0.0, 1.0))
		if float(t.grow) > 0.0:
			n.scale = (t.scale as Vector3) * (1.0 + k * float(t.grow))
		if float(t.spin) != 0.0:
			n.rotation.y += float(t.spin) * dt
	_update_warns(w)
	_update_effects(w, dt)
	_update_axes(w, dt)
	_follow_auras(w)

func _update_warns(w: SimWorld) -> void:
	for seq in _warns.keys():
		var wr: Dictionary = _warns[seq]
		var u: SimUnit = w.get_unit(int(wr.u))
		var n: Node3D = View.live(wr.node)
		if n == null or u == null or not u.alive or u.channel.is_empty() or int(u.channel.get("seq", -1)) != int(seq):
			if n != null:
				_timed_add(n, 0.2, wr.mat)
			_warns.erase(seq)
			continue
		var k := clampf((w.time - float(wr.start)) / maxf(0.05, float(wr.dur)), 0.0, 1.0)
		(wr.mat as ShaderMaterial).set_shader_parameter("fill", k)

## Gusts, Wind Walls, Hurricanes, knives and Joke Boxes, from the sim's live effects.
func _update_effects(w: SimWorld, dt: float) -> void:
	var seen_g := {}
	var seen_w := {}
	var seen_h := {}
	var seen_k := {}
	var seen_b := {}
	for e in w.effects:
		match String(e.get("kind", "")):
			"gust":
				seen_g[int(e.seq)] = true
				_gust(e, dt)
			"wind_wall":
				seen_w[int(e.seq)] = true
				if not _walls.has(int(e.seq)):
					_walls[int(e.seq)] = _make_wall(e)
				var wl: Dictionary = _walls[int(e.seq)]
				var left := float(e.until) - w.time
				(wl.mat as ShaderMaterial).set_shader_parameter("fade", clampf(minf(left / 0.4, 1.0), 0.0, 1.0))
				var wn: Node3D = View.live(wl.node)
				if wn:
					wn.visible = fx._seen(e.pos)
			"hurricane":
				seen_h[int(e.seq)] = true
				if not _storms.has(int(e.seq)):
					_storms[int(e.seq)] = _make_storm(e)
				var st: Dictionary = _storms[int(e.seq)]
				var sn: Node3D = View.live(st.node)
				if sn:
					sn.visible = fx._seen(e.pos)
					var fun: Node3D = View.live(st.funnel)
					if fun:
						fun.rotation.y += dt * 3.0
			"knife":
				seen_k[int(e.seq)] = true
				if not _knives.has(int(e.seq)):
					_knives[int(e.seq)] = _make_knife()
				var kn: Node3D = View.live(_knives[int(e.seq)])
				if kn:
					var p: Vector2 = e.pos
					kn.global_position = fx.ground3(p, 1.1)
					var d: Vector2 = e.dir
					kn.rotation = Vector3(0, atan2(d.x, -d.y), 0)
					(kn.get_child(0) as Node3D).rotation.x += dt * 25.0
					kn.visible = fx._seen(p)
			"joke_box":
				seen_b[int(e.seq)] = true
				if not _boxes.has(int(e.seq)):
					_boxes[int(e.seq)] = _make_box(e)
				var bx: Dictionary = _boxes[int(e.seq)]
				var bn: Node3D = View.live(bx.node)
				if bn:
					bn.visible = fx._seen(e.pos)
					var land := float(e.pop_at) - float(SimData.ability("joke_box").values.fuse[0])
					var from: Vector3 = bx.from
					var to := fx.ground3(e.pos, 0.0)
					var k := clampf(1.0 - (land - w.time) / 0.35, 0.0, 1.0)
					bn.global_position = from.lerp(to, k) + Vector3(0, sin(k * PI) * 2.0, 0)
					bn.rotation.y += dt * (8.0 if k < 1.0 else 0.0)
					if k >= 1.0:
						bn.scale = Vector3.ONE * (1.0 + 0.12 * sin(w.time * 30.0))
	_drop(_gusts, seen_g, "trail")
	_drop(_walls, seen_w, "")
	_drop(_storms, seen_h, "")
	_drop(_knives, seen_k, "")
	_drop(_boxes, seen_b, "")

func _drop(d: Dictionary, seen: Dictionary, trail_key: String) -> void:
	for k in d.keys():
		if seen.has(k):
			continue
		var v = d[k]
		var n: Node3D = View.live(v.node if v is Dictionary else v)
		if v is Dictionary and trail_key != "" and v.has(trail_key) and is_instance_valid(v[trail_key]):
			(v[trail_key] as Trail3D).stop()
		if n != null:
			fire.timed(n, 0.0)
		d.erase(k)

func _gust(e: Dictionary, _dt: float) -> void:
	var seq := int(e.seq)
	var p: Vector2 = e.pos
	if not _gusts.has(seq):
		var n := Node3D.new()
		add_child(n)
		var core := FireFx.core(0.35, WIND, 2.5)
		n.add_child(core)
		var streaks := FireFx.embers(0.9, 90.0, 0.45, 0.2, 0.05, WIND)
		n.add_child(streaks)
		var sm := FireFx.smoke(0.6, 30.0, 0.8, 0.5, 0.2, 0.25)
		n.add_child(sm)
		n.global_position = fx.ground3(p, 1.0)
		var tr := Trail3D.make(n, Color(0.85, 1.0, 0.95, 0.6), float(e.half) * 2.0 * View.S * 0.7, 0.35)
		add_child(tr)
		_gusts[seq] = {"node": n, "trail": tr}
	var g: Dictionary = _gusts[seq]
	var gn: Node3D = View.live(g.node)
	if gn:
		gn.global_position = fx.ground3(p, 1.0)
		gn.visible = fx._seen(p)

func _make_wall(e: Dictionary) -> Dictionary:
	var a: Vector2 = e.a
	var b: Vector2 = e.b
	var m := _mat("wall")
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(a.distance_to(b) * View.S, 3.2)
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var mid := (a + b) * 0.5
	mi.global_position = fx.ground3(mid, 1.6)
	var along := (b - a).normalized()
	mi.rotation.y = atan2(along.y, along.x)
	var dust := FireFx.smoke(a.distance_to(b) * View.S * 0.45, 20.0, 0.7, 1.0, 0.8, 0.2)
	mi.add_child(dust)
	dust.position = Vector3(0, -1.5, 0)
	return {"node": mi, "mat": m}

func _make_storm(e: Dictionary) -> Dictionary:
	var p: Vector2 = e.pos
	var r := float(e.radius) * View.S
	var root := Node3D.new()
	add_child(root)
	root.global_position = fx.ground3(p, 0.0)
	var dm := _mat("swirl")
	dm.set_shader_parameter("disc", 1.0)
	dm.set_shader_parameter("strength", 0.35)
	var disc := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	disc.mesh = q
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	disc.position = Vector3(0, 0.08, 0)
	var fm := _mat("swirl")
	fm.set_shader_parameter("disc", 0.0)
	fm.set_shader_parameter("strength", 0.13)
	var funnel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 0.55
	cyl.bottom_radius = r * 0.12
	cyl.height = 4.5
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 28
	funnel.mesh = cyl
	funnel.material_override = fm
	funnel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(funnel)
	funnel.position = Vector3(0, 2.25, 0)
	var leaves := FireFx.embers(r * 0.7, 60.0, 1.6, 2.5, 0.07, Color(0.45, 0.75, 0.3))
	root.add_child(leaves)
	var dust := FireFx.smoke(r * 0.6, 40.0, 1.2, 1.4, 1.8, 0.3)
	root.add_child(dust)
	return {"node": root, "funnel": funnel}

func _make_knife() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var spin := Node3D.new()
	n.add_child(spin)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.02, 0.32)
	blade.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.88, 0.95)
	mat.metallic = 0.9
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.65, 0.8)
	mat.emission_energy_multiplier = 0.4
	blade.material_override = mat
	spin.add_child(blade)
	var tr := Trail3D.make(blade, Color(1.0, 0.95, 1.0, 0.5), 0.05, 0.12)
	add_child(tr)
	return n

func _make_box(e: Dictionary) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.4, 0.45)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.12, 0.15)
	mat.roughness = 0.6
	box.material_override = mat
	n.add_child(box)
	box.position = Vector3(0, 0.2, 0)
	for k in 2:
		var rib := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.47 if k == 0 else 0.07, 0.42, 0.07 if k == 0 else 0.47)
		rib.mesh = rm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(1.0, 0.85, 0.25)
		gm.metallic = 0.6
		rib.material_override = gm
		n.add_child(rib)
		rib.position = Vector3(0, 0.2, 0)
	var fuse := FireFx.embers(0.04, 40.0, 0.4, 0.8, 0.03, Color(1.0, 0.8, 0.3))
	n.add_child(fuse)
	fuse.position = Vector3(0, 0.5, 0)
	var src: SimUnit = game.world.get_unit(int(e.src))
	var from := fx._chest(src.id, 0.7) if src else fx.ground3(e.pos, 1.0)
	n.global_position = from
	return {"node": n, "from": from}

## Burak's thrown axes, from the sim's list: spinning in flight, stuck where they landed, following a unit they hit.
func _update_axes(w: SimWorld, dt: float) -> void:
	var seen := {}
	for a in w.abilities.kits5.axes:
		var id := int(a.id)
		seen[id] = true
		if not _axes.has(id):
			_axes[id] = _make_axe()
		var n: Node3D = View.live(_axes[id])
		if n == null:
			continue
		var p: Vector2 = a.pos
		var spin: Node3D = n.get_child(0)
		var d: Vector2 = a.dir
		n.rotation.y = atan2(d.x, -d.y)
		match String(a.state):
			"fly":
				n.global_position = fx.ground3(p, 1.2)
				spin.rotation.x -= dt * 22.0
			"stuck":
				var on: SimUnit = w.get_unit(int(a.on))
				n.global_position = fx._chest(on.id, 0.55) if on else fx.ground3(p, 1.0)
				spin.rotation.x = -2.2
			"tree":
				n.global_position = fx.ground3(p, 1.1)
				spin.rotation.x = -1.9
			_:
				n.global_position = fx.ground3(p, 0.18)
				spin.rotation.x = -2.6
		n.visible = fx._seen(p)
	for id in _axes.keys():
		if not seen.has(id):
			var old: Node3D = View.live(_axes[id])
			if old:
				old.queue_free()
			_axes.erase(id)

func _make_axe() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var spin := Node3D.new()
	n.add_child(spin)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.26, 0.14)
	wood.roughness = 0.8
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.76, 0.8)
	steel.metallic = 0.85
	steel.roughness = 0.3
	var haft := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.025
	hm.bottom_radius = 0.025
	hm.height = 0.75
	haft.mesh = hm
	haft.material_override = wood
	spin.add_child(haft)
	haft.rotation.x = PI * 0.5
	var head := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.32, 0.26, 0.04)
	head.mesh = pm
	head.material_override = steel
	spin.add_child(head)
	head.position = Vector3(0, 0.12, -0.3)
	head.rotation = Vector3(0, PI * 0.5, PI)
	var tr := Trail3D.make(head, Color(1.0, 0.85, 0.6, 0.45), 0.12, 0.15)
	add_child(tr)
	return n

# ---- Auras (from the modifiers on units) -----------------------------------------------------------------------------------

const AURA_FX := ["tailwind", "rage", "reckless", "burak_berserk", "steel_stance", "tamed", "roar_pack", "blessed",
	"pie", "dizzy"]

func _scan(w: SimWorld) -> void:
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
			if not (f in AURA_FX):
				continue
			if f == "rage":
				# a glow once he has some Rage, smoke off him when it is full
				var r := int(m.get("charges", 0))
				if r < 10:
					continue
				f = "rage_full" if r >= 100 else ("rage_high" if r >= 50 else "rage")
			want[str(id) + ":" + f] = id
	for k in _auras.keys():
		if not want.has(k):
			var old: Node3D = View.live(_auras[k])
			if old:
				fire.timed(old, 0.0)
			_auras.erase(k)
	for k in want:
		if not _auras.has(k):
			_auras[k] = _make_aura(String(k).split(":")[1])

func _follow_auras(w: SimWorld) -> void:
	for k in _auras:
		var a: Node3D = View.live(_auras[k])
		var uid := int(String(k).split(":")[0])
		var v := fx._view_of(uid)
		if a == null or v == null:
			continue
		a.global_position = Vector3(v.global_position.x, fx.ground_y(View.to2(v.global_position)) + 0.05, v.global_position.z)
		if String(k).ends_with(":steel_stance"):
			var u: SimUnit = w.get_unit(uid)
			if u:
				a.rotation.y = View.yaw(u.facing) + PI
		elif String(k).ends_with(":dizzy") or String(k).ends_with(":tailwind"):
			a.rotation.y += 0.08
		var head := a.get_node_or_null("Head") as Node3D
		if head:
			head.position.y = v.bar_height * 0.85

func _make_aura(kind: String) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	match kind:
		"tailwind":
			for k in 3:
				var orb := Node3D.new()
				n.add_child(orb)
				orb.position = Vector3(cos(k * TAU / 3.0) * 0.55, 0.4 + k * 0.45, sin(k * TAU / 3.0) * 0.55)
				var tr := Trail3D.make(orb, Color(0.85, 1.0, 0.95, 0.55), 0.06, 0.3)
				add_child(tr)
			n.add_child(FireFx.embers(0.5, 16.0, 0.6, 0.6, 0.035, WIND))
		"rage", "rage_high", "rage_full":
			var hot := kind != "rage"
			var em := FireFx.embers(0.4, 14.0 if not hot else 28.0, 0.8, 1.4, 0.04, RAGE)
			em.position = Vector3(0, 0.6, 0)
			n.add_child(em)
			var l := FireFx.light(RAGE, 0.8 if not hot else 1.6, 3.0)
			l.position = Vector3(0, 1.4, 0)
			n.add_child(l)
			if kind == "rage_full":
				var sm := FireFx.smoke(0.35, 10.0, 0.6, 1.4, 1.2, 0.2)
				sm.position = Vector3(0, 1.5, 0)
				n.add_child(sm)
		"reckless":
			var em2 := FireFx.embers(0.55, 22.0, 0.5, 0.6, 0.04, Color(1.0, 0.25, 0.2))
			em2.position = Vector3(0, 1.0, 0)
			n.add_child(em2)
		"burak_berserk":
			var fl := FireFx.flames(0.4, 0.55, 28.0, 0.6, 1.3, "fire", 1.4)
			fl.position = Vector3(0, 0.2, 0)
			n.add_child(fl)
			var l2 := FireFx.light(Color(1.0, 0.4, 0.15), 2.0, 5.0)
			l2.position = Vector3(0, 1.4, 0)
			n.add_child(l2)
		"steel_stance":
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(1.0, 0.8, 0.35, 0.22)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			var arc := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.95
			cy.bottom_radius = 0.95
			cy.height = 1.9
			cy.cap_top = false
			cy.cap_bottom = false
			cy.radial_segments = 24
			arc.mesh = cy
			arc.material_override = m
			arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			arc.scale = Vector3(1.0, 1.0, 0.45)
			arc.position = Vector3(0, 0.95, 0.35)
			n.add_child(arc)
		"tamed":
			var em3 := FireFx.embers(0.45, 10.0, 1.0, 1.0, 0.04, SPIRIT)
			em3.position = Vector3(0, 0.3, 0)
			n.add_child(em3)
			var l3 := FireFx.light(SPIRIT, 0.7, 2.5)
			l3.position = Vector3(0, 1.2, 0)
			n.add_child(l3)
		"roar_pack":
			n.add_child(FireFx.embers(0.5, 18.0, 0.6, 1.0, 0.04, Color(1.0, 0.8, 0.4)))
		"blessed":
			var em4 := FireFx.embers(0.5, 20.0, 0.9, 1.4, 0.045, GOLD)
			n.add_child(em4)
			var l4 := FireFx.light(GOLD, 1.0, 3.0)
			l4.position = Vector3(0, 1.2, 0)
			n.add_child(l4)
		"pie":
			var head := Node3D.new()
			head.name = "Head"
			n.add_child(head)
			var cream := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.2
			sp.height = 0.22
			cream.mesh = sp
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(1.0, 0.97, 0.88)
			cm.roughness = 0.4
			cream.material_override = cm
			head.add_child(cream)
		"dizzy":
			var head2 := Node3D.new()
			head2.name = "Head"
			n.add_child(head2)
			for k in 3:
				var bird := FireFx.core(0.05, Color(1.0, 0.9, 0.3), 2.0)
				head2.add_child(bird)
				bird.position = Vector3(cos(k * TAU / 3.0) * 0.3, 0.15, sin(k * TAU / 3.0) * 0.3)
	return n

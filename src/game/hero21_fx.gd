class_name Hero21Fx
extends Node
## Blackfire's and Thyrandael's visuals (run 2026-10-21) and every unit's barrier shell. One-shot effects come from the
## sim's events; the grip's tether, Holy Beam, the judgement's charges over Thyrandael and the barrier shells are drawn
## from the live sim state every frame, so they can never be left behind. Units: metres (1 game unit = 1 cm).
##   Underworld Presence: a black soul with a violet core leaves each body near Blackfire and flies into his chest (a
##   hero's soul is bigger and brighter); he flares violet when it arrives.
##   Sacrificial Grip: a dark violet tether from his chest to the target's for the stun, shadow flames climbing the
##   target, a black burst where it lands.
##   Rise Up: a violet roar wave and ring; dark smoke and violet fire where each body rises; his Undead burn with violet
##   embers and smoke round their feet, darkened, while they last; the roar's aura as a slow dark swirl under him.
##   Fiend Edge: a violet slash on the target and a green-violet mote to each ally it heals.
##   Unfallen: a column of black smoke where he falls; violet fire and a shockwave when he rises; while he lives on, his
##   sword burns violet and his body smokes; the last blast is a black ring and a wall of force.
##   Divine Touch and every barrier: a soft shell round the unit (gold for All-damage, orange for physical, blue for
##   magic), brighter while it takes a blow.
##   Holy Beam: a white-gold beam from his chest along his facing, a burn line on the ground, a flare where it ends.
##   Quick Flash: a white burst ring and light; a spark on each enemy hit.
##   Spirit Step: a pillar of light where he leaves, a ring of light where he lands.
##   False Judgement: its charges circle over his head as small suns (they flare when full); the blast is a column of
##   light, a gold shockwave and cracks; judged enemies have gold sparks falling over their heads.

const EVENTS := ["soul_drain", "sacrificial_grip", "rise_up", "undead_rise", "fiend_edge", "unfallen_fall",
	"unfallen_rise", "unfallen_blast", "holy_beam_start", "holy_beam_end", "quick_flash", "spirit_step",
	"false_judgement", "barrier"]
const VIOLET := Color(0.62, 0.32, 1.0)
const PALE_VIOLET := Color(0.88, 0.75, 1.0)
const BLACK := Color(0.03, 0.01, 0.05)
const GOLD := Color(1.0, 0.86, 0.45)
const WHITE := Color(1.0, 0.98, 0.9)
const BARRIER_COL := {"all": Color(1.0, 0.85, 0.3), "phys": Color(1.0, 0.55, 0.25), "magic": Color(0.45, 0.7, 1.0)}

var game: Node
var fx: Fx
var fire: FireFx

var _clock := 0.0
var _scan_i := 0
var _timed: Array = []                      # {node, t, life, mat}
var _souls: Array = []                      # {node, from, to_id, t, dur, big}
var _auras := {}                            # unit id ":" kind -> node
var _dark := {}                             # unit id -> true while its model wears the Undead overlay
var _glow := {}                             # unit id -> true while Unfallen lights his sword
var _tethers := {}                          # Blackfire id -> {target, until, node, mat}
var _beams := {}                            # Thyrandael id -> {rod, ground, flare, mats}
var _halos := {}                            # Thyrandael id -> {node, orbs: []}
var _shells := {}                           # unit id -> {node, mat, hit}
static var _dark_mat: StandardMaterial3D

# ---- Shaders --------------------------------------------------------------------------------------------------------

## A glowing rod (a CylinderMesh along its local Y): bright where it faces the camera, flowing along its length.
const ROD_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.9, 0.5, 1.0);
uniform float fade = 1.0;
uniform float glow = 2.0;
uniform float flow = 6.0;
void fragment() {
	float f = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float core = pow(f, 2.2);
	float wave = 0.78 + 0.22 * sin(UV.y * 60.0 - TIME * flow);
	ALBEDO = mix(col.rgb, vec3(1.0), core * 0.65) * glow;
	ALPHA = clamp(core * fade * wave, 0.0, 1.0);
}
"""

## A flat streak on the ground: brightest down its middle (UV.x across, UV.y along).
const STREAK_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float fade = 1.0;
uniform float glow = 1.6;
void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float core = pow(across, 2.5);
	float ends = smoothstep(0.0, 0.06, UV.y) * smoothstep(0.0, 0.1, 1.0 - UV.y);
	float flick = 0.8 + 0.2 * sin(UV.y * 90.0 - TIME * 14.0);
	ALBEDO = mix(col.rgb, vec3(1.0), core * 0.4) * glow;
	ALPHA = clamp(core * ends * fade * flick, 0.0, 1.0);
}
"""

## A barrier shell: a sphere lit at its rim, a slow shimmer, brighter when struck.
const SHELL_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float fade = 1.0;
uniform float hit = 0.0;
void fragment() {
	float f = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float rim = pow(f, 3.0);
	float shimmer = 0.75 + 0.25 * sin(UV.y * 30.0 + UV.x * 18.0 + TIME * 3.0);
	ALBEDO = col.rgb * (1.4 + hit * 2.5);
	ALPHA = clamp((rim * 0.75 * shimmer + rim * hit * 0.6 + hit * 0.06) * fade, 0.0, 1.0);
}
"""

static var _shaders := {}

func _mat(kind: String, col: Color) -> ShaderMaterial:
	if _shaders.is_empty():
		for k in ["rod", "streak", "shell"]:
			var s := Shader.new()
			s.code = {"rod": ROD_CODE, "streak": STREAK_CODE, "shell": SHELL_CODE}[k]
			_shaders[k] = s
	var m := ShaderMaterial.new()
	m.shader = _shaders[kind]
	m.set_shader_parameter("col", col)
	return m

func _timed_add(node: Node3D, life: float, mat: ShaderMaterial = null) -> void:
	_timed.append({"node": node, "t": 0.0, "life": life, "mat": mat})

## A rod `mi` (CylinderMesh of height 1 along Y) stretched from `a` to `b`.
static func _rod(mi: Node3D, a: Vector3, b: Vector3, width: float) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.01:
		mi.visible = false
		return
	mi.visible = true
	var y := d / ln
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x * width, y * ln, z * width), (a + b) * 0.5)

func _new_rod(col: Color, glow := 2.0) -> Dictionary:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 1
	mi.mesh = cyl
	var m := _mat("rod", col)
	m.set_shader_parameter("glow", glow)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	return {"node": mi, "mat": m}

func _flat(centre: Vector2, size: Vector2, dir: Vector2, mat: Material, lift := 0.06) -> MeshInstance3D:
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

func _burst(at: Vector3, kind: String, col: Color, size := 1.0, dark := false) -> void:
	var fl := FireFx.flames(0.25 * size, 0.45 * size, 60.0 * size, 0.55, 1.6, kind, 1.6)
	fl.one_shot = true
	fl.explosiveness = 0.85
	add_child(fl)
	fl.global_position = at
	fire.timed(fl, 1.0)
	var em := FireFx.embers(0.35 * size, 60.0 * size, 0.9, 1.8, 0.05, col)
	em.one_shot = true
	em.explosiveness = 0.9
	add_child(em)
	em.global_position = at
	fire.timed(em, 1.4)
	if dark:
		var sm := FireFx.smoke(0.35 * size, 40.0 * size, 0.9 * size, 1.1, 0.9, 0.8)
		_tint_smoke(sm, Color(0.04, 0.02, 0.06))
		sm.one_shot = true
		sm.explosiveness = 0.85
		add_child(sm)
		sm.global_position = at
		fire.timed(sm, 1.8)

func _tint_smoke(sm: GPUParticles3D, c: Color) -> void:
	var q := sm.draw_pass_1 as QuadMesh
	if q and q.material is ShaderMaterial:
		(q.material as ShaderMaterial).set_shader_parameter("tint", c)

# ---- Events ---------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	var w: SimWorld = game.world
	match String(e.t):
		"soul_drain":
			var from: Vector2 = e.from
			var h := w.get_unit(int(e.u))
			if h != null and (fx._seen(from) or fx._seen(h.pos)):
				_soul(from, int(e.u), bool(e.get("hero", false)))
		"sacrificial_grip":
			var bu := w.get_unit(int(e.u))
			var tu := w.get_unit(int(e.target))
			if bu != null and tu != null:
				_tethers[bu.id] = {"target": tu.id, "until": _clock + float(e.dur), "rod": _new_rod(VIOLET, 2.2),
					"core": _new_rod(PALE_VIOLET, 3.0)}
				if fx._seen(tu.pos):
					_burst(fx._chest(tu.id, 0.5), "underworld", VIOLET, 1.1, true)
					fx.flash_light(fx._chest(tu.id, 0.6), VIOLET, 4.0, 5.0, 0.35)
					fx._shake(tu.pos, 0.1, 0.18)
		"rise_up":
			var ru := w.get_unit(int(e.u))
			if ru != null and fx._seen(ru.pos):
				fx.shockwave(fx.ground3(ru.pos, 0.05), float(e.radius) * View.S, VIOLET, 0.8, 0.12, 2.2)
				fx.force_wall(fx.ground3(ru.pos), 0.5, 3.5, 2.2, VIOLET, 0.5)
				fx.flash_light(fx._chest(ru.id, 0.7), VIOLET, 6.0, 9.0, 0.45)
				fx.edge_ring(fx.ground3(ru.pos, 0.06), float(e.radius) * View.S, VIOLET, 1.6)
				fx._shake(ru.pos, 0.14, 0.3)
		"undead_rise":
			var p: Vector2 = e.pos
			if fx._seen(p):
				_burst(fx.ground3(p, 0.4), "underworld", VIOLET, 1.0, true)
				fx.crack(fx.ground3(p, 0.02), 1.2, VIOLET, 2.0)
		"fiend_edge":
			var fu := w.get_unit(int(e.u))
			var ft := w.get_unit(int(e.target))
			if fu != null and ft != null and fx._seen(ft.pos):
				var c := fx._chest(ft.id, 0.55)
				fx.impact(c, VIOLET, 0.42)
				fx.sparks(c, Vector3.UP, 12, PALE_VIOLET, 5.0)
				var dir := (ft.pos - fu.pos).normalized()
				var m := _mat("streak", VIOLET)
				m.set_shader_parameter("glow", 2.6)
				var sl := _flat(ft.pos, Vector2(0.22, 2.0), dir.rotated(0.9), m, 1.1)
				_timed_add(sl, 0.25, m)
				for id in e.get("healed", []):
					if int(id) != fu.id:
						_mote(ft.id, int(id))
		"unfallen_fall":
			var du := w.get_unit(int(e.u))
			if du != null and fx._seen(du.pos):
				_burst(fx.ground3(du.pos, 0.3), "underworld", VIOLET, 1.4, true)
				fx.flash_light(fx.ground3(du.pos, 1.2), VIOLET, 4.0, 6.0, 0.6)
		"unfallen_rise":
			var uu := w.get_unit(int(e.u))
			if uu != null and fx._seen(uu.pos):
				fx.shockwave(fx.ground3(uu.pos, 0.05), 4.0, VIOLET, 0.6, 0.2, 3.0)
				fx.force_wall(fx.ground3(uu.pos), 0.4, 2.4, 3.0, PALE_VIOLET, 0.45)
				_burst(fx._chest(uu.id, 0.4), "underworld", VIOLET, 1.6, true)
				fx.flash_light(fx._chest(uu.id, 0.7), VIOLET, 8.0, 9.0, 0.5)
				fx._shake(uu.pos, 0.2, 0.3)
		"unfallen_blast":
			var bp: Vector2 = e.pos
			if fx._seen(bp):
				fx.shockwave(fx.ground3(bp, 0.05), float(e.radius) * View.S * 1.15, BLACK.lerp(VIOLET, 0.5), 0.55, 0.3, 3.5)
				fx.force_wall(fx.ground3(bp), 0.4, float(e.radius) * View.S, 2.6, VIOLET, 0.5)
				fx.crack(fx.ground3(bp, 0.02), float(e.radius) * View.S * 0.8, VIOLET, 3.0)
				_burst(fx.ground3(bp, 0.8), "underworld", VIOLET, 2.2, true)
				fx.flash_light(fx.ground3(bp, 1.5), VIOLET, 10.0, 12.0, 0.5)
				fx._shake(bp, 0.35, 0.45)
		"quick_flash":
			var qu := w.get_unit(int(e.u))
			if qu != null and fx._seen(qu.pos):
				fx.shockwave(fx.ground3(qu.pos, 0.05), float(e.radius) * View.S, GOLD, 0.35, 0.16, 3.2)
				fx.flash_light(fx._chest(qu.id, 0.6), WHITE, 7.0, float(e.radius) * View.S * 1.4, 0.22)
				fx.impact(fx._chest(qu.id, 0.55), WHITE, 0.55)
				for id in e.get("hits", []):
					var o := w.get_unit(int(id))
					if o != null:
						fx.sparks(fx._chest(o.id, 0.55), Vector3.UP, 6, GOLD, 4.0)
		"spirit_step":
			var a: Vector2 = e.from
			var b: Vector2 = e.to
			if fx._seen(a):
				fx._light_spike(fx.ground3(a), WHITE, 5.0)
				_burst(fx.ground3(a, 0.6), "holy", GOLD, 0.8)
			if fx._seen(b):
				fx._light_spike(fx.ground3(b), WHITE, 6.0)
				fx.shockwave(fx.ground3(b, 0.05), float(e.radius) * View.S, GOLD, 0.45, 0.18, 3.0)
				fx.edge_ring(fx.ground3(b, 0.06), float(e.radius) * View.S, GOLD, 1.0)
				fx.flash_light(fx.ground3(b, 1.2), WHITE, 6.0, 7.0, 0.3)
				fx._shake(b, 0.1, 0.15)
		"false_judgement":
			var jp: Vector2 = e.pos
			if fx._seen(jp):
				var big := 0.6 + float(e.get("frac", 1.0))
				fx._light_spike(fx.ground3(jp), WHITE, 9.0 * big)
				fx.shockwave(fx.ground3(jp, 0.05), float(e.radius) * View.S, GOLD, 0.6, 0.25, 4.0)
				fx.force_wall(fx.ground3(jp), 0.5, float(e.radius) * View.S, 3.0, WHITE, 0.55)
				fx.crack(fx.ground3(jp, 0.02), float(e.radius) * View.S * 0.9, GOLD, 3.0)
				_burst(fx.ground3(jp, 0.6), "holy", GOLD, 1.6 * big)
				fx.flash_light(fx.ground3(jp, 2.0), WHITE, 12.0 * big, 14.0, 0.5)
				fx._shake(jp, 0.25 * big, 0.4)
		"barrier":
			var sh: Dictionary = _shells.get(int(e.u), {})
			if not sh.is_empty():
				sh.hit = 1.0

## A soul leaving a body for Blackfire's chest.
func _soul(from: Vector2, to_id: int, big: bool) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = fx.ground3(from, 1.0)
	var core := FireFx.core(0.09 if not big else 0.15, PALE_VIOLET, 4.0)
	n.add_child(core)
	var fl := FireFx.flames(0.06, 0.22 if not big else 0.35, 30.0, 0.35, 0.4, "underworld", 1.4)
	n.add_child(fl)
	var tr := Trail3D.make(n, Color(0.45, 0.2, 0.85, 0.7), 0.1 if not big else 0.16, 0.35)
	add_child(tr)
	var l := FireFx.light(VIOLET, 1.0 if not big else 1.8, 2.5)
	n.add_child(l)
	_souls.append({"node": n, "from": n.global_position, "to": to_id, "t": 0.0, "dur": 0.7 if not big else 0.95,
		"big": big, "trail": tr, "side": randf_range(-1.0, 1.0)})

## A small heal mote from a struck enemy to an ally (Fiend Edge's drain).
func _mote(from_id: int, to_id: int) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = fx._chest(from_id, 0.55)
	var core := FireFx.core(0.06, Color(0.6, 1.0, 0.7), 3.0)
	n.add_child(core)
	var tr := Trail3D.make(n, Color(0.55, 0.9, 0.7, 0.6), 0.05, 0.25)
	add_child(tr)
	_souls.append({"node": n, "from": n.global_position, "to": to_id, "t": 0.0, "dur": 0.5, "big": false, "trail": tr,
		"side": randf_range(-1.0, 1.0), "mote": true})

func _update_souls(dt: float) -> void:
	for i in range(_souls.size() - 1, -1, -1):
		var s: Dictionary = _souls[i]
		s.t = float(s.t) + dt
		var n: Node3D = View.live(s.node)
		var k := clampf(float(s.t) / float(s.dur), 0.0, 1.0)
		var to := fx._chest(int(s.to), 0.6)
		if n != null:
			var from: Vector3 = s.from
			var mid := (from + to) * 0.5 + Vector3(0, 1.6 + float(s.side) * 0.4, 0) + (to - from).cross(Vector3.UP).normalized() * float(s.side) * 0.8
			var ease := k * k * (3.0 - 2.0 * k)
			n.global_position = from.lerp(mid, ease).lerp(mid.lerp(to, ease), ease)
		if k >= 1.0:
			if n != null:
				for p in n.find_children("*", "GPUParticles3D", true, false):
					(p as GPUParticles3D).emitting = false
				fire.timed(n, 0.4)
			var tr = s.get("trail")
			if tr is Trail3D and is_instance_valid(tr):
				(tr as Trail3D).stop()
			if not bool(s.get("mote", false)):
				fx.impact(to, VIOLET, 0.3 if not bool(s.big) else 0.5)
				fx.flash_light(to, VIOLET, 2.0 if not bool(s.big) else 4.0, 3.5, 0.25)
			_souls.remove_at(i)

# ---- Every frame ------------------------------------------------------------------------------------------------------

func update(w: SimWorld, _alpha: float, dt: float) -> void:
	_clock += dt
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
		if t.mat:
			(t.mat as ShaderMaterial).set_shader_parameter("fade", clampf(1.0 - float(t.t) / float(t.life), 0.0, 1.0))
	_update_souls(dt)
	_update_tethers(w)
	_update_beams(w)
	_update_halos(w, dt)
	_update_shells(w, dt)
	_follow_auras()

func _update_tethers(w: SimWorld) -> void:
	for id in _tethers.keys():
		var t: Dictionary = _tethers[id]
		var a := w.get_unit(int(id))
		var b := w.get_unit(int(t.target))
		var done := _clock >= float(t.until) or a == null or b == null or not a.alive or not b.alive
		if done:
			for k in ["rod", "core"]:
				var n: Node3D = View.live(t[k].node)
				if n:
					n.queue_free()
			_tethers.erase(id)
			continue
		var p0 := fx._chest(a.id, 0.6)
		var p1 := fx._chest(b.id, 0.55)
		var seen := fx._seen(a.pos) or fx._seen(b.pos)
		var left := float(t.until) - _clock
		for k in ["rod", "core"]:
			var n2: Node3D = View.live(t[k].node)
			if n2:
				n2.visible = seen
				_rod(n2, p0, p1, 0.09 if k == "rod" else 0.03)
				(t[k].mat as ShaderMaterial).set_shader_parameter("fade", clampf(left / 0.3, 0.0, 1.0) * (0.85 + 0.15 * sin(_clock * 13.0)))

## Holy Beam while Thyrandael channels it: a rod from his chest along his facing, a burn on the ground, a flare.
func _update_beams(w: SimWorld) -> void:
	var live := {}
	for h in w.heroes:
		if not h.alive or h.channel.is_empty() or String(h.channel.ability) != "holy_beam":
			continue
		live[h.id] = true
		if not _beams.has(h.id):
			var gm := _mat("streak", GOLD)
			var ground := _flat(h.pos, Vector2(1.0, 1.0), Vector2.UP, gm, 0.07)
			var flare := Node3D.new()
			add_child(flare)
			var fc := FireFx.core(0.2, WHITE, 5.0)
			flare.add_child(fc)
			var fl := FireFx.flames(0.25, 0.5, 40.0, 0.4, 1.2, "holy", 1.4)
			flare.add_child(fl)
			var lt := FireFx.light(GOLD, 2.5, 6.0)
			lt.position = Vector3(0, 0.6, 0)
			flare.add_child(lt)
			var hand := FireFx.light(WHITE, 2.0, 4.0)
			add_child(hand)
			_beams[h.id] = {"rod": _new_rod(GOLD, 2.4), "core": _new_rod(WHITE, 3.2), "ground": ground, "gmat": gm,
				"flare": flare, "hand": hand}
		var b: Dictionary = _beams[h.id]
		var v := fx._view_of(h.id)
		var line := w.abilities.kits9.beam_line(h)
		var a2: Vector2 = line[0]
		var z2: Vector2 = line[1]
		# from where his body is drawn (it lags the sim a little), along his facing
		if v != null:
			var ln := a2.distance_to(z2)
			a2 = View.to2(v.global_position) + Vector2.from_angle(h.facing) * (h.hull + 10.0)
			z2 = a2 + Vector2.from_angle(h.facing) * ln
		var p0 := fx.ground3(a2, 1.25)
		var p1 := fx.ground3(z2, 0.9)
		var seen := fx._seen(h.pos) or fx._seen(z2)
		for k in ["rod", "core"]:
			var n: Node3D = View.live(b[k].node)
			if n:
				n.visible = seen
				_rod(n, p0, p1, 0.16 if k == "rod" else 0.055)
		var g: MeshInstance3D = View.live(b.ground)
		if g:
			g.visible = seen
			var mid := (a2 + z2) * 0.5
			var dir := (z2 - a2)
			(g.mesh as QuadMesh).size = Vector2(1.4, dir.length() * View.S)
			g.global_position = fx.ground3(mid, 0.07)
			g.rotation.y = atan2(dir.x, -dir.y)
		var fl2: Node3D = View.live(b.flare)
		if fl2:
			fl2.visible = seen
			fl2.global_position = p1
		var hl: Node3D = View.live(b.hand)
		if hl:
			hl.global_position = p0
	for id in _beams.keys():
		if live.has(id):
			continue
		var b2: Dictionary = _beams[id]
		for k in ["rod", "core"]:
			var n3: Node3D = View.live(b2[k].node)
			if n3:
				n3.queue_free()
		for k2 in ["ground", "hand"]:
			var n4: Node3D = View.live(b2[k2])
			if n4:
				n4.queue_free()
		var fl3: Node3D = View.live(b2.flare)
		if fl3:
			for p in fl3.find_children("*", "GPUParticles3D", true, false):
				(p as GPUParticles3D).emitting = false
			fire.timed(fl3, 0.6)
		_beams.erase(id)

## False Judgement's charges: small suns circling over Thyrandael's head, one per charge; flaring when full.
func _update_halos(w: SimWorld, _dt: float) -> void:
	var live := {}
	for h in w.heroes:
		if not h.alive or h.ability_level_of("false_judgement") <= 0:
			continue
		var n := w.abilities.kits9.judgement_charges(h)
		var v := fx._view_of(h.id)
		if n <= 0 or v == null or not v.visible:
			continue
		live[h.id] = true
		var mx := w.abilities.kits9.judgement_max(h)
		if not _halos.has(h.id):
			var root := Node3D.new()
			add_child(root)
			var orbs: Array = []
			for i in 12:
				var o := FireFx.core(0.07, WHITE, 3.5)
				o.visible = false
				root.add_child(o)
				orbs.append(o)
			var l := FireFx.light(GOLD, 0.0, 3.0)
			root.add_child(l)
			_halos[h.id] = {"node": root, "orbs": orbs, "light": l}
		var hd: Dictionary = _halos[h.id]
		var r: Node3D = View.live(hd.node)
		if r == null:
			_halos.erase(h.id)
			continue
		r.global_position = v.global_position + Vector3(0, v.bar_height + 0.55, 0)
		var full := n >= mx
		var spin := _clock * (1.2 if not full else 2.6)
		for i in (hd.orbs as Array).size():
			var o2: Node3D = hd.orbs[i]
			o2.visible = i < n
			if i < n:
				var a := spin + TAU * float(i) / float(maxi(1, n))
				o2.position = Vector3(cos(a) * 0.55, sin(a * 2.0 + float(i)) * 0.05, sin(a) * 0.55)
				var s := 1.0 + (0.35 + 0.2 * sin(_clock * 8.0 + i) if full else 0.0)
				o2.scale = Vector3.ONE * s
		(hd.light as OmniLight3D).light_energy = 0.25 * float(n) / float(maxi(1, mx)) * (2.5 if full else 1.0)
	for id in _halos.keys():
		if not live.has(id):
			var old: Node3D = View.live(_halos[id].node)
			if old:
				old.queue_free()
			_halos.erase(id)

## Barrier shells round every unit that holds a SimBarrier pool (the strongest kind sets the colour).
func _update_shells(w: SimWorld, dt: float) -> void:
	var live := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView) or not v.visible:
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive or u.modifiers.is_empty():
			continue
		var kind := ""
		var amt := 0.0
		for m in u.modifiers:
			for k in ["all", "phys", "magic"]:
				var b := float(m.get("barrier_" + k, 0.0))
				if b > amt:
					amt = b
					kind = k
		if kind == "":
			continue
		live[id] = true
		if not _shells.has(id) or String(_shells[id].kind) != kind:
			if _shells.has(id):
				var old: Node3D = View.live(_shells[id].node)
				if old:
					old.queue_free()
			var mi := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.5
			sp.height = 1.0
			mi.mesh = sp
			var m2 := _mat("shell", BARRIER_COL[kind])
			mi.material_override = m2
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_shells[id] = {"node": mi, "mat": m2, "hit": 0.0, "kind": kind}
		var s: Dictionary = _shells[id]
		var sn: Node3D = View.live(s.node)
		if sn == null:
			_shells.erase(id)
			continue
		var hgt := maxf(1.2, (v as UnitView).bar_height * 0.95)
		sn.global_position = (v as UnitView).global_position + Vector3(0, hgt * 0.5, 0)
		sn.scale = Vector3(hgt * 0.62, hgt * 1.02, hgt * 0.62)
		s.hit = maxf(0.0, float(s.hit) - dt * 3.0)
		(s.mat as ShaderMaterial).set_shader_parameter("hit", float(s.hit))
	for id in _shells.keys():
		if not live.has(id):
			var o: Node3D = View.live(_shells[id].node)
			if o:
				o.queue_free()
			_shells.erase(id)

# ---- Auras (from the modifiers on units) ------------------------------------------------------------------------------

func _scan(w: SimWorld) -> void:
	var want := {}
	var dark := {}
	var glow := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView) or not v.visible:
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive or u.modifiers.is_empty():
			continue
		for m in u.modifiers:
			match String(m.get("fx", "")):
				"undead":
					want[str(id) + ":undead"] = id
					dark[id] = true
				"rise_up":
					want[str(id) + ":roar"] = id
				"grip":
					want[str(id) + ":grip"] = id
				"unfallen_fallen":
					want[str(id) + ":fallen"] = id
				"unfallen_risen":
					want[str(id) + ":risen"] = id
					glow[id] = true
				"false_judgement":
					want[str(id) + ":judged"] = id
				"quick_flash":
					if int(m.get("charges", 0)) >= 3:
						want[str(id) + ":marked"] = id
	for k in _auras.keys():
		if not want.has(k):
			var old: Node3D = View.live(_auras[k])
			if old:
				for p in old.find_children("*", "GPUParticles3D", true, false):
					(p as GPUParticles3D).emitting = false
				fire.timed(old, 1.2)
			_auras.erase(k)
	for k in want:
		if not _auras.has(k):
			_auras[k] = _make_aura(String(k).split(":")[1])
	# the Undead's darkened look
	for id in _dark.keys():
		if not dark.has(id):
			_overlay(int(id), false)
			_dark.erase(id)
	for id in dark:
		if not _dark.has(id):
			_overlay(int(id), true)
			_dark[id] = true
	for id in _glow.keys():
		if not glow.has(id):
			var v2 := fx._view_of(int(id))
			if v2:
				v2.set_weapon_glow(false)
			_glow.erase(id)
	for id in glow:
		if not _glow.has(id):
			var v3 := fx._view_of(int(id))
			if v3:
				v3.set_weapon_glow(true, VIOLET)
			_glow[id] = true

func _overlay(id: int, on: bool) -> void:
	var v := fx._view_of(id)
	if v == null:
		return
	if _dark_mat == null:
		_dark_mat = StandardMaterial3D.new()
		_dark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dark_mat.albedo_color = Color(0.06, 0.02, 0.1, 0.55)
		_dark_mat.rim_enabled = false
	for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = _dark_mat if on else null

func _follow_auras() -> void:
	for k in _auras:
		var a: Node3D = View.live(_auras[k])
		var v := fx._view_of(int(String(k).split(":")[0]))
		if a == null or v == null:
			continue
		var kind := String(k).split(":")[1]
		var up := v.bar_height + 0.25 if kind == "judged" or kind == "marked" else 0.05
		a.global_position = Vector3(v.global_position.x, (fx.ground_y(View.to2(v.global_position)) + up) if up < 0.1 else v.global_position.y + up, v.global_position.z)

func _make_aura(kind: String) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	match kind:
		"undead":
			var em := FireFx.embers(0.3, 10.0, 0.9, 0.9, 0.035, VIOLET)
			em.position = Vector3(0, 0.4, 0)
			n.add_child(em)
			var sm := FireFx.smoke(0.3, 6.0, 0.5, 1.4, 0.3, 0.35)
			_tint_smoke(sm, Color(0.05, 0.02, 0.08))
			n.add_child(sm)
			var eyes := FireFx.light(VIOLET, 0.5, 1.6)
			eyes.position = Vector3(0, 1.0, 0)
			n.add_child(eyes)
		"roar":
			var em2 := FireFx.embers(1.2, 16.0, 1.4, 0.8, 0.04, VIOLET)
			em2.position = Vector3(0, 0.1, 0)
			n.add_child(em2)
			var sm2 := FireFx.smoke(1.0, 8.0, 0.9, 2.0, 0.25, 0.3)
			_tint_smoke(sm2, Color(0.05, 0.02, 0.08))
			n.add_child(sm2)
		"grip":
			var fl := FireFx.flames(0.35, 0.5, 34.0, 0.6, 1.4, "underworld", 1.5)
			fl.position = Vector3(0, 0.1, 0)
			n.add_child(fl)
			var l := FireFx.light(VIOLET, 1.2, 3.0)
			l.position = Vector3(0, 1.0, 0)
			n.add_child(l)
		"fallen":
			var sm3 := FireFx.smoke(0.6, 26.0, 1.2, 2.4, 1.4, 0.8)
			_tint_smoke(sm3, Color(0.03, 0.01, 0.05))
			n.add_child(sm3)
			var em3 := FireFx.embers(0.6, 20.0, 1.2, 1.6, 0.04, VIOLET)
			n.add_child(em3)
		"risen":
			var fl2 := FireFx.flames(0.4, 0.55, 40.0, 0.6, 1.8, "underworld", 1.6)
			fl2.position = Vector3(0, 0.2, 0)
			n.add_child(fl2)
			var sm4 := FireFx.smoke(0.4, 10.0, 0.7, 1.6, 0.8, 0.5)
			_tint_smoke(sm4, Color(0.04, 0.02, 0.06))
			n.add_child(sm4)
			var l2 := FireFx.light(VIOLET, 2.0, 4.0)
			l2.position = Vector3(0, 1.2, 0)
			n.add_child(l2)
		"judged":
			var em4 := FireFx.embers(0.3, 14.0, 0.9, 0.15, 0.035, GOLD)
			n.add_child(em4)
		"marked":
			var em5 := FireFx.embers(0.2, 6.0, 0.6, 0.4, 0.03, WHITE)
			n.add_child(em5)
	return n

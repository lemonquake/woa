class_name Hero22Fx
extends Node
## Gancho's, Lord Kaileh's and Dracoxinia's visuals (run 2026-10-21 b). One-shot effects come from the sim's events;
## the vines in flight, the charges' dust and ghost riders and the sword in Dracoxinia's hands follow the live sim state
## every frame, so none can be left behind. Units: metres (1 game unit = 1 cm).
##   Root Snare: a vine grows from Gancho's hand along the line and wraps whoever it catches (a burst of leaves).
##   Seed Bomb: a glowing seed arcs to the point; it bursts in leaves and earth (the young tree grows in: Foliage).
##   Angry Forest: a green wave from Gancho, green motes round him while it lasts; each lash is a vine from a tree.
##   Lance Charge: dust behind Lord Kaileh and sparks on each enemy he meets; Cavalry Charge adds his six ghost riders
##   (his own body, see-through, charging beside him), fading in a puff when it ends.
##   Lance Sweep: a ring of dust and a gold sweep round him. War Banner: a banner on a pole in his house colours, its
##   reach a faint ring on the ground (made by Main's ward view, `make_banner`).
##   Dracoxinia: the sword she holds is the one Change Sword picked (swapped in her hand, a flash of its colour); a
##   Dragon Blade strike lights the blade and lands with its sword's power (lightning that jumps, a gold flare, a water
##   splash, a fire burst, a green heal); Dragon Dash leaves a streak in her sword's colour; Dragon Leap a trail of it
##   over her arc, dust where she leaves and a ring where she lands; Rising Slash a rising cut of light under the target.

const EVENTS := ["root_snare", "root_snare_end", "seed_bomb", "seed_bomb_burst", "angry_forest", "forest_lash",
	"lance_charge", "cavalry_charge", "lance_charge_hit", "cavalry_charge_hit", "lance_charge_end", "cavalry_charge_end",
	"lance_sweep", "war_banner", "sword_change", "dragon_blade_swing", "dragon_blade", "dragon_dash", "dragon_dash_hit",
	"dragon_leap", "rising_slash"]
const VINE := Color(0.35, 0.7, 0.2)
const LEAF := Color(0.3, 0.58, 0.2)
const EARTH := Color(0.36, 0.28, 0.2)
const DUST := Color(0.55, 0.47, 0.36)
const GOLD := Color(1.0, 0.82, 0.4)
const GHOST := Color(0.55, 0.8, 1.0)
## Dracoxinia's swords in SimKits11.SWORDS order: their colour and their flame kind (FireFx ramps).
const SWORD_COL := [Color(1.0, 0.45, 0.8), Color(1.0, 0.85, 0.35), Color(0.35, 0.6, 1.0), Color(1.0, 0.35, 0.25),
	Color(0.45, 1.0, 0.4)]
const SWORD_FIRE := ["void", "holy", "water", "fire", "shadowflame"]

var game: Node
var fx: Fx
var fire: FireFx

var _clock := 0.0
var _scan_i := 0
var _timed: Array = []                      # {node, t, life, mat}
var _snares := {}                           # seq -> {u, from, dir, dist, speed, t, rod, end_t, target}
var _seeds: Array = []                      # {node, from, to, t, dur, trail}
var _lashes: Array = []                     # {rod, from, target, t}
var _charges := {}                          # Kaileh id -> {until, dust, riders: [{view, unit, side, back}]}
var _auras := {}                            # unit id ":" kind -> node
var _held := {}                             # Dracoxinia id -> sword index her view holds
var _lit := {}                              # Dracoxinia id -> clock when her blade's strike glow goes out
static var _shaders := {}

## A flat ring on the ground (UV centre 0.5): bright at its edge, soft inside.
const RING_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float fade = 1.0;
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(0.86, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float fill = (1.0 - smoothstep(0.0, 1.0, r)) * 0.06;
	float pulse = 0.8 + 0.2 * sin(TIME * 2.0 - r * 6.0);
	ALBEDO = col.rgb * 1.4;
	ALPHA = clamp((edge * 0.55 + fill) * pulse * fade, 0.0, 1.0);
}
"""

## A banner cloth (a QuadMesh hanging from its top edge): it ripples in the wind more toward its free end.
const CLOTH_CODE := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 col : source_color = vec4(0.6, 0.08, 0.1, 1.0);
uniform vec4 trim : source_color = vec4(1.0, 0.8, 0.35, 1.0);
void vertex() {
	float free = UV.x;
	VERTEX.z += sin(TIME * 3.2 + UV.x * 6.0 + UV.y * 2.0) * 0.06 * free;
	VERTEX.y += sin(TIME * 2.1 + UV.x * 4.0) * 0.02 * free;
}
void fragment() {
	float band = step(0.86, UV.y) + step(UV.y, 0.06);
	float mark = 1.0 - smoothstep(0.1, 0.13, length((UV - vec2(0.42, 0.45)) * vec2(1.0, 1.4)));
	ALBEDO = mix(col.rgb, trim.rgb, clamp(band + mark, 0.0, 1.0));
	ROUGHNESS = 0.8;
}
"""

func _mat(kind: String, col: Color) -> ShaderMaterial:
	if _shaders.is_empty():
		for k in ["rod", "streak", "ring", "cloth"]:
			var s := Shader.new()
			s.code = {"rod": Hero21Fx.ROD_CODE, "streak": Hero21Fx.STREAK_CODE, "ring": RING_CODE, "cloth": CLOTH_CODE}[k]
			_shaders[k] = s
	var m := ShaderMaterial.new()
	m.shader = _shaders[kind]
	m.set_shader_parameter("col", col)
	return m

func _timed_add(node: Node3D, life: float, mat: ShaderMaterial = null) -> void:
	_timed.append({"node": node, "t": 0.0, "life": life, "mat": mat})

func _rod(col: Color, glow := 1.4) -> Dictionary:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	mi.mesh = cyl
	var m := _mat("rod", col)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("flow", 3.0)
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

## Leaves and bark chips thrown out of a point.
func _leaves(at: Vector3, n: int, speed := 2.0) -> void:
	fx.debris(at, n, LEAF, speed, 0.9, "leaf")
	fx.debris(at, maxi(2, n / 3), EARTH, speed * 1.2, 0.5, "chip")

func _dust(at: Vector3, size := 1.0) -> void:
	var sm := FireFx.smoke(0.4 * size, 40.0 * size, 0.9 * size, 1.2, 0.5, 0.45)
	_tint(sm, DUST)
	sm.one_shot = true
	sm.explosiveness = 0.85
	add_child(sm)
	sm.global_position = at
	fire.timed(sm, 1.8)

func _tint(sm: GPUParticles3D, c: Color) -> void:
	var q := sm.draw_pass_1 as QuadMesh
	if q and q.material is ShaderMaterial:
		(q.material as ShaderMaterial).set_shader_parameter("tint", c)

func _flames(at: Vector3, kind: String, size: float, col: Color) -> void:
	var fl := FireFx.flames(0.25 * size, 0.45 * size, 50.0 * size, 0.5, 1.4, kind, 1.6)
	fl.one_shot = true
	fl.explosiveness = 0.85
	add_child(fl)
	fl.global_position = at
	fire.timed(fl, 1.0)
	var em := FireFx.embers(0.3 * size, 40.0 * size, 0.8, 1.6, 0.045, col)
	em.one_shot = true
	em.explosiveness = 0.9
	add_child(em)
	em.global_position = at
	fire.timed(em, 1.3)

func _sword_col(e: Dictionary) -> Color:
	return SWORD_COL[clampi(int(e.get("sword", 0)), 0, SWORD_COL.size() - 1)]

# ---- Events ---------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	var w: SimWorld = game.world
	match String(e.t):
		"root_snare":
			_snares[int(e.seq)] = {"u": int(e.u), "from": e.from, "dir": e.dir, "dist": float(e.dist),
				"speed": float(e.speed), "t": 0.0, "rod": _rod(VINE, 1.3), "end_t": -1.0, "target": -1}
		"root_snare_end":
			var s: Dictionary = _snares.get(int(e.seq), {})
			if not s.is_empty():
				s.end_t = 0.0
				s.target = int(e.target)
				s.dist = (e.pos as Vector2).distance_to(s.from)
			if int(e.target) >= 0 and fx._seen(e.pos):
				var at := fx._chest(int(e.target), 0.4)
				_leaves(at, 10, 2.4)
				fx.impact(at, VINE, 0.35)
		"seed_bomb":
			var a: Vector2 = e.from
			var b: Vector2 = e.pos
			if fx._seen(a) or fx._seen(b):
				var n := Node3D.new()
				add_child(n)
				n.add_child(FireFx.core(0.07, Color(0.6, 1.0, 0.35), 3.0))
				var tr := Trail3D.make(n, Color(0.5, 0.9, 0.3, 0.5), 0.05, 0.25)
				add_child(tr)
				_seeds.append({"node": n, "from": fx.ground3(a, 1.5), "to": fx.ground3(b, 0.1), "t": 0.0,
					"dur": maxf(0.2, float(e.delay)), "trail": tr})
				var rm := _mat("ring", VINE)
				var ring := _flat(b, Vector2.ONE * 5.0, Vector2.UP, rm, 0.05)
				_timed_add(ring, maxf(0.3, float(e.delay)) + 0.1, rm)
		"seed_bomb_burst":
			var p: Vector2 = e.pos
			if fx._seen(p):
				var r := float(e.radius) * View.S
				fx.shockwave(fx.ground3(p, 0.05), r, VINE, 0.45, 0.2, 2.4)
				_leaves(fx.ground3(p, 0.4), 16, 3.2)
				_dust(fx.ground3(p, 0.2), 1.1)
				fx.flash_light(fx.ground3(p, 1.0), Color(0.55, 1.0, 0.4), 3.5, 5.0, 0.3)
				fx._shake(p, 0.08, 0.15)
		"angry_forest":
			var gu := w.get_unit(int(e.u))
			if gu != null and fx._seen(gu.pos):
				fx.shockwave(fx.ground3(gu.pos, 0.05), float(e.radius) * View.S, VINE, 0.9, 0.12, 2.0)
				fx.edge_ring(fx.ground3(gu.pos, 0.06), float(e.radius) * View.S, VINE, 1.4)
				_leaves(fx._chest(gu.id, 0.7), 18, 3.0)
				fx.flash_light(fx._chest(gu.id, 0.7), Color(0.5, 1.0, 0.35), 5.0, 9.0, 0.45)
		"forest_lash":
			var ft := w.get_unit(int(e.target))
			if ft != null and (fx._seen(e.from) or fx._seen(ft.pos)):
				_lashes.append({"rod": _rod(VINE, 1.6), "from": fx.ground3(e.from, 0.9), "target": ft.id, "t": 0.0})
		"lance_charge", "cavalry_charge":
			_charge_start(e)
		"lance_charge_hit", "cavalry_charge_hit":
			var ht := w.get_unit(int(e.target))
			if ht != null and fx._seen(ht.pos):
				var c := fx._chest(ht.id, 0.5)
				fx.impact(c, GOLD if String(e.t) == "lance_charge_hit" else GHOST, 0.45)
				fx.sparks(c, Vector3.UP, 10, GOLD, 5.0)
				fx._shake(ht.pos, 0.1 if not bool(e.get("carried", false)) else 0.16, 0.16)
		"lance_charge_end", "cavalry_charge_end":
			_charge_end(int(e.u))
			var ep: Vector2 = e.pos
			if fx._seen(ep):
				_dust(fx.ground3(ep, 0.2), 1.3)
				if int(e.get("target", -1)) >= 0:
					fx.crack(fx.ground3(ep, 0.02), 1.4, GOLD, 1.6)
					fx.shockwave(fx.ground3(ep, 0.05), 2.0, DUST, 0.35, 0.2, 1.6)
					fx._shake(ep, 0.18, 0.25)
		"lance_sweep":
			var su := w.get_unit(int(e.u))
			if su != null and fx._seen(su.pos):
				var r2 := float(e.radius) * View.S
				fx.shockwave(fx.ground3(su.pos, 0.05), r2, GOLD, 0.35, 0.22, 2.4)
				fx.force_wall(fx.ground3(su.pos), 0.4, r2, 1.2, DUST, 0.35)
				_dust(fx.ground3(su.pos, 0.15), 1.4)
				for id in e.get("hits", []):
					var o := w.get_unit(int(id))
					if o != null:
						fx.sparks(fx._chest(o.id, 0.5), Vector3.UP, 5, GOLD, 4.0)
		"war_banner":
			var bp: Vector2 = e.pos
			if fx._seen(bp):
				_dust(fx.ground3(bp, 0.1), 0.9)
				fx.shockwave(fx.ground3(bp, 0.05), 1.6, GOLD, 0.3, 0.2, 2.0)
				fx.debris(fx.ground3(bp, 0.1), 6, EARTH, 2.5, 0.6, "rock")
		"sword_change":
			var du := w.get_unit(int(e.u))
			_hold(du)
			if du != null and fx._seen(du.pos):
				var v := fx._view_of(du.id)
				var col := _sword_col(e)
				var hp := v.hand_point("R") if v != null else fx._chest(du.id, 0.6)
				fx.sparks(hp, Vector3.UP, 12, col, 4.0)
				fx.impact(hp, col, 0.3)
				fx.flash_light(hp, col, 3.0, 4.0, 0.3)
		"dragon_blade_swing":
			var bv := fx._view_of(int(e.u))
			if bv != null:
				bv.set_weapon_glow(false)
				bv.set_weapon_glow(true, _sword_col(e))
				_lit[int(e.u)] = _clock + 0.6
		"dragon_blade":
			_blade(e)
		"dragon_dash":
			var a2: Vector2 = e.from
			var b2: Vector2 = e.to
			if fx._seen(a2) or fx._seen(b2):
				var m := _mat("streak", _sword_col(e))
				m.set_shader_parameter("glow", 2.2)
				var d := b2 - a2
				var sl := _flat((a2 + b2) * 0.5, Vector2(0.9, d.length() * View.S), d, m, 0.08)
				_timed_add(sl, 0.55, m)
				_dust(fx.ground3(a2, 0.1), 0.8)
		"dragon_dash_hit":
			var dt := w.get_unit(int(e.target))
			if dt != null and fx._seen(dt.pos):
				var c2 := fx._chest(dt.id, 0.5)
				fx.impact(c2, _sword_col(e), 0.4)
				fx.sparks(c2, Vector3.UP, 7, _sword_col(e), 4.5)
		"dragon_leap":
			_leap(e)
		"rising_slash":
			var rt := w.get_unit(int(e.target))
			if rt != null and fx._seen(rt.pos):
				var col2 := _sword_col(e)
				var base := fx.ground3(rt.pos, 0.1)
				var rod := _rod(col2, 2.6)
				Hero21Fx._rod(rod.node, base, base + Vector3(0, 3.2, 0), 0.12)
				_timed_add(rod.node, 0.35, rod.mat)
				fx.sparks(base + Vector3(0, 0.8, 0), Vector3.UP, 14, col2, 6.0)
				fx.impact(fx._chest(rt.id, 0.5), col2, 0.4)
				_dust(base, 0.8)

## A Dragon Blade strike that landed: its sword's power.
func _blade(e: Dictionary) -> void:
	var w: SimWorld = game.world
	var t := w.get_unit(int(e.target))
	var u := w.get_unit(int(e.u))
	if t == null or u == null or not (fx._seen(t.pos) or fx._seen(u.pos)):
		return
	var col := _sword_col(e)
	var at := fx._chest(t.id, 0.55)
	fx.impact(at, col, 0.55)
	fx.sparks(at, Vector3.UP, 14, col, 5.5)
	fx.flash_light(at, col, 4.0, 5.0, 0.3)
	fx._shake(t.pos, 0.1, 0.15)
	match String(e.get("id", "")):
		"pink":
			var from := at
			for id in e.get("chain", []):
				var o := w.get_unit(int(id))
				if o == null:
					continue
				var to := fx._chest(o.id, 0.55)
				fx.lightning(from, to, col, 0.35, 0.08)
				fx.impact(to, col, 0.3)
				from = to
		"gold":
			fx._light_spike(fx.ground3(u.pos), Color(1.0, 0.95, 0.75), 3.5)
		"blue":
			fx.shockwave(fx.ground3(t.pos, 0.05), 1.4, col, 0.4, 0.2, 2.0)
			_flames(fx.ground3(t.pos, 0.3), "water", 1.0, col)
		"red":
			fire.burst(fx.ground3(t.pos, 0.6), 2.5, "fire", 1.0)
		"green":
			_flames(fx.ground3(u.pos, 0.2), "shadowflame", 0.8, col)
			fx.sparks(fx._chest(u.id, 0.5), Vector3.UP, 10, col, 3.0)

## Dragon Leap: dust where she jumps, a trail in her sword's colour over the arc, a ring of it where she lands.
func _leap(e: Dictionary) -> void:
	var a: Vector2 = e.from
	var b: Vector2 = e.to
	var col := _sword_col(e)
	if fx._seen(a):
		_dust(fx.ground3(a, 0.1), 0.9)
	var v := fx._view_of(int(e.u))
	if v != null and (fx._seen(a) or fx._seen(b)):
		var tip := Node3D.new()
		v.add_child(tip)
		tip.position = Vector3(0, 1.2, 0)
		var tr := Trail3D.make(tip, Color(col.r, col.g, col.b, 0.55), 0.2, 0.35)
		add_child(tr)
		var tw := create_tween()
		tw.tween_interval(float(e.dur))
		tw.tween_callback(func():
			if is_instance_valid(tr):
				tr.stop()
			if is_instance_valid(tip):
				tip.queue_free())
	var land := create_tween()
	land.tween_interval(float(e.dur))
	land.tween_callback(func():
		if fx._seen(b):
			fx.shockwave(fx.ground3(b, 0.05), 1.8, col, 0.35, 0.2, 2.2)
			_dust(fx.ground3(b, 0.1), 1.0))

# ---- Charges ----------------------------------------------------------------------------------------------------------

func _charge_start(e: Dictionary) -> void:
	var id := int(e.u)
	_charge_end(id)
	var dust := FireFx.smoke(0.5, 30.0, 0.9, 1.2, 0.4, 0.45)
	_tint(dust, DUST)
	add_child(dust)
	var c := {"until": _clock + float(e.dur) + 0.1, "dust": dust, "riders": []}
	var n := int(e.get("riders", 0))
	if n > 0:
		var half := float(e.get("width", 400.0)) * 0.5
		for i in n:
			var side := (1.0 if i % 2 == 0 else -1.0) * half * (0.35 + 0.65 * float(i / 2) / maxf(1.0, float(n / 2 - 1)))
			var r := _rider(side, -40.0 - 50.0 * float(i / 2))
			if not r.is_empty():
				c.riders.append(r)
	_charges[id] = c

## One ghost rider: Lord Kaileh's body, see-through, in his charge.
func _rider(side: float, back: float) -> Dictionary:
	var def: Dictionary = SimData.unit("araki_ghost").duplicate()
	def["model"] = "kaileh_ghost"
	var u := SimUnit.new()
	u.setup(-50000 - randi() % 10000, def, 0, Vector2.ZERO, 0.0)
	u.moving = true
	u.move_speed = 1400.0
	var v := UnitView.new()
	add_child(v)
	v.setup(u, game.terrain)
	v.tick(u)
	v.visible = false
	return {"view": v, "unit": u, "side": side, "back": back}

func _charge_end(id: int) -> void:
	var c: Dictionary = _charges.get(id, {})
	if c.is_empty():
		return
	var d: GPUParticles3D = View.live(c.dust)
	if d:
		d.emitting = false
		fire.timed(d, 1.4)
	for r in c.riders:
		var v: UnitView = View.live(r.view)
		if v:
			if v.visible:
				var at := v.global_position + Vector3(0, 1.0, 0)
				var sm := FireFx.smoke(0.4, 30.0, 0.8, 0.9, 0.6, 0.35)
				_tint(sm, GHOST)
				sm.one_shot = true
				sm.explosiveness = 0.9
				add_child(sm)
				sm.global_position = at
				fire.timed(sm, 1.4)
			v.queue_free()
	_charges.erase(id)

func _update_charges(w: SimWorld, dt: float) -> void:
	for id in _charges.keys():
		var c: Dictionary = _charges[id]
		var u := w.get_unit(int(id))
		var v := fx._view_of(int(id))
		if u == null or v == null or not u.alive or _clock >= float(c.until):
			_charge_end(int(id))
			continue
		var d: Node3D = View.live(c.dust)
		if d:
			d.global_position = v.global_position + Vector3(0, 0.1, 0)
		var me := View.to2(v.global_position)
		var f := Vector2.from_angle(u.facing)
		var seen := fx._seen(u.pos)
		for r in c.riders:
			var rv: UnitView = View.live(r.view)
			if rv == null:
				continue
			var p := me + f * float(r.back) + f.orthogonal() * float(r.side)
			rv.prev_pos = p
			rv.cur_pos = p
			rv.prev_facing = u.facing
			rv.cur_facing = u.facing
			rv.visible = seen
			if not r.has("layered"):
				# never in the HUD portrait (it draws only its own layer, but a merged mesh can carry it over)
				r["layered"] = true
				for vi in rv.find_children("*", "VisualInstance3D", true, false):
					(vi as VisualInstance3D).layers = 1
			rv.frame(1.0, dt)
			if rv.anim:
				rv.anim.advance(dt)

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
	_update_snares(w, dt)
	_update_seeds(dt)
	_update_lashes(w, dt)
	_update_charges(w, dt)
	for id in _lit.keys():
		if _clock >= float(_lit[id]):
			var v := fx._view_of(int(id))
			if v:
				v.set_weapon_glow(false)
			_lit.erase(id)
	for k in _auras:
		var a: Node3D = View.live(_auras[k])
		var av := fx._view_of(int(String(k).split(":")[0]))
		if a and av:
			a.global_position = av.global_position + Vector3(0, 0.1, 0)

## Root Snare's vine: from where Gancho threw it to its tip, growing at the snare's speed; it holds a moment on whoever
## it caught, then withers.
func _update_snares(w: SimWorld, dt: float) -> void:
	for seq in _snares.keys():
		var s: Dictionary = _snares[seq]
		s.t = float(s.t) + dt
		var rod: Dictionary = s.rod
		var n: Node3D = View.live(rod.node)
		if n == null:
			_snares.erase(seq)
			continue
		var from: Vector2 = s.from
		var a := fx.ground3(from, 1.1)
		var gu := fx._view_of(int(s.u))
		if gu != null and float(s.end_t) < 0.0:
			a = gu.hand_point("R")
		var reach := minf(float(s.t) * float(s.speed), float(s.dist))
		var b := fx.ground3(from + (s.dir as Vector2) * reach, 0.9)
		if float(s.end_t) >= 0.0:
			s.end_t = float(s.end_t) + dt
			if int(s.target) >= 0 and w.get_unit(int(s.target)) != null:
				b = fx._chest(int(s.target), 0.35)
			var left := 1.0 - float(s.end_t) / 0.6
			(rod.mat as ShaderMaterial).set_shader_parameter("fade", clampf(left, 0.0, 1.0))
			if left <= 0.0:
				n.queue_free()
				_snares.erase(seq)
				continue
		n.visible = fx._seen(from) or fx._seen(from + (s.dir as Vector2) * reach)
		Hero21Fx._rod(n, a, b, 0.045)
		if float(s.t) > float(s.dist) / maxf(1.0, float(s.speed)) + 1.5:
			n.queue_free()
			_snares.erase(seq)

func _update_seeds(dt: float) -> void:
	for i in range(_seeds.size() - 1, -1, -1):
		var s: Dictionary = _seeds[i]
		s.t = float(s.t) + dt
		var k := clampf(float(s.t) / float(s.dur), 0.0, 1.0)
		var n: Node3D = View.live(s.node)
		if n:
			var p: Vector3 = (s.from as Vector3).lerp(s.to, k)
			p.y += sin(k * PI) * 2.2
			n.global_position = p
		if k >= 1.0:
			if n:
				n.queue_free()
			var tr = s.trail
			if tr is Trail3D and is_instance_valid(tr):
				(tr as Trail3D).stop()
			_seeds.remove_at(i)

## Angry Forest's lashes: a vine snaps out of the tree to the enemy, holds for a blink and withers.
func _update_lashes(w: SimWorld, dt: float) -> void:
	for i in range(_lashes.size() - 1, -1, -1):
		var l: Dictionary = _lashes[i]
		l.t = float(l.t) + dt
		var n: Node3D = View.live(l.rod.node)
		var t := w.get_unit(int(l.target))
		if n == null or t == null or float(l.t) >= 0.45:
			if n:
				n.queue_free()
			_lashes.remove_at(i)
			continue
		var a: Vector3 = l.from
		var b := fx._chest(t.id, 0.4)
		var grow := clampf(float(l.t) / 0.12, 0.0, 1.0)
		Hero21Fx._rod(n, a, a.lerp(b, grow), 0.05)
		(l.rod.mat as ShaderMaterial).set_shader_parameter("fade", clampf((0.45 - float(l.t)) / 0.25, 0.0, 1.0))
		if grow >= 1.0 and not l.has("hit"):
			l["hit"] = true
			_leaves(b, 5, 1.8)

## Dracoxinia's sword in her hand, matched to the one she holds (every view, joined mid-game too); Angry Forest's
## motes round Gancho.
func _scan(w: SimWorld) -> void:
	var want := {}
	for h in w.heroes:
		if h.ability_level.has("change_sword"):
			_hold(h)
		if h.alive and not h.get_modifier("angry_forest").is_empty():
			want[str(h.id) + ":forest"] = h.id
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
			var n := Node3D.new()
			add_child(n)
			var em := FireFx.embers(0.9, 18.0, 1.4, 0.6, 0.04, Color(0.55, 1.0, 0.4))
			n.add_child(em)
			var lt := FireFx.light(Color(0.5, 1.0, 0.35), 0.8, 3.0)
			lt.position = Vector3(0, 1.2, 0)
			n.add_child(lt)
			_auras[k] = n

func _hold(h: SimUnit) -> void:
	if h == null:
		return
	var v := fx._view_of(h.id)
	if v == null:
		return
	var i: int = game.world.abilities.kits11.sword_of(h)
	if int(_held.get(h.id, 0)) == i and _held.has(h.id):
		return
	var names: Array = v.cfg.get("swords", [])
	if i < names.size():
		var trails: Array = v.cfg.get("sword_trails", [])
		v.swap_weapon("R", String(names[i]), trails[i] if i < trails.size() else null)
	_held[h.id] = i

# ---- Lord Kaileh's banner (Main's view for the War Banner ward) ------------------------------------------------------

## A banner on a pole in his house colours (team-tinted trim), its reach a faint ring on the ground.
func make_banner(team: int, radius: float) -> Node3D:
	var n := Node3D.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.2, 0.12)
	wood.roughness = 0.85
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.045
	cyl.height = 3.2
	pole.mesh = cyl
	pole.material_override = wood
	pole.position.y = 1.6
	n.add_child(pole)
	var bar := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.025
	bc.bottom_radius = 0.025
	bc.height = 1.0
	bar.mesh = bc
	bar.material_override = wood
	bar.rotation.z = PI * 0.5
	bar.position = Vector3(0.45, 3.05, 0)
	n.add_child(bar)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.78, 0.3)
	gold.metallic = 0.9
	gold.roughness = 0.3
	var top := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.08
	sp.height = 0.16
	top.mesh = sp
	top.material_override = gold
	top.position.y = 3.25
	n.add_child(top)
	var cloth := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 1.4)
	q.subdivide_width = 8
	q.subdivide_depth = 8
	cloth.mesh = q
	var cm := _mat("cloth", Color(0.55, 0.07, 0.09) if team == 0 else Color(0.2, 0.08, 0.32))
	cm.set_shader_parameter("trim", Color(1.0, 0.8, 0.35))
	cloth.material_override = cm
	cloth.position = Vector3(0.48, 2.32, 0)
	n.add_child(cloth)
	var rm := _mat("ring", Color(1.0, 0.82, 0.4) if team == 0 else Color(0.85, 0.5, 1.0))
	var ring := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2.ONE * radius * View.S * 2.0
	rq.orientation = PlaneMesh.FACE_Y
	ring.mesh = rq
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.06
	n.add_child(ring)
	return n

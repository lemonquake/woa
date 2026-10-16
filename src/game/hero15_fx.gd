class_name Hero15Fx
extends Node
## Visuals for Tock, the Clockmaker and Kragg, the Magnet Knight (run 2026-10-15 b), driven by their sim events and
## the modifiers on units. Units: metres (1 game unit = 1 cm).
##   Tock: Time Bolt (a golden core inside a turning clock ring, a gold ribbon), its hit (a clock-face flash), Fast
##   Forward (a green-gold ring turning fast over the ally), Rewind (a blue afterimage where he was, a streak to where
##   he lands), Slow Field (a slowly turning ground dial with 12 ticks for its 5 s), Stop Time (a pale dome over the area,
##   a still clock face on the ground), Quick Hands (gold sparks at his hands); delayed enemies carry a slow grey ring.
##   Kragg: Iron Grip (a lightning arc between them, a snap at the middle), Repel (a blue force wall and shockwave),
##   Overload (a ring of arcs bursting from Kragg and a bolt to each enemy hit), Magnet Field (blue rings on the ground
##   closing in on him, arcs to the enemies it drags), its end (a shockwave); Charges: small blue sparks orbiting the
##   enemy, one per Charge.

const EVENTS := ["time_bolt", "time_bolt_move", "time_bolt_hit", "fast_forward", "rewind", "slow_field", "slow_field_end",
	"stop_time", "quick_hands", "iron_grip", "repel", "overload", "magnet_field", "magnet_field_end"]
const GOLD := Color(1.0, 0.82, 0.38)
const TIME_BLUE := Color(0.55, 0.8, 1.0)
const SPARK := Color(0.45, 0.7, 1.0)

var game: Node
var fx: Fx
var fire: FireFx
var _bolts := {}                           # Time Bolt seq -> {node, trail}
var _timed: Array = []                     # {node, t, life, kind, mat, spin, follow}
var _charges := {}                         # unit id -> {node, n}
var _delayed := {}                         # unit id -> ring
var _fields := {}                          # Kragg id -> field node
var _scan_i := 0

const DIAL_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.82, 0.38, 1.0);
uniform float fade = 1.0;
uniform float hand = 0.0;
uniform float ticks = 12.0;
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float a = atan(q.y, q.x);
	float rim = smoothstep(0.86, 0.92, r) * (1.0 - smoothstep(0.95, 1.0, r));
	float inner = smoothstep(0.6, 0.63, r) * (1.0 - smoothstep(0.64, 0.67, r)) * 0.5;
	float tk = step(0.97, cos((a) * ticks)) * smoothstep(0.72, 0.76, r) * (1.0 - smoothstep(0.85, 0.87, r));
	float ha = mod(a - hand + 3.14159, 6.28318) - 3.14159;
	float h = (1.0 - smoothstep(0.0, 0.05, abs(ha))) * step(r, 0.82) * step(0.05, r);
	float fill = (1.0 - smoothstep(0.0, 1.0, r)) * 0.03;
	ALBEDO = col.rgb * 2.0;
	ALPHA = clamp((rim + inner + tk + h * 0.9 + fill) * fade, 0.0, 1.0);
}
"""

const DOME_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float fade = 1.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float bands = 0.5 + 0.5 * sin(UV.y * 60.0);
	ALBEDO = col.rgb * 1.6;
	ALPHA = clamp((f * 0.42 + bands * 0.025) * fade, 0.0, 1.0);
}
"""

static var _dial: Shader
static var _dome: Shader

static func dial_material(col: Color, ticks := 12.0) -> ShaderMaterial:
	if _dial == null:
		_dial = Shader.new()
		_dial.code = DIAL_CODE
	var m := ShaderMaterial.new()
	m.shader = _dial
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("ticks", ticks)
	return m

func _ground_disc(at: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.06, 0)
	return mi

func _timed_add(node: Node3D, life: float, kind := "", mat: Material = null, spin := 0.0, follow := -1) -> void:
	_timed.append({"node": node, "t": 0.0, "life": life, "kind": kind, "mat": mat, "spin": spin, "follow": follow})

# ---- Events -----------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	var w: SimWorld = game.world
	match String(e.t):
		"time_bolt":
			var n := Node3D.new()
			add_child(n)
			n.add_child(FireFx.core(0.16, GOLD, 5.0))
			var ring := _ground_disc(Vector3.ZERO, 0.45, dial_material(GOLD, 12.0))
			ring.reparent(n, false)
			ring.position = Vector3.ZERO
			ring.rotation.x = PI * 0.5
			n.add_child(FireFx.embers(0.1, 30.0, 0.5, 0.1, 0.04, GOLD))
			var from: Vector2 = e.from
			n.global_position = fx.ground3(from, 1.1)
			var tr := Trail3D.make(n, Color(1.0, 0.85, 0.45, 0.7), 0.18, 0.3)
			add_child(tr)
			_bolts[int(e.seq)] = {"node": n, "trail": tr, "ring": ring, "dir": e.dir}
		"time_bolt_move":
			var b = _bolts.get(int(e.seq))
			if b != null:
				var n2: Node3D = View.live(b.node)
				var p: Vector2 = e.pos
				n2.global_position = fx.ground3(p, 1.1)
				(b.ring as Node3D).rotation.z += 0.35
				if bool(e.done):
					(b.trail as Trail3D).stop()
					fire.timed(n2, 0.0)
					_bolts.erase(int(e.seq))
		"time_bolt_hit":
			var c := fx._chest(int(e.u), 0.6)
			fx.impact(c, GOLD, 0.35)
			fx.flash_light(c, GOLD, 2.0, 3.0, 0.2)
			var dm := dial_material(Color(0.8, 0.85, 1.0))
			var d := _ground_disc(c, 0.55, dm)
			d.rotation.x = 0.0
			_timed_add(d, 0.6, "fade", dm, 3.0)
		"fast_forward":
			var tu: SimUnit = w.get_unit(int(e.target))
			if tu:
				fx.sparks(fx._chest(tu.id, 0.6), Vector3.UP, 14, Color(0.7, 1.0, 0.55), 4.0)
				var fm := dial_material(Color(0.6, 1.0, 0.5), 8.0)
				var fd := _ground_disc(fx.ground3(tu.pos), 0.9, fm)
				_timed_add(fd, float(e.dur), "fade", fm, 9.0, tu.id)
		"rewind":
			var fr: Vector2 = e.from
			var to: Vector2 = e.to
			for p2 in [fr, to]:
				fx.flash_light(fx.ground3(p2, 1.0), TIME_BLUE, 3.0, 4.0, 0.3)
				fx.shockwave(fx.ground3(p2, 0.05), 1.0, TIME_BLUE, 0.45, 0.15, 2.0)
			if fr.distance_to(to) < 20.0:
				return
			fx.lightning(fx.ground3(fr, 1.0), fx.ground3(to, 1.0), Color(0.6, 0.85, 1.0), 0.35, 0.05, 8)
			var rv = fx._view_of(int(e.u))
			if rv and game.get("caziel_fx") != null:
				game.caziel_fx._ghost(rv, fx.ground3(fr), (to - fr).angle(), 0.0, 0.8)
		"slow_field":
			var sm := dial_material(Color(0.7, 0.85, 1.0), 12.0)
			var sd := _ground_disc(fx.ground3(e.pos), float(e.radius) * View.S, sm)
			_timed_add(sd, float(e.dur), "dial", sm, 0.4)
		"stop_time":
			var r := float(e.radius) * View.S
			var at := fx.ground3(e.pos)
			if _dome == null:
				_dome = Shader.new()
				_dome.code = DOME_CODE
			var dmat := ShaderMaterial.new()
			dmat.shader = _dome
			var dome := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = r
			sph.height = r * 1.2
			dome.mesh = sph
			dome.material_override = dmat
			dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(dome)
			dome.global_position = at
			_timed_add(dome, float(e.dur), "fade", dmat)
			var cm := dial_material(Color(0.42, 0.55, 0.8), 12.0)
			var cd := _ground_disc(at, r, cm)
			_timed_add(cd, float(e.dur), "fade", cm)
			fx.shockwave(at + Vector3(0, 0.05, 0), r, Color(0.8, 0.9, 1.0), 0.5, 0.3, 2.0)
			fx.flash_light(at + Vector3(0, 2, 0), Color(0.75, 0.85, 1.0), 4.0, r * 2.0, 0.4)
			for id in e.get("frozen", []):
				fx.sparks(fx._chest(int(id), 0.6), Vector3.UP, 8, Color(0.8, 0.9, 1.0), 2.0)
		"quick_hands":
			var qu: SimUnit = w.get_unit(int(e.u))
			if qu and fx._seen(qu.pos):
				fx.sparks(fx._chest(qu.id, 0.55), Vector3.UP, 6, GOLD, 2.5)
		"iron_grip":
			var ku: SimUnit = w.get_unit(int(e.u))
			var kt: SimUnit = w.get_unit(int(e.target))
			if ku and kt:
				fx.lightning(fx._chest(ku.id, 0.6), fx._chest(kt.id, 0.6), SPARK, 0.35, 0.09, 12)
				var mid := fx.ground3(e.mid, 1.0)
				fx.flash_light(mid, SPARK, 3.0, 4.0, 0.3)
				fx.sparks(mid, Vector3.UP, 14, Color(0.7, 0.85, 1.0), 4.0)
		"repel":
			var at2 := fx.ground3(e.pos)
			var rr := float(e.radius) * View.S
			fx.force_wall(at2, 0.4, rr, 1.6, SPARK, 0.4)
			fx.shockwave(at2 + Vector3(0, 0.05, 0), rr, SPARK, 0.4, 0.25, 2.5)
			fx.flash_light(at2 + Vector3(0, 1, 0), SPARK, 3.0, rr * 1.5, 0.25)
		"overload":
			# a burst of electric charge around Kragg: a ring of arcs over the ground and a bolt to everyone hit
			var ou: SimUnit = w.get_unit(int(e.u))
			if ou and fx._seen(ou.pos):
				var oc := fx._chest(ou.id, 0.6)
				var og := fx.ground3(e.get("pos", ou.pos))
				var orr := float(e.radius) * View.S
				fx.flash_light(oc, SPARK, 3.0, orr * 3.0, 0.3)
				fx.shockwave(og + Vector3(0, 0.05, 0), orr, SPARK, 0.3, 0.2, 2.0)
				for i in 6:
					var ang := TAU * i / 6.0 + float(Time.get_ticks_msec() % 1000) * 0.006
					var rim := og + Vector3(cos(ang) * orr, 0.25, sin(ang) * orr)
					fx.lightning(oc, rim, Color(0.75, 0.9, 1.0), 0.22, 0.04, 8)
				for id in e.get("hits", []):
					var tc := fx._chest(int(id), 0.55)
					fx.lightning(oc, tc, SPARK, 0.28, 0.06, 10)
					fx.impact(tc, SPARK, 0.3)
		"magnet_field":
			var mf := Node3D.new()
			add_child(mf)
			var mm := dial_material(SPARK, 24.0)
			var md := _ground_disc(Vector3.ZERO, float(e.radius) * View.S, mm)
			md.reparent(mf, false)
			md.position = Vector3(0, 0.06, 0)
			mf.add_child(FireFx.embers(float(e.radius) * View.S * 0.8, 40.0, 0.7, 0.4, 0.04, SPARK))
			mf.add_child(FireFx.light(SPARK, 1.4, 6.0))
			_fields[int(e.u)] = mf
			_timed_add(mf, float(e.dur) + 0.2, "field", mm, -1.2, int(e.u))
		"magnet_field_end":
			var eu: SimUnit = w.get_unit(int(e.u))
			if eu:
				var ea := fx.ground3(eu.pos)
				fx.shockwave(ea + Vector3(0, 0.05, 0), float(e.radius) * View.S, SPARK, 0.45, 0.3, 3.0)
				fx.crack(ea, 1.8, Color(0.4, 0.6, 1.0), 2.0)
				fx._shake(eu.pos, 0.2, 0.3)
				for id in e.get("stunned", []):
					fx.lightning(fx._chest(eu.id, 0.6), fx._chest(int(id), 0.6), SPARK, 0.3, 0.08, 10)
			_fields.erase(int(e.u))

# ---- Per frame --------------------------------------------------------------------------------------------------------

func update(w: SimWorld, _alpha: float, dt: float) -> void:
	_scan_i += 1
	if _scan_i % 3 == 0:
		_scan(w)
	for i in range(_timed.size() - 1, -1, -1):
		var t: Dictionary = _timed[i]
		t.t = float(t.t) + dt
		var n: Node3D = View.live(t.node)
		if not is_instance_valid(n) or float(t.t) >= float(t.life):
			if is_instance_valid(n):
				fire.timed(n, 0.0)
			_timed.remove_at(i)
			continue
		var k := float(t.t) / float(t.life)
		var follow := int(t.follow)
		if follow >= 0:
			var fv := fx._view_of(follow)
			if fv:
				n.global_position = Vector3(fv.global_position.x, fx.ground_y(View.to2(fv.global_position)) + 0.06, fv.global_position.z)
		var m: ShaderMaterial = t.mat
		if m:
			var fade := clampf(minf(float(t.t) / 0.15, (float(t.life) - float(t.t)) / 0.35), 0.0, 1.0)
			m.set_shader_parameter("fade", fade)
			if t.kind == "dial":
				m.set_shader_parameter("hand", k * TAU)
			elif t.kind == "field":
				m.set_shader_parameter("hand", -k * TAU * 3.0)
		if float(t.spin) != 0.0 and t.kind != "field":
			n.rotation.y += float(t.spin) * dt
		elif t.kind == "field":
			n.scale = Vector3.ONE * (1.0 - 0.08 * fmod(float(t.t) * 1.5, 1.0))
	# Magnet Field: an arc now and then to an enemy it drags
	if Engine.get_frames_drawn() % 9 == 0:
		for kid in _fields:
			var ku: SimUnit = w.get_unit(int(kid))
			if ku == null or not ku.alive:
				continue
			for o: SimUnit in w.query(ku.pos, 700.0):
				if o.alive and o.team != ku.team and not o.is_building() and randf() < 0.25 and fx._seen(o.pos):
					fx.lightning(fx._chest(ku.id, 0.6), fx._chest(o.id, 0.55), SPARK, 0.18, 0.04, 8)
					break
	# Charges orbit their unit
	var now := Time.get_ticks_msec() / 1000.0
	for id in _charges:
		var c: Dictionary = _charges[id]
		var v := fx._view_of(int(id))
		var n2: Node3D = View.live(c.node)
		if v == null or not is_instance_valid(n2):
			continue
		n2.visible = v.visible
		n2.global_position = v.global_position + Vector3(0, v.bar_height * 0.55, 0)
		var kids := n2.get_children()
		for j in kids.size():
			var a := now * 3.0 + TAU * j / maxf(1.0, kids.size())
			(kids[j] as Node3D).position = Vector3(cos(a), 0.15 * sin(now * 5.0 + j), sin(a)) * 0.55
	for id in _delayed:
		var dv := fx._view_of(int(id))
		var dn: Node3D = View.live(_delayed[id])
		if dv and is_instance_valid(dn):
			dn.visible = dv.visible
			dn.global_position = dv.global_position + Vector3(0, dv.bar_height + 0.15, 0)
			dn.rotation.y += dt * 0.6

func _scan(w: SimWorld) -> void:
	var want_charges := {}
	var want_delayed := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView) or not v.visible:
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive:
			continue
		for m in u.modifiers:
			var f := String(m.get("fx", ""))
			if f == "magnet" and w.time < float(m.expires):
				want_charges[id] = int(m.get("charges", 1))
			elif f == "time_slow" or f == "stop_time":
				want_delayed[id] = true
	for id in _charges.keys():
		if not want_charges.has(id) or int(_charges[id].n) != int(want_charges[id]):
			var old: Node3D = View.live(_charges[id].node)
			if is_instance_valid(old):
				old.queue_free()
			_charges.erase(id)
	for id in want_charges:
		if not _charges.has(id):
			var n := Node3D.new()
			add_child(n)
			for j in int(want_charges[id]):
				n.add_child(FireFx.core(0.06, SPARK, 4.0))
			_charges[id] = {"node": n, "n": int(want_charges[id])}
	for id in _delayed.keys():
		if not want_delayed.has(id):
			var old2: Node3D = View.live(_delayed[id])
			if is_instance_valid(old2):
				old2.queue_free()
			_delayed.erase(id)
	for id in want_delayed:
		if not _delayed.has(id):
			var dm := dial_material(Color(0.75, 0.82, 0.95), 12.0)
			dm.set_shader_parameter("fade", 0.8)
			var d := _ground_disc(Vector3.ZERO, 0.32, dm)
			_delayed[id] = d

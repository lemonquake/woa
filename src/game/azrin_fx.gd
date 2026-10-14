class_name AzrinFx
extends Node
## Azrin's fire, drawn with FireFx's particle fire:
##   * her presence: she hovers over a small pyre, flames lick from both hands, sparks drift off her and a warm light
##     flickers round her (all world-space, so the fire streams behind her as she glides);
##   * Spirit of Fire: up to five wisps of spirit flame circle her; shot, they arc to the target and burst there;
##   * Fiery Javelin: a great burning spear trailing fire, enemies it catches hauled along burning;
##   * Touch of Ember: a ring of spirit flame bursts over the area; marked enemies carry pale flames with a shrinking
##     ring (their time) until the flames explode;
##   * Divine Smite: a burning war hammer thrown end over end; where it lands the ground catches fire;
##   * Burning: any unit with a Fire burn on it (any source) is wreathed in flame, smoke and sparks.
## Built from simulation events and the units' modifiers every frame, so nothing outlives what it shows.

const EVENTS := ["javelin_launch", "javelin_move", "javelin_catch", "ember_cast", "ember_explode", "spirits_launch",
	"spirits_hit", "smite_launch", "smite_move", "smite_hit", "spirit_gain"]

var game: Node
var fx: Fx
var fire: FireFx
var _aura := {}                            # Azrin's view id -> {pyre, hands: [L, R], sparks, light}
var _spirits := {}                         # Azrin's id -> Array of {node, phase}
var _javelins := {}                        # seq -> {node, dir3, last}
var _hammers := {}                         # seq -> {node, from, t, spin}
var _flyers: Array = []                    # spirits shot: {node, from, to, t, dur, arc}
var _burning := {}                         # unit id -> Node3D (flames on the body)
var _marks := {}                           # unit id -> {node, ring, ring_mat, until, total}
var _scan_i := 0

const SPIRIT_ORBIT := 0.95                 # m from her centre
const FLOAT := 0.75                        # how high she hovers (matches ModelCatalog "hero_azrin")

# ---- Events -------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	match String(e.t):
		"javelin_launch":
			_javelin_launch(e)
		"javelin_move":
			_javelin_move(e)
		"javelin_catch":
			var v := fx._view_of(int(e.u))
			if v and v.visible:
				var c := fx._chest(int(e.u), 0.5)
				fire.burst(c, 0.5, "fire", 0.7)
				fx.sparks(c, Vector3.UP, 8, Color(1.0, 0.6, 0.2), 4.0)
		"ember_cast":
			var p: Vector2 = e.pos
			if fx._seen(p):
				var r := float(e.radius) * View.S
				fire.ground_fire(fx.ground3(p, 0.05), r, 0.5, "spirit")
				fire.burst(fx.ground3(p, 0.3), r * 0.6, "spirit", 1.0)
				fx.shockwave(fx.ground3(p, 0.05), r * 1.05, Color(1.0, 0.55, 0.35), 0.5, 0.12, 2.0)
		"ember_explode":
			var u: SimUnit = game.world.get_unit(int(e.u))
			if u and fx._seen(u.pos):
				var c2 := fx._chest(u.id, 0.5)
				fire.burst(c2, 1.1, "spirit", 1.4)
				fire.burst(fx.ground3(u.pos, 0.2), 0.8, "fire", 1.0)
				fx.shockwave(fx.ground3(u.pos, 0.05), 1.8, Color(1.0, 0.5, 0.3), 0.4, 0.2, 3.0)
				fx.flash_light(c2, Color(1.0, 0.6, 0.4), 5.0, 6.0, 0.35)
		"spirits_launch":
			_shoot_spirits(e)
		"spirits_hit":
			var sp: Vector2 = e.pos
			if fx._seen(sp):
				var rr := float(e.radius) * View.S
				var n := maxi(1, int(e.n))
				fire.burst(fx.ground3(sp, 0.4), rr * 0.7, "spirit", 0.6 + 0.15 * n)
				fire.ground_fire(fx.ground3(sp, 0.05), rr, 1.2 + 0.2 * n, "fire")
		"smite_launch":
			_smite_launch(e)
		"smite_move":
			if _hammers.has(int(e.seq)):
				_hammers[int(e.seq)]["goal"] = e.pos
		"smite_hit":
			_smite_hit(e)

# ---- Per frame -----------------------------------------------------------------------------------------------------

func update(w: SimWorld, _alpha: float, dt: float) -> void:
	_scan_i += 1
	if _scan_i % 3 == 0:
		_scan(w)
	_follow(w, dt)
	_update_flyers(dt)
	_update_hammers(dt)

## Which units need which visuals (modifiers change at 30 Hz at most).
func _scan(w: SimWorld) -> void:
	var want_aura := {}
	var want_burn := {}
	var want_mark := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView):
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive or not v.visible:
			continue
		if String(u.def.get("model", "")) == "hero_azrin":
			want_aura[id] = true
		for m in u.modifiers:
			var f := String(m.get("fx", ""))
			if f == "burn":
				want_burn[id] = true
			elif f == "ember_mark":
				want_mark[id] = m
	_sync(_aura, want_aura, _make_aura)
	_sync(_burning, want_burn, _make_burning)
	for id in _marks.keys():
		if not want_mark.has(id):
			_free_mark(id)
	for id in want_mark:
		if not _marks.has(id):
			_marks[id] = _make_mark(id, want_mark[id])
	# spirits circling each Azrin
	for id in want_aura:
		var u: SimUnit = w.get_unit(id)
		var n := int(u.stacks.get("spirits", 0))
		var list: Array = _spirits.get(id, [])
		while list.size() < n:
			var s := FireFx.fireball(0.62, "spirit")
			add_child(s)
			var v2: UnitView = game.views[id]
			s.global_position = v2.global_position + Vector3(0, 1.5, 0)
			list.append({"node": s, "phase": randf() * TAU})
			fire.burst(s.global_position, 0.25, "spirit", 0.4)
		while list.size() > n:
			var gone: Dictionary = list.pop_back()
			fire.timed(gone.node, 0.0)
		_spirits[id] = list
	for id in _spirits.keys():
		if not want_aura.has(id):
			for s in _spirits[id]:
				fire.timed(s.node, 0.0)
			_spirits.erase(id)

func _sync(store: Dictionary, want: Dictionary, make: Callable) -> void:
	for id in store.keys():
		if not want.has(id):
			var n = store[id]
			if n is Dictionary:
				for k in n:
					if n[k] is Node3D:
						fire.timed(n[k], 0.0)
					elif n[k] is Array:
						for x in n[k]:
							fire.timed(x, 0.0)
			elif is_instance_valid(n):
				fire.timed(n, 0.0)
			store.erase(id)
	for id in want:
		if not store.has(id):
			store[id] = make.call(id)

## Azrin's presence: a pyre burning on a scorched, glowing patch of ground under her; the hem of her robe streaming
## fire; burning hands; flames running through her hair; sparks; a flickering warm light.
func _make_aura(_id: int) -> Dictionary:
	var pyre := Node3D.new()
	add_child(pyre)
	var pf := FireFx.flames(0.34, 0.7, 26.0, 0.6, 1.4, "fire", 0.95)
	pyre.add_child(pf)
	var pe := FireFx.embers(0.35, 12.0, 1.8, 1.5)
	pyre.add_child(pe)
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	q.orientation = PlaneMesh.FACE_Y
	glow.mesh = q
	var gm := ShaderMaterial.new()
	var gs := Shader.new()
	gs.code = SCORCH_CODE
	gm.shader = gs
	glow.material_override = gm
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position.y = -0.08
	pyre.add_child(glow)
	# the robe's hem: a ring of flame round her legs that streams behind her as she glides
	var hem := FireFx.flames(0.0, 0.55, 60.0, 0.5, 0.9, "fire", 1.3)
	var hm := hem.process_material as ParticleProcessMaterial
	hm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	hm.emission_ring_axis = Vector3.UP
	hm.emission_ring_radius = 0.26
	hm.emission_ring_inner_radius = 0.16
	hm.emission_ring_height = 0.25
	add_child(hem)
	var hands: Array = []
	for i in 2:
		var hf := FireFx.flames(0.05, 0.45, 40.0, 0.4, 1.0, "fire", 1.6)
		add_child(hf)
		hands.append(hf)
	# hair aflame: tongues rising off the back of her head
	var hair := FireFx.flames(0.12, 0.42, 30.0, 0.45, 1.0, "fire", 1.2)
	add_child(hair)
	var crown := FireFx.embers(0.2, 8.0, 1.3, 1.0, 0.035)
	add_child(crown)
	var l := FireFx.light(Color(1.0, 0.55, 0.22), 1.3, 6.0)
	add_child(l)
	fire.flicker(l)
	return {"pyre": pyre, "hem": hem, "hands": hands, "hair": hair, "crown": crown, "light": l}

## The scorched ground under her: dark ash with embers glowing through cracks, pulsing.
const SCORCH_CODE := """
shader_type spatial;
render_mode blend_premul_alpha, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
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
	float n = vnoise(p * 5.0) * 0.6 + vnoise(p * 11.0 + 3.0) * 0.4;
	float edge = 1.0 - smoothstep(0.45, 1.0, r + (n - 0.5) * 0.3);
	float lines = 1.0 - smoothstep(0.01, 0.09, abs(n - 0.52));
	float pulse = 0.75 + 0.25 * sin(TIME * 3.1 + n * 6.0);
	float glow = lines * edge * edge * pulse;
	// dark ash that covers the ground, cracks glowing orange through it
	vec3 hot = mix(vec3(0.75, 0.14, 0.02), vec3(1.0, 0.42, 0.08), lines) * 1.2;
	float ash = edge * 0.6;
	ALBEDO = vec3(0.04, 0.03, 0.025) * ash + hot * glow;
	ALPHA = ash;
}
"""

func _make_burning(id: int) -> Node3D:
	var v: UnitView = game.views.get(id)
	var size := clampf(v.bar_height / 2.2, 0.7, 1.8) if v else 1.0
	var n := Node3D.new()
	add_child(n)
	var f := FireFx.flames(0.25 * size, 0.7 * size, 30.0 * size, 0.7, 1.4, "fire", 1.3)
	n.add_child(f)
	var e := FireFx.embers(0.3 * size, 8.0, 1.2, 1.3)
	n.add_child(e)
	var s := FireFx.smoke(0.2 * size, 2.5, 0.8 * size, 1.8, 0.9, 0.35)
	s.position.y = 0.9 * size
	n.add_child(s)
	var l := FireFx.light(Color(1.0, 0.5, 0.18), 1.2, 3.5)
	l.position.y = 0.8
	n.add_child(l)
	fire.flicker(l)
	return n

## Touch of Ember's mark: pale spirit flames round the unit, and a ring on the ground that closes as its time runs out.
func _make_mark(id: int, m: Dictionary) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	var f := FireFx.flames(0.3, 0.45, 26.0, 0.6, 1.0, "spirit", 1.4)
	var pm := f.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.45
	pm.emission_ring_inner_radius = 0.35
	pm.emission_ring_height = 1.2
	f.position.y = 0.9
	n.add_child(f)
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.8, 1.8)
	q.orientation = PlaneMesh.FACE_Y
	ring.mesh = q
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = RING_CODE
	mat.shader = sh
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	return {"node": n, "ring": ring, "mat": mat, "until": float(m.get("expires", 0.0)), "total": float(m.get("dur", 4.0))}

const RING_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float left = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.2832 + 0.5;
	float rim = smoothstep(0.8, 0.86, r) * (1.0 - smoothstep(0.9, 0.96, r));
	float timer = step(a, left) * smoothstep(0.62, 0.66, r) * (1.0 - smoothstep(0.72, 0.76, r));
	float pulse = 0.75 + 0.25 * sin(TIME * (6.0 + (1.0 - left) * 14.0));
	ALBEDO = mix(vec3(1.0, 0.45, 0.35), vec3(1.0, 0.85, 0.6), timer) * 2.2;
	ALPHA = clamp((rim * 0.7 + timer) * pulse, 0.0, 1.0);
}
"""

func _free_mark(id: int) -> void:
	var mk: Dictionary = _marks[id]
	fire.timed(mk.node, 0.0)
	if is_instance_valid(mk.ring):
		mk.ring.queue_free()
	_marks.erase(id)

func _follow(w: SimWorld, dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for id in _aura:
		var v: UnitView = game.views.get(id)
		var a: Dictionary = _aura[id]
		if v == null or not is_instance_valid(a.pyre):
			continue
		var base := v.global_position
		(a.pyre as Node3D).global_position = Vector3(base.x, fx.ground_y(View.to2(base)) + 0.1, base.z)
		var hs: Array = a.hands
		(hs[0] as Node3D).global_position = v.hand_point("L")
		(hs[1] as Node3D).global_position = v.hand_point("R")
		var head := _bone(v, "head", base + Vector3(0, FLOAT + 1.65, 0))
		(a.hair as Node3D).global_position = head + v.global_transform.basis.z * -0.08 + Vector3(0, 0.12, 0)
		(a.hem as Node3D).global_position = _bone(v, "hips", base + Vector3(0, FLOAT + 0.9, 0)) + Vector3(0, -0.75, 0)
		(a.crown as Node3D).global_position = head + Vector3(0, 0.2, 0)
		(a.light as Node3D).global_position = base + Vector3(0, 0.45, 0)
		# her spirits circle her chest, bobbing
		var list: Array = _spirits.get(id, [])
		for i in list.size():
			var s: Dictionary = list[i]
			var ang := now * 1.6 + TAU * i / maxf(1.0, list.size()) + float(s.phase) * 0.05
			var target := base + Vector3(cos(ang) * SPIRIT_ORBIT, FLOAT + 1.25 + sin(now * 2.3 + i) * 0.15, sin(ang) * SPIRIT_ORBIT)
			var node: Node3D = s.node
			node.global_position = node.global_position.lerp(target, clampf(dt * 10.0, 0.0, 1.0))
	for id in _burning:
		var bv: UnitView = game.views.get(id)
		if bv and is_instance_valid(_burning[id]):
			(_burning[id] as Node3D).global_position = bv.global_position + Vector3(0, 0.15, 0)
	for id in _marks:
		var mv: UnitView = game.views.get(id)
		var mk: Dictionary = _marks[id]
		if mv == null:
			continue
		(mk.node as Node3D).global_position = mv.global_position
		var gp := mv.global_position
		(mk.ring as Node3D).global_position = Vector3(gp.x, fx.ground_y(View.to2(gp)) + 0.06, gp.z)
		var left := clampf((float(mk.until) - w.time) / maxf(0.1, float(mk.total)), 0.0, 1.0)
		(mk.mat as ShaderMaterial).set_shader_parameter("left", left)

## A bone's world position from the view's current pose, or `fallback`.
func _bone(v: UnitView, bone: String, fallback: Vector3) -> Vector3:
	if v.skeleton:
		var bi := v.skeleton.find_bone(bone)
		if bi >= 0:
			return v.skeleton.global_transform * v.skeleton.get_bone_global_pose(bi).origin
	return fallback

# ---- Fiery Javelin ------------------------------------------------------------------------------------------------------

## A great spear of fire: a dark-gold shaft wreathed in flame, a white-hot head, sparks and a long trail.
func _javelin_node() -> Node3D:
	var n := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.045
	cyl.height = 2.3
	shaft.mesh = cyl
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.25, 0.12, 0.06)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.4, 0.1)
	sm.emission_energy_multiplier = 2.5
	shaft.material_override = sm
	shaft.rotation.x = PI * 0.5                          # along -z (forward)
	n.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.13
	cone.height = 0.55
	head.mesh = cone
	head.material_override = FireFx.core(0.1).material_override
	head.rotation.x = -PI * 0.5
	head.position.z = -1.4
	n.add_child(head)
	n.add_child(FireFx.core(0.2, Color(1.0, 0.55, 0.15), 3.0))
	(n.get_child(n.get_child_count() - 1) as Node3D).position.z = -1.25
	var f := FireFx.flames(0.0, 0.6, 140.0, 0.45, 0.6, "fire", 1.5)
	var pm := f.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.06, 0.06, 1.1)
	pm.gravity = Vector3(0, 2.0, 0)
	n.add_child(f)
	var e := FireFx.embers(0.0, 50.0, 0.9, 1.2)
	(e.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	(e.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.05, 0.05, 1.1)
	n.add_child(e)
	var l := FireFx.light(Color(1.0, 0.55, 0.2), 3.0, 6.0)
	n.add_child(l)
	return n

func _javelin_launch(e: Dictionary) -> void:
	var from: Vector2 = e.from
	var dir: Vector2 = e.dir
	var n := _javelin_node()
	add_child(n)
	var p := fx.ground3(from, 1.3 + FLOAT)
	n.global_position = p
	var d3 := Vector3(dir.x, 0.0, -dir.y).normalized()
	n.look_at(p + d3, Vector3.UP)
	_javelins[int(e.seq)] = {"node": n, "dir3": d3, "goal": p, "seen": fx._seen(from)}
	n.visible = bool(_javelins[int(e.seq)].seen)
	fire.burst(p, 0.3, "fire", 0.6)

func _javelin_move(e: Dictionary) -> void:
	var j = _javelins.get(int(e.seq))
	if j == null:
		return
	var n: Node3D = j.node
	var pos: Vector2 = e.pos
	n.visible = fx._seen(pos) or bool(j.seen) and n.visible
	n.global_position = fx.ground3(pos, 1.3)
	if bool(e.done):
		_javelins.erase(int(e.seq))
		if n.visible:
			fire.burst(n.global_position, 0.9, "fire", 1.2)
			fire.ground_fire(fx.ground3(pos, 0.05), 1.2, 1.0, "fire")
			fx.shockwave(fx.ground3(pos, 0.05), 2.0, Color(1.0, 0.55, 0.2), 0.45, 0.16, 2.5)
		for m in n.get_children():
			if m is MeshInstance3D:
				m.visible = false
		fire.timed(n, 0.0)

# ---- Spirit of Fire -------------------------------------------------------------------------------------------------------

func _shoot_spirits(e: Dictionary) -> void:
	var id := int(e.u)
	var list: Array = _spirits.get(id, [])
	_spirits[id] = []
	var to2: Vector2 = e.point
	var speed := float(e.speed)
	var u: SimUnit = game.world.get_unit(id)
	var dist := u.pos.distance_to(to2) if u else 600.0
	var dur := maxf(0.15, dist / maxf(100.0, speed))
	for i in list.size():
		var s: Dictionary = list[i]
		var spread := Vector2.from_angle(TAU * i / maxf(1.0, list.size())) * 60.0
		_flyers.append({"node": s.node, "from": (s.node as Node3D).global_position, "to": fx.ground3(to2 + spread, 0.6),
			"t": -0.05 * i, "dur": dur, "arc": 1.2 + 0.3 * i})

func _update_flyers(dt: float) -> void:
	for i in range(_flyers.size() - 1, -1, -1):
		var f: Dictionary = _flyers[i]
		if not is_instance_valid(f.node):
			_flyers.remove_at(i)
			continue
		var n: Node3D = f.node
		f.t = float(f.t) + dt
		var k := clampf(float(f.t) / float(f.dur), 0.0, 1.0)
		n.global_position = (f.from as Vector3).lerp(f.to, k) + Vector3(0, sin(k * PI) * float(f.arc), 0)
		if k >= 1.0:
			fire.timed(n, 0.0)
			_flyers.remove_at(i)

# ---- Divine Smite ---------------------------------------------------------------------------------------------------------

## A war hammer of fire: a dark iron head glowing through its cracks, a long haft, the whole thing burning.
func _hammer_node() -> Node3D:
	var n := Node3D.new()
	var spin := Node3D.new()
	spin.name = "Spin"
	n.add_child(spin)
	var haft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.06
	cyl.height = 1.6
	haft.mesh = cyl
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.3, 0.16, 0.08)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.45, 0.12)
	hm.emission_energy_multiplier = 1.6
	haft.material_override = hm
	spin.add_child(haft)
	var head := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.95, 0.5, 0.5)
	head.mesh = bx
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.12, 0.09, 0.08)
	mm.metallic = 0.9
	mm.roughness = 0.3
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.32, 0.06)
	mm.emission_energy_multiplier = 1.2
	head.material_override = mm
	head.position.y = 0.8
	spin.add_child(head)
	var glow := FireFx.core(0.5, Color(1.0, 0.4, 0.08), 1.2)
	glow.position.y = 0.8
	spin.add_child(glow)
	var f := FireFx.flames(0.0, 0.85, 120.0, 0.5, 0.8, "holy", 1.5)
	var pm := f.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.5, 0.3, 0.3)
	f.position.y = 0.8
	spin.add_child(f)
	var e := FireFx.embers(0.4, 60.0, 1.0, 1.6, 0.06)
	e.position.y = 0.8
	spin.add_child(e)
	var l := FireFx.light(Color(1.0, 0.6, 0.25), 4.0, 8.0)
	n.add_child(l)
	n.scale = Vector3.ONE * 1.25
	return n

func _smite_launch(e: Dictionary) -> void:
	var u: SimUnit = game.world.get_unit(int(e.u))
	if u == null:
		return
	var n := _hammer_node()
	add_child(n)
	var v := fx._view_of(u.id)
	var start := (v.hand_point("R") if v else fx.ground3(u.pos, 2.0)) + Vector3(0, 0.6, 0)
	n.global_position = start
	n.visible = fx._seen(u.pos)
	_hammers[int(e.seq)] = {"node": n, "from": start, "goal": u.pos, "t": 0.0}
	if n.visible:
		fire.burst(start, 0.5, "holy", 0.8)

func _update_hammers(dt: float) -> void:
	for seq in _hammers.keys():
		var hm: Dictionary = _hammers[seq]
		if not is_instance_valid(hm.node):
			_hammers.erase(seq)
			continue
		var n: Node3D = hm.node
		hm.t = float(hm.t) + dt
		var goal2: Vector2 = hm.goal
		var goal := fx.ground3(goal2, 1.4)
		# it flies high, tumbling end over end, and comes down on the target
		var flat := Vector2(goal.x - (hm.from as Vector3).x, goal.z - (hm.from as Vector3).z).length()
		var cur := n.global_position
		var to := goal - cur
		var step := minf(to.length(), (11.0 + flat * 0.4) * dt)
		var lift := clampf(Vector2(to.x, to.z).length() / maxf(1.0, flat), 0.0, 1.0)
		n.global_position = cur + to.normalized() * step + Vector3(0, lift * 2.5 * dt * 3.0, 0) * float(lift > 0.35)
		var sp := n.get_node("Spin") as Node3D
		sp.rotation.x -= dt * 14.0
		if Vector2(to.x, to.z).length() > 0.3:
			n.look_at(n.global_position + Vector3(to.x, 0, to.z).normalized(), Vector3.UP)
		n.visible = fx._seen(View.to2(n.global_position))

func _smite_hit(e: Dictionary) -> void:
	var seq := int(e.seq)
	if _hammers.has(seq):
		var n: Node3D = _hammers[seq].node
		for m in n.find_children("*", "MeshInstance3D", true, false):
			m.visible = false
		fire.timed(n, 0.0)
		_hammers.erase(seq)
	var p: Vector2 = e.pos
	if not fx._seen(p):
		return
	var r := float(e.radius) * View.S
	var at := fx.ground3(p, 0.3)
	fire.burst(at + Vector3(0, 0.8, 0), 1.6, "holy", 2.0)
	fire.burst(at, r * 0.5, "fire", 1.6)
	fire.ground_fire(fx.ground3(p, 0.05), r, 3.0, "fire")
	fx.shockwave(fx.ground3(p, 0.05), r * 1.15, Color(1.0, 0.6, 0.25), 0.55, 0.22, 3.0)
	fx.shockwave(fx.ground3(p, 0.05), r * 0.6, Color(1.0, 0.85, 0.5), 0.35, 0.3, 4.0)
	fx.flash_light(at + Vector3(0, 1.5, 0), Color(1.0, 0.65, 0.3), 8.0, 12.0, 0.5)
	fx.debris(at, 10, Color(0.25, 0.2, 0.18), 5.0, 1.0)
	fx._shake(p, 0.35, 0.35)

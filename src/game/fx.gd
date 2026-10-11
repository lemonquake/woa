class_name Fx
extends Node3D
## One-shot and travelling visual effects driven by simulation events: projectiles (arrows that stick into what they
## hit or into the ground when they miss, magic orbs, boulders, tower bolts), melee spark hits, debris, shockwaves,
## ground cracks, lightning, ability effects (Gale Shot, Arrow Storm, Ezee's kit), level-up bursts and order markers.
##
## Debris, sparks and splinters are "bits": tiny meshes with velocity, gravity, a bounce and a short life, simulated
## here (no particle systems, so nothing drifts about aimlessly).

const ARROW := "res://assets/weapons/arrow.glb"
const SHOCK_SHADER := preload("res://src/game/shockwave.gdshader")
const CRACK_SHADER := preload("res://src/game/ground_crack.gdshader")
const MAX_BITS := 260
const VIOLET := Color(0.62, 0.24, 1.0)

var game: Node
var _proj := {}                             # projectile id -> {node, start, h0, arc, t, target, style, trail, last}
var _arrow_scene: PackedScene
var _mats := {}
var _meshes := {}
var _gale: Node3D
var _gale_prev := Vector3.ZERO
var _bits: Array = []                       # {node, vel, spin, life, max, bounce, streak, len}
var _flyers: Array = []                     # arrows after the sim is done with them: {node, from, to, t, dur, arc, stick}
var _stuck: Array = []                      # {node, until, sink}: arrows left in the ground or in a body
var _waves: Array = []                      # {node, mat, t, dur, param}
var _lights: Array = []                     # {light, energy, t, dur}
var _bolts: Array = []                      # lightning: {mi, im, from, to, t, dur, width, color, seg}
var _homers: Array = []                     # dark bolts: {node, trail, from, to_id, t, dur, ctrl, done}
var _spark_budget := 0

func _ready() -> void:
	name = "Fx"
	_arrow_scene = load(ARROW)

# ---- Materials and meshes --------------------------------------------------------------------------------------------

func _glow(col: Color, energy := 4.0) -> StandardMaterial3D:
	var k := col.to_html() + str(energy)
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[k] = m
	return m

func _solid(col: Color, rough := 0.9) -> StandardMaterial3D:
	var k := "solid" + col.to_html() + str(rough)
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	_mats[k] = m
	return m

func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"spark":
			var b := BoxMesh.new()
			b.size = Vector3(0.014, 0.014, 0.17)
			m = b
		"rock":
			var p := PrismMesh.new()
			p.size = Vector3(0.12, 0.09, 0.1)
			p.left_to_right = 0.3
			m = p
		"chip":
			var b2 := BoxMesh.new()
			b2.size = Vector3(0.06, 0.03, 0.05)
			m = b2
		"splinter":
			var b3 := BoxMesh.new()
			b3.size = Vector3(0.035, 0.035, 0.28)
			m = b3
		"leaf":
			var q := QuadMesh.new()
			q.size = Vector2(0.1, 0.07)
			m = q
		_:
			var s := SphereMesh.new()
			s.radius = 0.05
			s.height = 0.1
			s.radial_segments = 6
			s.rings = 3
			m = s
	_meshes[kind] = m
	return m

func _sphere(r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Ground height under a sim point in metres, never below the river surface.
func ground_y(p: Vector2) -> float:
	return maxf(game.terrain.height_at(p), TerrainBuilder.WATER_LEVEL) * View.S

func ground3(p: Vector2, up := 0.0) -> Vector3:
	return Vector3(p.x * View.S, ground_y(p) + up, -p.y * View.S)

func _view_of(uid: int) -> UnitView:
	var v = game.views.get(uid)
	return v if v is UnitView else null

func _chest(uid: int, frac := 0.55) -> Vector3:
	var v := _view_of(uid)
	if v:
		return v.global_position + Vector3(0, v.bar_height * frac, 0)
	var u: SimUnit = game.world.get_unit(uid)
	return ground3(u.pos, 1.0) if u else Vector3.ZERO

## Only effects the player can see are worth drawing (and shaking the screen for).
func _seen(p: Vector2) -> bool:
	return game.world.vision.cell_visible(game.player_team, p)

# ---- Bits: sparks, debris, splinters ---------------------------------------------------------------------------------

func _bit(kind: String, mat: Material, at: Vector3, vel: Vector3, life: float, scale := 1.0, bounce := true,
		streak := false) -> void:
	if _bits.size() >= MAX_BITS:
		var old: Dictionary = _bits.pop_front()
		(old.node as Node3D).queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(kind)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * scale
	if not streak:
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_bits.append({"node": mi, "vel": vel, "spin": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)),
		"life": 0.0, "max": life, "bounce": bounce, "streak": streak, "scale": scale, "rest": false})

## Sparks thrown back off a blow: hot streaks in a cone around `dir`, falling fast.
func sparks(at: Vector3, dir: Vector3, n: int, col := Color(1.0, 0.78, 0.4), speed := 5.0) -> void:
	if _spark_budget <= 0:
		return
	_spark_budget -= 1
	var mat := _glow(col, 6.0)
	var basis_dir := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	for i in n:
		var v := (basis_dir + Vector3(randf_range(-0.8, 0.8), randf_range(-0.1, 0.9), randf_range(-0.8, 0.8))).normalized()
		_bit("spark", mat, at, v * speed * randf_range(0.5, 1.2), randf_range(0.14, 0.3), randf_range(0.7, 1.2), false, true)

## Rock or wood chunks bursting from a point; they bounce once and settle.
func debris(at: Vector3, n: int, col: Color, speed := 4.0, size := 1.0, kind := "rock") -> void:
	var mat := _solid(col)
	for i in n:
		var a := randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.4, 1.0)
		var v := (out + Vector3(0, randf_range(0.8, 1.6), 0)) * speed * randf_range(0.5, 1.0)
		_bit(kind, mat, at + out * 0.15, v, randf_range(0.8, 1.3), size * randf_range(0.6, 1.4))

func _update_bits(dt: float) -> void:
	for i in range(_bits.size() - 1, -1, -1):
		var b: Dictionary = _bits[i]
		var n: MeshInstance3D = b.node
		b.life += dt
		if b.life >= b.max or not is_instance_valid(n):
			if is_instance_valid(n):
				n.queue_free()
			_bits.remove_at(i)
			continue
		if not b.rest:
			var v: Vector3 = b.vel
			v.y -= (16.0 if b.streak else 11.0) * dt
			var p := n.global_position + v * dt
			var gy := ground_y(View.to2(p))
			if p.y <= gy:
				p.y = gy
				if b.bounce and absf(v.y) > 1.2:
					v = Vector3(v.x * 0.45, -v.y * 0.32, v.z * 0.45)
				else:
					b.rest = true
					v = Vector3.ZERO
			b.vel = v
			n.global_position = p
			if b.streak:
				if v.length() > 0.05:
					n.look_at(p + v, Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT)
				n.scale = Vector3(b.scale, b.scale, b.scale * clampf(v.length() / 4.0, 0.3, 1.6))
			else:
				n.rotation += (b.spin as Vector3) * dt
		var f: float = b.life / b.max
		if f > 0.7:
			var s: float = b.scale * (1.0 - (f - 0.7) / 0.3)
			if b.streak:
				n.scale = Vector3(s, s, n.scale.z)
			else:
				n.scale = Vector3.ONE * s

# ---- Waves, cracks, lights, lightning -------------------------------------------------------------------------------

## A flat expanding ring on the ground.
func shockwave(at: Vector3, radius: float, col: Color, dur := 0.5, thickness := 0.18, energy := 2.5) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = SHOCK_SHADER
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("thickness", thickness)
	m.set_shader_parameter("energy", energy)
	m.render_priority = 5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.08, 0)
	_waves.append({"node": mi, "mat": m, "t": 0.0, "dur": dur, "param": "progress"})

## Cracks in the ground that glow, cool and fade.
func crack(at: Vector3, radius: float, col: Color, life := 3.5) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = CRACK_SHADER
	m.set_shader_parameter("glow", col)
	m.set_shader_parameter("seed", randf() * 100.0)
	m.render_priority = 2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.05, 0)
	mi.rotation.y = randf() * TAU
	_waves.append({"node": mi, "mat": m, "t": 0.0, "dur": life, "param": "age"})

func flash_light(at: Vector3, col: Color, energy := 4.0, rng := 6.0, dur := 0.3) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)
	l.global_position = at
	_lights.append({"light": l, "energy": energy, "t": 0.0, "dur": dur})

## A jagged bolt between two points, re-jittered every frame for its short life.
func lightning(from: Vector3, to: Vector3, col: Color, dur := 0.35, width := 0.09, segments := 14) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	_bolts.append({"mi": mi, "im": im, "from": from, "to": to, "t": 0.0, "dur": dur, "width": width, "color": col,
		"seg": segments})

func _update_bolts(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	for i in range(_bolts.size() - 1, -1, -1):
		var b: Dictionary = _bolts[i]
		b.t += dt
		var im: ImmediateMesh = b.im
		if b.t >= b.dur or cam == null:
			(b.mi as Node3D).queue_free()
			_bolts.remove_at(i)
			continue
		im.clear_surfaces()
		var fade: float = 1.0 - float(b.t) / float(b.dur)
		var from: Vector3 = b.from
		var to: Vector3 = b.to
		var n: int = b.seg
		var pts: Array = []
		var len := from.distance_to(to)
		var side_a := (to - from).cross(Vector3.FORWARD).normalized()
		if side_a.length() < 0.1:
			side_a = Vector3.RIGHT
		var side_b := (to - from).cross(side_a).normalized()
		for k in n + 1:
			var f := float(k) / n
			var p := from.lerp(to, f)
			if k > 0 and k < n:
				var amp := len * 0.085 * sin(f * PI)
				p += side_a * randf_range(-amp, amp) + side_b * randf_range(-amp, amp)
			pts.append(p)
		var strands: Array = [pts]
		# a couple of forks peel off the main bolt
		if n >= 8:
			for fk in 2:
				var start := randi_range(2, n - 4)
				var fork: Array = [pts[start]]
				var dir := (to - from).normalized().rotated(side_b, randf_range(-0.9, 0.9))
				var step_len := len / n
				for s in randi_range(3, 5):
					var q: Vector3 = fork[-1] + dir * step_len + side_a * randf_range(-step_len, step_len) * 0.6
					fork.append(q)
				strands.append(fork)
		for si in strands.size():
			var strand: Array = strands[si]
			var thin := 1.0 if si == 0 else 0.5
			for pass_i in 2:
				var wdt: float = b.width * (1.7 if pass_i == 0 else 0.42) * thin
				var col: Color = b.color if pass_i == 0 else Color(0.95, 0.88, 1.0)
				col.a = (0.55 if pass_i == 0 else 1.0) * fade
				im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
				var m := strand.size()
				for k in m:
					var p: Vector3 = strand[k]
					var along: Vector3 = (strand[mini(k + 1, m - 1)] - strand[maxi(k - 1, 0)])
					var taper := 1.0 if si == 0 else (1.0 - float(k) / m)
					var side := along.cross(cam.global_position - p).normalized() * wdt * taper
					im.surface_set_color(col)
					im.surface_add_vertex(p + side)
					im.surface_set_color(col)
					im.surface_add_vertex(p - side)
				im.surface_end()

# ---- Projectiles ----------------------------------------------------------------------------------------------------

## Build the visual for a new projectile from the attacker's model.
func projectile(e: Dictionary, w: SimWorld) -> void:
	var src := w.get_unit(e.src)
	if src == null:
		return
	var info := ModelCatalog.info(String(src.def.model))
	var style := String(info.get("proj", ""))
	if src.kind == SimConst.Kind.TOWER:
		style = "tower_dawn" if src.team == 0 else "tower_dusk"
	elif src.kind == SimConst.Kind.FOUNTAIN:
		style = "fountain"
	if String(e.get("mod", "")) == "frost_quiver":
		style = "frost_arrow"
	var node := Node3D.new()
	var h0 := 1.4
	var arc := 0.0
	var trail: Trail3D = null
	match style:
		"arrow", "frost_arrow":
			var a := _arrow_scene.instantiate() as Node3D
			a.rotation.x = -PI * 0.5
			a.scale = Vector3.ONE * 1.25
			node.add_child(a)
			if style == "frost_arrow":
				node.add_child(_sphere(0.07, _glow(Color(0.5, 0.85, 1.0), 6.0)))
				trail = Trail3D.make(node, Color(0.55, 0.85, 1.0, 0.85), 0.05, 0.22)
			else:
				trail = Trail3D.make(node, Color(1.0, 0.97, 0.9, 0.35), 0.025, 0.12)
			h0 = 1.45
			arc = 0.35
		"sun_orb":
			node.add_child(_sphere(0.14, _glow(Color(1.0, 0.85, 0.4), 6.0)))
			trail = Trail3D.make(node, Color(1.0, 0.75, 0.3, 0.8), 0.1, 0.2)
		"doom_orb":
			node.add_child(_sphere(0.14, _glow(Color(0.55, 1.0, 0.45), 5.0)))
			trail = Trail3D.make(node, Color(0.4, 0.9, 0.35, 0.8), 0.1, 0.2)
		"boulder_sun", "boulder_doom":
			var rock := _sphere(0.28, _glow(Color(1.0, 0.6, 0.2) if style == "boulder_sun" else Color(0.7, 0.2, 0.9), 2.0))
			node.add_child(rock)
			trail = Trail3D.make(node, Color(1.0, 0.55, 0.2, 0.7) if style == "boulder_sun" else Color(0.6, 0.2, 0.8, 0.7), 0.16, 0.25)
			arc = 3.5
			h0 = 2.4
		"tower_dawn", "tower_dusk":
			var col := Color(1.0, 0.85, 0.45) if style == "tower_dawn" else Color(1.0, 0.25, 0.25)
			node.add_child(_sphere(0.2, _glow(col, 8.0)))
			trail = Trail3D.make(node, Color(col.r, col.g, col.b, 0.9), 0.16, 0.25)
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 1.5
			l.omni_range = 3.0
			node.add_child(l)
			h0 = 6.0
		"fountain":
			node.add_child(_sphere(0.3, _glow(Color(0.7, 0.95, 1.0), 8.0)))
			h0 = 4.0
		"fire", "fire_big":
			node.add_child(_sphere(0.16 if style == "fire" else 0.3, _glow(Color(1.0, 0.45, 0.1), 6.0)))
			trail = Trail3D.make(node, Color(1.0, 0.4, 0.1, 0.85), 0.14 if style == "fire" else 0.24, 0.22)
		"spear":
			var sp := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.015
			cyl.bottom_radius = 0.02
			cyl.height = 1.1
			sp.mesh = cyl
			sp.material_override = _solid(Color(0.4, 0.3, 0.2))
			sp.rotation.x = -PI * 0.5
			node.add_child(sp)
			arc = 0.6
		_:
			node.add_child(_sphere(0.1, _glow(Color(0.9, 0.9, 0.8), 3.0)))
	add_child(node)
	if trail:
		add_child(trail)
	var p0 := View.to3(src.pos, game.terrain.height_at(src.pos)) + Vector3(0, h0, 0)
	node.global_position = p0
	_proj[e.id] = {"node": node, "start": p0, "h0": h0, "arc": arc, "t": 0.0, "target": e.target, "style": style,
		"trail": trail, "last": p0, "src_team": src.team}

func _is_arrow(style: String) -> bool:
	return style in ["arrow", "frost_arrow", "spear"]

func projectile_end(e: Dictionary) -> void:
	var p = _proj.get(e.id)
	if p == null:
		return
	_proj.erase(e.id)
	var node: Node3D = p.node
	var style: String = p.style
	var hit := bool(e.get("hit", false))
	var miss := bool(e.get("miss", false))
	var at := node.global_position
	if _is_arrow(style):
		var dir: Vector3 = (at - (p.last as Vector3))
		if dir.length() < 0.001:
			dir = -node.global_transform.basis.z
		dir = dir.normalized()
		if hit:
			_embed(node, int(e.get("target", p.target)), dir, p.trail)
			if style == "frost_arrow":
				sparks(at, -dir + Vector3.UP * 0.3, 6, Color(0.6, 0.9, 1.0), 3.0)
			return
		# missed or the target died: the arrow flies on and sticks in the ground
		var land2: Vector2 = e.get("pos", View.to2(at))
		var flat := Vector2(dir.x, -dir.z).normalized()
		if flat == Vector2.ZERO:
			flat = Vector2.RIGHT
		var dist := randf_range(90.0, 200.0) if miss else randf_range(10.0, 50.0)
		var end2 := land2 + flat * dist + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		var end := ground3(end2, 0.06)
		var dur := clampf(at.distance_to(end) / 14.0, 0.08, 0.35)
		_flyers.append({"node": node, "from": at, "to": end, "t": 0.0, "dur": dur, "arc": 0.25 if miss else 0.05,
			"trail": p.trail})
		return
	if p.trail:
		(p.trail as Trail3D).stop()
	match style:
		"tower_dawn", "tower_dusk":
			var col := Color(1.0, 0.85, 0.45) if style == "tower_dawn" else Color(1.0, 0.3, 0.25)
			impact(at, col, 0.45)
			sparks(at, Vector3.UP, 8, col, 4.0)
			flash_light(at, col, 3.0, 4.0, 0.25)
		"boulder_sun", "boulder_doom":
			impact(at, Color(1.0, 0.7, 0.4), 0.5)
			debris(at, 7, Color(0.32, 0.28, 0.25) if style == "boulder_sun" else Color(0.18, 0.12, 0.2), 3.5, 1.1)
		"sun_orb", "doom_orb", "fire", "fire_big":
			var c2: Color = {"sun_orb": Color(1.0, 0.85, 0.45), "doom_orb": Color(0.55, 1.0, 0.45)}.get(style, Color(1.0, 0.5, 0.15))
			impact(at, c2, 0.3 if hit else 0.18)
			if hit:
				sparks(at, Vector3.UP, 5, c2, 2.6)
		_:
			if hit:
				impact(at, Color(1.0, 0.9, 0.6), 0.3)
	node.queue_free()

## An arrow that struck: it stays in the target's body for a moment, then goes.
func _embed(node: Node3D, target_id: int, dir: Vector3, trail: Trail3D) -> void:
	if trail:
		trail.stop()
	var v := _view_of(target_id)
	if v == null or not v.visible:
		node.queue_free()
		return
	var gt := node.global_transform
	node.get_parent().remove_child(node)
	v.add_child(node)
	node.global_transform = gt
	# sink the head into the body, aimed at its centre
	var centre := v.global_position + Vector3(0, v.bar_height * 0.5, 0)
	var to_c := centre - node.global_position
	var flat := Vector3(to_c.x, to_c.y * 0.3, to_c.z)
	node.global_position += flat * 0.55 + dir * 0.18
	_stuck.append({"node": node, "until": Time.get_ticks_msec() / 1000.0 + randf_range(1.0, 1.6), "sink": false})
	sparks(node.global_position, -dir + Vector3.UP * 0.4, 2, Color(1.0, 0.85, 0.6), 2.0)

func _update_flyers(dt: float) -> void:
	for i in range(_flyers.size() - 1, -1, -1):
		var f: Dictionary = _flyers[i]
		var n: Node3D = f.node
		if not is_instance_valid(n):
			_flyers.remove_at(i)
			continue
		f.t += dt
		var k := clampf(f.t / f.dur, 0.0, 1.0)
		var old := n.global_position
		var p: Vector3 = (f.from as Vector3).lerp(f.to, k) + Vector3(0, sin(k * PI) * float(f.arc), 0)
		n.global_position = p
		var d := p - old
		if d.length() > 0.0005:
			n.look_at(p + d, Vector3.UP)
		if k >= 1.0:
			# stuck in the ground at its flight angle, a puff of earth
			if f.trail:
				(f.trail as Trail3D).stop()
			n.global_position = (f.to as Vector3) + d.normalized() * 0.12
			debris(f.to, 3, Color(0.36, 0.28, 0.2), 1.6, 0.35, "chip")
			_stuck.append({"node": n, "until": Time.get_ticks_msec() / 1000.0 + 2.6, "sink": true})
			_flyers.remove_at(i)

func _update_stuck(dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_stuck.size() - 1, -1, -1):
		var s: Dictionary = _stuck[i]
		var n: Node3D = s.node
		if not is_instance_valid(n):
			_stuck.remove_at(i)
			continue
		var left: float = s.until - now
		if left <= 0.0:
			n.queue_free()
			_stuck.remove_at(i)
		elif left < 0.4:
			if s.sink:
				n.global_position.y -= dt * 0.5
			else:
				n.scale = Vector3.ONE * maxf(0.01, left / 0.4) * 1.25

## Projectiles follow the simulation's projectile positions; heights ease from launch to the target's chest.
func frame(w: SimWorld, alpha: float, dt: float) -> void:
	_spark_budget = 8
	var live := {}
	for p in w.projectiles:
		live[p.id] = p
	for id in _proj.keys():
		var v: Dictionary = _proj[id]
		var sp = live.get(id)
		var node: Node3D = v.node
		var tgt := w.get_unit(v.target)
		if sp == null:
			continue
		var pos2: Vector2 = sp.pos
		var tpos: Vector2 = tgt.pos if tgt else pos2
		var total := maxf(1.0, (View.to2(v.start)).distance_to(tpos))
		var left := pos2.distance_to(tpos)
		var f := clampf(1.0 - left / total, 0.0, 1.0)
		var ground: float = game.terrain.height_at(pos2) * View.S
		var tv := _view_of(v.target)
		var aim := 1.1 if tv == null else tv.bar_height * 0.5
		var h := lerpf(v.h0, aim, f) + sin(f * PI) * float(v.arc) * minf(1.0, total / 600.0)
		var np := View.to3(pos2) + Vector3(0, ground + h, 0)
		var old := node.global_position
		v.last = old
		node.global_position = old.lerp(np, clampf(dt * 30.0, 0.0, 1.0))
		var dir := node.global_position - old
		if dir.length() > 0.001:
			node.look_at(node.global_position + dir, Vector3.UP)
	_update_bits(dt)
	_update_flyers(dt)
	_update_stuck(dt)
	_update_bolts(dt)
	_update_homers(dt)
	for i in range(_waves.size() - 1, -1, -1):
		var wv: Dictionary = _waves[i]
		wv.t += dt
		var k: float = wv.t / wv.dur
		if k >= 1.0:
			(wv.node as Node3D).queue_free()
			_waves.remove_at(i)
		else:
			(wv.mat as ShaderMaterial).set_shader_parameter(wv.param, k)
	for i in range(_lights.size() - 1, -1, -1):
		var l: Dictionary = _lights[i]
		l.t += dt
		var lk: float = l.t / l.dur
		if lk >= 1.0:
			(l.light as Node).queue_free()
			_lights.remove_at(i)
		else:
			(l.light as OmniLight3D).light_energy = float(l.energy) * (1.0 - lk) * (1.0 - lk)

func impact(at: Vector3, col: Color, size := 0.4) -> void:
	var s := _sphere(size, _glow(col, 6.0).duplicate())
	add_child(s)
	s.global_position = at
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * 2.2, 0.16)
	tw.parallel().tween_property(s.material_override, "albedo_color:a", 0.0, 0.16)
	tw.tween_callback(s.queue_free)

# ---- Melee blows -----------------------------------------------------------------------------------------------------

## A melee attack landed: a few sparks where the weapon met the target (stone chips against buildings).
func melee_hit(src: SimUnit, t: SimUnit, amount: float) -> void:
	if not _seen(t.pos):
		return
	var tv := _view_of(t.id)
	var to_src := (src.pos - t.pos)
	if to_src.length() < 1.0:
		to_src = Vector2.from_angle(t.facing)
	to_src = to_src.normalized()
	var h := 1.1
	if tv:
		h = clampf(tv.bar_height * 0.5, 0.6, 1.6)
	var edge := t.hull if not t.is_building() else t.hull * 0.7
	var c2 := t.pos + to_src * edge
	var at := ground3(c2, h if not t.is_building() else 1.2)
	var back := Vector3(to_src.x, 0.35, -to_src.y)
	var model := String(src.def.model)
	if t.is_building():
		debris(at, 4, Color(0.42, 0.4, 0.38), 2.4, 0.4, "chip")
		sparks(at, back, 3, Color(1.0, 0.8, 0.5), 3.5)
		return
	if model.begins_with("ashfang"):
		return
	var heavy := src.is_hero() or amount > 60.0
	sparks(at, back, 7 if heavy else 4, Color(1.0, 0.8, 0.45), 5.5 if heavy else 4.0)
	if heavy:
		impact(at, Color(1.0, 0.9, 0.7), 0.12)

# ---- Galewarden ---------------------------------------------------------------------------------------------------

func gale_move(pos: Vector2) -> void:
	var p := View.to3(pos, game.terrain.height_at(pos)) + Vector3(0, 1.3, 0)
	if _gale == null or not is_instance_valid(_gale):
		_gale = Node3D.new()
		var a := _arrow_scene.instantiate() as Node3D
		a.rotation.x = -PI * 0.5
		a.scale = Vector3.ONE * 2.2
		_gale.add_child(a)
		_gale.add_child(_sphere(0.25, _glow(Color(0.7, 1.0, 0.9), 3.0)))
		add_child(_gale)
		_gale.global_position = p
		_gale_prev = p
		var tr := Trail3D.make(_gale, Color(0.75, 1.0, 0.95, 0.75), 0.45, 0.4)
		add_child(tr)
		get_tree().create_timer(0.8).timeout.connect(func():
			tr.stop()
			if is_instance_valid(_gale):
				_gale.queue_free())
	var dir := p - _gale_prev
	_gale.global_position = p
	if dir.length() > 0.01:
		_gale.look_at(p + dir, Vector3.UP)
	_gale_prev = p

func volley(pos: Vector2, radius: float) -> void:
	var center := ground3(pos)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 14:
		var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius * View.S
		var end := center + Vector3(off.x, 0.05, off.y)
		var a := _arrow_scene.instantiate() as Node3D
		var holder := Node3D.new()
		holder.add_child(a)
		a.rotation.x = PI
		a.scale = Vector3.ONE * 1.3
		add_child(holder)
		var start := end + Vector3(0.6, 9.0 + rng.randf() * 2.0, 0.3)
		holder.global_position = start
		var tw := holder.create_tween()
		var delay := rng.randf() * 0.25
		tw.tween_interval(delay)
		tw.tween_property(holder, "global_position", end, 0.22)
		tw.tween_callback(func():
			debris(end, 2, Color(0.36, 0.28, 0.2), 1.4, 0.3, "chip")
			_stuck.append({"node": holder, "until": Time.get_ticks_msec() / 1000.0 + 1.4, "sink": true}))
	shockwave(center, radius * View.S, Color(1.0, 0.8, 0.4, 0.8), 0.45, 0.08, 1.6)

func level_up(at: Vector3) -> void:
	for i in 2:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.5
		tm.outer_radius = 0.62
		ring.mesh = tm
		ring.material_override = _glow(Color(1.0, 0.85, 0.35, 0.9), 5.0)
		add_child(ring)
		ring.global_position = at + Vector3(0, 0.1 + i * 0.5, 0)
		ring.scale = Vector3(0.3, 0.3, 0.3)
		var tw := ring.create_tween()
		tw.tween_interval(i * 0.12)
		tw.tween_property(ring, "scale", Vector3(2.2, 0.6, 2.2), 0.6)
		tw.parallel().tween_property(ring, "global_position:y", at.y + 2.4, 0.6)
		tw.tween_callback(ring.queue_free)
	shockwave(at, 1.6, Color(1.0, 0.85, 0.4), 0.6, 0.12, 2.0)

# ---- Ezee, the Dark Paladin -------------------------------------------------------------------------------------------

func _shake(at2: Vector2, strength: float, dur: float) -> void:
	if game.camera and game.camera.has_method("shake") and _seen(at2):
		var d := View.to2(game.camera.target).distance_to(at2)
		var k := clampf(1.0 - d / 2600.0, 0.0, 1.0)
		if k > 0.0:
			game.camera.shake(strength * k, dur)

## Dark Stomp: a violet shockwave the size of the stomp, glowing cracks, flung stones and a thump.
func stomp(pos: Vector2, radius: float) -> void:
	if not _seen(pos):
		return
	var at := ground3(pos)
	shockwave(at, radius * View.S * 1.1, VIOLET, 0.55, 0.22, 3.0)
	shockwave(at, radius * View.S * 0.7, Color(0.9, 0.8, 1.0), 0.3, 0.12, 2.0)
	crack(at, radius * View.S * 0.55, VIOLET, 4.0)
	debris(at, 14, Color(0.2, 0.17, 0.2), 5.0, 1.2)
	flash_light(at + Vector3(0, 1.0, 0), VIOLET, 6.0, radius * View.S * 2.0, 0.45)
	_shake(pos, 0.35, 0.3)

## A hurled unit hit something: splinters off trees, stone off cliffs and buildings, sparks off units.
func push_impact(e: Dictionary) -> void:
	var p: Vector2 = e.pos
	if not _seen(p):
		return
	var at := ground3(p, 0.9)
	match String(e.what):
		"tree":
			debris(at, 10, Color(0.42, 0.28, 0.16), 4.0, 0.9, "splinter")
			debris(at + Vector3(0, 1.5, 0), 8, Color(0.24, 0.42, 0.16), 2.0, 1.0, "leaf")
		"cliff", "building":
			debris(at, 10, Color(0.36, 0.33, 0.3), 4.5, 1.0)
			shockwave(ground3(p), 1.2, Color(1.0, 0.9, 0.8), 0.3, 0.2, 1.5)
		_:
			sparks(at, Vector3.UP, 9, Color(0.85, 0.6, 1.0), 5.0)
	impact(at, Color(1.0, 0.85, 1.0), 0.35)
	_shake(p, 0.2, 0.18)

func push_land(uid: int) -> void:
	var u: SimUnit = game.world.get_unit(uid)
	if u == null or not _seen(u.pos):
		return
	debris(ground3(u.pos), 3, Color(0.3, 0.26, 0.22), 1.8, 0.5, "chip")

## Leap Strike: a violet streak follows Ezee through the air.
var _leap_trails := {}

func leap_start(uid: int) -> void:
	var v := _view_of(uid)
	if v == null:
		return
	var anchor := Node3D.new()
	v.add_child(anchor)
	anchor.position = Vector3(0, 1.1, 0)
	var tr := Trail3D.make(anchor, Color(0.55, 0.2, 1.0, 0.75), 0.26, 0.28)
	add_child(tr)
	var tr2 := Trail3D.make(anchor, Color(0.08, 0.0, 0.12, 0.8), 0.16, 0.2, false)
	add_child(tr2)
	_leap_trails[uid] = [anchor, tr, tr2]
	var u: SimUnit = game.world.get_unit(uid)
	if u:
		shockwave(ground3(u.pos), 1.4, VIOLET, 0.35, 0.2, 2.0)
		debris(ground3(u.pos), 5, Color(0.25, 0.2, 0.22), 3.0, 0.7)

func leap_land(e: Dictionary) -> void:
	var uid := int(e.u)
	if _leap_trails.has(uid):
		var arr: Array = _leap_trails[uid]
		(arr[1] as Trail3D).stop()
		(arr[2] as Trail3D).stop()
		(arr[0] as Node3D).queue_free()
		_leap_trails.erase(uid)
	var p: Vector2 = e.pos
	if not _seen(p):
		return
	var at := ground3(p)
	shockwave(at, 2.6, VIOLET, 0.45, 0.25, 3.0)
	crack(at, 1.6, VIOLET, 3.0)
	debris(at, 10, Color(0.2, 0.17, 0.2), 4.5, 1.0)
	flash_light(at + Vector3(0, 1.0, 0), VIOLET, 5.0, 6.0, 0.35)
	if bool(e.hit):
		var t := int(e.target)
		sparks(_chest(t), Vector3.UP, 12, Color(0.85, 0.55, 1.0), 6.0)
		impact(_chest(t), Color(0.9, 0.7, 1.0), 0.4)
	_shake(p, 0.4, 0.25)

## Tainted Touch: purple lightning from the sky into Ezee's raised sword.
func taint_cast(uid: int) -> void:
	var v := _view_of(uid)
	var u: SimUnit = game.world.get_unit(uid)
	if v == null or u == null or not _seen(u.pos):
		return
	var tip := v.weapon_tip()
	# from high up and behind (away from the camera), so the bolt crosses the screen instead of filling it
	var sky := tip + Vector3(randf_range(-2.0, 2.0), 8.5, -7.0)
	lightning(sky, tip, VIOLET, 0.45, 0.07, 22)
	lightning(sky + Vector3(1.6, 0.5, -0.6), tip, Color(0.8, 0.5, 1.0), 0.28, 0.04, 16)
	flash_light(tip, Color(0.75, 0.45, 1.0), 9.0, 9.0, 0.45)
	sparks(tip, Vector3.UP, 12, Color(0.85, 0.6, 1.0), 5.0)
	shockwave(ground3(u.pos), 1.8, VIOLET, 0.4, 0.15, 2.5)
	_shake(u.pos, 0.18, 0.15)

func curse_hit(uid: int) -> void:
	var u: SimUnit = game.world.get_unit(uid)
	if u == null or not _seen(u.pos):
		return
	var c := _chest(uid)
	impact(c, VIOLET, 0.3)
	sparks(c, Vector3.UP, 6, Color(0.75, 0.4, 1.0), 3.0)

## Unholy Might: a roar that blasts a dark ring outwards and shakes the screen for half a second.
func unholy_start(uid: int) -> void:
	var u: SimUnit = game.world.get_unit(uid)
	if u == null:
		return
	var at := ground3(u.pos)
	if _seen(u.pos):
		shockwave(at, 6.0, Color(0.35, 0.1, 0.6), 0.7, 0.3, 2.5)
		shockwave(at, 3.5, VIOLET, 0.45, 0.18, 3.0)
		crack(at, 1.8, VIOLET, 3.0)
		flash_light(at + Vector3(0, 1.5, 0), VIOLET, 7.0, 10.0, 0.6)
		debris(at, 8, Color(0.18, 0.14, 0.2), 3.5, 0.8)
	if game.camera and game.camera.has_method("shake") and _seen(u.pos):
		game.camera.shake(0.55, 0.5)

func unholy_end(uid: int) -> void:
	var u: SimUnit = game.world.get_unit(uid)
	if u and _seen(u.pos):
		shockwave(ground3(u.pos), 2.0, Color(0.4, 0.2, 0.6), 0.5, 0.12, 1.5)

## The deflected half of a blow: a dark bolt arcs from Ezee into a nearby enemy.
func unholy_reflect(from_id: int, to_id: int) -> void:
	var from := _chest(from_id, 0.6)
	var fu: SimUnit = game.world.get_unit(from_id)
	if fu == null or not _seen(fu.pos):
		return
	impact(from, Color(0.5, 0.2, 0.9), 0.3)
	if to_id < 0:
		return
	var head := Node3D.new()
	head.add_child(_sphere(0.13, _glow(Color(0.7, 0.35, 1.0), 6.0)))
	head.add_child(_sphere(0.22, _glow(Color(0.1, 0.0, 0.15, 0.7), 1.0)))
	add_child(head)
	head.global_position = from
	var tr := Trail3D.make(head, Color(0.6, 0.25, 1.0, 0.9), 0.14, 0.25)
	add_child(tr)
	var tr2 := Trail3D.make(head, Color(0.05, 0.0, 0.08, 0.8), 0.09, 0.2, false)
	add_child(tr2)
	var up := Vector3(randf_range(-1.0, 1.0), randf_range(1.6, 2.6), randf_range(-1.0, 1.0))
	_homers.append({"node": head, "trails": [tr, tr2], "from": from, "to_id": to_id, "t": 0.0, "dur": 0.22, "ctrl": up})

func _update_homers(dt: float) -> void:
	for i in range(_homers.size() - 1, -1, -1):
		var h: Dictionary = _homers[i]
		h.t += dt
		var k := clampf(h.t / h.dur, 0.0, 1.0)
		var to := _chest(int(h.to_id))
		var from: Vector3 = h.from
		var mid: Vector3 = (from + to) * 0.5 + (h.ctrl as Vector3)
		var p := from.lerp(mid, k).lerp(mid.lerp(to, k), k)
		(h.node as Node3D).global_position = p
		if k >= 1.0:
			for t in h.trails:
				(t as Trail3D).stop()
			(h.node as Node3D).queue_free()
			impact(to, Color(0.6, 0.3, 1.0), 0.35)
			sparks(to, Vector3.UP, 7, Color(0.75, 0.45, 1.0), 4.0)
			_homers.remove_at(i)

## A tree knocked down by an impact or an axe: it topples away from the blow.
func tree_fell(index: int, from_pos: Vector2) -> void:
	if game.foliage and game.foliage.has_method("fell_tree"):
		game.foliage.fell_tree(index, from_pos)

## Town Portal: a column of light at the hero and at the destination while channelling.
var _tp := {}

func tp_start(uid: int, from: Vector3, to: Vector3, team: int) -> void:
	tp_end(uid)
	var col := Color(0.45, 0.85, 1.0) if team == 0 else Color(1.0, 0.35, 0.4)
	var nodes: Array = []
	for at in [from, to]:
		var n := Node3D.new()
		add_child(n)
		n.global_position = at
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.55
		cyl.bottom_radius = 0.75
		cyl.height = 7.0
		cyl.cap_top = false
		cyl.cap_bottom = false
		beam.mesh = cyl
		var m := _glow(Color(col.r, col.g, col.b, 0.35), 3.0).duplicate() as StandardMaterial3D
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = m
		beam.position.y = 3.5
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(beam)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.85
		tm.outer_radius = 1.0
		ring.mesh = tm
		ring.scale = Vector3(1, 0.1, 1)
		ring.material_override = _glow(col, 4.0)
		ring.position.y = 0.08
		n.add_child(ring)
		var tw := beam.create_tween().set_loops()
		tw.tween_property(beam, "scale", Vector3(1.15, 1.0, 1.15), 0.4)
		tw.tween_property(beam, "scale", Vector3(0.9, 1.0, 0.9), 0.4)
		var tw2 := ring.create_tween().set_loops()
		tw2.tween_property(ring, "rotation:y", TAU, 2.0).from(0.0)
		nodes.append(n)
	_tp[uid] = nodes

func tp_end(uid: int, flash := false) -> void:
	if not _tp.has(uid):
		return
	for n: Node3D in _tp[uid]:
		if flash:
			impact(n.global_position + Vector3(0, 1.0, 0), Color(0.8, 0.95, 1.0), 1.2)
			shockwave(n.global_position, 2.2, Color(0.7, 0.9, 1.0), 0.4, 0.15, 2.0)
		n.queue_free()
	_tp.erase(uid)

## Attack-range rings for enemy towers near your hero: yellow, or red while the tower is targeting you.
var _ranges := {}

func tower_ranges(w: SimWorld, h: SimUnit, team: int) -> void:
	for u in w.units:
		if u.kind != SimConst.Kind.TOWER or u.team == team:
			continue
		var near := h != null and h.alive and u.alive and h.pos.distance_to(u.pos) < u.attack_range + u.hull + 700.0
		var ring: MeshInstance3D = _ranges.get(u.id)
		if not near:
			if ring:
				ring.visible = false
			continue
		if ring == null:
			ring = MeshInstance3D.new()
			var tm := TorusMesh.new()
			var r := (u.attack_range + u.hull) * View.S
			tm.inner_radius = r - 0.07
			tm.outer_radius = r
			tm.rings = 96
			tm.ring_segments = 4
			ring.mesh = tm
			ring.scale = Vector3(1, 0.05, 1)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring.material_override = m
			add_child(ring)
			ring.global_position = View.to3(u.pos, game.terrain.height_at(u.pos)) + Vector3(0, 0.1, 0)
			_ranges[u.id] = ring
		ring.visible = true
		var aggro := u.atk_target == h.id
		var d := h.pos.distance_to(u.pos) - (u.attack_range + u.hull)
		var a := clampf(1.0 - d / 700.0, 0.25, 0.9)
		(ring.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.2, 0.15, 0.95) if aggro else Color(1.0, 0.85, 0.3, a)

## Dota's order feedback: a green ripple where you move, a red one on what you attack.
func marker(at: Vector3, attack: bool) -> void:
	var col := Color(1.0, 0.25, 0.2, 0.9) if attack else Color(0.3, 1.0, 0.4, 0.9)
	# never under the river surface, and drawn after the water so it always shows
	at.y = maxf(at.y, TerrainBuilder.WATER_LEVEL * View.S)
	var mat := _glow(col, 3.0).duplicate() as StandardMaterial3D
	mat.render_priority = 20
	for i in 2:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.32
		tm.outer_radius = 0.4
		ring.mesh = tm
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.global_position = at + Vector3(0, 0.06, 0)
		ring.scale = Vector3(1.0, 0.05, 1.0) * (1.0 + i * 0.5)
		var tw := ring.create_tween()
		tw.tween_property(ring, "scale", Vector3(0.15, 0.05, 0.15), 0.35)
		tw.tween_callback(ring.queue_free)

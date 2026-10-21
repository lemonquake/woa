class_name Fx
extends Node3D
## One-shot and travelling visual effects driven by simulation events: projectiles (arrows that stick into what they
## hit or into the ground when they miss, magic orbs, boulders, tower bolts), melee spark hits, debris, shockwaves,
## ground cracks, lightning, ability effects (Blood Ranger's and Ezee's kits), level-up bursts and order markers.
##
## Debris, sparks and splinters are "bits": tiny meshes with velocity, gravity, a bounce and a short life, simulated
## here (no particle systems, so nothing drifts about aimlessly).

const ARROW := "res://assets/weapons/arrow.glb"
const SHOCK_SHADER := preload("res://src/game/shockwave.gdshader")
const CRACK_SHADER := preload("res://src/game/ground_crack.gdshader")
const WALL_SHADER := preload("res://src/game/force_wall.gdshader")
const MAX_BITS := 260
const VIOLET := Color(0.62, 0.24, 1.0)

var game: Node
var fire: FireFx                           # particle fire (fireballs)
var _proj := {}                             # projectile id -> {node, start, h0, arc, t, target, style, trail, last}
var _arrow_scene: PackedScene
var _mats := {}
var _meshes := {}
var _gales := {}                            # caster id -> {node, prev, trails, spin}
const BLOOD := Color(0.86, 0.06, 0.1)
const BLOOD_HOT := Color(1.0, 0.32, 0.22)
var _bits: Array = []                       # {node, vel, spin, life, max, bounce, streak, len}
var _flyers: Array = []                     # arrows after the sim is done with them: {node, from, to, t, dur, arc, stick}
var _stuck: Array = []                      # {node, until, sink}: arrows left in the ground or in a body
var _waves: Array = []                      # {node, mat, t, dur, param}
var _lights: Array = []                     # {light, energy, t, dur}
var _bolts: Array = []                      # lightning: {mi, im, from, to, t, dur, width, color, seg}
var _homers: Array = []                     # dark bolts: {node, trail, from, to_id, t, dur, ctrl, done}
var _spikes: Array = []                     # erupting stone spikes: {node, t, h, y}
var _walls: Array = []                      # rising force walls: {node, mat, t, dur, r0, r1}
var _spike_meshes: Array = []
var _spike_mat: ShaderMaterial

## A faceted stone shard (unit height): an uneven hexagonal base narrowing through a twisted waist to a bent tip.
func _shard_mesh(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var sides := 6
	var base: Array = []
	var waist: Array = []
	var twist := rng.randf_range(0.3, 0.7)
	for i in sides:
		var a := TAU * i / sides + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(0.13, 0.2)
		base.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
		waist.append(Vector3(cos(a + twist) * r * 0.55, rng.randf_range(0.42, 0.55), sin(a + twist) * r * 0.55))
	var tip := Vector3(rng.randf_range(-0.06, 0.06), 1.0, rng.randf_range(-0.06, 0.06))
	for i in sides:
		var j := (i + 1) % sides
		# lower band
		st.add_vertex(base[i]); st.add_vertex(base[j]); st.add_vertex(waist[j])
		st.add_vertex(base[i]); st.add_vertex(waist[j]); st.add_vertex(waist[i])
		# upper facets to the tip
		st.add_vertex(waist[i]); st.add_vertex(waist[j]); st.add_vertex(tip)
	st.generate_normals()
	return st.commit()
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
	return game.sees_cell(p)

# ---- Bits: sparks, debris, splinters ---------------------------------------------------------------------------------

func _bit(kind: String, mat: Material, at: Vector3, vel: Vector3, life: float, scale := 1.0, bounce := true,
		streak := false) -> void:
	if _bits.size() >= MAX_BITS:
		var old: Dictionary = _bits.pop_front()
		if is_instance_valid(old.node):
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
		b.life += dt
		if b.life >= b.max or not is_instance_valid(b.node):
			if is_instance_valid(b.node):
				(b.node as Node).queue_free()
			_bits.remove_at(i)
			continue
		var n: MeshInstance3D = View.live(b.node)
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

## A wall of force rising from the ground and racing outwards (an open cylinder that grows and fades).
func force_wall(at: Vector3, r0: float, r1: float, height: float, col: Color, dur := 0.45) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 48
	cyl.rings = 1
	mi.mesh = cyl
	var m := ShaderMaterial.new()
	m.shader = WALL_SHADER
	m.set_shader_parameter("color", col)
	m.render_priority = 6
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, height * 0.5 - 0.05, 0)
	mi.scale = Vector3(r0, height, r0)
	_walls.append({"node": mi, "mat": m, "t": 0.0, "dur": dur, "r0": r0, "r1": r1, "h": height})

## Obsidian spikes erupting in a ring around a point: they burst up, hold, and sink back into the ground.
func spike_ring(center: Vector2, radius: float, count: int, height := 1.3) -> void:
	if _spike_mat == null:
		for v in 4:
			_spike_meshes.append(_shard_mesh(v))
		_spike_mat = ShaderMaterial.new()
		_spike_mat.shader = preload("res://src/game/spike.gdshader")
	for i in count:
		var a := TAU * float(i) / count + randf_range(-0.06, 0.06)
		var d := radius * randf_range(0.9, 1.0)
		var p := center + Vector2.from_angle(a) * d
		# never through a unit: the enemies it hits must stay readable
		var blocked := false
		for u in game.world.query(p, 70.0, true):
			if not u.is_building():
				blocked = true
				break
		if blocked:
			continue
		var h := height * randf_range(0.85, 1.1)
		var mi := MeshInstance3D.new()
		mi.mesh = _spike_meshes[randi() % _spike_meshes.size()]
		mi.material_override = _spike_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		var base := ground3(p)
		# where it broke through: a dark contact patch and a few chunks of earth around its foot
		var patch := MeshInstance3D.new()
		patch.mesh = Dressing.blob_mesh()
		patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(patch)
		patch.global_position = base + Vector3(0, 0.03, 0)
		patch.scale = Vector3(0.9, 1.0, 0.9) * h * 0.55
		_spikes.append({"node": patch, "t": -0.02, "h": 0.0, "base": base + Vector3(0, 0.03, 0), "dir": Vector3.UP, "patch": true})
		for c in 3:
			var cv := Vector3(randf_range(-1, 1), randf_range(1.5, 2.5), randf_range(-1, 1)).normalized() * randf_range(1.5, 3.0)
			_bit("rock", _solid(Color(0.24, 0.2, 0.18)), base + Vector3(0, 0.1, 0), cv, randf_range(0.6, 1.0), randf_range(0.5, 0.9))
		# lean outwards, away from the blast
		var out := Vector3(cos(a), 0.0, -sin(a))
		var tilt := 0.32
		var axis := Vector3.UP.cross(out).normalized()
		var wdt := randf_range(2.6, 3.0)
		mi.global_transform = Transform3D(Basis(axis, -tilt) * Basis(Vector3.UP, a).scaled(Vector3(wdt, h, wdt)), base)
		mi.set_meta("basis", mi.global_transform.basis)
		_spikes.append({"node": mi, "t": -randf() * 0.06, "h": h, "base": base, "dir": mi.global_transform.basis.y.normalized()})

func _update_spikes(dt: float) -> void:
	for i in range(_spikes.size() - 1, -1, -1):
		var s: Dictionary = _spikes[i]
		if not is_instance_valid(s.node):
			_spikes.remove_at(i)
			continue
		s.t += dt
		var t: float = s.t
		var n: MeshInstance3D = View.live(s.node)
		# burst up with an overshoot, hold, then sink
		var k := 0.0
		if t < 0.0:
			k = 0.0
		elif t < 0.08:
			k = t / 0.08 * 1.12
		elif t < 0.14:
			k = lerpf(1.12, 1.0, (t - 0.08) / 0.06)
		elif t < 0.75:
			k = 1.0
		elif t < 1.25:
			k = 1.0 - (t - 0.75) / 0.5
		else:
			n.queue_free()
			_spikes.remove_at(i)
			continue
		if s.get("patch", false):
			n.visible = t >= 0.0
			continue
		var dir: Vector3 = s.dir
		n.global_position = (s.base as Vector3) + dir * float(s.h) * (k - 1.0) * 0.5 + dir * float(s.h) * 0.5 * clampf(k, 0.0, 1.2)
		n.visible = k > 0.01

func _update_walls(dt: float) -> void:
	for i in range(_walls.size() - 1, -1, -1):
		var wl: Dictionary = _walls[i]
		wl.t += dt
		var k: float = wl.t / wl.dur
		if k >= 1.0 or not is_instance_valid(wl.node):
			if is_instance_valid(wl.node):
				(wl.node as Node).queue_free()
			_walls.remove_at(i)
			continue
		var r := lerpf(float(wl.r0), float(wl.r1), 1.0 - pow(1.0 - k, 2.0))
		var hh: float = float(wl.h) * (1.0 - k * 0.5)
		(wl.node as Node3D).scale = Vector3(r, hh, r)
		(wl.mat as ShaderMaterial).set_shader_parameter("progress", k)

## A bright band marking an area's edge on the ground that holds, then fades (the boundary of a blast).
func edge_ring(at: Vector3, radius: float, col: Color, life := 1.2) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.06
	tm.outer_radius = radius + 0.03
	tm.rings = 96
	tm.ring_segments = 4
	mi.mesh = tm
	mi.scale = Vector3(1, 0.06, 1)
	var m := _glow(col, 3.5).duplicate() as StandardMaterial3D
	m.render_priority = 7
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.1, 0)
	var tw := mi.create_tween()
	tw.tween_interval(life * 0.6)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 0.4)
	tw.tween_callback(mi.queue_free)

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
	if String(e.get("kind", "")) == "spell" and String(e.get("key", "")) == "burst_shot":
		style = "blood_arrow"
	elif String(e.get("kind", "")) == "effect":
		style = "root_orb"
	elif bool(e.get("burst", false)):
		style = "burst_arrow"
	var node := Node3D.new()
	var h0 := 1.4
	var arc := 0.0
	var trail: Trail3D = null
	var start := Vector3.INF
	# Roydo's Anomaly throws gravity orbs whatever his base model says
	if src.is_hero() and not src.get_modifier("anomaly").is_empty() and String(e.get("kind", "")) == "attack":
		style = "gravity_orb"
	if style in Hero16Fx.PROJ and game.get("hero16_fx") != null:
		var made: Dictionary = game.hero16_fx.make_projectile(style, src)
		node.free()
		node = made.node
		trail = made.trail
		h0 = float(made.h0)
		start = made.start
		style = "h16:" + style
	match style:
		"knife":
			# Feran Mock's thrown knife: tumbling end over end, a thin pale streak behind it
			var kscene := ModelCatalog.weapon("throwing_knife")
			if kscene:
				var pivot := Node3D.new()
				node.add_child(pivot)
				var kn := kscene.instantiate() as Node3D
				kn.rotation.x = -PI * 0.5
				kn.scale = Vector3.ONE * 1.6
				pivot.add_child(kn)
				var tw := pivot.create_tween().set_loops()
				tw.tween_property(pivot, "rotation:x", -TAU, 0.16).from(0.0)
			trail = Trail3D.make(node, Color(1.0, 0.9, 0.85, 0.55), 0.035, 0.16)
			arc = 0.12
		"arrow", "burst_arrow", "blood_arrow":
			var a := _arrow_scene.instantiate() as Node3D
			a.rotation.x = -PI * 0.5
			a.scale = Vector3.ONE * 1.25
			node.add_child(a)
			arc = 0.35
			if style == "blood_arrow":
				a.scale = Vector3.ONE * 1.7
			if style == "burst_arrow":
				# Masterful Archery: a charged arrow, hot core and a long crimson streak
				node.add_child(_sphere(0.08, _glow(BLOOD_HOT, 7.0)))
				trail = Trail3D.make(node, Color(1.0, 0.25, 0.2, 0.9), 0.07, 0.26)
			elif style == "blood_arrow":
				# Burst Shot: arrows loosed high so they rain down, each with a hot tip and a blood-red streak
				node.add_child(_sphere(0.06, _glow(BLOOD_HOT, 6.0)))
				trail = Trail3D.make(node, Color(1.0, 0.16, 0.16, 0.9), 0.1, 0.3)
				arc = randf_range(2.4, 3.4)
			else:
				trail = Trail3D.make(node, Color(1.0, 0.97, 0.9, 0.35), 0.025, 0.12)
			h0 = 1.45
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
			var big := bool(e.get("fortify", false))
			var dawn := style == "tower_dawn"
			node.add_child(_tower_shot(dawn, big))
			var tcol := Color(1.0, 0.86, 0.5, 0.9) if dawn else Color(0.55, 0.06, 0.28, 0.75)
			trail = Trail3D.make(node, tcol, (0.12 if dawn else 0.1) * (1.35 if big else 1.0), 0.3 if dawn else 0.26)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.85, 0.5) if dawn else Color(0.9, 0.15, 0.4)
			l.light_energy = 2.2 if big else 1.5
			l.omni_range = 3.5 if big else 3.0
			node.add_child(l)
			var bv = game.views.get(src.id)
			h0 = (bv as BuildingView).bolt_height if bv is BuildingView else 4.0
		"fountain":
			node.add_child(_sphere(0.3, _glow(Color(0.7, 0.95, 1.0), 8.0)))
			h0 = 4.0
		"root_orb":
			# Root Staff: a knot of green-brown light trailing leaves
			node.add_child(_sphere(0.15, _glow(Color(0.45, 0.9, 0.3), 6.0)))
			node.add_child(_sphere(0.24, _glow(Color(0.35, 0.25, 0.1, 0.5), 1.5)))
			trail = Trail3D.make(node, Color(0.4, 0.85, 0.25, 0.8), 0.12, 0.3)
		"frost_bolt":
			# Froster's attack: an icy core in glittering vapour; a Frost Heart attack is bigger and brighter
			var big := bool(e.get("frost", false))
			node.add_child(FrosterFx.bolt(1.7 if big else 1.0))
			if big:
				node.add_child(FireFx.light(FrosterFx.ICE, 2.0, 3.0))
			h0 = 1.75
		"fire", "fire_big", "fireball":
			# real particle fire (FireFx): a hot core in licking flame, trailing fire and sparks
			var fb := FireFx.fireball({"fire": 0.9, "fire_big": 1.5, "fireball": 1.15}[style])
			node.add_child(fb)
			if style == "fireball":
				h0 = 1.95                              # Azrin hovers: her hands are higher than a walker's
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
		"thorn":
			# Gancho's thrown thorn: a dark wooden spike with a green tip, a faint leafy streak behind it
			var th := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.035
			cone.height = 0.42
			cone.radial_segments = 6
			th.mesh = cone
			th.material_override = _solid(Color(0.32, 0.22, 0.12), 0.7)
			th.rotation.x = -PI * 0.5
			node.add_child(th)
			var tipg := _sphere(0.03, _glow(Color(0.45, 1.0, 0.35), 2.5))
			tipg.position = Vector3(0, 0, -0.2)
			node.add_child(tipg)
			trail = Trail3D.make(node, Color(0.45, 0.85, 0.3, 0.45), 0.03, 0.18)
			arc = 0.1
		_:
			# Roydo's and Blau's shots (h16:...) come fully made; anything else unknown gets a plain glowing ball
			if not style.begins_with("h16:"):
				node.add_child(_sphere(0.1, _glow(Color(0.9, 0.9, 0.8), 3.0)))
	add_child(node)
	if trail and game.args.has("notrails"):
		trail.free()
		trail = null
	if trail:
		add_child(trail)
	var p0 := View.to3(src.pos, game.terrain.height_at(src.pos)) + Vector3(0, h0, 0)
	if start != Vector3.INF:
		p0 = start
		h0 = start.y - game.terrain.height_at(src.pos)
	node.global_position = p0
	_proj[e.id] = {"node": node, "start": p0, "h0": h0, "arc": arc, "t": 0.0, "target": e.target, "style": style,
		"trail": trail, "last": p0, "src_team": src.team, "big": bool(e.get("fortify", false))}

func _is_arrow(style: String) -> bool:
	return style in ["arrow", "burst_arrow", "blood_arrow", "spear", "thorn"]

func projectile_end(e: Dictionary) -> void:
	var p = _proj.get(e.id)
	if p == null:
		return
	_proj.erase(e.id)
	var node: Node3D = View.live(p.node)
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
			if style == "blood_arrow":
				blood_hit(int(e.get("target", p.target)), dir)
			return
		# missed or the target died: the arrow flies on and sticks in the ground
		var land2: Vector2 = e.get("pos", View.to2(at))
		var flat := Vector2(dir.x, -dir.z).normalized()
		if flat == Vector2.ZERO:
			flat = Vector2.RIGHT
		var dist := randf_range(90.0, 200.0) if miss else randf_range(10.0, 50.0)
		if bool(e.get("ground", false)):
			dist = randf_range(4.0, 14.0)
			if style == "blood_arrow" and _seen(land2):
				debris(ground3(land2), 3, Color(0.4, 0.32, 0.24), 2.2, 0.4, "chip")
		var end2 := land2 + flat * dist + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		var end := ground3(end2, 0.06)
		var dur := clampf(at.distance_to(end) / 14.0, 0.08, 0.35)
		_flyers.append({"node": node, "from": at, "to": end, "t": 0.0, "dur": dur, "arc": 0.25 if miss else 0.05,
			"trail": p.trail})
		return
	if p.trail:
		(p.trail as Trail3D).stop()
	if style.begins_with("h16:") and game.get("hero16_fx") != null:
		game.hero16_fx.projectile_end(style.substr(4), at, hit)
		node.queue_free()
		return
	match style:
		"tower_dawn":
			# a spike of light where the lance strikes, gold sparks, a small ring on the ground
			var k := 1.35 if bool(p.get("big", false)) else 1.0
			impact(at, Color(1.0, 0.95, 0.78), 0.32 * k)
			_light_spike(at, Color(1.0, 0.88, 0.55), 2.2 * k)
			sparks(at, Vector3.UP, 9, Color(1.0, 0.82, 0.4), 4.5)
			if _seen(View.to2(at)):
				shockwave(ground3(View.to2(at)), 0.8 * k, Color(1.0, 0.85, 0.45), 0.3, 0.22, 2.0)
			flash_light(at, Color(1.0, 0.85, 0.5), 3.2 * k, 4.5, 0.25)
		"tower_dusk":
			# the black sun collapses into itself, then bursts crimson; the ground cracks under it
			var k2 := 1.35 if bool(p.get("big", false)) else 1.0
			_implode(at, 0.5 * k2)
			sparks(at, Vector3.UP, 8, Color(0.95, 0.2, 0.4), 3.8)
			if _seen(View.to2(at)):
				crack(ground3(View.to2(at)), 0.7 * k2, Color(0.9, 0.15, 0.35), 1.1)
			flash_light(at, Color(0.85, 0.15, 0.45), 3.0 * k2, 4.0, 0.3)
		"boulder_sun", "boulder_doom":
			impact(at, Color(1.0, 0.7, 0.4), 0.5)
			debris(at, 7, Color(0.32, 0.28, 0.25) if style == "boulder_sun" else Color(0.18, 0.12, 0.2), 3.5, 1.1)
		"root_orb":
			impact(at, Color(0.45, 0.9, 0.3), 0.35)
			debris(at, 6, Color(0.3, 0.45, 0.15), 2.5, 0.5, "chip")
		"frost_bolt":
			for m in node.find_children("*", "MeshInstance3D", true, false):
				m.visible = false
			if hit and game.get("froster_fx") != null:
				game.froster_fx.burst_shards(at, 6, 0.12, 3.0)
			if fire:
				fire.timed(node, 0.0)
				return
		"fire", "fire_big", "fireball":
			# the flames already in the air burn out where it struck; a small burst of fire there
			for m in node.find_children("*", "MeshInstance3D", true, false):
				m.visible = false
			if fire:
				if hit:
					fire.burst(at, 0.35 if style != "fire_big" else 0.6, "fire", 0.55)
				fire.timed(node, 0.0)
				return
		"sun_orb", "doom_orb":
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
		if not is_instance_valid(f.node):
			_flyers.remove_at(i)
			continue
		var n: Node3D = View.live(f.node)
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
		if not is_instance_valid(s.node):
			_stuck.remove_at(i)
			continue
		var n: Node3D = View.live(s.node)
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
		var node: Node3D = View.live(v.node)
		var tgt := w.get_unit(v.target)
		if sp == null:
			continue
		var pos2: Vector2 = sp.pos
		var tpos: Vector2 = tgt.pos if tgt and tgt.alive else (sp.get("point", pos2) as Vector2)
		var total := maxf(1.0, (View.to2(v.start)).distance_to(tpos))
		var left := pos2.distance_to(tpos)
		var f := clampf(1.0 - left / total, 0.0, 1.0)
		var ground: float = game.terrain.height_at(pos2) * View.S
		var tv := _view_of(v.target)
		var aim := (1.1 if int(v.target) >= 0 else 0.1) if tv == null else tv.bar_height * 0.5
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
	_update_spikes(dt)
	_update_walls(dt)
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

## A tower's shot. Ancient Light: a lance of sunlight (a white-hot core in a gold sheath, a bright head). Black Sun:
## a small black sun with a crimson corona in a violet haze. Fortified shots are a third bigger. Travels along -Z.
func _tower_shot(dawn: bool, big: bool) -> Node3D:
	var n := Node3D.new()
	var s := 1.35 if big else 1.0
	if dawn:
		var core := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.06 * s
		cap.height = 0.85 * s
		core.mesh = cap
		core.rotation.x = PI * 0.5
		core.material_override = _glow(Color(1.0, 0.97, 0.86), 9.0)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(core)
		var sheath := MeshInstance3D.new()
		var cap2 := CapsuleMesh.new()
		cap2.radius = 0.16 * s
		cap2.height = 1.3 * s
		sheath.mesh = cap2
		sheath.rotation.x = PI * 0.5
		sheath.material_override = _glow(Color(1.0, 0.78, 0.32, 0.32), 3.0)
		sheath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(sheath)
		var head := _sphere(0.12 * s, _glow(Color(1.0, 1.0, 0.92), 10.0))
		head.position.z = -0.38 * s
		n.add_child(head)
	else:
		n.add_child(_sphere(0.15 * s, _solid(Color(0.03, 0.0, 0.04), 1.0)))
		# the corona always faces the camera, so it reads as an eclipse from any angle
		var corona := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.75, 0.75) * s
		corona.mesh = q
		corona.material_override = _corona_mat()
		corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(corona)
	return n

var _corona: ShaderMaterial

## The Black Sun shot's corona: a camera-facing crimson ring with soft flares, dark in the middle where the black core
## sits.
func _corona_mat() -> ShaderMaterial:
	if _corona == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ring = exp(-pow((r - 0.42) * 14.0, 2.0));
	float flare = (0.55 + 0.45 * sin(a * 7.0 + TIME * 5.0)) * smoothstep(1.0, 0.42, r) * step(0.42, r) * 0.55;
	vec3 col = mix(vec3(1.0, 0.22, 0.38), vec3(0.65, 0.15, 0.95), smoothstep(0.42, 0.95, r));
	ALBEDO = col * (ring * 2.4 + flare);
}
"""
		_corona = ShaderMaterial.new()
		_corona.shader = sh
		_corona.render_priority = 3
	return _corona

## A thin spike of light standing up from a point, shooting up and fading (the Ancient Light tower's hit).
func _light_spike(at: Vector3, col: Color, height: float) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.01
	cyl.bottom_radius = 0.1
	cyl.height = height
	cyl.radial_segments = 12
	mi.mesh = cyl
	var m := _glow(col, 7.0).duplicate() as StandardMaterial3D
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, height * 0.35, 0)
	mi.scale = Vector3(1.0, 0.2, 1.0)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(1.4, 1.0, 1.4), 0.12)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.32)
	tw.tween_callback(mi.queue_free)

## A dark sphere that swells, then collapses to nothing, ringed by a crimson flash (the Black Sun tower's hit).
func _implode(at: Vector3, size: float) -> void:
	var dark := _sphere(size, _solid(Color(0.02, 0.0, 0.03), 1.0))
	add_child(dark)
	dark.global_position = at
	dark.scale = Vector3.ONE * 0.4
	var tw := dark.create_tween()
	tw.tween_property(dark, "scale", Vector3.ONE, 0.07)
	tw.tween_property(dark, "scale", Vector3.ONE * 0.05, 0.16).set_ease(Tween.EASE_IN)
	tw.tween_callback(impact.bind(at, Color(1.0, 0.25, 0.42), size * 0.8))
	tw.tween_callback(dark.queue_free)

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

# ---- Blood Ranger -------------------------------------------------------------------------------------------------

## Gale Impact's great arrow: a long shaft wrapped in two corkscrewing wind ribbons and a pale light, kicking up grit
## from the ground beneath it. One per caster (a mirror match can fire two at once).
func gale_move(src: int, pos: Vector2, done: bool) -> void:
	var p := View.to3(pos, game.terrain.height_at(pos)) + Vector3(0, 1.25, 0)
	var g: Dictionary = _gales.get(src, {})
	if g.is_empty() or not is_instance_valid(g.node):
		var node := _great_arrow()
		add_child(node)
		node.global_position = p
		var trails: Array = []
		for k in 2:
			var anchor := Node3D.new()
			node.add_child(anchor)
			var tr := Trail3D.make(anchor, Color(0.82, 1.0, 0.96, 0.55), 0.16, 0.45)
			add_child(tr)
			trails.append([anchor, tr])
		var core := Trail3D.make(node, Color(1.0, 1.0, 1.0, 0.6), 0.32, 0.22)
		add_child(core)
		trails.append([node, core])
		var l := OmniLight3D.new()
		l.light_color = Color(0.75, 1.0, 0.95)
		l.light_energy = 2.2
		l.omni_range = 4.5
		node.add_child(l)
		g = {"node": node, "prev": p, "trails": trails, "spin": 0.0}
		_gales[src] = g
	var n: Node3D = View.live(g.node)
	var dir: Vector3 = p - (g.prev as Vector3)
	n.global_position = p
	if dir.length() > 0.01:
		n.look_at(p + dir, Vector3.UP)
	g.prev = p
	g.spin = float(g.spin) + 0.9
	for k in 2:
		var anchor: Node3D = View.live(g.trails[k][0])
		var ang := float(g.spin) + k * PI
		anchor.position = Vector3(cos(ang) * 0.38, sin(ang) * 0.38, 0.3)
	if _seen(pos) and randf() < 0.6:
		debris(ground3(pos, 0.05), 2, Color(0.5, 0.45, 0.36), 2.2, 0.35, "chip")
	if done:
		_end_gale(src)

func _end_gale(src: int) -> void:
	var g: Dictionary = _gales.get(src, {})
	_gales.erase(src)
	if g.is_empty() or not is_instance_valid(g.node):
		return
	for pair in g.trails:
		var tr: Trail3D = pair[1]
		if is_instance_valid(tr):
			tr.stop()
	var n: Node3D = View.live(g.node)
	var at := n.global_position
	if _seen(View.to2(at)):
		shockwave(ground3(View.to2(at)), 1.8, Color(0.8, 1.0, 0.95), 0.4, 0.12, 2.0)
		sparks(at, -n.global_transform.basis.z + Vector3.UP * 0.3, 10, Color(0.8, 1.0, 0.95), 5.0)
		debris(ground3(View.to2(at), 0.05), 5, Color(0.5, 0.45, 0.36), 3.0, 0.5, "chip")
	n.queue_free()

## Gale Impact's arrow: a long glowing shaft with a broad head and fletching inside a turning sheath of wind. It points
## along -Z (look_at).
func _great_arrow() -> Node3D:
	var node := Node3D.new()
	var core := _glow(Color(0.85, 1.0, 0.97), 3.5)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 2.0
	cyl.radial_segments = 6
	shaft.mesh = cyl
	shaft.material_override = core
	shaft.rotation.x = PI * 0.5
	shaft.position.z = 0.3
	node.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 0.5
	cone.radial_segments = 4
	head.mesh = cone
	head.material_override = _glow(Color(1.0, 1.0, 1.0), 5.0)
	head.rotation.x = -PI * 0.5
	head.position.z = -0.92
	node.add_child(head)
	for k in 3:
		var f := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.22, 0.45)
		f.mesh = q
		f.material_override = _glow(Color(0.7, 1.0, 0.9, 0.8), 2.5)
		var holder := Node3D.new()
		holder.rotation.z = k * TAU / 3.0
		holder.add_child(f)
		f.position = Vector3(0, 0.1, 1.1)
		f.rotation = Vector3(0, PI * 0.5, 0)
		node.add_child(holder)
	var sheath := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.06
	sc.bottom_radius = 0.5
	sc.height = 2.2
	sc.cap_top = false
	sc.cap_bottom = false
	sc.radial_segments = 16
	sheath.mesh = sc
	var sm := _glow(Color(0.8, 1.0, 0.95, 0.16), 1.5).duplicate() as StandardMaterial3D
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sheath.material_override = sm
	sheath.rotation.x = -PI * 0.5
	sheath.position.z = 0.4
	node.add_child(sheath)
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spin := sheath.create_tween().set_loops()
	spin.tween_property(sheath, "rotation:y", TAU, 0.25).from(0.0)
	return node

## Gale Impact leaves the bow: a gust ring at her feet and a flash at the string.
func gale_launch(e: Dictionary) -> void:
	var u: SimUnit = game.world.get_unit(int(e.u))
	if u == null or not _seen(u.pos):
		return
	var at := ground3(u.pos)
	shockwave(at, 2.2, Color(0.8, 1.0, 0.95), 0.4, 0.14, 2.0)
	var d: Vector2 = e.dir
	var front := at + Vector3(d.x, 0.0, -d.y) * 0.6 + Vector3(0, 1.4, 0)
	flash_light(front, Color(0.8, 1.0, 0.95), 4.0, 6.0, 0.3)
	sparks(front, Vector3(d.x, 0.2, -d.y), 8, Color(0.85, 1.0, 0.95), 6.0)
	_shake(u.pos, 0.12, 0.12)

## A unit struck by the gale arrow: a burst of wind and grit off its body.
func gale_hit(e: Dictionary) -> void:
	var p: Vector2 = e.pos
	if not _seen(p):
		return
	var c := _chest(int(e.u))
	impact(c, Color(0.85, 1.0, 0.95), 0.22)
	var d: Vector2 = e.dir
	sparks(c, Vector3(d.x, 0.4, -d.y), 10, Color(0.85, 1.0, 0.95), 6.0)
	shockwave(ground3(p), 1.4, Color(0.8, 1.0, 0.95), 0.35, 0.2, 2.0)
	flash_light(c, Color(0.8, 1.0, 0.95), 3.0, 4.0, 0.25)

## Masterful Archery: the charged arrow bursts in a crimson star, a ring and a hot flash.
func masterful_hit(e: Dictionary) -> void:
	var t: SimUnit = game.world.get_unit(int(e.target))
	if t == null or not _seen(t.pos):
		return
	var c := _chest(t.id)
	impact(c, BLOOD_HOT, 0.22)
	_spark_budget += 3
	for i in 3:
		sparks(c, Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)), 6,
			BLOOD_HOT if i != 1 else Color(1.0, 0.8, 0.45), 7.0)
	shockwave(ground3(t.pos), 1.6, BLOOD, 0.35, 0.22, 3.0)
	flash_light(c, BLOOD_HOT, 6.0, 5.0, 0.3)
	_shake(t.pos, 0.08, 0.1)

## Lifesteal: a red pulse at the healed hero, at most four times a second.
var _ls_next := {}

func lifesteal(uid: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_ls_next.get(uid, 0.0)):
		return
	_ls_next[uid] = now + 0.25
	var u: SimUnit = game.world.get_unit(uid)
	if u == null or not _seen(u.pos):
		return
	var c := _chest(uid, 0.5)
	flash_light(c, Color(1.0, 0.1, 0.1), 2.0, 2.5, 0.2)
	for i in 5:
		_bit("sphere", _glow(Color(1.0, 0.15, 0.15), 5.0), c + Vector3(randf_range(-0.3, 0.3), randf_range(-0.4, 0.2), randf_range(-0.3, 0.3)),
			Vector3(0, randf_range(1.2, 2.2), 0), randf_range(0.35, 0.55), 0.6, false)

## Burst Shot: a crimson circle marks the area for the channel's length; each wave flashes at the bow.
var _burst_marks := {}

const BURST_MARK_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float fade = 1.0;
uniform float notches = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float n = noise(p * 5.0 + vec2(TIME * 0.3, 0.0)) * 0.6 + noise(p * 13.0) * 0.4;
	// a stained, uneven crimson fill that thickens towards a ragged rim
	float edge = 0.92 + (n - 0.5) * 0.08;
	float inside = 1.0 - smoothstep(edge - 0.02, edge, r);
	float rim = smoothstep(edge - 0.16, edge - 0.02, r) * inside;
	// arrow-shaped notches pointing inwards around the rim
	float notch = smoothstep(0.72, 0.9, abs(sin(a * 8.0))) * smoothstep(edge - 0.3, edge - 0.12, r) * inside;
	float fill = inside * (0.05 + 0.12 * n * smoothstep(0.2, 0.95, r));
	float alpha = clamp(fill * (2.2 - notches * 1.2) + rim * 0.55 + notch * 0.25 * notches, 0.0, 0.8) * fade;
	vec3 col = mix(vec3(0.16, 0.0, 0.01), vec3(0.55, 0.02, 0.04), clamp(rim * 1.2 + n * 0.2, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = alpha;
}
"""
var _burst_mark_shader: Shader

func burst_start(e: Dictionary) -> void:
	burst_end(int(e.u))
	var p: Vector2 = e.point
	var u: SimUnit = game.world.get_unit(int(e.u))
	if u == null:
		return
	if u.team != game.player_team and not _seen(u.pos) and not _seen(p):
		return
	if _burst_mark_shader == null:
		_burst_mark_shader = Shader.new()
		_burst_mark_shader.code = BURST_MARK_CODE
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var r := float(e.radius) * View.S
	q.size = Vector2(r * 2.0, r * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _burst_mark_shader
	m.render_priority = 2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = ground3(p, 0.05)
	mi.scale = Vector3(0.6, 1, 0.6)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_burst_marks[int(e.u)] = mi
	shockwave(ground3(p), r, Color(0.9, 0.1, 0.12, 0.5), 0.45, 0.05, 1.2)

func burst_wave(e: Dictionary) -> void:
	var v := _view_of(int(e.u))
	var u: SimUnit = game.world.get_unit(int(e.u))
	if v == null or u == null or not _seen(u.pos):
		return
	var d := Vector2.from_angle(u.facing)
	var bow := v.global_position + Vector3(d.x * 0.5, 1.5, -d.y * 0.5)
	flash_light(bow, BLOOD_HOT, 3.5, 4.0, 0.18)
	sparks(bow, Vector3(d.x, 0.9, -d.y), 5, Color(1.0, 0.35, 0.25), 4.5)

func burst_end(uid: int) -> void:
	var mi = _burst_marks.get(uid)
	_burst_marks.erase(uid)
	if mi != null and is_instance_valid(mi):
		var m: MeshInstance3D = mi
		var tw := m.create_tween()
		tw.tween_interval(0.5)
		tw.tween_method(func(k: float): (m.material_override as ShaderMaterial).set_shader_parameter("fade", k), 1.0, 0.0, 0.6)
		tw.tween_callback(m.queue_free)

## A Burst Shot arrow struck a unit: a spray of blood, a dark splash on the ground and a hot spark.
func blood_hit(uid: int, dir: Vector3) -> void:
	var u: SimUnit = game.world.get_unit(uid)
	if u == null or not _seen(u.pos):
		return
	var c := _chest(uid, 0.6)
	var mat := _glow(Color(0.75, 0.02, 0.05), 2.0)
	for i in 6:
		var v := (dir.normalized() * 0.8 + Vector3(randf_range(-0.7, 0.7), randf_range(0.3, 1.2), randf_range(-0.7, 0.7))) * randf_range(2.0, 3.6)
		_bit("sphere", mat, c, v, randf_range(0.35, 0.6), randf_range(0.7, 1.3), false)
	_splat(u.pos + Vector2(randf_range(-30, 30), randf_range(-30, 30)))
	sparks(c, -dir + Vector3.UP * 0.3, 3, BLOOD_HOT, 3.5)

var _splats: Array = []

func _splat(p: Vector2) -> void:
	if _burst_mark_shader == null:
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var r := randf_range(0.25, 0.42)
	q.size = Vector2(r * 2.0, r * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = _burst_mark_shader
	m.set_shader_parameter("fade", 1.6)
	m.set_shader_parameter("notches", 0.0)
	m.render_priority = 3
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = ground3(p, 0.06)
	mi.rotation.y = randf() * TAU
	var tw := mi.create_tween()
	tw.tween_interval(2.0)
	tw.tween_method(func(k: float): m.set_shader_parameter("fade", k), 1.6, 0.0, 1.0)
	tw.tween_callback(mi.queue_free)
	_splats.append(mi)
	if _splats.size() > 40:
		var old = _splats.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()

## Blood Ranger's ultimate: blood mist rising off her, a crimson ring and a short shake.
func blood_ranger_start(uid: int) -> void:
	var u: SimUnit = game.world.get_unit(uid)
	if u == null or not _seen(u.pos):
		return
	var at := ground3(u.pos)
	shockwave(at, 4.5, BLOOD, 0.6, 0.25, 3.0)
	shockwave(at, 2.4, BLOOD_HOT, 0.4, 0.15, 3.5)
	flash_light(at + Vector3(0, 1.4, 0), BLOOD_HOT, 7.0, 8.0, 0.5)
	for i in 14:
		var a := randf() * TAU
		var o := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.2, 0.6)
		_bit("sphere", _glow(Color(0.85, 0.05, 0.1), 4.0), at + o + Vector3(0, randf_range(0.3, 1.6), 0),
			o * 1.5 + Vector3(0, randf_range(2.0, 4.0), 0), randf_range(0.5, 0.9), randf_range(0.8, 1.4), false)
	_shake(u.pos, 0.2, 0.2)

## The back leap: a crimson streak through the air and a scuff of dust where she takes off and lands.
var _hop_trails := {}

func back_leap(e: Dictionary) -> void:
	var uid := int(e.u)
	var v := _view_of(uid)
	if v == null:
		return
	var from: Vector2 = e.from
	if _seen(from):
		debris(ground3(from), 4, Color(0.4, 0.34, 0.28), 2.2, 0.4, "chip")
	back_leap_land({"u": uid, "pos": Vector2.INF})
	var anchor := Node3D.new()
	v.add_child(anchor)
	anchor.position = Vector3(0, 1.0, 0)
	var tr := Trail3D.make(anchor, Color(0.9, 0.1, 0.14, 0.6), 0.22, 0.25)
	add_child(tr)
	_hop_trails[uid] = [anchor, tr]

func back_leap_land(e: Dictionary) -> void:
	var uid := int(e.u)
	if _hop_trails.has(uid):
		var arr: Array = _hop_trails[uid]
		if is_instance_valid(arr[1]):
			(arr[1] as Trail3D).stop()
		if is_instance_valid(arr[0]):
			(arr[0] as Node3D).queue_free()
		_hop_trails.erase(uid)
	var p: Vector2 = e.pos
	if p != Vector2.INF and _seen(p):
		debris(ground3(p), 5, Color(0.4, 0.34, 0.28), 2.0, 0.45, "chip")
		shockwave(ground3(p), 0.9, Color(0.9, 0.15, 0.15), 0.3, 0.25, 2.0)

## Vegan Picker: leaves stream from the eaten tree into the hero.
func tango_eat(uid: int, tree_pos: Vector2) -> void:
	var u: SimUnit = game.world.get_unit(uid)
	if u == null or not _seen(u.pos):
		return
	var to := _chest(u.id, 0.6)
	var from := ground3(tree_pos, 1.6)
	for i in 10:
		var start := from + Vector3(randf_range(-0.6, 0.6), randf_range(-0.4, 0.8), randf_range(-0.6, 0.6))
		_bit("leaf", _solid(Color(0.3, 0.55, 0.18)), start, (to - start) * randf_range(1.6, 2.4) + Vector3(0, 1.5, 0),
			randf_range(0.4, 0.6), 1.0, false)
	impact(to, Color(0.5, 1.0, 0.45, 0.7), 0.3)

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

# ---- Disables: bash, item debuffs, neutral spells ---------------------------------------------------------------------

## A bash: a heavy yellow flash on the head, sparks and a short thump of the camera when it is close.
func bash_hit(target_id: int) -> void:
	var u: SimUnit = game.world.get_unit(target_id)
	if u == null or not _seen(u.pos):
		return
	var at := _chest(target_id, 0.85)
	impact(at, Color(1.0, 0.9, 0.4), 0.45)
	sparks(at, Vector3.UP, 10, Color(1.0, 0.85, 0.4), 4.5)
	flash_light(at, Color(1.0, 0.85, 0.4), 3.5, 4.0, 0.2)
	_shake(u.pos, 0.08, 0.15)

## An item disable lands on a unit: a burst in the debuff's colour (silence violet, disarm orange, hex green, root
## green-brown, stun yellow).
func debuff_hit(target_id: int, kind: String) -> void:
	var u: SimUnit = game.world.get_unit(target_id)
	if u == null or not _seen(u.pos):
		return
	var col: Color = {"silence": Color(0.62, 0.3, 1.0), "disarm": Color(1.0, 0.55, 0.15), "hex": Color(0.4, 1.0, 0.45),
		"root_staff": Color(0.45, 0.85, 0.25), "overwhelm": Color(1.0, 0.85, 0.35)}.get(kind, Color(1, 1, 1))
	var at := _chest(target_id, 0.6)
	impact(at, col, 0.5)
	sparks(at, Vector3.UP, 8, col, 3.0)
	shockwave(ground3(u.pos), 1.2, col, 0.4, 0.08, 2.0)
	if kind == "hex":
		# a puff of smoke as the unit turns into a sheep
		debris(at, 10, Color(0.9, 0.95, 0.9), 2.5, 0.6, "chip")
		flash_light(at, col, 4.0, 4.0, 0.3)

## Silence Staff's end: the stored damage bursts out in violet.
func soul_burst(uid: int) -> void:
	var u: SimUnit = game.world.get_unit(uid)
	if u == null or not _seen(u.pos):
		return
	var at := _chest(uid, 0.6)
	impact(at, Color(0.62, 0.3, 1.0), 0.7)
	shockwave(ground3(u.pos), 1.8, Color(0.62, 0.3, 1.0), 0.45, 0.1, 2.5)
	flash_light(at, Color(0.62, 0.3, 1.0), 4.0, 5.0, 0.3)

## The neutrals' spells: Stomp (a dusty shockwave and cracks), Smash (a heavy crater), Snarl (a grey roar ring).
func neutral_spell(e: Dictionary) -> void:
	var pos: Vector2 = e.pos
	if not _seen(pos):
		return
	var at := ground3(pos)
	var r := float(e.radius) * View.S
	match String(e.ability):
		"stomp":
			shockwave(at, r * 1.15, Color(0.85, 0.7, 0.45), 0.45, 0.14, 1.6)
			edge_ring(at, r, Color(1.0, 0.85, 0.5, 0.5), 0.6)
			crack(at, r, Color(0.8, 0.55, 0.25), 3.0)
			debris(at, 12, Color(0.35, 0.28, 0.2), 4.5, 1.0)
			_shake(pos, 0.25, 0.25)
		"smash":
			shockwave(at, r * 1.2, Color(0.9, 0.75, 0.5), 0.5, 0.18, 2.0)
			crack(at, r * 1.1, Color(0.85, 0.5, 0.2), 4.0)
			debris(at, 18, Color(0.32, 0.26, 0.2), 5.5, 1.3)
			flash_light(at + Vector3(0, 0.8, 0), Color(1.0, 0.75, 0.4), 4.0, 5.0, 0.3)
			_shake(pos, 0.4, 0.3)
		"snarl":
			shockwave(at, r * 1.1, Color(0.75, 0.75, 0.8), 0.5, 0.1, 1.2)
			edge_ring(at, r, Color(0.8, 0.8, 0.9, 0.35), 0.5)

## Reveal Dust: a glittering cloud thrown out from the hero to the edge of its area.
func dust(e: Dictionary) -> void:
	var pos: Vector2 = e.pos
	if not _seen(pos):
		return
	var at := ground3(pos, 0.4)
	shockwave(ground3(pos), float(e.radius) * View.S, Color(1.0, 0.95, 0.7), 0.7, 0.08, 1.2)
	sparks(at, Vector3.UP, 26, Color(1.0, 0.95, 0.75), 6.0)
	debris(at, 10, Color(0.95, 0.9, 0.75), 3.0, 0.4, "chip")

## Smash's wind-up: the area it will hit glows red on the ground until it lands, so heroes can step out.
func smash_warning(pos: Vector2, radius: float, dur: float) -> void:
	if not _seen(pos):
		return
	edge_ring(ground3(pos), radius * View.S, Color(1.0, 0.25, 0.15, 0.85), dur)
	edge_ring(ground3(pos), radius * View.S * 0.55, Color(1.0, 0.35, 0.2, 0.5), dur)

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
	var r := radius * View.S
	force_wall(at, 0.4, r * 1.05, 1.5, Color(0.5, 0.24, 0.95), 0.45)
	spike_ring(pos, radius * 1.0, 14, 1.9)
	shockwave(at, r * 1.1, Color(0.45, 0.28, 0.75), 0.5, 0.12, 1.4)
	edge_ring(at, r, Color(0.62, 0.38, 0.9, 0.4), 0.7)
	# scorched fissures run from the stomp out to the spikes
	crack(at, r * 1.05, Color(0.42, 0.24, 0.66), 4.5)
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
		for k in [1, 2]:
			if is_instance_valid(arr[k]):
				(arr[k] as Trail3D).stop()
		if is_instance_valid(arr[0]):
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
		if not is_instance_valid(h.node):
			_homers.remove_at(i)
			continue
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

## Attack-range rings of the buildings that attack (towers and fountains), shown only while `show` (Alt held): an
## enemy's yellow, red while it is targeting your hero; your team's pale blue.
var _ranges := {}

func tower_ranges(w: SimWorld, h: SimUnit, team: int, show := false) -> void:
	for u in w.units:
		if u.kind != SimConst.Kind.TOWER and u.kind != SimConst.Kind.FOUNTAIN:
			continue
		var near := show and u.alive
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
		var mat := ring.material_override as StandardMaterial3D
		if u.team == team:
			mat.albedo_color = Color(0.45, 0.75, 1.0, 0.6)
			continue
		var aggro := h != null and u.atk_target == h.id
		mat.albedo_color = Color(1.0, 0.2, 0.15, 0.95) if aggro else Color(1.0, 0.85, 0.3, 0.8)

## A ping: three yellow rings pulsing outwards on the ground.
func ping(p: Vector2) -> void:
	var at := ground3(p)
	for i in 3:
		get_tree().create_timer(i * 0.28).timeout.connect(func(): shockwave(at, 2.4, Color(1.0, 0.85, 0.3), 0.7, 0.1, 2.5))

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

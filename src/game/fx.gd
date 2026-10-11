class_name Fx
extends Node3D
## One-shot and travelling visual effects driven by simulation events: projectiles (arrows, magic orbs, boulders,
## tower bolts), impact flashes, ability effects (Gale Shot, Arrow Storm), level-up bursts and order markers.

const ARROW := "res://assets/weapons/arrow.glb"

var game: Node
var _proj := {}                             # projectile id -> {node, prev, cur, h0, h1, arc, t}
var _arrow_scene: PackedScene
var _mats := {}
var _gale: Node3D
var _gale_prev := Vector3.ZERO

func _ready() -> void:
	name = "Fx"
	_arrow_scene = load(ARROW)

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

func _trail(col: Color, amount := 24, size := 0.12) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.35
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.05
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.3
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var qm := SphereMesh.new()
	qm.radius = size
	qm.height = size * 2.0
	qm.radial_segments = 6
	qm.rings = 3
	p.mesh = qm
	p.material_override = _glow(col, 3.0)
	return p

## Build the visual for a new projectile from the attacker's model.
func projectile(e: Dictionary, w: SimWorld) -> void:
	var src := w.get_unit(e.src)
	if src == null:
		return
	var style := ""
	var info := ModelCatalog.info(String(src.def.model))
	style = String(info.get("proj", ""))
	if src.kind == SimConst.Kind.TOWER:
		style = "tower_dawn" if src.team == 0 else "tower_dusk"
	elif src.kind == SimConst.Kind.FOUNTAIN:
		style = "fountain"
	if String(e.get("mod", "")) == "frost_quiver":
		style = "frost_arrow"
	var node := Node3D.new()
	var h0 := 1.4
	var arc := 0.0
	match style:
		"arrow", "frost_arrow":
			var a := _arrow_scene.instantiate() as Node3D
			a.rotation.x = -PI * 0.5
			a.scale = Vector3.ONE * 1.1
			node.add_child(a)
			if style == "frost_arrow":
				node.add_child(_sphere(0.09, _glow(Color(0.5, 0.85, 1.0), 6.0)))
				node.add_child(_trail(Color(0.55, 0.85, 1.0), 20, 0.07))
			h0 = 1.45
		"sun_orb":
			node.add_child(_sphere(0.14, _glow(Color(1.0, 0.85, 0.4), 6.0)))
			node.add_child(_trail(Color(1.0, 0.75, 0.3)))
		"doom_orb":
			node.add_child(_sphere(0.14, _glow(Color(0.55, 1.0, 0.45), 5.0)))
			node.add_child(_trail(Color(0.4, 0.9, 0.35)))
		"boulder_sun", "boulder_doom":
			var rock := _sphere(0.28, _glow(Color(1.0, 0.6, 0.2) if style == "boulder_sun" else Color(0.7, 0.2, 0.9), 2.0))
			node.add_child(rock)
			node.add_child(_trail(Color(1.0, 0.55, 0.2) if style == "boulder_sun" else Color(0.6, 0.2, 0.8), 20, 0.16))
			arc = 3.5
			h0 = 2.4
		"tower_dawn", "tower_dusk":
			var col := Color(1.0, 0.85, 0.45) if style == "tower_dawn" else Color(1.0, 0.25, 0.25)
			node.add_child(_sphere(0.2, _glow(col, 8.0)))
			node.add_child(_trail(col, 30, 0.14))
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
			node.add_child(_trail(Color(1.0, 0.4, 0.1), 24, 0.15))
		_:
			node.add_child(_sphere(0.1, _glow(Color(0.9, 0.9, 0.8), 3.0)))
	add_child(node)
	var p0 := View.to3(src.pos, game.terrain.height_at(src.pos)) + Vector3(0, h0, 0)
	node.global_position = p0
	_proj[e.id] = {"node": node, "start": p0, "h0": h0, "arc": arc, "t": 0.0, "target": e.target}

func projectile_end(e: Dictionary) -> void:
	var p = _proj.get(e.id)
	if p == null:
		return
	_proj.erase(e.id)
	var node: Node3D = p.node
	if bool(e.get("hit", false)):
		impact(node.global_position, Color(1.0, 0.9, 0.6), 0.35)
	node.queue_free()

## Projectiles follow the simulation's projectile positions; heights ease from launch to the target's chest.
func frame(w: SimWorld, alpha: float, dt: float) -> void:
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
		var h := lerpf(v.h0, 1.1, f) + sin(f * PI) * float(v.arc)
		var np := View.to3(pos2) + Vector3(0, ground + h, 0)
		var old := node.global_position
		node.global_position = old.lerp(np, clampf(dt * 30.0, 0.0, 1.0))
		var dir := node.global_position - old
		if dir.length() > 0.001:
			node.look_at(node.global_position + dir, Vector3.UP)

func impact(at: Vector3, col: Color, size := 0.4) -> void:
	var s := _sphere(size, _glow(col, 6.0).duplicate())
	add_child(s)
	s.global_position = at
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * 2.2, 0.18)
	tw.parallel().tween_property(s.material_override, "albedo_color:a", 0.0, 0.18)
	tw.tween_callback(s.queue_free)

# ---- Abilities and markers ------------------------------------------------------------------------------------------

func gale_move(pos: Vector2) -> void:
	var p := View.to3(pos, game.terrain.height_at(pos)) + Vector3(0, 1.3, 0)
	if _gale == null or not is_instance_valid(_gale):
		_gale = Node3D.new()
		var a := _arrow_scene.instantiate() as Node3D
		a.rotation.x = -PI * 0.5
		a.scale = Vector3.ONE * 2.2
		_gale.add_child(a)
		_gale.add_child(_sphere(0.25, _glow(Color(0.7, 1.0, 0.9), 3.0)))
		var tr := _trail(Color(0.75, 1.0, 0.95), 60, 0.25)
		tr.lifetime = 0.6
		tr.initial_velocity_max = 1.5
		_gale.add_child(tr)
		add_child(_gale)
		_gale.global_position = p
		_gale_prev = p
		get_tree().create_timer(0.8).timeout.connect(func():
			if is_instance_valid(_gale):
				_gale.queue_free())
	var dir := p - _gale_prev
	_gale.global_position = p
	if dir.length() > 0.01:
		_gale.look_at(p + dir, Vector3.UP)
	_gale_prev = p

func volley(pos: Vector2, radius: float) -> void:
	var center := View.to3(pos, game.terrain.height_at(pos))
	var rng := RandomNumberGenerator.new()
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
		tw.tween_callback(func(): impact(end + Vector3(0, 0.1, 0), Color(0.95, 0.85, 0.6), 0.18))
		tw.tween_interval(0.6)
		tw.tween_callback(holder.queue_free)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * View.S * 0.94
	tm.outer_radius = radius * View.S
	ring.mesh = tm
	ring.scale = Vector3(1, 0.04, 1)
	ring.material_override = _glow(Color(1.0, 0.8, 0.4, 0.8), 3.0)
	add_child(ring)
	ring.global_position = center + Vector3(0, 0.08, 0)
	var tw2 := ring.create_tween()
	tw2.tween_property(ring, "scale", Vector3(1.05, 0.04, 1.05), 0.4)
	tw2.tween_callback(ring.queue_free)

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

## Dota's order feedback: a green ripple where you move, a red one on what you attack.
func marker(at: Vector3, attack: bool) -> void:
	var col := Color(1.0, 0.25, 0.2, 0.9) if attack else Color(0.3, 1.0, 0.4, 0.9)
	for i in 2:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.32
		tm.outer_radius = 0.4
		ring.mesh = tm
		ring.material_override = _glow(col, 3.0)
		add_child(ring)
		ring.global_position = at + Vector3(0, 0.06, 0)
		ring.scale = Vector3(1.0, 0.05, 1.0) * (1.0 + i * 0.5)
		var tw := ring.create_tween()
		tw.tween_property(ring, "scale", Vector3(0.15, 0.05, 0.15), 0.35)
		tw.tween_callback(ring.queue_free)

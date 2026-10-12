class_name SludgeFx
extends Node3D
## Sludge's visuals, driven every frame by the simulation:
##   Shuriken Hook: a big four-bladed shuriken spinning flat (a faint smear and blade-tip streaks while it flies), on a real
##     chain of links paid out from his left fist that sags, whips on a miss and reels in. On a catch it bites into the
##     victim (blood, a metal clang, a camera kick for Sludge's player), spins down and hauls the victim back.
##   Stench: a low cloud of sickly green-brown gas rolling round him while it is on; enemies inside get a green tint.
##   Blubber: a wet pulse over the body. Chomp: blood with every bite. Growing Gut: a "+2" over his head.
## The hook reads the simulation's hook effect directly (interpolated between ticks), so it is always where the rules
## say it is.

const SHURIKEN := "res://assets/weapons/shuriken.glb"
const LINK := "res://assets/weapons/chain_link.glb"
const TIP_SCALE := 2.6                      # the flying shuriken: about 1.35 m across
const LINK_SCALE := 2.4
const LINK_STEP := 0.148                    # metres between link centres
const MAX_LINKS := 150
const STEEL := Color(0.86, 0.9, 1.0)
const STENCH := Color(0.42, 0.5, 0.18)
const IRON := Color(0.16, 0.15, 0.145)       # the chain: dark, heavy iron that reads against grass and stone

var game: Node
var fx: Fx
var _hooks := {}                            # seq -> {tip, spin_node, blur, blur_mat, chain, trails, prev, cur, tick, ...}
var _shuriken_scene: PackedScene
var _link_mesh: Mesh
var _clouds := {}                           # caster id -> {node, puffs: [{mi, phase, r, a, h}], mat}
var _chain_mat: StandardMaterial3D
var _alpha := 0.0
var _dt := 0.0

func _ready() -> void:
	name = "SludgeFx"
	# lay the chain after every animation has posed its skeleton this frame, so it leaves the fist exactly
	process_priority = 100
	_chain_mat = StandardMaterial3D.new()
	_chain_mat.albedo_color = IRON
	_chain_mat.metallic = 0.8
	_chain_mat.roughness = 0.42
	_shuriken_scene = load(SHURIKEN) if ResourceLoader.exists(SHURIKEN) else null
	var ls := load(LINK) as PackedScene if ResourceLoader.exists(LINK) else null
	if ls:
		var n := ls.instantiate()
		var mis := n.find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty():
			_link_mesh = (mis[0] as MeshInstance3D).mesh
		n.free()

# ---- Shuriken Hook --------------------------------------------------------------------------------------------------

func _hook_height(p2: Vector2) -> float:
	return fx.ground_y(p2) + 1.05

func hook_launch(e: Dictionary) -> void:
	var u: SimUnit = game.world.get_unit(int(e.u))
	if u == null:
		return
	var seq := int(e.seq)
	var root := Node3D.new()
	add_child(root)
	var tip := Node3D.new()
	root.add_child(tip)
	var spin := Node3D.new()
	tip.add_child(spin)
	if _shuriken_scene:
		var s := _shuriken_scene.instantiate() as Node3D
		spin.add_child(s)
		s.scale = Vector3.ONE * TIP_SCALE
		# the model is built lying flat (blades in the ground plane), so it faces the top-down camera as it is
		for mi: MeshInstance3D in s.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_worn_steel(mi)
	# motion blur: a faint grey smear where the blades sweep (kept dim so the blades stay readable)
	var blur := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.35, 1.35)
	q.orientation = PlaneMesh.FACE_Y
	blur.mesh = q
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.42, 0.7, 0.86, 1.0])
	gr.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.3, 0.32, 0.36, 0.18),
		Color(0.45, 0.47, 0.5, 0.28), Color(0, 0, 0, 0)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	bm.albedo_texture = gt
	blur.material_override = bm
	blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tip.add_child(blur)
	# two streaks off opposite blade tips: a spiral swirl behind the spinning star
	var trails: Array = []
	for k in 2:
		var anchor := Node3D.new()
		spin.add_child(anchor)
		anchor.position = Vector3(cos(k * PI), 0.0, sin(k * PI)) * 0.55
		var tr := Trail3D.make(anchor, Color(0.62, 0.65, 0.7, 0.28), 0.03, 0.08)
		root.add_child(tr)
		trails.append(tr)
	# the chain
	var chain := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _link_mesh if _link_mesh else BoxMesh.new()
	mm.instance_count = MAX_LINKS
	mm.visible_instance_count = 0
	chain.multimesh = mm
	chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	chain.material_override = _chain_mat
	root.add_child(chain)
	var from2: Vector2 = e.from
	var p := View.to3(from2) + Vector3(0, _hook_height(from2), 0)
	tip.global_position = p
	_hooks[seq] = {"root": root, "tip": tip, "spin_node": spin, "blur": blur, "blur_mat": bm, "chain": chain,
		"trails": trails, "src": int(e.u), "prev": p, "cur": p, "tick": game.world.tick, "spin": 0.0, "rate": 30.0,
		"state": "out", "target": -1, "whip": 0.0, "dir": e.dir, "latched_at": -1.0, "embed": 0.0, "bleed": 0.0}
	var v := fx._view_of(int(e.u))
	if v:
		v.hide_weapon("L", true)
	if fx._seen(u.pos):
		var hand := _hand(int(e.u))
		fx.sparks(hand, Vector3(e.dir.x, 0.3, -e.dir.y), 6, Color(0.9, 0.95, 1.0), 6.0)
		fx.flash_light(hand, Color(0.85, 0.9, 1.0), 2.0, 4.0, 0.2)

## Darken the star's pale blades to worn, dark steel (its red stays: old blood).
func _worn_steel(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		var m := src.duplicate() as BaseMaterial3D
		var c := src.albedo_color
		if c.r < c.g * 1.4:                    # steel, not the red blood
			m.albedo_color = Color(0.5, 0.49, 0.47) * Color(c.v, c.v, c.v)
			m.metallic = 0.55
			m.roughness = 0.5
		mi.set_surface_override_material(i, m)

## Sludge's left fist (the chain's root), or his chest.
func _hand(uid: int) -> Vector3:
	var v := fx._view_of(uid)
	if v:
		return v.hand_point("L")
	return fx._chest(uid)

func hook_latch(e: Dictionary) -> void:
	var h: Dictionary = _hooks.get(int(e.seq), {})
	if h.is_empty():
		return
	h.target = int(e.u)
	h.latched_at = Time.get_ticks_msec() / 1000.0
	var pos: Vector2 = e.pos
	var c := fx._chest(int(e.u), 0.55)
	if fx._seen(pos):
		var caster: SimUnit = game.world.get_unit(int(e.src))
		var back := View.to3(pos) - (View.to3(caster.pos) if caster else View.to3(pos) + Vector3.FORWARD)
		back.y = 0.0
		fx.sparks(c, -back.normalized() + Vector3.UP * 0.4, 10, Color(1.0, 0.92, 0.75), 7.0)
		fx.impact(c, Color(1.0, 0.95, 0.85), 0.35)
		if not bool(e.get("ally", false)):
			fx.blood_hit(int(e.u), -back.normalized())
			fx.blood_hit(int(e.u), Vector3.UP)
		fx.flash_light(c, Color(1.0, 0.9, 0.8), 3.0, 5.0, 0.18)
		if int(e.src) == game.player_hero_id and game.camera:
			game.camera.shake(0.18, 0.22)

func hook_kill(e: Dictionary) -> void:
	var u: SimUnit = game.world.get_unit(int(e.u))
	if u and fx._seen(u.pos):
		var c := fx._chest(int(e.u), 0.5)
		for i in 3:
			fx.blood_hit(int(e.u), Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)))
		fx.debris(c, 6, Color(0.5, 0.06, 0.06), 4.0, 0.7, "sphere")

## Per frame: place every hook's tip from the simulation (interpolated), spin it, lay the chain.
func frame(w: SimWorld, alpha: float, dt: float) -> void:
	var live := {}
	for e in w.effects:
		if e.kind == "hook":
			live[int(e.seq)] = e
	for seq in _hooks.keys():
		var h: Dictionary = _hooks[seq]
		var e = live.get(seq)
		if e == null:
			_end_hook(seq)
			continue
		var p2: Vector2 = e.pos
		var target := w.get_unit(int(e.target))
		var y := _hook_height(p2)
		if target != null and int(e.target) >= 0:
			var tv := fx._view_of(target.id)
			y = fx.ground_y(p2) + (tv.bar_height * 0.5 if tv else 1.0)
		var np := View.to3(p2) + Vector3(0, y, 0)
		var caster := w.get_unit(int(h.src))
		if target != null and int(e.target) >= 0 and caster != null and caster.pos.distance_to(p2) > 1.0:
			# bitten in on the side facing Sludge, so the star stays in sight in front of the victim
			np += View.to3(caster.pos - p2).normalized() * 0.4
		if w.tick != int(h.tick):
			h.prev = h.cur
			h.cur = np
			h.tick = w.tick
		var pos := (h.prev as Vector3).lerp(h.cur, alpha)
		var tip: Node3D = h.tip
		tip.global_position = pos
		var was: String = h.state
		h.state = String(e.state)
		if was == "out" and h.state == "back":
			for tr in h.trails:                     # the streaks belong to the flight out only
				if is_instance_valid(tr):
					(tr as Trail3D).stop()
		if was == "out" and h.state == "back" and int(e.target) < 0:
			_ring_off(h, pos)
		# spin: fast going out, a slow grind once it has bitten into something
		var rate: float = h.rate
		if int(h.target) >= 0:
			rate = lerpf(rate, 0.0, clampf(dt * 6.0, 0.0, 1.0))
			h.embed = minf(1.0, float(h.embed) + dt * 5.0)
			h.bleed = float(h.bleed) - dt
			if float(h.bleed) <= 0.0 and target != null and fx._seen(target.pos):
				h.bleed = 0.12
				fx._splat(target.pos + Vector2(randf_range(-25, 25), randf_range(-25, 25)))
		elif h.state == "back":
			rate = lerpf(rate, 14.0, clampf(dt * 3.0, 0.0, 1.0))
		h.rate = rate
		h.spin = float(h.spin) + rate * dt
		var sn: Node3D = h.spin_node
		sn.rotation = Vector3(0.0, -float(h.spin), 0.0)
		# biting in: tilt the star up into the victim's body
		sn.rotation.x = -float(h.embed) * 0.5
		var bmat: StandardMaterial3D = h.blur_mat
		bmat.albedo_color = Color(1, 1, 1, clampf((rate - 6.0) / 24.0, 0.0, 1.0) * 0.8)
		_lay_chain(h, pos, dt)

func _ring_off(h: Dictionary, pos: Vector3) -> void:
	h.whip = 1.0
	if fx._seen(View.to2(pos)):
		fx.sparks(pos, Vector3.UP, 5, Color(0.9, 0.95, 1.0), 4.0)
		game.audio.at("hit_metal_3", pos, -12.0, 0, 0.1, 0.15)

## The chain: links from the fist to the tip, along a gentle sag, with a travelling whip after a miss and a little
## wobble as it pays out. Alternate links turn 90 degrees, like a real chain.
func _lay_chain(h: Dictionary, tip: Vector3, dt: float) -> void:
	var a := _hand(int(h.src))
	var mmi: MultiMeshInstance3D = h.chain
	var mm := mmi.multimesh
	var span := a.distance_to(tip)
	var n := clampi(int(span / LINK_STEP), 0, MAX_LINKS)
	mm.visible_instance_count = n
	if n == 0:
		return
	h.whip = maxf(0.0, float(h.whip) - dt * 1.6)
	var t_now := Time.get_ticks_msec() / 1000.0
	var dir := (tip - a) / maxf(0.001, span)
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var sag := 0.08 + 0.02 * span
	if h.state == "back":
		sag *= 1.6
	var prev := a
	for i in n:
		var t := (i + 0.5) / n
		var p := a.lerp(tip, t)
		p.y -= sin(t * PI) * sag
		p += side * sin(t * 14.0 - t_now * 22.0) * 0.06 * sin(t * PI) * (0.35 + float(h.whip) * 2.0)
		var nxt := a.lerp(tip, minf(1.0, t + 1.0 / n))
		nxt.y -= sin(minf(1.0, t + 1.0 / n) * PI) * sag
		var tan := (nxt - p).normalized() if nxt.distance_to(p) > 0.0001 else dir
		var up := tan
		var right := up.cross(Vector3.UP).normalized() if absf(up.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		var fwd := right.cross(up).normalized()
		var basis := Basis(right, up, fwd)
		if i % 2 == 1:
			basis = basis * Basis(Vector3.UP, PI * 0.5)
		basis = basis.scaled(Vector3.ONE * LINK_SCALE)
		mm.set_instance_transform(i, Transform3D(basis, p))
		prev = p

func _end_hook(seq: int) -> void:
	var h: Dictionary = _hooks.get(seq, {})
	_hooks.erase(seq)
	if h.is_empty():
		return
	for tr in h.trails:
		if is_instance_valid(tr):
			(tr as Trail3D).stop()
	var v := fx._view_of(int(h.src))
	if v:
		v.hide_weapon("L", false)
	var root: Node3D = h.root
	var tip: Node3D = h.tip
	if is_instance_valid(tip) and fx._seen(View.to2(tip.global_position)):
		fx.sparks(tip.global_position, Vector3.UP, 4, Color(0.9, 0.95, 1.0), 3.0)
	# let the trails fade, then clear up
	var tw := root.create_tween()
	tw.tween_interval(0.25)
	tw.tween_callback(root.queue_free)
	if is_instance_valid(tip):
		tip.visible = false
	(h.chain as MultiMeshInstance3D).visible = false

# ---- Stench ---------------------------------------------------------------------------------------------------------

func toggle(e: Dictionary) -> void:
	if String(e.ability) != "stench":
		return
	var uid := int(e.u)
	if bool(e.on):
		_cloud(uid)
		var u: SimUnit = game.world.get_unit(uid)
		if u:
			game.audio.at("drain", View.to3(u.pos, game.terrain.height_at(u.pos)) + Vector3(0, 1, 0), -8.0, 0, 0.3)
	else:
		_end_cloud(uid)

## A ring of soft, slowly turning gas puffs hugging the ground, sized to the ability's radius.
func _cloud(uid: int) -> void:
	if _clouds.has(uid):
		return
	var node := Node3D.new()
	add_child(node)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(STENCH.r, STENCH.g, STENCH.b, 0.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
	gt.gradient = gr
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	m.albedo_texture = gt
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	var puffs: Array = []
	for i in 22:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.6, 1.6)
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
		puffs.append({"mi": mi, "phase": randf() * TAU, "r": randf_range(0.2, 1.0), "a": randf() * TAU,
			"h": randf_range(0.15, 0.9), "s": randf_range(0.8, 1.5)})
	_clouds[uid] = {"node": node, "puffs": puffs, "mat": m, "fade": 0.0, "off": false}

func _end_cloud(uid: int) -> void:
	var c: Dictionary = _clouds.get(uid, {})
	if c.is_empty():
		return
	c.off = true

func _update_clouds(w: SimWorld, dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for uid in _clouds.keys():
		var c: Dictionary = _clouds[uid]
		var u := w.get_unit(uid)
		if u == null or not u.alive:
			c.off = true
		c.fade = clampf(float(c.fade) + (dt * 3.0 if not c.off else -dt * 2.0), 0.0, 1.0)
		var m: StandardMaterial3D = c.mat
		m.albedo_color = Color(STENCH.r, STENCH.g, STENCH.b, 0.42 * float(c.fade))
		if c.off and float(c.fade) <= 0.0:
			(c.node as Node3D).queue_free()
			_clouds.erase(uid)
			continue
		if u == null:
			continue
		var v := fx._view_of(uid)
		var centre := v.global_position if v else View.to3(u.pos, game.terrain.height_at(u.pos))
		var radius: float = game.world.abilities.val(u, "stench", "radius") * View.S
		var node: Node3D = c.node
		node.global_position = centre
		node.visible = fx._seen(u.pos)
		for p in c.puffs:
			var a := float(p.a) + t * 0.35 * (1.0 if int(p.phase * 10.0) % 2 == 0 else -1.0)
			var r: float = float(p.r) * radius * (0.85 + 0.15 * sin(t * 1.3 + float(p.phase)))
			var mi: MeshInstance3D = p.mi
			mi.position = Vector3(cos(a) * r, float(p.h) + 0.15 * sin(t * 2.0 + float(p.phase)), sin(a) * r)
			var s := float(p.s) * (0.9 + 0.2 * sin(t * 1.7 + float(p.phase)))
			mi.scale = Vector3.ONE * s

# ---- Blubber, Chomp, Growing Gut ------------------------------------------------------------------------------------

func blubber(e: Dictionary) -> void:
	var u: SimUnit = game.world.get_unit(int(e.u))
	if u == null or not fx._seen(u.pos):
		return
	var c := fx._chest(u.id, 0.45)
	fx.shockwave(fx.ground3(u.pos, 0.05), 1.6, Color(0.75, 0.68, 0.45), 0.45, 0.2, 1.6)
	fx.impact(c, Color(0.9, 0.85, 0.6), 0.5)
	game.audio.at("armor_rustle_2", c, -6.0, 0, 0.3)

func chomp_bite(e: Dictionary) -> void:
	var t: SimUnit = game.world.get_unit(int(e.target))
	var u: SimUnit = game.world.get_unit(int(e.u))
	if t == null or u == null or not fx._seen(t.pos):
		return
	var dir := View.to3(t.pos) - View.to3(u.pos)
	dir.y = 0.0
	fx.blood_hit(t.id, dir.normalized() + Vector3.UP * 0.5)
	game.audio.at("hit_flesh", fx._chest(t.id), -4.0, 3, 0.08)
	if randf() < 0.5:
		game.audio.at("hit_bone", fx._chest(t.id), -8.0, 3, 0.08)

func growing_gut(e: Dictionary) -> void:
	var u: SimUnit = game.world.get_unit(int(e.u))
	if u == null:
		return
	var v := fx._view_of(u.id)
	var at := v.global_position + Vector3(0, v.bar_height + 0.4, 0) if v else fx._chest(u.id, 1.2)
	game.bars.popup("+%d" % int(round(float(e.gain))), at, Color(0.95, 0.15, 0.12), 28, 1.4, 1.6)
	game.audio.at("heartbeat", at, -4.0, 0, 0.5)

## Called by main each frame; the work happens in _process, after the animations.
func update(_w: SimWorld, alpha: float, dt: float) -> void:
	_alpha = alpha
	_dt = dt

func _process(_delta: float) -> void:
	if game == null or game.world == null:
		return
	frame(game.world, _alpha, _dt)
	_update_clouds(game.world, _dt)
